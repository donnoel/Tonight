import XCTest
@testable import Tonight

final class MovieListDocumentTests: XCTestCase {
    func testSortedExportRoundTripsRemakesCommasAndUnresolvedTitles() {
        let older = Movie(title: "The Thing", releaseYear: 1982, resolutionStatus: .resolved)
        let newer = Movie(title: "The Thing", releaseYear: 2011, resolutionStatus: .resolved)
        let comma = Movie(title: "I, Robot", releaseYear: 2004, resolutionStatus: .resolved)
        let unresolved = Movie(title: "Unmatched", importedYear: 1999)
        let text = MovieListDocument.text(for: [newer, unresolved, older, comma])
        let entries = MovieImportParser.parse(text)
        XCTAssertEqual(entries.map(\.title), ["I, Robot", "The Thing", "The Thing", "Unmatched"])
        XCTAssertEqual(entries.map(\.year), [2004, 1982, 2011, 1999])
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testSingleMovieWithCommaAndQuotesRemainsOneEntry() {
        let title = "A, \"Quoted\" Title"
        let text = MovieListDocument.text(for: [Movie(title: title, releaseYear: 2001, resolutionStatus: .resolved)])
        XCTAssertEqual(MovieImportParser.parse(text).map(\.title), [title])
        XCTAssertEqual(MovieImportParser.parse(text).first?.year, 2001)
        XCTAssertEqual(MovieListDocument.text(for: []), "")
    }

    @MainActor
    func testTextFileLoadsIntoExistingReviewWithoutImporting() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try "Amélie (2001)\nI, Robot (2004)\n".write(to: file, atomically: true, encoding: .utf8)
        let model = ImportViewModel()
        await model.loadTextFile(file)
        XCTAssertEqual(model.phase, .editor)
        XCTAssertFalse(model.isReadingFile)
        model.prepareReview()
        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.entries.map(\.title), ["Amélie", "I, Robot"])
    }
}
