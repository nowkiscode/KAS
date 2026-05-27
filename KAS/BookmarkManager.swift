//
//  BookmarkManager.swift
//  KAS
//

import Foundation
import SwiftUI
import Combine

@MainActor
class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    @Published var bookmarkedArticles: [CafeArticle] = []

    private let storageKey = "bookmarkedArticles"

    init() {
        load()
    }

    // MARK: - Public API

    func toggle(article: CafeArticle) {
        if let idx = bookmarkedArticles.firstIndex(where: { $0.link == article.link }) {
            bookmarkedArticles.remove(at: idx)
        } else {
            bookmarkedArticles.insert(article, at: 0)
        }
        save()
    }

    func isBookmarked(_ article: CafeArticle) -> Bool {
        bookmarkedArticles.contains(where: { $0.link == article.link })
    }

    func remove(article: CafeArticle) {
        bookmarkedArticles.removeAll { $0.link == article.link }
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarkedArticles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let articles = try? JSONDecoder().decode([CafeArticle].self, from: data) {
            bookmarkedArticles = articles
        }
    }
}
