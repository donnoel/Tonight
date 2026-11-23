import Foundation

struct AppleTVMovieLinkQuery: Hashable, Sendable {
    let title: String
    let year: Int?
    var alternateTitles: [String] = []

    var titles: [String] { [title] + alternateTitles }
}

struct AppleTVMovieLinkCandidate: Sendable {
    let title: String
    let year: Int?
    let url: URL
}

/// Looks up an Apple display page for an already-owned movie, never ownership or playback rights.
actor AppleTVMovieLinkResolver {
    static let shared = AppleTVMovieLinkResolver(catalogURLs: { title in
        await AppleTVPublicMovieCatalog.shared.urls(for: title)
    })
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let cachedDeals: @Sendable () async -> [CachedMovieDeal]
    private let catalogURLs: @Sendable (String) async -> [URL]
    private var links: [AppleTVMovieLinkQuery: URL] = [:]

    init(
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        },
        cachedDeals: @escaping @Sendable () async -> [CachedMovieDeal] = {
            MovieDealsCache().load()?.items ?? []
        },
        catalogURLs: @escaping @Sendable (String) async -> [URL] = { _ in [] }
    ) {
        self.transport = transport
        self.cachedDeals = cachedDeals
        self.catalogURLs = catalogURLs
    }

    func link(for query: AppleTVMovieLinkQuery) async throws -> URL? {
        guard query.year != nil else { return nil }
        if let cached = links[query] { return cached }
        let deals = await cachedDeals()
        try Task.checkCancellation()
        let known = deals.map {
            AppleTVMovieLinkCandidate(title: $0.appleDeal.title, year: $0.releaseYear, url: $0.appleDeal.appleURL)
        }
        if let url = Self.match(query, candidates: known) {
            remember(url, for: query)
            return url
        }

        var components = URLComponents(string: "https://tv.apple.com/us/search")!
        components.queryItems = [URLQueryItem(name: "term", value: query.title)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let matched: URL?
        if let exact = try await catalogMatch(for: query) {
            matched = exact
        } else {
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  let html = String(data: data, encoding: .utf8) else { return nil }
            matched = Self.match(query, candidates: (try? Self.candidates(in: html)) ?? [])
        }
        if let matched { remember(matched, for: query) }
        return matched
    }

    private func catalogMatch(for query: AppleTVMovieLinkQuery) async throws -> URL? {
        var urls = Set<URL>()
        for title in query.titles {
            let candidates = await catalogURLs(title)
            urls.formUnion(candidates)
        }
        // These URLs are hints. The movie page has to independently verify title and year.
        guard urls.count <= 5 else { return nil }
        var candidates: [AppleTVMovieLinkCandidate] = []
        for url in urls.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            try Task.checkCancellation()
            do {
                let (data, response) = try await transport(URLRequest(url: url, timeoutInterval: 10))
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let finalURL = http.url, finalURL.lastPathComponent == url.lastPathComponent,
                      let html = String(data: data, encoding: .utf8),
                      let candidate = Self.moviePageCandidate(in: html, url: finalURL) else { continue }
                candidates.append(candidate)
            } catch {
                try Task.checkCancellation()
            }
        }
        try Task.checkCancellation()
        return Self.match(query, candidates: candidates)
    }

    nonisolated static func moviePageCandidate(in html: String, url: URL) -> AppleTVMovieLinkCandidate? {
        struct PageMovie: Decodable {
            let type: String
            let name: String
            let datePublished: String
            enum CodingKeys: String, CodingKey { case type = "@type", name, datePublished }
        }
        guard let expression = try? NSRegularExpression(
            pattern: #"<script\b[^>]*type="application/ld\+json"[^>]*>(.*?)</script>"#,
            options: [.dotMatchesLineSeparators]
        ) else { return nil }
        let results = expression.matches(in: html, range: NSRange(html.startIndex..., in: html))
        let movies = results.compactMap { result -> PageMovie? in
            guard let range = Range(result.range(at: 1), in: html),
                  let movie = try? JSONDecoder().decode(PageMovie.self, from: Data(html[range].utf8)),
                  movie.type == "Movie" else { return nil }
            return movie
        }
        guard movies.count == 1, let movie = movies.first,
              let year = Int(movie.datePublished.prefix(4)), (1888...2100).contains(year) else { return nil }
        return AppleTVMovieLinkCandidate(title: movie.name, year: year, url: url)
    }

    private func remember(_ url: URL, for query: AppleTVMovieLinkQuery) {
        if links.count >= 64 { links.removeAll(keepingCapacity: true) }
        links[query] = url
    }

    nonisolated static func match(_ query: AppleTVMovieLinkQuery,
                                 candidates: [AppleTVMovieLinkCandidate]) -> URL? {
        guard let year = query.year else { return nil }
        let titles = Set(query.titles.map(MovieTitleNormalizer.normalize))
        let matches = candidates.filter {
            titles.contains(MovieTitleNormalizer.normalize($0.title)) && $0.year == year
        }.compactMap { candidate -> URL? in
            guard var url = URLComponents(url: candidate.url, resolvingAgainstBaseURL: false),
                  url.scheme == "https", url.host == "tv.apple.com", url.user == nil,
                  url.password == nil, url.port == nil, url.path.hasPrefix("/us/movie/"),
                  candidate.url.lastPathComponent.hasPrefix("umc.cmc.") else { return nil }
            url.query = nil
            url.fragment = nil
            return url.url
        }
        guard Set(matches.map(\.lastPathComponent)).count == 1 else { return nil }
        return matches.min(by: { $0.absoluteString < $1.absoluteString })
    }

    nonisolated static func candidates(in html: String) throws -> [AppleTVMovieLinkCandidate] {
        let expression = try NSRegularExpression(
            pattern: #"<script\b[^>]*id="serialized-server-data"[^>]*>(.*?)</script>"#,
            options: [.dotMatchesLineSeparators])
        guard let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let data = String(html[range]).data(using: .utf8) else { return [] }
        let root = try JSONSerialization.jsonObject(with: data)
        var result: [AppleTVMovieLinkCandidate] = []
        func visit(_ value: Any) {
            if let object = value as? [String: Any] {
                if object["type"] as? String == "Movie", let title = object["title"] as? String,
                   let date = object["releaseDate"] as? Double, date.isFinite,
                   let value = object["url"] as? String, let url = URL(string: value) {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    let year = calendar.component(.year, from: Date(timeIntervalSince1970: date / 1_000))
                    if (1888...2100).contains(year) {
                        result.append(AppleTVMovieLinkCandidate(title: title, year: year, url: url))
                    }
                }
                for child in object.values { visit(child) }
            } else if let array = value as? [Any] {
                for child in array { visit(child) }
            }
        }
        visit(root)
        return result
    }
}
