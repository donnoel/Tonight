import XCTest
@testable import Tonight

final class MovieSearchQueryTests: XCTestCase {
    func testSpecialEditionSuffixIsRemovedForSearch() {
        XCTAssertEqual(
            MovieSearchQuery.title(from: "Aliens (Special Edition)"),
            "Aliens"
        )
    }

    func testDirectorsCutSuffixIsRemovedForSearch() {
        XCTAssertEqual(
            MovieSearchQuery.title(from: "Blade Runner [Director's Cut]"),
            "Blade Runner"
        )
    }

    func testUnbracketedFinalCutSuffixIsRemovedForSearch() {
        XCTAssertEqual(
            MovieSearchQuery.title(from: "Blade Runner – The Final Cut"),
            "Blade Runner"
        )
    }

    func testAnniversaryEditionSuffixIsRemovedForSearch() {
        XCTAssertEqual(
            MovieSearchQuery.title(from: "The Movie (25th Anniversary Edition)"),
            "The Movie"
        )
    }

    func testStandaloneRemasteredSuffixIsRemovedForSearch() {
        XCTAssertEqual(
            MovieSearchQuery.title(from: "The Movie [Remastered]"),
            "The Movie"
        )
    }

    func testOrdinaryParentheticalTitleIsPreserved() {
        XCTAssertEqual(
            MovieSearchQuery.title(from: "Birdman (or the Unexpected Virtue of Ignorance)"),
            "Birdman (or the Unexpected Virtue of Ignorance)"
        )
    }
}
