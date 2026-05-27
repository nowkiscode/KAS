//
//  ContentView.swift
//  KAS
//
//  Created by 권민재 on 5/20/26.
//

import SwiftUI
import WebKit

enum NaverCafeConfig {
    static let cafeId = "28411094"
    static let cafeSlug = "kwdmd"
    static let cafeName = "계원디지털미디어디자인"
    static let mobileCafeURL = "https://m.cafe.naver.com/\(cafeSlug)"
    static let desktopCafeURL = "https://cafe.naver.com/\(cafeSlug)"
    static let loginURL = "https://nid.naver.com/nidlogin.login"
}

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
    @AppStorage("nid_aut") private var nidAut = ""
    @AppStorage("nid_ses") private var nidSes = ""
    @AppStorage("recentSearches") private var recentSearchesString = ""
    
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    
    @State private var isShowingLoginSheet = false
    @State private var selectedMenuId: String? = nil

    var trimmedUserName: String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredSearchResults: [CafeArticle] {
        if let selectedMenuId = selectedMenuId {
            return searchViewModel.searchResults.filter { $0.menuId == selectedMenuId }
        }
        return searchViewModel.searchResults
    }

    private var recentSearches: [String] {
        recentSearchesString.components(separatedBy: ",").filter { !$0.isEmpty }
    }

    private func addRecentSearch(_ name: String) {
        var list = recentSearches
        if let idx = list.firstIndex(of: name) { list.remove(at: idx) }
        list.insert(name, at: 0)
        if list.count > 10 { list.removeLast() }
        recentSearchesString = list.joined(separator: ",")
    }

    private func removeRecentSearch(_ name: String) {
        var list = recentSearches
        if let idx = list.firstIndex(of: name) { list.remove(at: idx) }
        recentSearchesString = list.joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                    
                Text("Kaywon Assignment System")
                    .font(.largeTitle)
                    //.fontWeight(.bold)

                Text("현재 버전 : 0.3.1 (beta)")
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

                HStack {
                    TextField("학생 이름 입력", text: $userName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !trimmedUserName.isEmpty {
                                addRecentSearch(trimmedUserName)
                                searchViewModel.searchCafeArticles(userName: trimmedUserName, nidAut: nidAut, nidSes: nidSes)
                            }
                        }

                    Button {
                        if !trimmedUserName.isEmpty {
                            downloadManager.openDownloadsDir(for: trimmedUserName)
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(trimmedUserName.isEmpty)
                }

                if !recentSearches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("최근:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(recentSearches, id: \.self) { name in
                                RecentSearchTagView(
                                    name: name,
                                    onSelect: {
                                        userName = name
                                        addRecentSearch(name)
                                        searchViewModel.searchCafeArticles(userName: name, nidAut: nidAut, nidSes: nidSes)
                                    },
                                    onDelete: {
                                        removeRecentSearch(name)
                                    }
                                )
                            }
                        }
                    }
                }

                Text("이름을 입력하면 해당 학생의 최근 과제 제출글을 검색합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    addRecentSearch(trimmedUserName)
                    searchViewModel.searchCafeArticles(userName: trimmedUserName, nidAut: nidAut, nidSes: nidSes)
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("과제 검색 및 조회")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedUserName.isEmpty)

                if searchViewModel.isLoading {
                    ProgressView("네이버 카페 검색 중...")
                }

                if !searchViewModel.errorMessage.isEmpty {
                    Text(searchViewModel.errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }

                if !searchViewModel.searchResults.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                selectedMenuId = nil
                            } label: {
                                Text("전체 (\(searchViewModel.searchResults.count))")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedMenuId == nil ? Color.blue : Color.gray.opacity(0.1))
                                    .foregroundStyle(selectedMenuId == nil ? .white : .primary)
                                    .cornerRadius(15)
                            }
                            
                            ForEach(searchViewModel.availableMenuIds, id: \.self) { menuId in
                                let count = searchViewModel.searchResults.filter { $0.menuId == menuId }.count
                                let title = searchViewModel.menuIdMap[menuId] ?? "게시판 \(menuId)"
                                
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

                    if !searchViewModel.menuLoadErrorMessage.isEmpty {
                        Text(searchViewModel.menuLoadErrorMessage)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                if !searchViewModel.searchResults.isEmpty {
                    let isLoggedIn = !nidAut.isEmpty && !nidSes.isEmpty
                    let isBatchActive: Bool = {
                        if case .fetchingInfo = downloadManager.batchStatus { return true }
                        if case .downloading = downloadManager.batchStatus { return true }
                        return false
                    }()
                    
                    VStack(spacing: 6) {
                        if isBatchActive {
                            Button {
                                downloadManager.cancelBatch()
                            } label: {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("일괄 다운로드 취소")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button {
                                downloadManager.resetBatch()
                                downloadManager.downloadAll(
                                    articles: filteredSearchResults,
                                    studentName: trimmedUserName,
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
                            .disabled(!isLoggedIn)
                        }

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
                                    .font(.caption)
                                Text("\(count)개 게시글 다운로드 완료 - Finder에서 열림")
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

                List(filteredSearchResults) { article in
                    let menuName = searchViewModel.menuIdMap[article.menuId ?? ""] ?? "게시판 \(article.menuId ?? "")"
                    ArticleRowView(
                        article: article,
                        menuName: menuName,
                        downloadManager: downloadManager,
                        studentName: trimmedUserName,
                        nidAut: nidAut,
                        nidSes: nidSes
                    )
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("KAS")
            .onAppear {
                searchViewModel.loadCafeMenuNames()
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

    private func logoutNaver() {
        nidAut = ""
        nidSes = ""
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let naverRecords = records.filter { $0.displayName.contains("naver") }
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: naverRecords) { }
        }
    }
}

#if os(macOS)
struct NaverLoginWebView: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var nidAut: String
    @Binding var nidSes: String
    
    func makeNSView(context: Context) -> WKWebView { return context.coordinator.makeWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
}
#else
struct NaverLoginWebView: UIViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var nidAut: String
    @Binding var nidSes: String
    
    func makeUIView(context: Context) -> WKWebView { return context.coordinator.makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
}
#endif

extension NaverLoginWebView {
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: NaverLoginWebView
        init(_ parent: NaverLoginWebView) { self.parent = parent }
        
        func makeWebView() -> WKWebView {
            let webView = WKWebView()
            webView.navigationDelegate = self
            
            let dataStore = WKWebsiteDataStore.default()
            dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                let naverRecords = records.filter { $0.displayName.contains("naver") }
                dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: naverRecords) {
                    if let url = URL(string: NaverCafeConfig.loginURL) {
                        let request = URLRequest(url: url)
                        DispatchQueue.main.async { webView.load(request) }
                    }
                }
            }
            return webView
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                var aut = "", ses = ""
                for cookie in cookies {
                    if cookie.name == "NID_AUT" { aut = cookie.value }
                    else if cookie.name == "NID_SES" { ses = cookie.value }
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

struct RecentSearchTagView: View {
    let name: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(Color.blue.opacity(0.1))
        .foregroundStyle(.blue)
        .cornerRadius(8)
        .overlay(
            Group {
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .background(Circle().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            , alignment: .topTrailing
        )
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hover
            }
        }
        .padding(.top, 4)
        .padding(.trailing, 4)
    }
}
