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

    private let session: URLSession
    private let collectionURL: URL

    init(
        session: URLSession = .shared,
        collectionURL: URL = Self.collectionURL
    ) {
        self.session = session
        self.collectionURL = collectionURL
    }

    func fetchDeals() async throws -> [AppleMovieDeal] {
        var request = URLRequest(
            url: collectionURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppleMovieDealsError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppleMovieDealsError.server(statusCode: httpResponse.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw AppleMovieDealsError.unreadablePage
        }
        return try AppleMovieDealsParser.parse(html: html, retrievedAt: .now)
    }
}

enum AppleMovieDealsParser {
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
