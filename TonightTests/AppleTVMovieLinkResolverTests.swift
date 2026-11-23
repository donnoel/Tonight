import XCTest
@testable import Tonight

final class AppleTVMovieLinkResolverTests: XCTestCase {
    func testRequiresExactTitleYearAndUniqueAppleMovieIdentity() {
        let query = AppleTVMovieLinkQuery(title: "I Love You, Man", year: 2009)
        let correct = candidate("I Love You, Man", year: 2009, id: "correct")
        XCTAssertEqual(AppleTVMovieLinkResolver.match(query, candidates: [
            candidate("Thirteen Days", year: 2000, id: "wrong"), correct
        ]), correct.url)
        XCTAssertNil(AppleTVMovieLinkResolver.match(query, candidates: [
            candidate("I Love You, Man", year: 2019, id: "remake")
        ]))
        XCTAssertNil(AppleTVMovieLinkResolver.match(query, candidates: [correct,
            candidate("I Love You, Man", year: 2009, id: "other-edition")]))
        XCTAssertNil(AppleTVMovieLinkResolver.match(.init(title: query.title, year: nil), candidates: [correct]))
    }

    func testRejectsForeignURLsAndDoesNotDropEditionNames() {
        let query = AppleTVMovieLinkQuery(title: "Apocalypse Now Final Cut", year: 1979)
        XCTAssertNil(AppleTVMovieLinkResolver.match(query, candidates: [
            candidate("Apocalypse Now", year: 1979, id: "theatrical")]))
        let foreign = AppleTVMovieLinkCandidate(title: query.title, year: 1979,
            url: URL(string: "https://example.com/us/movie/test/umc.cmc.test")!)
        XCTAssertNil(AppleTVMovieLinkResolver.match(query, candidates: [foreign]))
    }

    func testStripsPriceContextAndDeduplicatesSameDestination() {
        let query = AppleTVMovieLinkQuery(title: "Movie", year: 2000)
        let base = candidate("Movie", year: 2000, id: "one")
        let priced = AppleTVMovieLinkCandidate(title: "Movie", year: 2000,
            url: URL(string: base.url.absoluteString + "?ctx_price=4.99#details")!)
        let alias = AppleTVMovieLinkCandidate(title: "Movie", year: 2000,
            url: URL(string: "https://tv.apple.com/us/movie/movie-alias/umc.cmc.one")!)
        let result = AppleTVMovieLinkResolver.match(query, candidates: [base, priced, alias])
        XCTAssertEqual(result?.lastPathComponent, base.url.lastPathComponent)
        XCTAssertNil(result?.query)
    }

    func testParsesOnlyMovieRecordsAndLeavesRecommendationsUnmatched() throws {
        let html = try fixture(title: "Other Movie", year: 2000)
        let candidates = try AppleTVMovieLinkResolver.candidates(in: html)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertNil(AppleTVMovieLinkResolver.match(.init(title: "Wanted Movie", year: 2000), candidates: candidates))
        XCTAssertTrue(try AppleTVMovieLinkResolver.candidates(in: "Changed page markup").isEmpty)
    }

    func testVerifiedCachedDealNeedsNoRequest() async throws {
        let deal = DealsTestSupport.cachedItem(metadata: DealsTestSupport.metadata(title: "Test Movie", year: 2001))
        let resolver = AppleTVMovieLinkResolver(transport: { _ in
            XCTFail("A verified cached listing should not require a search")
            throw CancellationError()
        }, cachedDeals: { [deal] })
        let url = try await resolver.link(for: .init(title: "Test Movie", year: 2001))
        XCTAssertEqual(url?.host, "tv.apple.com")
        XCTAssertNil(url?.query)
    }

    func testSearchResultIsCachedAndUsesEncodedTitle() async throws {
        let data = Data(try fixture(title: "Tom & Jerry", year: 2000).utf8)
        let counter = MovieLinkRequestCounter()
        let resolver = AppleTVMovieLinkResolver(transport: { request in
            await counter.increment()
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "term" })?.value, "Tom & Jerry")
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, cachedDeals: { [] })
        let query = AppleTVMovieLinkQuery(title: "Tom & Jerry", year: 2000)
        let first = try await resolver.link(for: query)
        let second = try await resolver.link(for: query)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testCancellationIsNotConvertedToAnUnmatchedListing() async {
        let resolver = AppleTVMovieLinkResolver(transport: { _ in throw CancellationError() }, cachedDeals: { [] })
        do {
            _ = try await resolver.link(for: .init(title: "Movie", year: 2000))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCatalogPageRequiresAnExactMovieAndYear() async throws {
        let url = URL(string: "https://tv.apple.com/us/movie/the-conversation/umc.cmc.catalog")!
        let html = #"<script type="application/ld+json">{"@type":"Movie","name":"The Conversation","datePublished":"1974-04-07T00:00:00.000Z"}</script>"#
        let resolver = AppleTVMovieLinkResolver(transport: { request in
            let body = request.url == url ? html : ""
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, cachedDeals: { [] }, catalogURLs: { _ in [url] })

        let exact = try await resolver.link(for: .init(title: "The Conversation", year: 1974))
        let alternate = try await resolver.link(for: .init(title: "Conversation", year: 1974, alternateTitles: ["The Conversation"]))
        let otherEdition = try await resolver.link(for: .init(title: "The Conversation Final Cut", year: 1974))
        let wrongYear = try await resolver.link(for: .init(title: "The Conversation", year: 2024))
        XCTAssertEqual(exact, url)
        XCTAssertEqual(alternate, url)
        XCTAssertNil(otherEdition)
        XCTAssertNil(wrongYear)
    }

    private func candidate(_ title: String, year: Int, id: String) -> AppleTVMovieLinkCandidate {
        AppleTVMovieLinkCandidate(title: title, year: year,
            url: URL(string: "https://tv.apple.com/us/movie/movie/umc.cmc.\(id)")!)
    }

    private func fixture(title: String, year: Int) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: year, month: 6, day: 1))!
        let json: [String: Any] = ["data": ["items": [[
            "type": "Movie", "title": title, "releaseDate": date.timeIntervalSince1970 * 1000,
            "url": "https://tv.apple.com/us/movie/movie/umc.cmc.fixture"
        ]]]]
        let text = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8)!
        return "<script id=\"serialized-server-data\" type=\"application/json\">\(text)</script>"
    }
}

private actor MovieLinkRequestCounter {
    var count = 0
    func increment() { count += 1 }
}
