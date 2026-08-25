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
