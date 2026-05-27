//
//  ArticleRowView.swift
//  KAS
//

import SwiftUI

struct ArticleRowView: View {
    let article: CafeArticle
    let menuName: String
    @ObservedObject var downloadManager: DownloadManager
    let studentName: String
    let nidAut: String
    let nidSes: String
    
    var body: some View {
        if let url = URL(string: article.link) {
            HStack(alignment: .top, spacing: 8) {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cleanHTML(article.title))
                            .font(.headline)
                            .foregroundStyle(.blue)
                        
                        let articleId = article.link.components(separatedBy: "/").last ?? ""
                        if downloadManager.downloadedArticleIds.contains(articleId) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("이전에 다운로드 완료됨")
                            }
                            .font(.caption2)
                            .foregroundStyle(.green)
                        }

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
                            
                            if article.menuId != nil {
                                Text(menuName)
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

                let status = downloadManager.statusByArticle[article.link] ?? .idle
                VStack {
                    switch status {
                    case .idle:
                        Button {
                            downloadManager.downloadArticle(
                                article,
                                studentName: studentName,
                                nidAut: nidAut, nidSes: nidSes
                            )
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.title2)
                                .foregroundStyle(nidAut.isEmpty ? .gray : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(nidAut.isEmpty || nidSes.isEmpty || studentName.isEmpty)
                    case .fetchingInfo:
                        Button {
                            downloadManager.cancelArticle(link: article.link)
                        } label: {
                            Image(systemName: "stop.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    case .downloading(let p):
                        VStack(spacing: 2) {
                            Button {
                                downloadManager.cancelArticle(link: article.link)
                            } label: {
                                Image(systemName: "stop.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
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
    
    private func cleanHTML(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let unescaped = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        return unescaped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
