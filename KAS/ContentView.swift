//
//  ContentView.swift
//  KAS
//
//  Created by 권민재 on 5/20/26.
//

import SwiftUI
import WebKit
import QuickLook

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
    var hasAttachment: Bool? = nil
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
    let attachFile: Bool?
}

nonisolated struct CafeSearchWriterInfo: Decodable, Sendable {
    let nickname: String
}

enum SortOrder: String, CaseIterable, Identifiable {
    case newest = "최신순"
    case oldest = "오래된순"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    // 내 이름 (설정 / 내 제출현황에서 사용)
    @AppStorage("savedUserName") private var savedUserName = ""
    @AppStorage("nid_aut") private var nidAut = ""
    @AppStorage("nid_ses") private var nidSes = ""
    @AppStorage("recentSearches") private var recentSearchesString = ""
    
    @StateObject private var searchViewModel = SearchViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var bookmarkManager = BookmarkManager.shared
    
    @State private var isShowingLoginSheet = false
    @State private var isShowingSettingsSheet = false
    @State private var isShowingSubmissionSheet = false
    @State private var selectedMenuId: String? = nil
    @State private var previewURL: URL? = nil
    @State private var selectedTab = 0  // 0: 검색, 1: 즐겨찾기
    
    // 검색창 전용 변수 (savedUserName과 완전히 분리)
    @State private var searchQuery = ""
    
    @State private var showOnlyWithAttachments = false
    @State private var showOnlyNotDownloaded = false
    @State private var sortOrder = SortOrder.newest
    
    // Toast State
    @State private var showToast = false
    @State private var toastMessage = ""

    var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredSearchResults: [CafeArticle] {
        var results = searchViewModel.searchResults
        
        if let selectedMenuId = selectedMenuId {
            results = results.filter { $0.menuId == selectedMenuId }
        }
        
        if showOnlyWithAttachments {
            results = results.filter { $0.hasAttachment == true }
        }
        
        if showOnlyNotDownloaded {
            results = results.filter { article in
                let articleId = article.link.components(separatedBy: "/").last ?? ""
                return !downloadManager.downloadedArticleIds.contains(articleId)
            }
        }
        
        results.sort { art1, art2 in
            let id1 = Int(art1.link.components(separatedBy: "/").last ?? "") ?? 0
            let id2 = Int(art2.link.components(separatedBy: "/").last ?? "") ?? 0
            return sortOrder == .newest ? id1 > id2 : id1 < id2
        }
        
        return results
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
        ZStack(alignment: .bottom) {
            NavigationStack {
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("", selection: $selectedTab) {
                        Label("검색", systemImage: "magnifyingglass").tag(0)
                        Label("즐겨찾기", systemImage: "star.fill").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    if selectedTab == 0 {
                        searchTabContent
                    } else {
                        bookmarkTabContent
                    }
                }
                .background(.ultraThinMaterial)
                .navigationTitle("KAS")
                .onAppear {
                    searchViewModel.loadCafeMenuNames()
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        HStack(spacing: 8) {
                            // 내 제출 현황 버튼
                            Button {
                                isShowingSubmissionSheet = true
                            } label: {
                                Image(systemName: "list.clipboard")
                            }
                            .help("내 제출 현황")

                            Button {
                                isShowingSettingsSheet = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .help("설정")
                            
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
                .sheet(isPresented: $isShowingSettingsSheet) {
                    SettingsView(isPresented: $isShowingSettingsSheet, downloadManager: downloadManager)
                }
                .sheet(isPresented: $isShowingSubmissionSheet) {
                    MySubmissionView(
                        isPresented: $isShowingSubmissionSheet,
                        nidAut: nidAut,
                        nidSes: nidSes,
                        menuIdMap: searchViewModel.menuIdMap
                    )
                }
            }
            .onChange(of: downloadManager.batchStatus) { _, newStatus in
                if case .done(let count) = newStatus {
                    showToastMessage("\(count)개 과제 일괄 다운로드 완료!")
                }
            }
            .overlay(
                VStack {
                    Spacer()
                    if showToast {
                        Text(toastMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.9))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 30)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showToast)
            )
            .quickLookPreview($previewURL)
        }
    }

    // MARK: - Search Tab

    @ViewBuilder
    private var searchTabContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                    
                Text("Kaywon Assignment System")
                    .font(.largeTitle)
                    //.fontWeight(.bold)

                Text("현재 버전 : 0.4.0 (beta)")
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
                    TextField("학생 이름 입력", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !trimmedSearchQuery.isEmpty {
                                addRecentSearch(trimmedSearchQuery)
                                searchViewModel.searchCafeArticles(userName: trimmedSearchQuery, nidAut: nidAut, nidSes: nidSes)
                            }
                        }

                    Button {
                        let targetName = trimmedSearchQuery.isEmpty ? searchViewModel.searchedStudentName : trimmedSearchQuery
                        if !targetName.isEmpty {
                            downloadManager.openDownloadsDir(for: targetName)
                        }
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(trimmedSearchQuery.isEmpty && searchViewModel.searchedStudentName.isEmpty)
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
                                        searchQuery = name
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

//                Text("이름을 입력하면 해당 학생의 최근 과제 제출글을 검색합니다")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)

                Button {
                    addRecentSearch(trimmedSearchQuery)
                    searchViewModel.searchCafeArticles(userName: trimmedSearchQuery, nidAut: nidAut, nidSes: nidSes)
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("과제 검색 및 조회")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedSearchQuery.isEmpty)

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
                    
                    // Filter & Sort Bar
                    HStack(spacing: 16) {
                        Toggle(isOn: $showOnlyWithAttachments) {
                            Text("첨부파일 있음")
                                .font(.subheadline)
                        }
                        .toggleStyle(.checkbox)
                        
                        Toggle(isOn: $showOnlyNotDownloaded) {
                            Text("미다운로드")
                                .font(.subheadline)
                        }
                        .toggleStyle(.checkbox)
                        
                        Spacer()
                        
                        Picker("정렬", selection: $sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
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
                                    studentName: searchViewModel.searchedStudentName,
                                    menuIdMap: searchViewModel.menuIdMap,
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

                if searchViewModel.searchResults.isEmpty && !searchViewModel.isLoading && searchViewModel.errorMessage.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "folder.magnifyingglass")
                            .font(.system(size: 64))
                            .foregroundStyle(.blue.opacity(0.4))
                        Text("학생 이름을 검색하여 과제를 확인하세요")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 80)
                    Spacer()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSearchResults) { article in
                            let menuName = searchViewModel.menuIdMap[article.menuId ?? ""] ?? "게시판 \(article.menuId ?? "")"
                            ArticleRowView(
                                article: article,
                                menuName: menuName,
                                downloadManager: downloadManager,
                                bookmarkManager: bookmarkManager,
                                studentName: searchViewModel.searchedStudentName,
                                nidAut: nidAut,
                                nidSes: nidSes,
                                onPreview: { url in
                                    self.previewURL = url
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
            }
            .padding()
        } // end ScrollView (searchTabContent)
    }

    // MARK: - Bookmark Tab

    @ViewBuilder
    private var bookmarkTabContent: some View {
        if bookmarkManager.bookmarkedArticles.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "star")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow.opacity(0.5))
                Text("즐겨찾기가 비어있습니다")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("게시글 목록에서 ★를 눌러 즐겨찾기에 추가하세요")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(bookmarkManager.bookmarkedArticles) { article in
                        let menuName = searchViewModel.menuIdMap[article.menuId ?? ""] ?? "게시판 \(article.menuId ?? "")"
                        ArticleRowView(
                            article: article,
                            menuName: menuName,
                            downloadManager: downloadManager,
                            bookmarkManager: bookmarkManager,
                            studentName: searchViewModel.searchedStudentName,
                            nidAut: nidAut,
                            nidSes: nidSes,
                            onPreview: { url in
                                self.previewURL = url
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }

    // (body closing brace moved up)

    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showToast = false }
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

struct SettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var downloadManager: DownloadManager
    
    @AppStorage("savedUserName") private var savedUserName = ""
    @AppStorage("customDownloadPath") private var customDownloadPath = ""
    @AppStorage("openFinderOnDownload") private var openFinderOnDownload = true
    
    @State private var syncStatusMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("KAS 설정")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("닫기") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 10)
            
            Form {
                Section(header: Text("내 정보").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("내 이름")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("이름 입력 (내 제출 현황 화면에 사용)", text: $savedUserName)
                            .textFieldStyle(.roundedBorder)
                        Text("입력한 이름으로 내 제출 현황 (클립보드 아이콘)을 조회합니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section(header: Text("다운로드 설정").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("저장 경로")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text(customDownloadPath.isEmpty ? "Downloads/KAS (기본값)" : customDownloadPath)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                            
                            Button("선택...") {
                                selectDownloadFolder()
                            }
                            
                            if !customDownloadPath.isEmpty {
                                Button("초기화") {
                                    customDownloadPath = ""
                                    UserDefaults.standard.removeObject(forKey: "customDownloadBookmark")
                                }
                            }
                        }
                        
                        Text("선택한 경로 아래에 각 학생 이름으로 폴더가 생성됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    
                    Divider()
                    
                    Toggle("다운로드 완료 후 Finder로 폴더 열기", isOn: $openFinderOnDownload)
                        .padding(.vertical, 6)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("다운로드 내역 동기화")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                let count = downloadManager.scanAndSyncDownloadHistory()
                                if count > 0 {
                                    syncStatusMessage = "\(count)개의 다운로드 내역이 동기화되었습니다."
                                } else {
                                    syncStatusMessage = "새로운 다운로드 내역을 찾지 못했습니다."
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                    syncStatusMessage = ""
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("기존 다운로드 파일 스캔 및 동기화")
                                }
                            }
                            
                            if !syncStatusMessage.isEmpty {
                                Text(syncStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .transition(.opacity)
                            }
                        }
                        
                        Text("설정된 저장 경로의 폴더들을 스캔하여 기존 다운로드 내역을 앱으로 불러옵니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .formStyle(.grouped)
            
            Spacer()
        }
        .padding()
        .frame(width: 520, height: 560)
    }
    
    private func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "다운로드 저장 폴더 선택"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: "customDownloadBookmark")
                customDownloadPath = url.path
            } catch {
                print("Failed to save bookmark: \(error)")
            }
        }
    }
}
