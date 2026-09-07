import XCTest
@testable import Tonight

final class AppleMovieDealsParserTests: XCTestCase {
    func testParsesVerifiedPurchaseDealsInCollectionOrder() throws {
        let deals = try AppleMovieDealsParser.parse(
            html: Self.representativeCollectionFixture,
            retrievedAt: DealsTestSupport.now
        )

        XCTAssertEqual(deals.map(\.title), ["Tom & Jerry", "Second Movie"])
        XCTAssertEqual(deals.map(\.contentIdentifier), ["umc.cmc.one", "umc.cmc.two"])
        XCTAssertEqual(deals.map(\.position), [0, 1])
        XCTAssertTrue(deals.allSatisfy { $0.priceInCents == 499 })
        XCTAssertTrue(
            deals.allSatisfy { $0.priceEvidence == .buyCollectionAndLinkContext }
        )
    }

    func testFiltersOtherPricesAndDeduplicatesAppleIdentifiers() throws {
        let deals = try AppleMovieDealsParser.parse(
            html: Self.representativeCollectionFixture,
            retrievedAt: DealsTestSupport.now
        )

        XCTAssertEqual(deals.count, 2)
        XCTAssertFalse(deals.contains { $0.title == "Wrong Price" })
        XCTAssertEqual(deals.count { $0.contentIdentifier == "umc.cmc.one" }, 1)
    }

    func testAllowsAValidEmptyCollection() throws {
        let html = """
        <html><h1>Buy for $4.99</h1><div data-testid="grid"></div></html>
        """

        let deals = try AppleMovieDealsParser.parse(
            html: html,
            retrievedAt: DealsTestSupport.now
        )

        XCTAssertTrue(deals.isEmpty)
    }

    func testReportsChangedMarkupInsteadOfPretendingThereAreNoDeals() {
        let html = """
        <html><h1>Buy for $4.99</h1><div data-testid="grid">
          <li data-testid="grid-item">A movie in an unknown format</li>
        </div></html>
        """

        XCTAssertThrowsError(
            try AppleMovieDealsParser.parse(
                html: html,
                retrievedAt: DealsTestSupport.now
            )
        ) { error in
            guard case AppleMovieDealsError.pageFormatChanged = error else {
                return XCTFail("Expected pageFormatChanged, got \(error)")
            }
        }
    }

    func testRejectsACollectionWithoutTheExpectedHeading() {
        let html = "<html><div data-testid=\"grid\"></div></html>"

        XCTAssertThrowsError(
            try AppleMovieDealsParser.parse(
                html: html,
                retrievedAt: DealsTestSupport.now
            )
        ) { error in
            guard case AppleMovieDealsError.unexpectedCollection = error else {
                return XCTFail("Expected unexpectedCollection, got \(error)")
            }
        }
    }

    private static let representativeCollectionFixture = """
    <html>
      <h1>Buy for $4.99</h1>
      <div data-testid="grid">
        <li data-testid="grid-item">
          <a data-testid="lockup" href="https://tv.apple.com/us/movie/tom-and-jerry/umc.cmc.one?ctx_price=tvs.vds.9023_4.99_4.99_1">
            <span class="visually-hidden">Tom &amp; Jerry</span>
          </a>
        </li>
        <li data-testid="grid-item">
          <a data-testid="lockup" href="https://tv.apple.com/us/movie/wrong-price/umc.cmc.wrong?ctx_price=tvs.vds.9023_9.99_9.99_1">
            <span class="visually-hidden">Wrong Price</span>
          </a>
        </li>
        <li data-testid="grid-item">
          <a data-testid="lockup" href="https://tv.apple.com/us/movie/duplicate/umc.cmc.one?ctx_price=tvs.vds.9023_4.99_4.99_1">
            <span class="visually-hidden">Duplicate</span>
          </a>
        </li>
        <li data-testid="grid-item">
          <a data-testid="lockup" href="https://tv.apple.com/us/movie/second/umc.cmc.two?ctx_price=tvs.vds.9023_4.99_4.99_1">
            <span class="visually-hidden">Second Movie</span>
          </a>
        </li>
      </div>
    </html>
    """
}

final class AppleMovieDealsPaginationTests: XCTestCase {
    private static let collectionID = AppleMovieDealsProvider.collectionURL.lastPathComponent

    private static func initialPage(token: String? = "page2") -> Data {
        let trigger: [[String: Any]] = token.map { [[
            "$kind": "ShelfPaginationTrigger",
            "paginationIntent": [
                "$kind": "ShelfBasicPaginationIntent", "collectionId": collectionID,
                "nextToken": $0
            ]
        ]] } ?? []
        let state: [String: Any] = ["data": [
            ["data": ["configuration": ["applicationProps": ["requiredParamsMap": [
                "Default": ["sf": "143441", "locale": "en-US"]
            ]]]]],
            ["data": ["shelves": [["items": trigger]]]]
        ]]
        let json = String(data: try! JSONSerialization.data(withJSONObject: state), encoding: .utf8)!
        return Data("""
        <h1>Buy for $4.99</h1><div data-testid="grid">
        <a data-testid="lockup" href="https://tv.apple.com/us/movie/one/umc.cmc.one?ctx_price=tvs.vds.9023_4.99_4.99_1"><span class="visually-hidden">One</span></a>
        </div><script type="application/json" id="serialized-server-data">\(json)</script>
        """.utf8)
    }

    private static func page(ids: [String], token: String? = nil, price: String = "4.99") -> Data {
        var shelf: [String: Any] = [
            "id": collectionID,
            "items": ids.map { [
                "id": "umc.cmc.\($0)", "type": "Movie", "title": $0,
                "url": "https://tv.apple.com/us/movie/\($0)/umc.cmc.\($0)?ctx_price=tvs.vds.9023_\(price)_\(price)_1"
            ] }
        ]
        shelf["nextToken"] = token
        return try! JSONSerialization.data(withJSONObject: ["data": ["shelf": shelf]])
    }

    private static func provider(pages: [String: Data], failingToken: String? = nil) -> AppleMovieDealsProvider {
        AppleMovieDealsProvider { request in
            let token = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "nextToken" })?.value ?? "initial"
            guard let data = pages[token] else { throw AppleMovieDealsError.invalidResponse }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: token == failingToken ? 503 : 200,
                httpVersion: nil, headerFields: nil
            )!
            return (data, response)
        }
    }

    func testLoadsEveryPageAndDeduplicatesInCollectionOrder() async throws {
        let provider = Self.provider(pages: [
            "initial": Self.initialPage(),
            "page2": Self.page(ids: ["one", "two"], token: "page3"),
            "page3": Self.page(ids: ["three"])
        ])
        let deals = try await provider.fetchDeals()
        XCTAssertEqual(deals.map(\.id), ["umc.cmc.one", "umc.cmc.two", "umc.cmc.three"])
        XCTAssertEqual(deals.map(\.position), [0, 1, 2])
        XCTAssertEqual(Set(deals.map(\.retrievedAt)).count, 1)
    }

    func testSinglePageStopsWithoutAnotherRequest() async throws {
        let deals = try await Self.provider(pages: ["initial": Self.initialPage(token: nil)]).fetchDeals()
        XCTAssertEqual(deals.count, 1)
    }

    func testLaterPageFailureDoesNotReturnPartialCatalog() async {
        do {
            _ = try await Self.provider(pages: [
                "initial": Self.initialPage(), "page2": Self.page(ids: ["two"])
            ], failingToken: "page2").fetchDeals()
            XCTFail("Expected refresh failure")
        } catch {
            guard case AppleMovieDealsError.server(statusCode: 503) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRepeatedTokenFailsInsteadOfLoopingOrReturningPartialCatalog() async {
        do {
            _ = try await Self.provider(pages: [
                "initial": Self.initialPage(), "page2": Self.page(ids: ["two"], token: "page2")
            ]).fetchDeals()
            XCTFail("Expected pagination failure")
        } catch {
            guard case AppleMovieDealsError.pageFormatChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsUnverifiedPriceAndWrongCollection() throws {
        XCTAssertThrowsError(try AppleMovieDealsParser.parsePage(
            data: Self.page(ids: ["two"], price: "9.99"),
            collectionID: Self.collectionID, retrievedAt: .now
        ))
        XCTAssertThrowsError(try AppleMovieDealsParser.parsePage(
            data: Self.page(ids: ["two"]), collectionID: "another-collection", retrievedAt: .now
        ))
    }

    func testMissingPaginationStateFailsRatherThanClaimingCompleteness() {
        XCTAssertThrowsError(try AppleMovieDealsParser.pagination(
            html: "<h1>Buy for $4.99</h1><div data-testid=\"grid\"></div>"
        ))
    }

    func testOldPartialCacheRemainsReadableButNeedsRefresh() throws {
        let snapshot = DealCatalogSnapshot(
            catalogVersion: nil, items: [], lastSuccessfulRefresh: .now, enrichmentState: .complete
        )
        let decoded = try JSONDecoder().decode(
            DealCatalogSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        XCTAssertNil(decoded.catalogVersion)
        XCTAssertFalse(decoded.isFresh(at: .now, lifetime: 21_600))
    }

    func testCancellationPropagates() async {
        let provider = AppleMovieDealsProvider { _ in throw CancellationError() }
        do {
            _ = try await provider.fetchDeals()
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
