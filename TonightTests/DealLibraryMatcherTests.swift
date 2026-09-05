import XCTest
@testable import Tonight

final class DealLibraryMatcherTests: XCTestCase {
    func testUsesTMDBIdentifierWhenAvailable() {
        let owned = movie(id: 42, title: "Localized Library Title", year: 2001)
        let item = DealsTestSupport.cachedItem(
            metadata: DealsTestSupport.metadata(id: 42, title: "Apple Title")
        )

        XCTAssertTrue(DealLibraryMatcher.movie(for: item, in: [owned]) === owned)
    }

    func testFallsBackToUniqueNormalizedTitleAndYear() {
        let owned = movie(id: 7, title: "Spider-Man", year: 2001)
        let item = DealsTestSupport.cachedItem(
            metadata: DealsTestSupport.metadata(
                id: 99,
                title: "Spider Man",
                year: 2001
            )
        )

        XCTAssertTrue(DealLibraryMatcher.movie(for: item, in: [owned]) === owned)
    }

    func testUsesUniqueAppleTitleWhenTMDBEnrichmentIsUnavailable() {
        let owned = movie(id: 7, title: "The Conversation", year: 1974)
        let deal = DealsTestSupport.appleDeal(title: "The Conversation")
        let item = DealsTestSupport.cachedItem(
            deal: deal,
            metadata: nil,
            status: .unavailable
        )

        XCTAssertTrue(DealLibraryMatcher.movie(for: item, in: [owned]) === owned)
    }

    func testDoesNotGuessWhenAnUnenrichedTitleIsAmbiguous() {
        let first = movie(id: 1, title: "Crash", year: 1996)
        let second = movie(id: 2, title: "Crash", year: 2005)
        let deal = DealsTestSupport.appleDeal(title: "Crash")
        let item = DealsTestSupport.cachedItem(
            deal: deal,
            metadata: nil,
            status: .unresolved
        )

        XCTAssertNil(DealLibraryMatcher.movie(for: item, in: [first, second]))
    }

    func testReusableIndexPreservesExactIDPriorityAndAmbiguousYearFallback() {
        let first = movie(id: 1, title: "Same", year: 2000)
        let second = movie(id: 2, title: "Same", year: 2000)
        let index = DealLibraryIndex([first, second])
        let exact = DealsTestSupport.cachedItem(
            metadata: DealsTestSupport.metadata(id: 2, title: "Same", year: 2000)
        )
        let ambiguous = DealsTestSupport.cachedItem(
            metadata: DealsTestSupport.metadata(id: 3, title: "Same", year: 2000)
        )
        XCTAssertTrue(index.movie(for: exact) === second)
        XCTAssertNil(index.movie(for: ambiguous))
        XCTAssertTrue(index.movie(for: exact) === second)
    }

    private func movie(id: Int, title: String, year: Int) -> Movie {
        Movie(
            tmdbID: id,
            title: title,
            importedYear: year,
            releaseYear: year,
            resolutionStatus: .resolved
        )
    }
}
