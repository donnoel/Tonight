import XCTest
@testable import Tonight

final class AppleTVSavedMovieLinkTests: XCTestCase {
    private let query = AppleTVMovieLinkQuery(title: "127 Hours", year: 2010)
    private let url = URL(string: "https://tv.apple.com/us/movie/127-hours/umc.cmc.test")!

    func testVerifiesPageMovieRatherThanSuggestedTitles() throws {
        let correct = page(title: "127 Hours", year: 2010)
        XCTAssertEqual(try AppleTVMovieLinkResolver.verifiedPage(correct, url: url, query: query), url)
        XCTAssertNil(try AppleTVMovieLinkResolver.verifiedPage(page(title: "Other Movie", year: 2010),
            url: url, query: query))
        XCTAssertNil(try AppleTVMovieLinkResolver.verifiedPage(page(title: "127 Hours", year: 2011),
            url: url, query: query))
        XCTAssertNil(try AppleTVMovieLinkResolver.verifiedPage(
            page(title: "Other Movie", year: 2010) + correct, url: url, query: query))
        XCTAssertNil(try AppleTVMovieLinkResolver.verifiedPage(
            "<script id=\"serialized-server-data\">{\"type\":\"Movie\",\"title\":\"127 Hours\"}</script>",
            url: url, query: query))
    }

    func testRejectsNonMovieForeignAndCredentialBearingLinks() {
        for text in ["http://tv.apple.com/us/movie/movie/umc.cmc.test",
                     "https://example.com/us/movie/movie/umc.cmc.test",
                     "https://tv.apple.com.evil.test/us/movie/movie/umc.cmc.test",
                     "https://user@tv.apple.com/us/movie/movie/umc.cmc.test",
                     "https://tv.apple.com:8443/us/movie/movie/umc.cmc.test",
                     "https://tv.apple.com/gb/movie/movie/umc.cmc.test",
                     "https://tv.apple.com/us/show/movie/umc.cmc.test",
                     "https://tv.apple.com/us/movie/movie/umc.cmc."] {
            XCTAssertNil(AppleTVMovieLinkResolver.canonicalMovieURL(URL(string: text)!))
        }
    }

    func testVerifiedSavedLinkSurvivesResolverRecreationAndSkipsSearch() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(page(title: query.title, year: 2010).utf8)
        let resolver = AppleTVMovieLinkResolver(transport: { request in
            XCTAssertEqual(request.url?.query, nil)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, cachedDeals: { [] }, savedLinks: .init(fileURL: file))
        try await resolver.saveLink(url.absoluteString + "?playableId=ignored#details", for: query)
        let recreated = AppleTVMovieLinkResolver(transport: { _ in
            XCTFail("The saved verified URL must not need another search")
            throw CancellationError()
        }, cachedDeals: { [] }, savedLinks: .init(fileURL: file))
        let restored = try await recreated.link(for: .init(title: "127 HOURS", year: 2010))
        XCTAssertEqual(restored, url)
        let otherYear = try await AppleTVMovieLinkStore(fileURL: file).link(for: .init(title: query.title, year: 2011))
        XCTAssertNil(otherYear)
    }

    func testWrongTitleOrRedirectDoesNotReplacePreviouslySavedLink() async throws {
        let store = AppleTVMovieLinkStore(fileURL: nil)
        try await store.save(url, for: query)
        let wrongPage = Data(page(title: "Another Movie", year: 2010).utf8)
        let resolver = AppleTVMovieLinkResolver(transport: { request in
            (wrongPage, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, cachedDeals: { [] }, savedLinks: store)
        do {
            try await resolver.saveLink("https://tv.apple.com/us/movie/another/umc.cmc.other", for: query)
            XCTFail("Expected mismatched movie rejection")
        } catch is AppleTVMovieLinkResolver.LinkError {
        }
        let retained = try await store.link(for: query)
        XCTAssertEqual(retained, url)

        let correctPage = Data(page(title: query.title, year: 2010).utf8)
        let redirect = AppleTVMovieLinkResolver(transport: { _ in
            (correctPage, HTTPURLResponse(url: URL(string: "https://example.com/us/movie/movie/umc.cmc.other")!,
                statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, cachedDeals: { [] }, savedLinks: store)
        do {
            try await redirect.saveLink(url.absoluteString, for: query)
            XCTFail("Expected foreign redirect rejection")
        } catch is AppleTVMovieLinkResolver.LinkError {
        }
    }

    func testCorruptSavedFileIsNotOverwritten() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let original = Data("damaged but preserved".utf8)
        try original.write(to: file)
        do {
            try await AppleTVMovieLinkStore(fileURL: file).save(url, for: query)
            XCTFail("A corrupt file must be preserved")
        } catch is DecodingError {
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    private func page(title: String, year: Int) -> String {
        "<script type=\"application/ld+json\">{\"@type\":\"Movie\",\"name\":\"\(title)\",\"datePublished\":\"\(year)-11-12T00:00:00.000Z\"}</script>"
    }
}
