//
//  ContentView.swift
//  KAS
//
//  Created by 권민재 on 5/20/26.
//

import SwiftUI

nonisolated struct CafeArticle: Identifiable, Codable, Sendable {
    var id = UUID()
    let title: String
    let link: String
    let cafeName: String?
    let description: String?
    var menuId: String? = nil
    var writerNickname: String? = nil
}

nonisolated struct CafeSearchResponse: Decodable, Sendable {
    let result: CafeSearchResult
}

nonisolated struct CafeSearchResult: Decodable, Sendable {
    let articleList: [CafeSearchArticleContainer]
}

nonisolated struct CafeSearchArticleContainer: Decodable, Sendable {
    let type: String
    let item: CafeSearchArticleItem
}

nonisolated struct CafeSearchArticleItem: Decodable, Sendable {
    let cafeId: Int
    let menuId: Int
    let articleId: Int
    let subject: String
    let summary: String?
    let addDate: String?
    let writerInfo: CafeSearchWriterInfo?
}

nonisolated struct CafeSearchWriterInfo: Decodable, Sendable {
    let nickname: String
}

struct ContentView: View {

    @AppStorage("savedUserName") private var userName = ""
    @State private var searchResults: [CafeArticle] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    // menuId 필터링용 상태 변수들
    @State private var selectedMenuId: String? = nil
    
    // 게시판 ID -> 한글 게시판 이름 동적 매핑 딕셔너리
    @State private var menuIdMap: [String: String] = [:]

    // 고유 menuId 목록 추출 (정렬됨)
    var availableMenuIds: [String] {
        let ids = searchResults.compactMap { $0.menuId }
        return Array(Set(ids)).sorted()
    }

    // 선택된 menuId에 따라 필터링된 결과
    var filteredSearchResults: [CafeArticle] {
        if let selectedMenuId = selectedMenuId {
            return searchResults.filter { $0.menuId == selectedMenuId }
        }
        return searchResults
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                Text("KAS")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("현재 버전 : 0.2.0 (beta)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("학생 이름 입력", text: $userName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !userName.isEmpty {
                            searchCafeArticles()
                        }
                    }

                Text("이름을 입력하면 해당 학생의 최근 과제 제출글을 검색합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    searchCafeArticles()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("과제 검색 및 조회")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(userName.isEmpty)

                // 1. API 로딩 상태 인디케이터
                if isLoading {
                    ProgressView("네이버 카페 검색 중...")
                }



                // 에러 메시지 표시
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }

                // 3. 게시판(menuId) 필터 칩 UI
                if !searchResults.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                selectedMenuId = nil
                            } label: {
                                Text("전체 (\(searchResults.count))")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedMenuId == nil ? Color.blue : Color.gray.opacity(0.1))
                                    .foregroundStyle(selectedMenuId == nil ? .white : .primary)
                                    .cornerRadius(15)
                            }
                            
                            ForEach(availableMenuIds, id: \.self) { menuId in
                                let count = searchResults.filter { $0.menuId == menuId }.count
                                let title = menuIdMap[menuId] ?? "게시판 \(menuId)"
                                
                                Button {
                                    selectedMenuId = menuId
                                } label: {
                                    Text("\(title) (\(count))")
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedMenuId == menuId ? Color.blue : Color.gray.opacity(0.1))
                                        .foregroundStyle(selectedMenuId == menuId ? .white : .primary)
                                        .cornerRadius(15)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 35)
                }

                // 4. 과제물 리스트 (기본 웹 브라우저 연결)
                List(filteredSearchResults) { article in
                    if let url = URL(string: article.link) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(cleanHTML(article.title))
                                    .font(.headline)
                                    .foregroundStyle(.blue)

                                HStack(spacing: 8) {
                                    if let nickname = article.writerNickname {
                                        Text(nickname)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                    } else if let cafeName = article.cafeName {
                                        Text(cafeName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    // 게시판 ID 뱃지 표시
                                    if let menuId = article.menuId {
                                        let boardName = menuIdMap[menuId] ?? "게시판 \(menuId)"
                                        Text(boardName)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundStyle(.blue)
                                            .cornerRadius(4)
                                    }
                                }

                                if let description = article.description {
                                    Text(cleanHTML(description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("과제 관리 및 필터")
            .onAppear {
                loadCafeMenuNames()
            }
        }
    }

    func fetchArticles(query: String, searchBy: String, completion: @escaping ([CafeArticle]?) -> Void) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(nil)
            return
        }
        let urlString = "https://apis.naver.com/cafe-web/cafe-search-api/v2/cafes/28411094/search/articles?query=\(encodedQuery)&page=1&perPage=100&adUnit=MW_CAF&sortBy=RECENCY&searchBy=\(searchBy)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.cafe.naver.com/kwdmd", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            do {
                let decoded = try JSONDecoder().decode(CafeSearchResponse.self, from: data)
                let articles = decoded.result.articleList.map { container -> CafeArticle in
                    let item = container.item
                    let link = "https://cafe.naver.com/kwdmd/\(item.articleId)"
                    return CafeArticle(
                        title: item.subject,
                        link: link,
                        cafeName: "계원디지털미디어디자인",
                        description: item.summary,
                        menuId: String(item.menuId),
                        writerNickname: item.writerInfo?.nickname
                    )
                }
                completion(articles)
            } catch {
                completion(nil)
            }
        }.resume()
    }

    func searchCafeArticles() {
        isLoading = true
        errorMessage = ""
        searchResults = []
        selectedMenuId = nil

        let query = userName
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "이름을 입력해주세요"
            isLoading = false
            return
        }

        let nfcQuery = query.precomposedStringWithCanonicalMapping
        let nfdQuery = query.decomposedStringWithCanonicalMapping

        let group = DispatchGroup()
        let lock = NSLock()
        var allArticles: [CafeArticle] = []

        // 4가지 조건으로 병렬 검색 수행 (NFC/NFD 각각 작성자/제목+내용)
        let searchTasks = [
            (nfcQuery, "3"), // NFC 작성자
            (nfcQuery, "0"), // NFC 제목+내용
            (nfdQuery, "3"), // NFD 작성자
            (nfdQuery, "0")  // NFD 제목+내용
        ]

        for (q, searchBy) in searchTasks {
            group.enter()
            fetchArticles(query: q, searchBy: searchBy) { articles in
                if let articles = articles {
                    lock.lock()
                    allArticles.append(contentsOf: articles)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.isLoading = false
            
            var merged: [String: CafeArticle] = [:]
            for art in allArticles {
                merged[art.link] = art
            }

            if merged.isEmpty {
                self.errorMessage = "해당 이름의 글을 찾지 못했습니다"
                return
            }

            // articleId 기준 내림차순 정렬 (최신순 보장)
            let sortedArticles = merged.values.sorted { art1, art2 in
                let id1 = Int(art1.link.components(separatedBy: "/").last ?? "") ?? 0
                let id2 = Int(art2.link.components(separatedBy: "/").last ?? "") ?? 0
                return id1 > id2
            }

            self.searchResults = sortedArticles
        }
    }

    func cleanHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // 카페의 전체 게시판 목록(menuId -> 한글 게시판 이름)을 동적으로 로드하는 함수
    func loadCafeMenuNames() {
        guard let url = URL(string: "https://cafe.naver.com/kwdmd") else { return }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }

            let cp949 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
            guard let html = String(data: data, encoding: String.Encoding(rawValue: cp949)) else { return }

            let pattern = #"menuid=(\d+)[^>]*>([^<]+)</a>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }

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

            DispatchQueue.main.async {
                self.menuIdMap = newMap
            }
        }.resume()
    }
}


#Preview {
    ContentView()
}


