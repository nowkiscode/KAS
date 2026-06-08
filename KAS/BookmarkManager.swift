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

// MARK: - Board Bookmark

struct BoardBookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    let menuId: String
    let menuName: String
    var dateAdded: Date
}

@MainActor
class BoardBookmarkManager: ObservableObject {
    static let shared = BoardBookmarkManager()
    
    @Published var bookmarks: [BoardBookmark] = []
    
    private let userDefaultsKey = "savedBoardBookmarks"
    
    private init() {
        loadBookmarks()
    }
    
    func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([BoardBookmark].self, from: data) {
            self.bookmarks = decoded
        }
    }
    
    func saveBookmarks() {
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    func addBookmark(menuId: String, menuName: String) {
        if !bookmarks.contains(where: { $0.menuId == menuId }) {
            let newBookmark = BoardBookmark(menuId: menuId, menuName: menuName, dateAdded: Date())
            bookmarks.append(newBookmark)
            saveBookmarks()
        }
    }
    
    func removeBookmark(menuId: String) {
        bookmarks.removeAll { $0.menuId == menuId }
        saveBookmarks()
    }
}
