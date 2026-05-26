//
//  DownloadManager.swift
//  KAS
//

import Foundation
import AppKit
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
    let contentHtml: String?
}

nonisolated struct AttachFile: Decodable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let url: String
}

nonisolated struct ArticleImage: Decodable, Sendable {
    let url: String?
    let org: String?
    // 이미지 다운로드용 URL 반환 (org 우선)
    var downloadURL: String? { org ?? url }
}

// MARK: - Download Status

enum DownloadStatus: Equatable {
    case idle
    case fetchingInfo    // 게시글 첨부파일 정보 조회 중
    case downloading(progress: Double)  // 다운로드 진행 중 (0.0~1.0)
    case done(count: Int)   // 완료
    case error(String)
}

nonisolated struct DownloadAttemptResult: Sendable {
    let successCount: Int
    let lastErrorMessage: String?
}

nonisolated struct AttachmentFetchResult: Sendable {
    let files: [(name: String, url: URL)]
    let errorMessage: String?
}

// MARK: - DownloadManager

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "KAS", category: "Download")

    @Published var statusByArticle: [String: DownloadStatus] = [:]  // key: article link
    @Published var batchStatus: DownloadStatus = .idle
    @Published var batchProgress: Double = 0.0

    // MARK: - Public Interface

    /// 단일 게시글 첨부파일 다운로드
    func downloadArticle(_ article: CafeArticle, studentName: String, nidAut: String, nidSes: String) {
        logger.info("Starting single download for article: \(article.link, privacy: .public)")
        guard statusByArticle[article.link] == nil || statusByArticle[article.link] == .idle else { return }

        guard let articleId = articleId(from: article.link) else {
            statusByArticle[article.link] = .error("게시글 ID를 찾을 수 없습니다")
            return
        }

        statusByArticle[article.link] = .fetchingInfo
        fetchAttachments(articleId: articleId, nidAut: nidAut, nidSes: nidSes) { [weak self] result in
            guard let self = self else { return }
            Task { @MainActor in
                if result.files.isEmpty {
                    self.logger.error("Attachment lookup failed for article \(article.link, privacy: .public): \(result.errorMessage ?? "unknown error", privacy: .public)")
                    self.statusByArticle[article.link] = .error(result.errorMessage ?? "첨부파일 또는 이미지가 없습니다")
                    return
                }
                self.logger.info("Attachment lookup succeeded for article \(article.link, privacy: .public), file count: \(result.files.count)")
                let destDir = self.downloadsDir(for: studentName)
                let result = await self.downloadFiles(
                    result.files,
                    to: destDir,
                    progressKey: article.link,
                    nidAut: nidAut,
                    nidSes: nidSes
                )

                if result.successCount == 0 {
                    self.logger.error("Single download failed for article \(article.link, privacy: .public): \(result.lastErrorMessage ?? "unknown error", privacy: .public)")
                    self.statusByArticle[article.link] = .error(result.lastErrorMessage ?? "다운로드에 실패했습니다")
                } else {
                    self.logger.info("Single download completed for article \(article.link, privacy: .public), success count: \(result.successCount)")
                }
            }
        }
    }

    /// 일괄 다운로드
    func downloadAll(articles: [CafeArticle], studentName: String, nidAut: String, nidSes: String) {
        logger.info("Starting batch download, article count: \(articles.count)")
        guard batchStatus == .idle else { return }
        batchStatus = .fetchingInfo
        batchProgress = 0.0

        let destDir = downloadsDir(for: studentName)

        Task {
            let total = articles.count
            guard total > 0 else {
                await MainActor.run {
                    self.batchStatus = .error("다운로드할 게시글이 없습니다")
                }
                return
            }
            var completed = 0
            var downloadedArticles = 0

            for article in articles {
                guard let articleId = articleId(from: article.link) else {
                    completed += 1
                    await MainActor.run {
                        self.batchProgress = Double(completed) / Double(total)
                    }
                    continue
                }

                await withCheckedContinuation { continuation in
                    fetchAttachments(articleId: articleId, nidAut: nidAut, nidSes: nidSes) { result in
                        Task {
                            var batchErrorMessage = result.errorMessage
                            if !result.files.isEmpty {
                                self.logger.info("Batch attachment lookup succeeded for article \(article.link, privacy: .public), file count: \(result.files.count)")
                                let result = await self.downloadFiles(
                                    result.files,
                                    to: destDir,
                                    progressKey: nil,
                                    nidAut: nidAut,
                                    nidSes: nidSes
                                )
                                if result.successCount > 0 {
                                    downloadedArticles += 1
                                    self.logger.info("Batch download succeeded for article \(article.link, privacy: .public), success count: \(result.successCount)")
                                } else if batchErrorMessage == nil {
                                    batchErrorMessage = result.lastErrorMessage
                                    self.logger.error("Batch download failed for article \(article.link, privacy: .public): \(result.lastErrorMessage ?? "unknown error", privacy: .public)")
                                }
                            } else {
                                self.logger.error("Batch attachment lookup failed for article \(article.link, privacy: .public): \(result.errorMessage ?? "unknown error", privacy: .public)")
                            }
                            completed += 1
                            await MainActor.run {
                                self.batchProgress = Double(completed) / Double(total)
                                self.batchStatus = .downloading(progress: Double(completed) / Double(total))
                                if completed == total && downloadedArticles == 0 {
                                    self.batchStatus = .error(batchErrorMessage ?? "다운로드된 파일이 없습니다")
                                }
                            }
                            continuation.resume()
                        }
                    }
                }
            }

            await MainActor.run {
                if downloadedArticles > 0 {
                    self.batchStatus = .done(count: downloadedArticles)
                    self.logger.info("Batch download completed, downloaded articles: \(downloadedArticles)")
                    // Finder에서 폴더 열기
                    NSWorkspace.shared.open(destDir)
                } else if case .error = self.batchStatus {
                    self.logger.error("Batch download ended with detailed error state")
                    // keep detailed error from the last attempt
                } else {
                    self.logger.error("Batch download failed with no downloaded files")
                    self.batchStatus = .error("다운로드된 파일이 없습니다")
                }
            }
        }
    }

    func resetBatch() {
        batchStatus = .idle
        batchProgress = 0.0
    }

    func resetArticle(link: String) {
        statusByArticle[link] = .idle
    }

    // MARK: - Private Helpers

    private func articleId(from link: String) -> String? {
        link.components(separatedBy: "/").last
    }

    private func downloadsDir(for studentName: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let safeStudentName = sanitizedDirectoryName(from: studentName)
        let dir = downloads.appendingPathComponent("KAS").appendingPathComponent(safeStudentName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 게시글 상세 API 호출 → 첨부파일 URL 목록 반환
    private func fetchAttachments(articleId: String, nidAut: String, nidSes: String,
                                  completion: @escaping (AttachmentFetchResult) -> Void) {
        let urlString = "https://apis.naver.com/cafe-web/cafe-articleapi/v2.1/cafes/\(NaverCafeConfig.cafeId)/articles/\(articleId)?useCafeId=true"
        guard let url = URL(string: urlString) else {
            logger.error("Failed to build attachment URL for article id: \(articleId, privacy: .public)")
            completion(AttachmentFetchResult(files: [], errorMessage: "게시글 상세 URL 생성에 실패했습니다"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue(NaverCafeConfig.mobileCafeURL, forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")
        request.setValue("NID_AUT=\(nidAut); NID_SES=\(nidSes)", forHTTPHeaderField: "Cookie")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                let message = (error as NSError?)?.localizedDescription ?? "게시글 상세 정보를 불러오지 못했습니다"
                self.logger.error("Attachment request failed for article id \(articleId, privacy: .public): \(message, privacy: .public)")
                completion(AttachmentFetchResult(files: [], errorMessage: message))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                self.logger.error("Attachment request rejected for article id \(articleId, privacy: .public), status: \(httpResponse.statusCode)")
                completion(AttachmentFetchResult(files: [], errorMessage: "첨부 정보 요청이 거부되었습니다 (HTTP \(httpResponse.statusCode))"))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ArticleDetailResponse.self, from: data)
                let article = decoded.result.article
                var files: [(name: String, url: URL)] = []

                // 첨부파일
                for file in article.attachFileList ?? [] {
                    if let fileURL = URL(string: file.url) {
                        files.append((name: file.name, url: fileURL))
                    }
                }

                // 이미지 (첨부파일이 없을 경우 폴백)
                if files.isEmpty {
                    for (idx, img) in (article.imageList ?? []).enumerated() {
                        if let urlStr = img.downloadURL, let imgURL = URL(string: urlStr) {
                            let ext = (urlStr as NSString).pathExtension.isEmpty ? "jpg" : (urlStr as NSString).pathExtension
                            files.append((name: "image_\(idx + 1).\(ext)", url: imgURL))
                        }
                    }
                }

                if files.isEmpty, let contentHtml = article.contentHtml {
                    let htmlFiles = self.extractFilesFromHTML(contentHtml)
                    if !htmlFiles.isEmpty {
                        self.logger.info("Recovered \(htmlFiles.count) downloadable file(s) from contentHtml for article id \(articleId, privacy: .public)")
                        files.append(contentsOf: htmlFiles)
                    }
                }

                let errorMessage = files.isEmpty ? "이 게시글에는 내려받을 첨부파일이 없거나 권한이 없습니다" : nil
                if let errorMessage {
                    self.logger.error("No downloadable files found for article id \(articleId, privacy: .public): \(errorMessage, privacy: .public)")
                }
                completion(AttachmentFetchResult(files: files, errorMessage: errorMessage))
            } catch {
                self.logger.error("Failed to decode attachment response for article id \(articleId, privacy: .public)")
                completion(AttachmentFetchResult(files: [], errorMessage: "첨부 정보를 해석하지 못했습니다"))
            }
        }.resume()
    }

    /// 파일 목록을 지정 디렉토리에 순차 다운로드
    private func downloadFiles(
        _ files: [(name: String, url: URL)],
        to dir: URL,
        progressKey: String?,
        nidAut: String,
        nidSes: String
    ) async -> DownloadAttemptResult {
        await MainActor.run {
            if let key = progressKey {
                statusByArticle[key] = .downloading(progress: 0)
            }
        }

        let total = files.count
        var successCount = 0
        var lastErrorMessage: String?
        for (idx, file) in files.enumerated() {
            var request = URLRequest(url: file.url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue(NaverCafeConfig.mobileCafeURL, forHTTPHeaderField: "Referer")
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")
            request.setValue("NID_AUT=\(nidAut); NID_SES=\(nidSes)", forHTTPHeaderField: "Cookie")
            logger.info("Downloading file \(file.name, privacy: .public) from \(file.url.absoluteString, privacy: .public)")

            do {
                let (tempURL, response) = try await URLSession.shared.download(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    lastErrorMessage = "파일 요청이 거부되었습니다 (HTTP \(httpResponse.statusCode))"
                    logger.error("File download rejected for \(file.name, privacy: .public), status: \(httpResponse.statusCode), url: \(file.url.absoluteString, privacy: .public)")
                    try? FileManager.default.removeItem(at: tempURL)
                    continue
                }

                let destURL = dir.appendingPathComponent(file.name)

                // 덮어쓰기 방지: 같은 이름 파일이 있으면 숫자 붙임
                let finalURL = uniqueURL(for: destURL)
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
                successCount += 1
                logger.info("Saved file \(file.name, privacy: .public) to \(finalURL.path, privacy: .public)")

                let progress = Double(idx + 1) / Double(total)
                await MainActor.run {
                    if let key = progressKey {
                        statusByArticle[key] = .downloading(progress: progress)
                    }
                }
            } catch {
                let nsError = error as NSError
                lastErrorMessage = nsError.localizedDescription
                logger.error("File download failed for \(file.name, privacy: .public), url: \(file.url.absoluteString, privacy: .public), error: \(nsError.localizedDescription, privacy: .public)")
            }
        }

        await MainActor.run {
            if let key = progressKey {
                statusByArticle[key] = successCount > 0 ? .done(count: successCount) : .error(lastErrorMessage ?? "다운로드에 실패했습니다")
                if successCount > 0 {
                    // 완료 시 Finder 열기
                    NSWorkspace.shared.open(dir)
                }
            }
        }

        return DownloadAttemptResult(successCount: successCount, lastErrorMessage: lastErrorMessage)
    }

    /// 같은 이름 파일 존재 시 _1, _2 등 붙여 고유 URL 생성
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

    private func extractFilesFromHTML(_ html: String) -> [(name: String, url: URL)] {
        var files: [(name: String, url: URL)] = []
        var seenURLs = Set<String>()

        let imageMatches = matches(
            pattern: #"<img[^>]+(?:data-src|src)=["']([^"']+)["']"#,
            in: html
        )

        for (index, urlString) in imageMatches.enumerated() {
            guard let normalizedURL = normalizedDownloadURL(from: urlString),
                  seenURLs.insert(normalizedURL.absoluteString).inserted else {
                continue
            }

            let ext = normalizedURL.pathExtension.isEmpty ? "jpg" : normalizedURL.pathExtension
            files.append((name: "content_image_\(index + 1).\(ext)", url: normalizedURL))
        }

        let linkMatches = matches(
            pattern: #"<a[^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#,
            in: html,
            captureGroup: 1
        )

        for urlString in linkMatches {
            guard let normalizedURL = normalizedDownloadURL(from: urlString),
                  seenURLs.insert(normalizedURL.absoluteString).inserted else {
                continue
            }

            let fileName = inferredFileName(from: normalizedURL)
            files.append((name: fileName, url: normalizedURL))
        }

        return files
    }

    private func matches(pattern: String, in text: String, captureGroup: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup,
                  let captureRange = Range(match.range(at: captureGroup), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    private func normalizedDownloadURL(from rawURL: String) -> URL? {
        let decoded = rawURL
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")

        guard decoded.hasPrefix("http://") || decoded.hasPrefix("https://") else {
            return nil
        }

        return URL(string: decoded)
    }

    private func inferredFileName(from url: URL) -> String {
        let lastPath = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if !lastPath.isEmpty, lastPath != "/" {
            return lastPath
        }

        return "attachment"
    }
}
