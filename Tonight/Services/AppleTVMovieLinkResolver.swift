import Foundation

struct AppleTVMovieLinkQuery: Hashable, Codable, Sendable {
    let title: String
    let year: Int?
}

struct AppleTVMovieLinkCandidate: Sendable {
    let title: String
    let year: Int?
    let url: URL
}

/// Looks up an Apple display page for an already-owned movie, never ownership or playback rights.
actor AppleTVMovieLinkResolver {
    static let shared = AppleTVMovieLinkResolver()
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let cachedDeals: @Sendable () async -> [CachedMovieDeal]
    private let savedLinks: AppleTVMovieLinkStore
    private var links: [AppleTVMovieLinkQuery: URL] = [:]

    init(
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        },
        cachedDeals: @escaping @Sendable () async -> [CachedMovieDeal] = {
            MovieDealsCache().load()?.items ?? []
        },
        savedLinks: AppleTVMovieLinkStore = AppleTVMovieLinkStore()
    ) {
        self.transport = transport
        self.cachedDeals = cachedDeals
        self.savedLinks = savedLinks
    }

    func link(for query: AppleTVMovieLinkQuery) async throws -> URL? {
        guard query.year != nil else { return nil }
        if let cached = links[query] { return cached }
        if let saved = try? await savedLinks.link(for: query),
           let url = Self.canonicalMovieURL(saved) {
            try Task.checkCancellation()
            remember(url, for: query)
            return url
        }
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
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let matched = Self.match(query, candidates: try Self.candidates(in: html))
        if let matched { remember(matched, for: query) }
        return matched
    }

    enum LinkError: LocalizedError {
        case invalidURL, couldNotVerify
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Paste an HTTPS Apple TV movie link from the U.S. store."
            case .couldNotVerify: "This page could not be verified as the same movie and release year. Check the link and try again."
            }
        }
    }

    func saveLink(_ input: String, for query: AppleTVMovieLinkQuery) async throws {
        guard let inputURL = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let url = Self.canonicalMovieURL(inputURL) else { throw LinkError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let finalURL = response.url.flatMap(Self.canonicalMovieURL),
              let html = String(data: data, encoding: .utf8),
              let verified = try Self.verifiedPage(html, url: finalURL, query: query),
              verified.lastPathComponent == url.lastPathComponent else { throw LinkError.couldNotVerify }
        try await savedLinks.save(verified, for: query)
        remember(verified, for: query)
    }

    /// A pasted page is checked against its own Movie structured data, never related-title shelves.
    nonisolated static func verifiedPage(_ html: String, url: URL,
                                         query: AppleTVMovieLinkQuery) throws -> URL? {
        let expression = try NSRegularExpression(
            pattern: #"<script\b[^>]*type="application/ld\+json"[^>]*>(.*?)</script>"#,
            options: [.dotMatchesLineSeparators])
        var candidates: [AppleTVMovieLinkCandidate] = []
        for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let data = String(html[range]).data(using: .utf8) else { continue }
            let root = try JSONSerialization.jsonObject(with: data)
            let objects = (root as? [[String: Any]]) ?? (root as? [String: Any]).map { [$0] } ?? []
            for object in objects where object["@type"] as? String == "Movie" {
                guard let title = object["name"] as? String,
                      let date = object["datePublished"] as? String,
                      let year = Int(date.prefix(4)), (1888...2100).contains(year) else { continue }
                candidates.append(.init(title: title, year: year, url: url))
            }
        }
        guard candidates.count == 1 else { return nil }
        return Self.match(query, candidates: candidates)
    }

    private func remember(_ url: URL, for query: AppleTVMovieLinkQuery) {
        if links.count >= 64 { links.removeAll(keepingCapacity: true) }
        links[query] = url
    }

    nonisolated static func match(_ query: AppleTVMovieLinkQuery,
                                 candidates: [AppleTVMovieLinkCandidate]) -> URL? {
        guard let year = query.year else { return nil }
        let title = MovieTitleNormalizer.normalize(query.title)
        let matches = candidates.filter {
            MovieTitleNormalizer.normalize($0.title) == title && $0.year == year
        }.compactMap { candidate -> URL? in
            Self.canonicalMovieURL(candidate.url)
        }
        let unique = Set(matches)
        return unique.count == 1 ? unique.first : nil
    }

    nonisolated static func canonicalMovieURL(_ input: URL) -> URL? {
        guard var url = URLComponents(url: input, resolvingAgainstBaseURL: false),
              url.scheme == "https", url.host == "tv.apple.com", url.user == nil,
              url.password == nil, url.port == nil,
              input.pathComponents.count == 5, url.path.hasPrefix("/us/movie/"),
              input.lastPathComponent.hasPrefix("umc.cmc."),
              input.lastPathComponent.count > "umc.cmc.".count else { return nil }
        url.query = nil
        url.fragment = nil
        return url.url
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
