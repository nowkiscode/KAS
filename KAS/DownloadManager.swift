import Foundation
import AppKit
import WebKit
import Combine
import OSLog

// MARK: - API Response Models
nonisolated struct ArticleDetailResponse: Decodable, Sendable {
    let result: ArticleDetailResult
}
nonisolated struct ArticleDetailResult: Decodable, Sendable {
    let article: ArticleDetail
}
nonisolated struct ArticleDetail: Decodable, Sendable {
    let subject: String
    let attachFileList: [AttachFile]?
    let imageList: [ArticleImage]?
}
nonisolated struct AttachFile: Decodable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let url: String
}
nonisolated struct ArticleImage: Decodable, Sendable {
    let url: String?
    let org: String?
    var downloadURL: String? { org ?? url }
}

// MARK: - Download Status
enum DownloadStatus: Equatable {
    case idle
    case fetchingInfo
    case downloading(progress: Double)
    case done(count: Int)
    case error(String)
}

nonisolated struct DownloadAttemptResult: Sendable {
    let successCount: Int
    let lastErrorMessage: String?
}

@MainActor
class WebViewScraper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var activeContinuation: CheckedContinuation<[(name: String, url: URL)], Error>?
    private var retries = 0
    
    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        self.webView.navigationDelegate = self
    }
    
    enum ScraperError: Error, LocalizedError {
        case timeout
        case failed
        
        var errorDescription: String? {
            switch self {
            case .timeout: return "웹뷰 스크래핑 시간 초과"
            case .failed: return "웹뷰 스크래핑 실패"
            }
        }
    }
    
    func scrapeAttachments(url: URL, nidAut: String, nidSes: String) async throws -> [(name: String, url: URL)] {
        if let existing = activeContinuation {
            existing.resume(throwing: ScraperError.failed)
            activeContinuation = nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.activeContinuation = continuation
            self.retries = 10
            
            let dataStore = webView.configuration.websiteDataStore
            let autCookie = HTTPCookie(properties: [.domain: ".naver.com", .path: "/", .name: "NID_AUT", .value: nidAut, .secure: "TRUE"])!
            let sesCookie = HTTPCookie(properties: [.domain: ".naver.com", .path: "/", .name: "NID_SES", .value: nidSes, .secure: "TRUE"])!
            
            dataStore.httpCookieStore.setCookie(autCookie) {
                dataStore.httpCookieStore.setCookie(sesCookie) {
                    DispatchQueue.main.async {
                        self.webView.load(URLRequest(url: url))
                    }
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollDOM()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeContinuation(throwing: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeContinuation(throwing: error)
    }
    
    private func resumeContinuation(returning value: [(name: String, url: URL)]) {
        activeContinuation?.resume(returning: value)
        activeContinuation = nil
    }
    
    private func resumeContinuation(throwing error: Error) {
        activeContinuation?.resume(throwing: error)
        activeContinuation = nil
    }
    
    private func pollDOM() {
        let script = """
        (() => {
          const candidates = [];
          const roots = [document];
          const frames = Array.from(document.querySelectorAll('iframe'));
          for (const frame of frames) {
            try {
              if (frame.contentDocument) roots.push(frame.contentDocument);
            } catch (_) {}
          }
          for (const root of roots) {
            const buttons = root.querySelectorAll('a.se-file-save-button, a[href*="downapi.cafe.naver.com/v1.0/cafes/article/file"]');
            for (const btn of buttons) {
              const url = btn.getAttribute('href') || btn.dataset.link;
              if (!url) continue;
              let name = "attachment";
              const container = btn.closest('div[class*="se-file"], div[class*="se-module-file"], div[class*="file_box"], div[class*="Attachment"]') || btn.parentElement;
              if (container) {
                const nameEl = container.querySelector('.se-file-name, .file_name, strong, span.name');
                if (nameEl && nameEl.textContent.trim()) {
                  name = nameEl.textContent.trim();
                } else {
                    let containerText = container.textContent.replace(btn.textContent, '').replace(/\\s+/g, ' ').trim();
                    if (containerText.length > 0 && containerText.length < 100) {
                        name = containerText;
                    }
                }
              }
              candidates.push({ name: name, url: url });
            }
          }
          return JSON.stringify(candidates);
        })();
        """
        
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self, self.activeContinuation != nil else { return }
            
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                let files: [(name: String, url: URL)] = items.compactMap { dict in
                    guard let name = dict["name"], let urlStr = dict["url"], let url = URL(string: urlStr) else { return nil }
                    return (name: name, url: url)
                }
                if !files.isEmpty {
                    self.resumeContinuation(returning: files)
                    return
                }
            }
            
            if self.retries > 0 {
                self.retries -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.pollDOM()
                }
            } else {
                self.resumeContinuation(returning: [])
            }
        }
    }
}

// MARK: - DownloadManager
@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KAS", category: "Download")
    private let scraper = WebViewScraper()

    @Published var statusByArticle: [String: DownloadStatus] = [:]
    @Published var batchStatus: DownloadStatus = .idle
    @Published var batchProgress: Double = 0.0
    @Published var downloadedArticleIds: Set<String> = []

    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var batchTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "downloadedArticles"),
           let set = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.downloadedArticleIds = set
        }
    }

    private func saveDownloadedIds() {
        if let data = try? JSONEncoder().encode(downloadedArticleIds) {
            UserDefaults.standard.set(data, forKey: "downloadedArticles")
        }
    }

    // MARK: - Public Interface

    func downloadArticle(_ article: CafeArticle, studentName: String, nidAut: String, nidSes: String) {
        guard statusByArticle[article.link] == nil || statusByArticle[article.link] == .idle else { return }
        guard let articleId = articleId(from: article.link) else {
            statusByArticle[article.link] = .error("게시글 ID를 찾을 수 없습니다")
            return
        }

        statusByArticle[article.link] = .fetchingInfo
        
        let task = Task {
            do {
                try Task.checkCancellation()
                let files = try await fetchAttachments(articleId: articleId, nidAut: nidAut, nidSes: nidSes)
                if files.isEmpty {
                    self.statusByArticle[article.link] = .error("이 게시글에는 내려받을 첨부파일이 없거나 권한이 없습니다")
                    self.activeTasks.removeValue(forKey: article.link)
                    return
                }
                
                try Task.checkCancellation()
                let destDir = self.createAndGetDownloadsDir(for: studentName)
                let result = await self.downloadFiles(files, to: destDir, progressKey: article.link, nidAut: nidAut, nidSes: nidSes)
                
                if result.successCount == 0 {
                    self.statusByArticle[article.link] = .error(result.lastErrorMessage ?? "다운로드에 실패했습니다")
                } else {
                    self.downloadedArticleIds.insert(articleId)
                    self.saveDownloadedIds()
                }
            } catch is CancellationError {
                self.statusByArticle[article.link] = .idle
            } catch {
                self.statusByArticle[article.link] = .error(error.localizedDescription)
            }
            self.activeTasks.removeValue(forKey: article.link)
        }
        activeTasks[article.link] = task
    }

    func downloadAll(articles: [CafeArticle], studentName: String, nidAut: String, nidSes: String) {
        guard batchStatus == .idle else { return }
        batchStatus = .fetchingInfo
        batchProgress = 0.0
        let destDir = getDownloadsDirURL(for: studentName) // 실제 폴더 생성은 나중에 수행

        let task = Task {
            let total = articles.count
            guard total > 0 else {
                self.batchStatus = .error("다운로드할 게시글이 없습니다")
                self.batchTask = nil
                return
            }
            
            var completed = 0
            var downloadedArticles = 0
            var lastErrorMsg: String?

            for article in articles {
                if Task.isCancelled { break }
                guard let articleId = articleId(from: article.link) else {
                    completed += 1
                    self.batchProgress = Double(completed) / Double(total)
                    continue
                }

                do {
                    let files = try await fetchAttachments(articleId: articleId, nidAut: nidAut, nidSes: nidSes)
                    if Task.isCancelled { break }
                    if !files.isEmpty {
                        // 실제로 다운로드할 파일이 있을 때만 폴더 생성
                        _ = self.createAndGetDownloadsDir(for: studentName)
                        
                        let result = await self.downloadFiles(files, to: destDir, progressKey: nil, nidAut: nidAut, nidSes: nidSes)
                        if result.successCount > 0 {
                            downloadedArticles += 1
                            self.downloadedArticleIds.insert(articleId)
                            self.saveDownloadedIds()
                        } else {
                            lastErrorMsg = result.lastErrorMessage
                        }
                    } else {
                        lastErrorMsg = "빈 파일 목록"
                    }
                } catch {
                    lastErrorMsg = error.localizedDescription
                }
                
                completed += 1
                self.batchProgress = Double(completed) / Double(total)
                self.batchStatus = .downloading(progress: Double(completed) / Double(total))
            }

            if Task.isCancelled {
                self.batchStatus = .idle
            } else if downloadedArticles > 0 {
                self.batchStatus = .done(count: downloadedArticles)
                NSWorkspace.shared.open(destDir)
            } else {
                self.batchStatus = .error(lastErrorMsg ?? "다운로드된 파일이 없습니다")
            }
            self.batchTask = nil
        }
        batchTask = task
    }

    func resetBatch() {
        batchStatus = .idle
        batchProgress = 0.0
    }

    func cancelBatch() {
        batchTask?.cancel()
        batchTask = nil
    }

    func resetArticle(link: String) {
        statusByArticle[link] = .idle
    }

    func cancelArticle(link: String) {
        activeTasks[link]?.cancel()
        activeTasks.removeValue(forKey: link)
        statusByArticle[link] = .idle
    }

    func openDownloadsDir(for studentName: String) {
        let dir = getDownloadsDirURL(for: studentName)
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        } else {
            // 폴더가 없으면 상위 KAS 폴더를 엽니다
            let baseDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("KAS")
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(baseDir)
        }
    }

    // MARK: - Private Helpers
    private func articleId(from link: String) -> String? { link.components(separatedBy: "/").last }

    private func getDownloadsDirURL(for studentName: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let safeStudentName = sanitizedDirectoryName(from: studentName)
        return downloads.appendingPathComponent("KAS").appendingPathComponent(safeStudentName)
    }

    private func createAndGetDownloadsDir(for studentName: String) -> URL {
        let dir = getDownloadsDirURL(for: studentName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fetchAttachments(articleId: String, nidAut: String, nidSes: String) async throws -> [(name: String, url: URL)] {
        let urlString = "https://apis.naver.com/cafe-web/cafe-articleapi/v2.1/cafes/\(NaverCafeConfig.cafeId)/articles/\(articleId)?useCafeId=true"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue(NaverCafeConfig.mobileCafeURL, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")

        let cookies = await fetchAllCookies()
        var cookieValues = ["NID_AUT=\(nidAut)", "NID_SES=\(nidSes)"]
        for cookie in cookies where cookie.name != "NID_AUT" && cookie.name != "NID_SES" {
            cookieValues.append("\(cookie.name)=\(cookie.value)")
        }
        request.setValue(cookieValues.joined(separator: "; "), forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                self.logger.info("API 401 for article \(articleId, privacy: .public). Fallback to scraper.")
                let fallbackURL = URL(string: "https://m.cafe.naver.com/\(NaverCafeConfig.cafeSlug)/\(articleId)")!
                return try await scraper.scrapeAttachments(url: fallbackURL, nidAut: nidAut, nidSes: nidSes)
            } else if !(200...299).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
        }

        let decoded = try JSONDecoder().decode(ArticleDetailResponse.self, from: data)
        var files: [(name: String, url: URL)] = []
        for file in decoded.result.article.attachFileList ?? [] {
            if let fileURL = URL(string: file.url) {
                files.append((name: file.name, url: fileURL))
            }
        }

        if files.isEmpty {
            self.logger.info("API 200 but no files for \(articleId, privacy: .public). Fallback to scraper.")
            let fallbackURL = URL(string: "https://m.cafe.naver.com/\(NaverCafeConfig.cafeSlug)/\(articleId)")!
            return try await scraper.scrapeAttachments(url: fallbackURL, nidAut: nidAut, nidSes: nidSes)
        }

        return files
    }

    private func downloadFiles(_ files: [(name: String, url: URL)], to dir: URL, progressKey: String?, nidAut: String, nidSes: String) async -> DownloadAttemptResult {
        if let key = progressKey {
            statusByArticle[key] = .downloading(progress: 0)
        }

        let total = files.count
        var successCount = 0
        var lastErrorMessage: String?
        
        let allCookies = await fetchAllCookies()
        var cookieValues = ["NID_AUT=\(nidAut)", "NID_SES=\(nidSes)"]
        for cookie in allCookies where cookie.name != "NID_AUT" && cookie.name != "NID_SES" {
            cookieValues.append("\(cookie.name)=\(cookie.value)")
        }
        let fullCookieString = cookieValues.joined(separator: "; ")

        for (idx, file) in files.enumerated() {
            var request = URLRequest(url: file.url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue(NaverCafeConfig.mobileCafeURL, forHTTPHeaderField: "Referer")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")
            request.setValue(fullCookieString, forHTTPHeaderField: "Cookie")

            do {
                let (tempURL, response) = try await URLSession.shared.download(for: request)
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    lastErrorMessage = "HTTP \(httpResponse.statusCode)"
                    try? FileManager.default.removeItem(at: tempURL)
                    continue
                }

                var finalName = file.name
                if let httpResponse = response as? HTTPURLResponse,
                   let header = httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? httpResponse.allHeaderFields["Content-Disposition"] as? String {
                    if let filenameRange = header.range(of: "filename=\"") {
                        let rest = header[filenameRange.upperBound...]
                        if let endQuote = rest.firstIndex(of: "\"") {
                            let name = String(rest[..<endQuote])
                            if !name.isEmpty { finalName = name }
                        }
                    } else if let filenameUtf8Range = header.range(of: "filename*=UTF-8''") {
                        let name = String(header[filenameUtf8Range.upperBound...])
                        if let decodedName = name.removingPercentEncoding, !decodedName.isEmpty {
                            finalName = decodedName
                        }
                    }
                }
                
                let destURL = dir.appendingPathComponent(finalName)
                let finalURL = uniqueURL(for: destURL)
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
                successCount += 1

                let progress = Double(idx + 1) / Double(total)
                if let key = progressKey {
                    statusByArticle[key] = .downloading(progress: progress)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        if let key = progressKey {
            statusByArticle[key] = successCount > 0 ? .done(count: successCount) : .error(lastErrorMessage ?? "다운로드 실패")
            if successCount > 0 { NSWorkspace.shared.open(dir) }
        }

        return DownloadAttemptResult(successCount: successCount, lastErrorMessage: lastErrorMessage)
    }
    
    private func fetchAllCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }
    }

    private func uniqueURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var counter = 1
        var candidate: URL
        repeat {
            let newName = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    private func sanitizedDirectoryName(from name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Student" : trimmed
    }
}
