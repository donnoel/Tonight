import Foundation

protocol AppleMovieDealsProviding: Sendable {
    func fetchDeals() async throws -> [AppleMovieDeal]
}

enum AppleMovieDealsError: LocalizedError, Sendable {
    case invalidResponse
    case server(statusCode: Int)
    case unreadablePage
    case unexpectedCollection
    case pageFormatChanged

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Apple returned an unreadable response."
        case .server(let statusCode):
            "Apple returned an error (HTTP \(statusCode))."
        case .unreadablePage:
            "Tonight could not read Apple’s movie-deals page."
        case .unexpectedCollection:
            "Apple’s public page no longer identifies the Buy for $4.99 collection."
        case .pageFormatChanged:
            "Apple changed the public movie-deals page format."
        }
    }
}

struct AppleMovieDealsProvider: AppleMovieDealsProviding, Sendable {
    static let collectionURL = URL(
        string: "https://tv.apple.com/us/collection/buy-for-499/edt.col.5c9ea81b-fbfe-461e-ac43-9d8b52eaa3dc"
    )!

    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let collectionURL: URL

    init(
        session: URLSession = .shared,
        collectionURL: URL = Self.collectionURL
    ) {
        self.transport = { try await session.data(for: $0) }
        self.collectionURL = collectionURL
    }

    init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.transport = transport
        self.collectionURL = Self.collectionURL
    }

    func fetchDeals() async throws -> [AppleMovieDeal] {
        let data = try await fetch(collectionURL, accept: "text/html,application/xhtml+xml")
        guard let html = String(data: data, encoding: .utf8) else {
            throw AppleMovieDealsError.unreadablePage
        }
        let retrievedAt = Date.now
        var deals = try AppleMovieDealsParser.parse(html: html, retrievedAt: retrievedAt)
        guard let pagination = try AppleMovieDealsParser.pagination(html: html) else {
            return deals
        }
        var nextToken: String? = pagination.nextToken
        var seenTokens: Set<String> = []
        var seenIDs = Set(deals.map(\.id))
        while let token = nextToken {
            try Task.checkCancellation()
            guard seenTokens.insert(token).inserted, seenTokens.count <= 100 else {
                throw AppleMovieDealsError.pageFormatChanged
            }
            let pageData = try await fetch(pagination.url(token: token), accept: "application/json")
            let page = try AppleMovieDealsParser.parsePage(
                data: pageData, collectionID: pagination.collectionID, retrievedAt: retrievedAt
            )
            for deal in page.deals where seenIDs.insert(deal.id).inserted {
                deals.append(AppleMovieDeal(
                    title: deal.title, appleURL: deal.appleURL, priceInCents: deal.priceInCents,
                    contentIdentifier: deal.contentIdentifier, position: deals.count,
                    retrievedAt: retrievedAt, priceEvidence: deal.priceEvidence
                ))
            }
            nextToken = page.nextToken
        }
        return deals
    }

    private func fetch(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw AppleMovieDealsError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AppleMovieDealsError.server(statusCode: response.statusCode)
        }
        return data
    }

}

enum AppleMovieDealsParser {
    struct Pagination: Sendable {
        let collectionID: String
        let nextToken: String
        let parameters: [String: String]

        func url(token: String) throws -> URL {
            var components = URLComponents(string: "https://tv.apple.com/api/uts/v3/shelves/\(collectionID)")!
            var query = parameters
            query["nextToken"] = token
            components.queryItems = query.sorted { $0.key < $1.key }.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
            guard let url = components.url else { throw AppleMovieDealsError.pageFormatChanged }
            return url
        }
    }

    // Use Apple's page-provided pagination configuration, never a copied session token.
    static func pagination(html: String) throws -> Pagination? {
        let pattern = #"<script\b[^>]*id="serialized-server-data"[^>]*>(.*?)</script>"#
        let expression = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        guard let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let data = String(html[range]).data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else {
            throw AppleMovieDealsError.pageFormatChanged
        }
        let payloads = entries.compactMap { $0["data"] as? [String: Any] }
        let shelves = payloads.flatMap { $0["shelves"] as? [[String: Any]] ?? [] }
        guard !shelves.isEmpty else { throw AppleMovieDealsError.pageFormatChanged }
        let triggers = shelves.flatMap { $0["items"] as? [[String: Any]] ?? [] }
            .filter { $0["$kind"] as? String == "ShelfPaginationTrigger" }
        guard !triggers.isEmpty else { return nil }
        guard triggers.count == 1,
              let intent = triggers[0]["paginationIntent"] as? [String: Any],
              intent["$kind"] as? String == "ShelfBasicPaginationIntent",
              let id = intent["collectionId"] as? String,
              id == AppleMovieDealsProvider.collectionURL.lastPathComponent,
              let token = intent["nextToken"] as? String, !token.isEmpty,
              let configuration = payloads.compactMap({ $0["configuration"] as? [String: Any] }).first,
              let props = configuration["applicationProps"] as? [String: Any],
              let map = props["requiredParamsMap"] as? [String: Any],
              let parameters = map["Default"] as? [String: String],
              parameters["sf"] == "143441" else {
            throw AppleMovieDealsError.pageFormatChanged
        }
        return Pagination(collectionID: id, nextToken: token, parameters: parameters)
    }

    static func parsePage(
        data: Data, collectionID: String, retrievedAt: Date
    ) throws -> (deals: [AppleMovieDeal], nextToken: String?) {
        struct Response: Decodable {
            struct Payload: Decodable { let shelf: Shelf }
            struct Shelf: Decodable {
                let id: String
                let items: [Item]
                let nextToken: String?
            }
            struct Item: Decodable {
                let id: String
                let type: String
                let title: String
                let url: URL
            }
            let data: Payload
        }
        let shelf = try JSONDecoder().decode(Response.self, from: data).data.shelf
        guard shelf.id == collectionID else { throw AppleMovieDealsError.unexpectedCollection }
        var deals: [AppleMovieDeal] = []
        for item in shelf.items {
            guard item.type == "Movie", isUSMovieURL(item.url), hasVerifiedPriceContext(item.url),
                  contentIdentifier(from: item.url) == item.id, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppleMovieDealsError.pageFormatChanged
            }
            deals.append(AppleMovieDeal(
                title: item.title, appleURL: item.url, priceInCents: 499,
                contentIdentifier: item.id, position: deals.count, retrievedAt: retrievedAt,
                priceEvidence: .buyCollectionAndLinkContext
            ))
        }
        if let token = shelf.nextToken, token.isEmpty || shelf.items.isEmpty {
            throw AppleMovieDealsError.pageFormatChanged
        }
        return (deals, shelf.nextToken)
    }

    static func parse(html: String, retrievedAt: Date) throws -> [AppleMovieDeal] {
        guard html.localizedCaseInsensitiveContains("Buy for $4.99") else {
            throw AppleMovieDealsError.unexpectedCollection
        }
        guard html.contains("data-testid=\"grid\"") else {
            throw AppleMovieDealsError.pageFormatChanged
        }

        let anchorPattern = #"<a\b(?=[^>]*\bdata-testid="lockup")(?=[^>]*\bhref="([^"]+)")[^>]*>(.*?)</a>"#
        let titlePattern = #"<span\b[^>]*class="[^"]*visually-hidden[^"]*"[^>]*>(.*?)</span>"#
        let anchorExpression = try NSRegularExpression(
            pattern: anchorPattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        let titleExpression = try NSRegularExpression(
            pattern: titlePattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )

        let htmlRange = NSRange(html.startIndex..., in: html)
        let matches = anchorExpression.matches(in: html, range: htmlRange)
        var seenIdentifiers: Set<String> = []
        var deals: [AppleMovieDeal] = []

        for match in matches {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let anchorBodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let decodedHref = decodeHTMLEntities(String(html[hrefRange]))
            guard let url = URL(string: decodedHref),
                  isUSMovieURL(url),
                  hasVerifiedPriceContext(url),
                  let contentIdentifier = contentIdentifier(from: url) else {
                continue
            }

            let body = String(html[anchorBodyRange])
            let bodyRange = NSRange(body.startIndex..., in: body)
            guard let titleMatch = titleExpression.firstMatch(in: body, range: bodyRange),
                  let titleRange = Range(titleMatch.range(at: 1), in: body) else {
                continue
            }

            let title = cleanTitle(String(body[titleRange]))
            guard !title.isEmpty, seenIdentifiers.insert(contentIdentifier).inserted else {
                continue
            }

            deals.append(
                AppleMovieDeal(
                    title: title,
                    appleURL: url,
                    priceInCents: 499,
                    contentIdentifier: contentIdentifier,
                    position: deals.count,
                    retrievedAt: retrievedAt,
                    priceEvidence: .buyCollectionAndLinkContext
                )
            )
        }

        if matches.isEmpty {
            guard !html.contains("data-testid=\"grid-item\"") else {
                throw AppleMovieDealsError.pageFormatChanged
            }
            return []
        }
        guard !deals.isEmpty else {
            throw AppleMovieDealsError.pageFormatChanged
        }
        return deals
    }

    private static func isUSMovieURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == "tv.apple.com"
            && url.path.hasPrefix("/us/movie/")
    }

    private static func hasVerifiedPriceContext(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let priceContext = components.queryItems?.first(where: {
                  $0.name == "ctx_price"
              })?.value else {
            return false
        }
        return priceContext.contains("_4.99_4.99_")
    }

    private static func contentIdentifier(from url: URL) -> String? {
        url.pathComponents.last(where: { $0.hasPrefix("umc.cmc.") })
    }

    private static func cleanTitle(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        let numericPattern = #"&#(x[0-9A-Fa-f]+|[0-9]+);"#
        guard let expression = try? NSRegularExpression(pattern: numericPattern) else {
            return result
        }
        let matches = expression.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let rawValue = String(result[valueRange])
            let scalarValue = rawValue.lowercased().hasPrefix("x")
                ? UInt32(rawValue.dropFirst(), radix: 16)
                : UInt32(rawValue, radix: 10)
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            result.replaceSubrange(wholeRange, with: String(Character(scalar)))
        }
        return result
    }
}
