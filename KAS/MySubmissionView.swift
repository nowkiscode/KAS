//
//  MySubmissionView.swift
//  KAS
//

import SwiftUI
import Combine

// MARK: - View Model

@MainActor
class MySubmissionViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var groupedResults: [SubmissionGroup] = []
    @Published var totalCount = 0

    struct SubmissionGroup: Identifiable {
        let id = UUID()
        let menuName: String
        let articles: [CafeArticle]

        var count: Int { articles.count }
        var latestDate: String? { articles.first?.description }
    }

    private var activeToken = UUID()

    func load(userName: String, nidAut: String, nidSes: String, menuIdMap: [String: String]) {
        guard !userName.isEmpty else {
            errorMessage = "설정에서 내 이름을 먼저 입력해주세요."
            return
        }

        let token = UUID()
        activeToken = token
        isLoading = true
        errorMessage = ""
        groupedResults = []
        totalCount = 0

        let cafeId = NaverCafeConfig.cafeId
        let mobileCafeURL = NaverCafeConfig.mobileCafeURL
        let desktopCafeURL = NaverCafeConfig.desktopCafeURL
        let cafeName = NaverCafeConfig.cafeName
        let currentYear = Calendar.current.component(.year, from: Date())

        Task {
            let nfcQuery = userName.precomposedStringWithCanonicalMapping
            let nfdQuery = userName.decomposedStringWithCanonicalMapping

            let searchTasks: [(String, String)] = [
                (nfcQuery, "3"), (nfcQuery, "0"),
                (nfdQuery, "3"), (nfdQuery, "0")
            ]

            var allArticles: [CafeArticle] = []

            await withTaskGroup(of: [CafeArticle]?.self) { group in
                for (q, searchBy) in searchTasks {
                    group.addTask {
                        guard let encodedQuery = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
                        let urlStr = "https://apis.naver.com/cafe-web/cafe-search-api/v2/cafes/\(cafeId)/search/articles?query=\(encodedQuery)&page=1&perPage=100&adUnit=MW_CAF&sortBy=RECENCY&searchBy=\(searchBy)"
                        guard let url = URL(string: urlStr) else { return nil }

                        var request = URLRequest(url: url)
                        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                        request.setValue(mobileCafeURL, forHTTPHeaderField: "Referer")
                        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
                        request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")
                        if !nidAut.isEmpty && !nidSes.isEmpty {
                            request.setValue("NID_AUT=\(nidAut); NID_SES=\(nidSes)", forHTTPHeaderField: "Cookie")
                        }

                        guard let (data, response) = try? await URLSession.shared.data(for: request),
                              let http = response as? HTTPURLResponse,
                              (200...299).contains(http.statusCode),
                              let decoded = try? JSONDecoder().decode(CafeSearchResponse.self, from: data) else { return nil }

                        return decoded.result.articleList.map { container in
                            let item = container.item
                            let link = "\(desktopCafeURL)/\(item.articleId)"
                            return CafeArticle(
                                title: item.subject,
                                link: link,
                                cafeName: cafeName,
                                description: item.addDate,
                                menuId: String(item.menuId),
                                writerNickname: item.writerInfo?.nickname,
                                hasAttachment: item.attachFile ?? false
                            )
                        }
                    }
                }
                for await result in group {
                    if let result { allArticles.append(contentsOf: result) }
                }
            }

            guard self.activeToken == token else { return }
            self.isLoading = false

            // Deduplicate
            var merged: [String: CafeArticle] = [:]
            for art in allArticles { merged[art.link] = art }
            let deduped = Array(merged.values)

            // Filter by current year
            let yearFiltered = deduped.filter { article in
                guard let dateStr = article.description else { return true }
                // addDate format: "YYYY.MM.DD." or "YYYY-MM-DD" or just year prefix
                let yearStr = String(dateStr.prefix(4))
                if let y = Int(yearStr) { return y == currentYear }
                return true
            }

            if yearFiltered.isEmpty {
                self.errorMessage = "올해(\(String(currentYear))년) 제출한 게시글을 찾지 못했습니다."
                return
            }

            // Group by menuId
            var grouped: [String: [CafeArticle]] = [:]
            for art in yearFiltered {
                let key = art.menuId ?? "기타"
                grouped[key, default: []].append(art)
            }

            self.totalCount = yearFiltered.count
            self.groupedResults = grouped.map { (menuId, articles) in
                let sorted = articles.sorted {
                    let id1 = Int($0.link.components(separatedBy: "/").last ?? "") ?? 0
                    let id2 = Int($1.link.components(separatedBy: "/").last ?? "") ?? 0
                    return id1 > id2
                }
                let menuName = menuIdMap[menuId] ?? "게시판 \(menuId)"
                return SubmissionGroup(menuName: menuName, articles: sorted)
            }.sorted { $0.menuName < $1.menuName }
        }
    }
}

// MARK: - View

struct MySubmissionView: View {
    @Binding var isPresented: Bool
    let nidAut: String
    let nidSes: String
    let menuIdMap: [String: String]

    @AppStorage("savedUserName") private var savedUserName = ""

    @StateObject private var viewModel = MySubmissionViewModel()

    private var trimmedName: String { savedUserName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("내 제출 현황")
                        .font(.title2)
                        .fontWeight(.bold)
                    if !trimmedName.isEmpty {
                        Text("\(trimmedName) · \(String(Calendar.current.component(.year, from: Date())))년")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !viewModel.isLoading {
                    Button {
                        viewModel.load(userName: trimmedName, nidAut: nidAut, nidSes: nidSes, menuIdMap: menuIdMap)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("새로고침")
                }
                Button("닫기") { isPresented = false }
                    .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            if trimmedName.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("설정에서 내 이름을 먼저 입력해주세요")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("설정(⚙) → 내 이름 설정")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if viewModel.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.3)
                    Text("제출 내역을 검색하는 중...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if !viewModel.errorMessage.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(viewModel.errorMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if viewModel.groupedResults.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("조회 버튼을 눌러 제출 현황을 확인하세요")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                // Summary banner
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                        Text("총 \(viewModel.totalCount)개 게시판에 제출")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Text("\(String(Calendar.current.component(.year, from: Date())))년 기준")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.07))

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.groupedResults) { group in
                            SubmissionGroupCard(group: group)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 540, minHeight: 560)
        .onAppear {
            if !trimmedName.isEmpty && viewModel.groupedResults.isEmpty && !viewModel.isLoading {
                viewModel.load(userName: trimmedName, nidAut: nidAut, nidSes: nidSes, menuIdMap: menuIdMap)
            }
        }
    }
}

// MARK: - Group Card

struct SubmissionGroupCard: View {
    let group: MySubmissionViewModel.SubmissionGroup
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Text("\(group.count)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.menuName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("제출 \(group.count)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(group.articles) { article in
                        SubmissionArticleRow(article: article)
                        if article.id != group.articles.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.07), radius: 6, y: 3)
        )
    }
}

// MARK: - Article Row (Submission)

struct SubmissionArticleRow: View {
    let article: CafeArticle

    private func cleanHTML(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if let url = URL(string: article.link) {
            Link(destination: url) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue.opacity(0.7))
                        .font(.caption)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(cleanHTML(article.title))
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .lineLimit(1)

                        if let dateStr = article.description, !dateStr.isEmpty {
                            Text(dateStr)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if article.hasAttachment == true {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
