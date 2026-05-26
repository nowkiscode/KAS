//
//  ContentView.swift
//  KAS
//
//  Created by 권민재 on 5/20/26.
//

import SwiftUI

nonisolated struct CafeArticle: Identifiable, Codable, Sendable {
    let id = UUID()
    let title: String
    let link: String
    let cafeName: String?
    let description: String?
    var menuId: String? = nil // 백그라운드 파싱으로 채워질 게시판 ID

    enum CodingKeys: String, CodingKey {
        case title
        case link
        case cafeName = "cafename"
        case description
        // menuId는 API 응답에 직접 없으므로 디코딩에서 제외
    }
}

nonisolated struct NaverSearchResponse: Codable, Sendable {
    let items: [CafeArticle]
}

struct ContentView: View {

    @AppStorage("savedUserName") private var userName = ""
    @State private var searchResults: [CafeArticle] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    // menuId 필터링용 상태 변수들
    @State private var selectedMenuId: String? = nil
    @State private var parsingCount = 0
    @State private var totalToParse = 0
    @State private var isParsingMenuId = false

    // 네이버 개발자센터에서 받은 값
    private let clientID = "25g1Mh3xBCX_IfHKM1Uw"
    private let clientSecret = "CCBos1_iG6"
    
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

                // 2. menuId 백그라운드 파싱 진행 표시
                if isParsingMenuId {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("게시판 정보 분석 중... (\(parsingCount)/\(totalToParse))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                                HStack(spacing: 6) {
                                    if let cafeName = article.cafeName {
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
                                    } else {
                                        Text("분석 중...")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.gray.opacity(0.15))
                                            .foregroundStyle(.gray)
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

    func searchCafeArticles() {
        isLoading = true
        errorMessage = ""
        searchResults = []
        selectedMenuId = nil
        parsingCount = 0
        totalToParse = 0
        isParsingMenuId = false

        let query = userName
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // 디스플레이 수를 100개로 늘려 한 번에 최대한 많은 글을 긁어올 수 있게 개선
        guard let url = URL(string: "https://openapi.naver.com/v1/search/cafearticle.json?query=\(encodedQuery)&sort=date&display=100") else {
            errorMessage = "URL 생성 실패"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(clientID, forHTTPHeaderField: "X-Naver-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "X-Naver-Client-Secret")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
            }

            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    errorMessage = "데이터 없음"
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(NaverSearchResponse.self, from: data)

                DispatchQueue.main.async {
                    // 계원디지털미디어디자인 카페에 등록된 글만 우선 필터링
                    let filtered = decoded.items.filter { article in
                        let cafeName = article.cafeName ?? ""
                        return cafeName.lowercased().contains("계원디지털미디어디자인")
                    }

                    self.searchResults = filtered
                    
                    if filtered.isEmpty {
                        errorMessage = "해당 이름의 글을 찾지 못했습니다"
                    } else {
                        // 백그라운드 menuId 파싱 시작
                        self.startParsingMenuIds(for: filtered)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "데이터 해석 실패"
                }
            }
        }.resume()
    }

    // 각 게시글에 대해 백그라운드로 menuId 파싱을 주도하는 함수
    func startParsingMenuIds(for articles: [CafeArticle]) {
        isParsingMenuId = true
        totalToParse = articles.count
        parsingCount = 0

        for article in articles {
            fetchMenuId(for: article) { menuId in
                DispatchQueue.main.async {
                    if let menuId = menuId {
                        // 결과 리스트 내의 매칭 글에 menuId 업데이트
                        if let index = self.searchResults.firstIndex(where: { $0.id == article.id }) {
                            self.searchResults[index].menuId = menuId
                        }
                    }
                    
                    self.parsingCount += 1
                    if self.parsingCount >= self.totalToParse {
                        self.isParsingMenuId = false
                    }
                }
            }
        }
    }

    // 카페 정보 및 글 번호 추출용 내부 맵 및 헬퍼 함수들
    private let cafeClubIdMap: [String: String] = [
        "kwdmd": "28411094", // 계원디지털미디어디자인 카페
        "chogca": "21231131"  // 초보 그림 카페 (테스트용)
    ]

    func extractArticleId(from link: String) -> String? {
        if let url = URL(string: link),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let articleId = queryItems.first(where: { $0.name.lowercased() == "articleid" })?.value {
            return articleId
        }
        
        let cleanedLink = link.components(separatedBy: "?")[0]
        if let lastComponent = cleanedLink.components(separatedBy: "/").last,
           let _ = Int(lastComponent) {
            return lastComponent
        }
        
        return nil
    }

    func extractClubId(from link: String) -> String? {
        if let url = URL(string: link),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let clubId = queryItems.first(where: { $0.name.lowercased() == "clubid" })?.value {
            return clubId
        }
        return nil
    }

    func extractCafeName(from link: String) -> String? {
        guard let url = URL(string: link) else { return nil }
        let pathComponents = url.pathComponents
        if pathComponents.count >= 3 {
            return pathComponents[1]
        }
        return nil
    }

    // 게시글의 PC 인쇄용 페이지(ArticlePrint.nhn)로부터 menu_id를 추출하는 비동기 함수 (보안 정책 우회)
    func fetchMenuId(for article: CafeArticle, completion: @escaping (String?) -> Void) {
        guard let articleId = extractArticleId(from: article.link) else {
            completion(nil)
            return
        }
        
        var clubId = "28411094" // 기본값: 계원디지털미디어디자인
        if let extractedClubId = extractClubId(from: article.link) {
            clubId = extractedClubId
        } else if let cafeName = extractCafeName(from: article.link),
                  let mappedClubId = cafeClubIdMap[cafeName] {
            clubId = mappedClubId
        }
        
        // 인쇄용 화면은 비로그인 상태에서도 차단 없이 완전 공개되며 가볍습니다 (14KB 내외)
        let printUrlString = "https://cafe.naver.com/ArticlePrint.nhn?clubid=\(clubId)&articleid=\(articleId)"
        guard let url = URL(string: printUrlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            // 네이버 카페 PC 인쇄 페이지는 MS949 (EUC-KR) 인코딩 사용
            let eucKR = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))
            var htmlString = String(data: data, encoding: String.Encoding(rawValue: eucKR))
            if htmlString == nil {
                // EUC-KR 디코딩 실패 시 cp949(dosKorean)로 재시도
                let cp949 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
                htmlString = String(data: data, encoding: String.Encoding(rawValue: cp949))
            }
            if htmlString == nil {
                htmlString = String(data: data, encoding: .utf8)
            }

            guard let html = htmlString else {
                completion(nil)
                return
            }

            // script 내 설정되어 있는 menu_id 추출 정규식
            // 예: menu_id: '1012'
            let pattern = #"menu_id:\s*'([0-9]+)'"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
                if let match = regex.firstMatch(in: html, options: [], range: nsRange) {
                    if let range = Range(match.range(at: 1), in: html) {
                        let extractedId = String(html[range])
                        completion(extractedId)
                        return
                    }
                }
            }
            completion(nil)
        }.resume()
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


