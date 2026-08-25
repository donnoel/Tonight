import Foundation
import XCTest
@testable import Tonight

final class MovieDealsCacheTests: XCTestCase {
    func testRoundTripsDisposableDealCatalog() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directoryURL.appending(path: "deals.json")
        let cache = MovieDealsCache(fileURL: fileURL)
        let expected = DealsTestSupport.snapshot()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try await cache.save(expected)
        let actual = await cache.load()

        XCTAssertEqual(actual, expected)
    }

    func testMissingCacheReturnsNil() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "missing.json")
        let cache = MovieDealsCache(fileURL: fileURL)

        let snapshot = await cache.load()

        XCTAssertNil(snapshot)
    }
}
