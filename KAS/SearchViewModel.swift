//
//  SearchViewModel.swift
//  KAS
//

import Foundation
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchResults: [CafeArticle] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var menuLoadErrorMessage = ""
    @Published var menuIdMap: [String: String] = [:]
    
    private var activeSearchToken = UUID()
    
    var availableMenuIds: [String] {
        Array(Set(searchResults.compactMap { $0.menuId })).sorted()
    }
    
    func fetchArticlesAsync(query: String, searchBy: String, nidAut: String, nidSes: String) async throws -> [CafeArticle] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        
        let urlString = "https://apis.naver.com/cafe-web/cafe-search-api/v2/cafes/\(NaverCafeConfig.cafeId)/search/articles?query=\(encodedQuery)&page=1&perPage=100&adUnit=MW_CAF&sortBy=RECENCY&searchBy=\(searchBy)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue(NaverCafeConfig.mobileCafeURL, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")
        
        if !nidAut.isEmpty && !nidSes.isEmpty {
            request.setValue("NID_AUT=\(nidAut); NID_SES=\(nidSes)", forHTTPHeaderField: "Cookie")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoded = try JSONDecoder().decode(CafeSearchResponse.self, from: data)
        return decoded.result.articleList.map { container in
            let item = container.item
            let link = "\(NaverCafeConfig.desktopCafeURL)/\(item.articleId)"
            return CafeArticle(
                title: item.subject,
                link: link,
                cafeName: NaverCafeConfig.cafeName,
                description: item.summary,
                menuId: String(item.menuId),
                writerNickname: item.writerInfo?.nickname
            )
        }
    }
    
    func searchCafeArticles(userName: String, nidAut: String, nidSes: String) {
        let query = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "이름을 입력해주세요"
            return
        }
        
        let searchToken = UUID()
        activeSearchToken = searchToken
        isLoading = true
        errorMessage = ""
        searchResults = []
        
        let nfcQuery = query.precomposedStringWithCanonicalMapping
        let nfdQuery = query.decomposedStringWithCanonicalMapping
        
        let searchTasks = [
            (nfcQuery, "3"), (nfcQuery, "0"),
            (nfdQuery, "3"), (nfdQuery, "0")
        ]
        
        Task {
            var allArticles: [CafeArticle] = []
            var successCount = 0
            
            await withTaskGroup(of: [CafeArticle]?.self) { group in
                for (q, searchBy) in searchTasks {
                    group.addTask {
                        try? await self.fetchArticlesAsync(query: q, searchBy: searchBy, nidAut: nidAut, nidSes: nidSes)
                    }
                }
                
                for await result in group {
                    if let result = result {
                        allArticles.append(contentsOf: result)
                        successCount += 1
                    }
                }
            }
            
            guard self.activeSearchToken == searchToken else { return }
            self.isLoading = false
            
            var merged: [String: CafeArticle] = [:]
            for art in allArticles {
                merged[art.link] = art
            }
            
            if merged.isEmpty {
                self.errorMessage = successCount == 0
                    ? "검색 요청이 모두 실패했습니다. 네트워크 상태나 네이버 로그인 세션을 확인해주세요."
                    : "해당 이름의 글을 찾지 못했습니다"
                return
            }
            
            let sortedArticles = merged.values.sorted { art1, art2 in
                let id1 = Int(art1.link.components(separatedBy: "/").last ?? "") ?? 0
                let id2 = Int(art2.link.components(separatedBy: "/").last ?? "") ?? 0
                return id1 > id2
            }
            
            self.searchResults = sortedArticles
        }
    }
    
    func loadCafeMenuNames() {
        Task {
            menuLoadErrorMessage = ""
            guard let url = URL(string: NaverCafeConfig.desktopCafeURL) else { return }
            
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                
                let cp949 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
                guard let html = String(data: data, encoding: String.Encoding(rawValue: cp949)) else {
                    throw URLError(.cannotDecodeRawData)
                }
                
                let pattern = #"menuid=(\d+)[^>]*>([^<]+)</a>"#
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
                let matches = regex.matches(in: html, options: [], range: nsRange)
                
                var newMap: [String: String] = [:]
                for match in matches {
                    if match.numberOfRanges >= 3,
                       let idRange = Range(match.range(at: 1), in: html),
                       let nameRange = Range(match.range(at: 2), in: html) {
                        let menuId = String(html[idRange])
                        let menuName = String(html[nameRange])
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !menuName.isEmpty {
                            newMap[menuId] = menuName
                        }
                    }
                }
                
                self.menuIdMap = newMap
                if newMap.isEmpty {
                    self.menuLoadErrorMessage = "게시판 이름을 찾지 못했습니다. 숫자 ID로 계속 표시합니다."
                }
            } catch {
                self.menuLoadErrorMessage = "게시판 이름을 불러오지 못했습니다. 숫자 ID로 계속 표시합니다."
            }
        }
    }
}
