//
//  DownloadManager.swift
//  KAS
//

import Foundation
import AppKit
import Combine

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

// MARK: - DownloadManager

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var statusByArticle: [String: DownloadStatus] = [:]  // key: article link
    @Published var batchStatus: DownloadStatus = .idle
    @Published var batchProgress: Double = 0.0

    private let cafeId = "28411094"

    // MARK: - Public Interface

    /// 단일 게시글 첨부파일 다운로드
    func downloadArticle(_ article: CafeArticle, studentName: String, nidAut: String, nidSes: String) {
        guard statusByArticle[article.link] == nil || statusByArticle[article.link] == .idle else { return }

        guard let articleId = articleId(from: article.link) else {
            statusByArticle[article.link] = .error("게시글 ID를 찾을 수 없습니다")
            return
        }

        statusByArticle[article.link] = .fetchingInfo
        fetchAttachments(articleId: articleId, nidAut: nidAut, nidSes: nidSes) { [weak self] files in
            guard let self = self else { return }
            Task { @MainActor in
                if files.isEmpty {
                    self.statusByArticle[article.link] = .done(count: 0)
                    return
                }
                let destDir = self.downloadsDir(for: studentName)
                await self.downloadFiles(files, to: destDir, progressKey: article.link)
            }
        }
    }

    /// 일괄 다운로드
    func downloadAll(articles: [CafeArticle], studentName: String, nidAut: String, nidSes: String) {
        guard batchStatus == .idle else { return }
        batchStatus = .fetchingInfo
        batchProgress = 0.0

        let destDir = downloadsDir(for: studentName)

        Task {
            let total = articles.count
            var completed = 0

            for article in articles {
                guard let articleId = articleId(from: article.link) else {
                    completed += 1
                    await MainActor.run {
                        self.batchProgress = Double(completed) / Double(total)
                    }
                    continue
                }

                await withCheckedContinuation { continuation in
                    fetchAttachments(articleId: articleId, nidAut: nidAut, nidSes: nidSes) { files in
                        Task {
                            if !files.isEmpty {
                                await self.downloadFiles(files, to: destDir, progressKey: nil)
                            }
                            completed += 1
                            await MainActor.run {
                                self.batchProgress = Double(completed) / Double(total)
                                self.batchStatus = .downloading(progress: Double(completed) / Double(total))
                            }
                            continuation.resume()
                        }
                    }
                }
            }

            await MainActor.run {
                self.batchStatus = .done(count: total)
                // Finder에서 폴더 열기
                NSWorkspace.shared.open(destDir)
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
        let dir = downloads.appendingPathComponent("KAS").appendingPathComponent(studentName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 게시글 상세 API 호출 → 첨부파일 URL 목록 반환
    private func fetchAttachments(articleId: String, nidAut: String, nidSes: String,
                                  completion: @escaping ([(name: String, url: URL)]) -> Void) {
        let urlString = "https://apis.naver.com/cafe-web/cafe-articleapi/v2.1/cafes/\(cafeId)/articles/\(articleId)?useCafeId=true"
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.cafe.naver.com/kwdmd", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("mobile", forHTTPHeaderField: "X-Cafe-Product")
        request.setValue("NID_AUT=\(nidAut); NID_SES=\(nidSes)", forHTTPHeaderField: "Cookie")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion([])
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

                completion(files)
            } catch {
                completion([])
            }
        }.resume()
    }

    /// 파일 목록을 지정 디렉토리에 순차 다운로드
    private func downloadFiles(_ files: [(name: String, url: URL)], to dir: URL, progressKey: String?) async {
        await MainActor.run {
            if let key = progressKey {
                statusByArticle[key] = .downloading(progress: 0)
            }
        }

        let total = files.count
        for (idx, file) in files.enumerated() {
            var request = URLRequest(url: file.url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("https://cafe.naver.com/kwdmd", forHTTPHeaderField: "Referer")

            do {
                let (tempURL, _) = try await URLSession.shared.download(for: request)
                let destURL = dir.appendingPathComponent(file.name)

                // 덮어쓰기 방지: 같은 이름 파일이 있으면 숫자 붙임
                let finalURL = uniqueURL(for: destURL)
                try FileManager.default.moveItem(at: tempURL, to: finalURL)

                let progress = Double(idx + 1) / Double(total)
                await MainActor.run {
                    if let key = progressKey {
                        statusByArticle[key] = .downloading(progress: progress)
                    }
                }
            } catch {
                // 개별 파일 실패는 무시하고 계속
            }
        }

        await MainActor.run {
            if let key = progressKey {
                statusByArticle[key] = .done(count: total)
                // 완료 시 Finder 열기
                NSWorkspace.shared.open(dir)
            }
        }
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
}
