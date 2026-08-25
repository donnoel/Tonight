import XCTest
@testable import Tonight

final class MovieFactoryTests: XCTestCase {
    func testRichDetailsMapIntoPersistedMovie() {
        let details = TMDBMovieDetailsDTO(
            id: 238,
            title: "The Godfather",
            originalTitle: "The Godfather",
            releaseDate: "1972-03-14",
            overview: "Overview",
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            runtime: 175,
            genres: [
                TMDBGenreDTO(id: 18, name: "Drama"),
                TMDBGenreDTO(id: 80, name: "Crime")
            ],
            voteAverage: 8.7,
            voteCount: 21_000,
            originalLanguage: "en",
            credits: TMDBCreditsDTO(
                cast: [
                    TMDBCastMemberDTO(id: 2, name: "Al Pacino", character: "Michael", order: 1),
                    TMDBCastMemberDTO(id: 1, name: "Marlon Brando", character: "Vito", order: 0)
                ],
                crew: [
                    TMDBCrewMemberDTO(id: 3, name: "Francis Ford Coppola", job: "Director")
                ]
            )
        )
        let entry = LibraryImportEntry(title: "The Godfather", year: 1972)

        let movie = MovieFactory.enrichedMovie(from: details, importedEntry: entry)

        XCTAssertEqual(movie.tmdbID, 238)
        XCTAssertEqual(movie.releaseYear, 1972)
        XCTAssertEqual(movie.runtimeMinutes, 175)
        XCTAssertEqual(movie.genres, ["Drama", "Crime"])
        XCTAssertEqual(movie.director, "Francis Ford Coppola")
        XCTAssertEqual(movie.primaryCast, ["Marlon Brando", "Al Pacino"])
        XCTAssertEqual(movie.originalLanguage, "en")
        XCTAssertEqual(movie.resolutionStatus, .resolved)
    }

    func testArtworkURLsUseContextAppropriateSizes() {
        XCTAssertEqual(
            TMDBImageURL.make(path: "/poster.jpg", size: .posterCard)?.absoluteString,
            "https://image.tmdb.org/t/p/w342/poster.jpg"
        )
        XCTAssertEqual(
            TMDBImageURL.make(path: "/backdrop.jpg", size: .backdrop)?.absoluteString,
            "https://image.tmdb.org/t/p/w1280/backdrop.jpg"
        )
    }

    func testEnrichingExistingMoviePreservesPersonalLibraryState() {
        let movie = Movie(
            title: "Blade Runner (Director's Cut)",
            importedTitle: "Blade Runner (Director's Cut)",
            importedYear: 1982,
            resolutionStatus: .unresolved,
            resolutionNote: "Needs a match"
        )
        movie.isWatched = true
        movie.userRating = 4.5
        movie.recommendationCount = 3
        let originalID = movie.id

        let details = TMDBMovieDetailsDTO(
            id: 78,
            title: "Blade Runner",
            originalTitle: "Blade Runner",
            releaseDate: "1982-06-25",
            overview: "Overview",
            posterPath: "/blade-runner.jpg",
            backdropPath: "/blade-runner-backdrop.jpg",
            runtime: 118,
            genres: [TMDBGenreDTO(id: 878, name: "Science Fiction")],
            voteAverage: 7.9,
            voteCount: 14_000,
            originalLanguage: "en",
            credits: nil
        )

        MovieFactory.enrich(movie, from: details)

        XCTAssertEqual(movie.id, originalID)
        XCTAssertEqual(movie.importedTitle, "Blade Runner (Director's Cut)")
        XCTAssertEqual(movie.importedYear, 1982)
        XCTAssertTrue(movie.isWatched)
        XCTAssertEqual(movie.userRating, 4.5)
        XCTAssertEqual(movie.recommendationCount, 3)
        XCTAssertEqual(movie.tmdbID, 78)
        XCTAssertEqual(movie.title, "Blade Runner")
        XCTAssertEqual(movie.resolutionStatus, .resolved)
        XCTAssertNil(movie.resolutionNote)
    }
}
