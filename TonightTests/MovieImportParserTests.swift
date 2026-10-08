import XCTest
@testable import Tonight

final class MovieImportParserTests: XCTestCase {
    func testParsesOneMoviePerLine() {
        let entries = MovieImportParser.parse(
            """
            Heat
            Alien
            Jaws
            """
        )

        XCTAssertEqual(entries.map(\.title), ["Heat", "Alien", "Jaws"])
        XCTAssertEqual(entries.map(\.year), [nil, nil, nil])
    }

    func testExtractsYears() {
        let entries = MovieImportParser.parse(
            """
            Heat (1995)
            Alien (1979)
            """
        )

        XCTAssertEqual(entries.map(\.title), ["Heat", "Alien"])
        XCTAssertEqual(entries.map(\.year), [1995, 1979])
    }

    func testNormalizesWhitespaceAndIgnoresEmptyLines() {
        let entries = MovieImportParser.parse(
            """

                 2001:   A Space Odyssey

              Jaws

            """
        )

        XCTAssertEqual(entries.map(\.title), ["2001: A Space Odyssey", "Jaws"])
    }

    func testRemovesDuplicateTitleAndYearPairs() {
        let entries = MovieImportParser.parse(
            """
            Alien (1979)
            alien (1979)
            Dune (1984)
            Dune (2021)
            """
        )

        XCTAssertEqual(entries.map(\.title), ["Alien", "Dune", "Dune"])
        XCTAssertEqual(entries.map(\.year), [1979, 1984, 2021])
    }

    func testParsesBasicCommaSeparatedInput() {
        let entries = MovieImportParser.parse("Heat (1995), Alien (1979), Jaws")

        XCTAssertEqual(entries.map(\.title), ["Heat", "Alien", "Jaws"])
        XCTAssertEqual(entries.map(\.year), [1995, 1979, nil])
    }

    func testLineBasedImportPreservesCommasInMovieTitles() {
        let entries = MovieImportParser.parse("Heat (1995)\nI, Robot (2004)\nLock, Stock and Two Smoking Barrels (1998)")

        XCTAssertEqual(entries.map(\.title), ["Heat", "I, Robot", "Lock, Stock and Two Smoking Barrels"])
        XCTAssertEqual(entries.map(\.year), [1995, 2004, 1998])
    }

    func testQuotedCommaSeparatedTitleStaysOneMovie() {
        let entries = MovieImportParser.parse("Heat (1995), \"I, Robot (2004)\", Alien (1979)")

        XCTAssertEqual(entries.map(\.title), ["Heat", "I, Robot", "Alien"])
        XCTAssertEqual(entries.map(\.year), [1995, 2004, 1979])
    }

    func testQuotedSingleMovieAndEscapedQuotes() {
        let entries = MovieImportParser.parse("\"I, Robot (2004)\", \"The \"\"Quoted\"\" Movie\"")

        XCTAssertEqual(entries.map(\.title), ["I, Robot", "The \"Quoted\" Movie"])
    }

    func testWindowsLinesPreserveCommaTitlesAndRemoveDuplicates() {
        let entries = MovieImportParser.parse("I, Robot (2004)\r\n\r\nI, Robot (2004)\r\nAlien")

        XCTAssertEqual(entries.map(\.title), ["I, Robot", "Alien"])
    }
}
