import XCTest
@testable import Tonight

final class LibrarySortTests: XCTestCase {
    private let alpha = Movie(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Alpha",
        releaseYear: 2001,
        runtimeMinutes: 120,
        genres: ["Drama"],
        tmdbVoteAverage: 7.1,
        director: "Ava Director",
        dateAdded: Date(timeIntervalSince1970: 200)
    )
    private let bravo = Movie(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        title: "Bravo",
        runtimeMinutes: 90,
        dateAdded: Date(timeIntervalSince1970: 300)
    )
    private let charlie = Movie(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        title: "Charlie",
        releaseYear: 1984,
        runtimeMinutes: 150,
        genres: ["Thriller"],
        tmdbVoteAverage: 8.6,
        dateAdded: Date(timeIntervalSince1970: 100)
    )

    func testTitleSortSupportsBothDirections() {
        let ascending = LibrarySort.movies(
            [charlie, alpha, bravo],
            by: .title,
            direction: .ascending
        )
        let descending = LibrarySort.movies(
            [alpha, charlie, bravo],
            by: .title,
            direction: .descending
        )

        XCTAssertEqual(ascending.map(\.title), ["Alpha", "Bravo", "Charlie"])
        XCTAssertEqual(descending.map(\.title), ["Charlie", "Bravo", "Alpha"])
    }

    func testReleaseYearSortSupportsBothDirectionsAndKeepsUnknownLast() {
        let oldest = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .releaseYear,
            direction: .ascending
        )
        let newest = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .releaseYear,
            direction: .descending
        )

        XCTAssertEqual(oldest.map(\.title), ["Charlie", "Alpha", "Bravo"])
        XCTAssertEqual(newest.map(\.title), ["Alpha", "Charlie", "Bravo"])
    }

    func testDateAddedSortsNewestFirst() {
        let result = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .dateAdded,
            direction: .descending
        )

        XCTAssertEqual(result.map(\.title), ["Bravo", "Alpha", "Charlie"])
    }

    func testRuntimeSortsShortestFirst() {
        let result = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .runtime,
            direction: .ascending
        )

        XCTAssertEqual(result.map(\.title), ["Bravo", "Alpha", "Charlie"])
    }

    func testRatingSortsHighestFirstAndKeepsUnknownLast() {
        let result = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .rating,
            direction: .descending
        )

        XCTAssertEqual(result.map(\.title), ["Charlie", "Alpha", "Bravo"])
    }

    func testLastWatchedSortsMostRecentFirstAndKeepsUnknownLast() {
        alpha.lastWatchedDate = Date(timeIntervalSince1970: 100)
        charlie.lastWatchedDate = Date(timeIntervalSince1970: 300)

        let result = LibrarySort.movies(
            [alpha, bravo, charlie],
            by: .lastWatched,
            direction: .descending
        )

        XCTAssertEqual(result.map(\.title), ["Charlie", "Alpha", "Bravo"])
    }

    func testShuffleUsesStableProvidedRanks() {
        let result = LibrarySort.shuffledMovies(
            [alpha, bravo, charlie],
            shuffleRanks: [
                alpha.id: 2,
                bravo.id: 0,
                charlie.id: 1
            ]
        )

        XCTAssertEqual(result.map(\.title), ["Bravo", "Charlie", "Alpha"])
    }

    func testWatchFilterSeparatesWatchedAndUnwatchedMovies() {
        alpha.isWatched = true

        let watched = LibraryFilter.movies(
            [alpha, bravo, charlie],
            showing: .watched,
            matching: ""
        )
        let unwatched = LibraryFilter.movies(
            [alpha, bravo, charlie],
            showing: .unwatched,
            matching: ""
        )

        XCTAssertEqual(watched.map(\.title), ["Alpha"])
        XCTAssertEqual(unwatched.map(\.title), ["Bravo", "Charlie"])
    }

    func testSearchMatchesUsefulMovieMetadata() {
        let directorMatch = LibraryFilter.movies(
            [alpha, bravo, charlie],
            showing: .all,
            matching: "ava"
        )
        let genreMatch = LibraryFilter.movies(
            [alpha, bravo, charlie],
            showing: .all,
            matching: "thriller"
        )
        let yearMatch = LibraryFilter.movies(
            [alpha, bravo, charlie],
            showing: .all,
            matching: "2001"
        )

        XCTAssertEqual(directorMatch.map(\.title), ["Alpha"])
        XCTAssertEqual(genreMatch.map(\.title), ["Charlie"])
        XCTAssertEqual(yearMatch.map(\.title), ["Alpha"])
    }
}
