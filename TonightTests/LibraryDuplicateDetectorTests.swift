import XCTest
@testable import Tonight

final class LibraryDuplicateDetectorTests: XCTestCase {
    func testMatchingTMDBIDIsDuplicateEvenWhenTitlesDiffer() {
        let existing = [
            MovieIdentity(tmdbID: 550, title: "Fight Club", releaseYear: 1999)
        ]
        let candidate = MovieIdentity(tmdbID: 550, title: "Different Display Title", releaseYear: 2000)

        XCTAssertTrue(LibraryDuplicateDetector.contains(candidate, in: existing))
    }

    func testDifferentTMDBIDsAreNotDuplicates() {
        let existing = [
            MovieIdentity(tmdbID: 841, title: "Dune", releaseYear: 1984)
        ]
        let candidate = MovieIdentity(tmdbID: 438631, title: "Dune", releaseYear: 1984)

        XCTAssertFalse(LibraryDuplicateDetector.contains(candidate, in: existing))
    }

    func testNormalizedTitleAndYearAreFallbackDuplicateKey() {
        let existing = [
            MovieIdentity(tmdbID: nil, title: "2001: A Space Odyssey", releaseYear: 1968)
        ]
        let candidate = MovieIdentity(tmdbID: nil, title: "  2001 A SPACE ODYSSEY ", releaseYear: 1968)

        XCTAssertTrue(LibraryDuplicateDetector.contains(candidate, in: existing))
    }

    func testSameTitleDifferentYearIsNotFallbackDuplicate() {
        let existing = [
            MovieIdentity(tmdbID: nil, title: "Dune", releaseYear: 1984)
        ]
        let candidate = MovieIdentity(tmdbID: nil, title: "Dune", releaseYear: 2021)

        XCTAssertFalse(LibraryDuplicateDetector.contains(candidate, in: existing))
    }
}

