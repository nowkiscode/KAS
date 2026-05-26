//
//  ContentView.swift
//  KAS
//
//  Created by 권민재 on 5/20/26.
//

import SwiftUI
import WebKit

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
    
    // 네이버 로그인 세션 쿠키
    @AppStorage("nid_aut") private var nidAut = ""
    @AppStorage("nid_ses") private var nidSes = ""
    @State private var isShowingLoginSheet = false

    // 다운로드 매니저
    @StateObject private var downloadManager = DownloadManager.shared
    
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
                
                if !nidAut.isEmpty && !nidSes.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("네이버 로그인 세션 활성화됨 (멤버공개 검색 가능)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("네이버 로그인 비활성화됨 (전체공개 검색만 가능)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

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

                // 일괄 다운로드 버튼 및 진행 상태
                if !searchResults.isEmpty {
                    let isLoggedIn = !nidAut.isEmpty && !nidSes.isEmpty
                    VStack(spacing: 6) {
                        Button {
                            downloadManager.resetBatch()
                            downloadManager.downloadAll(
                                articles: filteredSearchResults,
                                studentName: userName.trimmingCharacters(in: .whitespacesAndNewlines),
                                nidAut: nidAut, nidSes: nidSes
                            )
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("첨부파일 모두 다운로드 (\(filteredSearchResults.count)개)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isLoggedIn || downloadManager.batchStatus != .idle)

                        if !isLoggedIn {
                            Text("다운로드 기능은 네이버 로그인 후 사용 가능합니다")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        switch downloadManager.batchStatus {
                        case .fetchingInfo:
                            ProgressView("첨부파일 정보 조회 중...")
                                .font(.caption)
                        case .downloading(let progress):
                            VStack(spacing: 2) {
                                ProgressView(value: progress)
                                Text(String(format: "다운로드 중 %.0f%%", progress * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        case .done(let count):
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("\(count)개 게시글 처리 완료 — Finder에서 열림")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Button("초기화") { downloadManager.resetBatch() }
                                    .font(.caption)
                            }
                        case .error(let msg):
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                        case .idle:
                            EmptyView()
                        }
                    }
                }

                // 4. 과제물 리스트 (기본 웹 브라우저 연결)
                List(filteredSearchResults) { article in
                    if let url = URL(string: article.link) {
                        HStack(alignment: .top, spacing: 8) {
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

                            Spacer()

                            // 개별 다운로드 버튼
                            let status = downloadManager.statusByArticle[article.link] ?? .idle
                            VStack {
                                switch status {
                                case .idle:
                                    Button {
                                        downloadManager.downloadArticle(
                                            article,
                                            studentName: userName.trimmingCharacters(in: .whitespacesAndNewlines),
                                            nidAut: nidAut, nidSes: nidSes
                                        )
                                    } label: {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.title2)
                                            .foregroundStyle(nidAut.isEmpty ? .gray : .blue)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(nidAut.isEmpty || nidSes.isEmpty)
                                case .fetchingInfo:
                                    ProgressView()
                                        .scaleEffect(0.7)
                                case .downloading(let p):
                                    VStack(spacing: 2) {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.6)
                                        Text(String(format: "%.0f%%", p * 100))
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                    }
                                case .done:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.title2)
                                        .onTapGesture {
                                            downloadManager.resetArticle(link: article.link)
                                        }
                                case .error:
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.title2)
                                        .onTapGesture {
                                            downloadManager.resetArticle(link: article.link)
                                        }
                                }
                            }
                            .frame(width: 34)
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if nidAut.isEmpty || nidSes.isEmpty {
                        Button {
                            isShowingLoginSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("네이버 로그인")
                            }
                        }
                    } else {
                        Button(role: .destructive) {
                            logoutNaver()
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                Text("로그아웃")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingLoginSheet) {
                VStack {
                    HStack {
                        Spacer()
                        Button("닫기") {
                            isShowingLoginSheet = false
                        }
                        .padding()
                    }
                    NaverLoginWebView(isPresented: $isShowingLoginSheet, nidAut: $nidAut, nidSes: $nidSes)
                }
                .frame(minWidth: 450, minHeight: 650)
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

        // 네이버 로그인 세션 쿠키 주입
        if !nidAut.isEmpty && !nidSes.isEmpty {
            let cookieHeader = "NID_AUT=\(nidAut); NID_SES=\(nidSes)"
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

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

    func logoutNaver() {
        nidAut = ""
        nidSes = ""
        
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let naverRecords = records.filter { $0.displayName.contains("naver") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: naverRecords) {
                // Done
            }
        }
    }
}


#if os(macOS)
struct NaverLoginWebView: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var nidAut: String
    @Binding var nidSes: String
    
    func makeNSView(context: Context) -> WKWebView {
        return context.coordinator.makeWebView()
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
#else
struct NaverLoginWebView: UIViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var nidAut: String
    @Binding var nidSes: String
    
    func makeUIView(context: Context) -> WKWebView {
        return context.coordinator.makeWebView()
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
#endif

extension NaverLoginWebView {
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: NaverLoginWebView
        
        init(_ parent: NaverLoginWebView) {
            self.parent = parent
        }
        
        func makeWebView() -> WKWebView {
            let webView = WKWebView()
            webView.navigationDelegate = self
            
            // Delete existing cookies in the web view just in case to show clean login page
            let dataStore = WKWebsiteDataStore.default()
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                let naverRecords = records.filter { $0.displayName.contains("naver") }
                dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: naverRecords) {
                    if let url = URL(string: "https://nid.naver.com/nidlogin.login") {
                        let request = URLRequest(url: url)
                        DispatchQueue.main.async {
                            webView.load(request)
                        }
                    }
                }
            }
            
            return webView
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                var aut = ""
                var ses = ""
                for cookie in cookies {
                    if cookie.name == "NID_AUT" {
                        aut = cookie.value
                    } else if cookie.name == "NID_SES" {
                        ses = cookie.value
                    }
                }
                
                if !aut.isEmpty && !ses.isEmpty {
                    DispatchQueue.main.async {
                        self.parent.nidAut = aut
                        self.parent.nidSes = ses
                        self.parent.isPresented = false
                    }
                }
            }
        }
    }
}


#Preview {
    ContentView()
}


