import XCTest
@testable import Tonight

final class LibrarySortTests: XCTestCase {
    private let alpha = Movie(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Alpha",
        releaseYear: 2001
    )
    private let bravo = Movie(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        title: "Bravo"
    )
    private let charlie = Movie(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        title: "Charlie",
        releaseYear: 1984
    )

    func testTitleAscendingSortsAToZ() {
        let result = LibrarySort.movies(
            [charlie, alpha, bravo],
            by: .titleAscending
        )

        XCTAssertEqual(result.map(\.title), ["Alpha", "Bravo", "Charlie"])
    }

    func testTitleDescendingSortsZToA() {
        let result = LibrarySort.movies(
            [alpha, charlie, bravo],
            by: .titleDescending
        )

        XCTAssertEqual(result.map(\.title), ["Charlie", "Bravo", "Alpha"])
    }

    func testYearSortsOldestFirstAndUnknownLast() {
        let result = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .releaseYear
        )

        XCTAssertEqual(result.map(\.title), ["Charlie", "Alpha", "Bravo"])
    }

    func testShuffleUsesStableProvidedRanks() {
        let result = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .shuffled,
            shuffleRanks: [
                alpha.id: 2,
                bravo.id: 0,
                charlie.id: 1
            ]
        )

        XCTAssertEqual(result.map(\.title), ["Bravo", "Charlie", "Alpha"])
    }
}
