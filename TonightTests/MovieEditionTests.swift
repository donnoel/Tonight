import SwiftData
import XCTest
@testable import Tonight

final class MovieEditionTests: XCTestCase {
    func testCutNamesHaveSeparateIdentitiesAndExportImportRoundTrips() {
        let original = Movie(tmdbID: 28, title: "Apocalypse Now", importedYear: 1979, releaseYear: 1979, resolutionStatus: .resolved)
        let final = Movie(tmdbID: 28, title: "Apocalypse Now (Final Cut)", importedYear: 1979, releaseYear: 1979, resolutionStatus: .resolved)
        final.edition = .finalCut
        let redux = Movie(tmdbID: 28, title: "Apocalypse Now (Redux)", importedYear: 2001, releaseYear: 1979, resolutionStatus: .resolved)
        redux.edition = .redux
        let movies = [original, final, redux]
        let names = movies.map { SyncedLibraryMovie(movie: $0).details.recordName }
        XCTAssertEqual(names, ["tmdb-28", "tmdb-28-edition-final-cut", "tmdb-28-edition-redux"])
        XCTAssertFalse(LibraryDuplicateDetector.contains(MovieIdentity(movie: final), in: [MovieIdentity(movie: original)]))
        XCTAssertTrue(LibraryDuplicateDetector.contains(MovieIdentity(movie: final), in: movies.map(MovieIdentity.init(movie:))))
        let parsed = MovieImportParser.parse(MovieListDocument.text(for: movies))
        XCTAssertEqual(Set(parsed.compactMap(\.edition)), [.finalCut, .redux])
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(MovieSearchQuery.title(from: "Apocalypse Now Redux"), "Apocalypse Now")
        XCTAssertEqual(MovieSearchQuery.title(from: "Apocalypse Now: Final Cut"), "Apocalypse Now")
        XCTAssertEqual(MovieSearchQuery.title(from: "Final Cut"), "Final Cut")
        XCTAssertNil(MovieEdition.parse("  Ordinary Title  "))
        XCTAssertNil(LibraryImportEntry(title: "Apocalypse Now Redux", year: 2001).searchYear)
    }

    func testEnrichmentKeepsCutLabelAndOwnedRuntime() {
        let details = TMDBMovieDetailsDTO(id: 28, title: "Apocalypse Now", originalTitle: "Apocalypse Now",
            releaseDate: "1979-08-15", overview: "Overview", posterPath: "/poster", backdropPath: nil,
            runtime: 147, genres: [], voteAverage: 8, voteCount: 100, originalLanguage: "en", credits: nil)
        let movie = MovieFactory.enrichedMovie(from: details,
            importedEntry: LibraryImportEntry(title: "Apocalypse Now Redux", year: 2001))
        XCTAssertEqual(movie.edition, .redux)
        XCTAssertEqual(movie.title, "Apocalypse Now (Redux)")
        XCTAssertNil(movie.runtimeMinutes) // Never label an extended cut with the theatrical runtime.
        movie.runtimeMinutes = 196
        MovieFactory.enrich(movie, from: details)
        XCTAssertEqual(movie.runtimeMinutes, 196)
        XCTAssertEqual(movie.edition, .redux)
    }

    func testOldPayloadWithoutEditionKeepsOriginalRecordName() throws {
        let movie = Movie(tmdbID: 28, title: "Apocalypse Now")
        let snapshot = SyncedLibraryMovie(movie: movie)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SyncedLibraryMovie.self, from: data)
        XCTAssertNil(decoded.details.editionRawValue)
        XCTAssertEqual(decoded.details.recordName, "tmdb-28")
        let document = LibrarySyncDocument(movie: decoded, revision: .initial, initial: true)
        XCTAssertEqual(document.version, 1)
        XCTAssertTrue(document.isSupportedFormat)
    }
}
