//
//  ContentView.swift
//  KAS
//
//  Created by 권민재 on 5/20/26.
//

import SwiftUI

struct CafeArticle: Identifiable, Codable, Sendable {
    let id = UUID()
    let title: String
    let link: String
    let cafeName: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case title
        case link
        case cafeName = "cafename"
        case description
    }
}

struct NaverSearchResponse: Codable, Sendable {
    let items: [CafeArticle]
}

struct ContentView: View {

    @AppStorage("savedUserName") private var userName = ""
    @State private var searchResults: [CafeArticle] = []
    @State private var isLoading = false
    @State private var errorMessage = ""

    // 네이버 개발자센터에서 받은 값으로 교체
    private let clientID = "25g1Mh3xBCX_IfHKM1Uw"
    private let clientSecret = "CCBos1_iG6"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                Text("KAS")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("현재 버전 : 0.1.0 (beta)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("이름 입력", text: $userName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !userName.isEmpty {
                            searchCafeArticles()
                        }
                    }

                Text("이름만 입력하면 최근 제출글을 자동으로 검색합니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    searchCafeArticles()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("과제 제출 확인")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(userName.isEmpty)

                if isLoading {
                    ProgressView()
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                List(searchResults) { article in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cleanHTML(article.title))
                            .font(.headline)

                        if let cafeName = article.cafeName {
                            Text(cafeName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let description = article.description {
                            Text(cleanHTML(description))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Link("게시글 열기", destination: URL(string: article.link)!)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("과제 체크")
        }
    }

    func searchCafeArticles() {

        isLoading = true
        errorMessage = ""
        searchResults = []

        let query = userName
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        guard let url = URL(string: "https://openapi.naver.com/v1/search/cafearticle.json?query=\(encodedQuery)&sort=date&display=30") else {
            errorMessage = "URL 생성 실패"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(clientID, forHTTPHeaderField: "X-Naver-Client-Id")
        request.setValue(clientSecret, forHTTPHeaderField: "X-Naver-Client-Secret")

        URLSession.shared.dataTask(with: request) { data, response, error in

                DispatchQueue.main.async {
                    isLoading = false
                }

            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    errorMessage = "데이터 없음"
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(NaverSearchResponse.self, from: data)

                DispatchQueue.main.async {

                    print("================ NAVER API RESPONSE ================")
                    print("📦 total items: \(decoded.items.count)")

                    let filtered = decoded.items.filter { article in
                        let cafeName = article.cafeName ?? ""

                        let containsCafe =
                            cafeName.lowercased().contains("계원디지털미디어디자인")

                        return containsCafe
                    }

                    print("✅ filtered items: \(filtered.count)")

                    for (index, article) in filtered.enumerated() {

                        print("\n================ RESULT \(index + 1) ================")
                        print("📄 title: \(cleanHTML(article.title))")
                        print("🏫 cafe: \(article.cafeName ?? "nil")")
                        print("📝 description: \(cleanHTML(article.description ?? "nil"))")
                        print("🔗 link: \(article.link)")
                    }

                    print("====================================================")

                    searchResults = filtered

                    if filtered.isEmpty {
                        errorMessage = "최근 제출 글을 찾지 못했습니다"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "JSON 파싱 실패"
                }
            }
        }.resume()
    }


    func cleanHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
    }
}

#Preview {
    ContentView()
}
