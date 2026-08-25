import XCTest
@testable import Tonight

@MainActor
final class DealsViewModelTests: XCTestCase {
    func testRefreshFailureKeepsCachedCatalogAndShowsItsAge() async {
        let cached = DealsTestSupport.snapshot()
        let client = MovieDealsClient(
            loadCached: { cached },
            refresh: { _ in throw TestRetrievalError() }
        )
        let model = DealsViewModel(
            client: client,
            now: { DealsTestSupport.now.addingTimeInterval(24 * 60 * 60) }
        )

        await model.load(library: [], forceRefresh: true)

        XCTAssertEqual(model.snapshot, cached)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.notice?.contains("Showing deals last updated") == true)
        XCTAssertTrue(model.notice?.contains("fixture retrieval failed") == true)
    }

    func testRefreshFailureWithoutCacheShowsRetrievalError() async {
        let client = MovieDealsClient(
            loadCached: { nil },
            refresh: { _ in throw TestRetrievalError() }
        )
        let model = DealsViewModel(client: client)

        await model.load(library: [], forceRefresh: true)

        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.errorMessage, "The fixture retrieval failed.")
        XCTAssertNil(model.notice)
    }
}

private struct TestRetrievalError: LocalizedError {
    var errorDescription: String? { "The fixture retrieval failed." }
}
