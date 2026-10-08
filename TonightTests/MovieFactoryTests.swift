import XCTest
import SwiftData
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

@MainActor
final class MovieMatchRecoveryTests: XCTestCase {
    func testResolvedMovieSearchUsesCurrentTitleAndYear() {
        let movie = Movie(tmdbID: 2048, title: "I, Robot", importedTitle: "I",
                          importedYear: 2016, releaseYear: 2004, resolutionStatus: .resolved)
        let model = UnresolvedMatchViewModel()

        model.prepare(for: movie)

        XCTAssertEqual(model.query, "I, Robot")
        XCTAssertEqual(model.yearText, "2004")
    }

    func testUnresolvedMovieSearchPreservesImportedIdentity() {
        let movie = Movie(title: "Wrong details", importedTitle: "Blade Runner (Director's Cut)",
                          importedYear: 1982, releaseYear: 2016)
        let model = UnresolvedMatchViewModel()

        model.prepare(for: movie)

        XCTAssertEqual(model.query, "Blade Runner")
        XCTAssertEqual(model.yearText, "1982")
    }

    func testCorrectingResolvedMovieToExistingMatchPreservesHistoryWithoutNetworking() async throws {
        let container = try ModelContainer(for: Movie.self, RecommendationEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let incorrect = Movie(tmdbID: 646690, title: "The Robot", importedTitle: "Robot",
                              releaseYear: 2016, resolutionStatus: .resolved)
        incorrect.isWatched = true
        incorrect.isLiked = true
        incorrect.userRating = 4
        let correct = Movie(tmdbID: 2048, title: "I, Robot", releaseYear: 2004,
                            posterPath: "/poster.jpg", resolutionStatus: .resolved)
        let event = RecommendationEvent(movie: incorrect, kind: .hiddenGem, response: .accepted)
        context.insert(incorrect); context.insert(correct); context.insert(event)
        try context.save()
        let candidate = TMDBSearchCandidate(id: 2048, title: "I, Robot", originalTitle: "I, Robot",
                                            releaseYear: 2004, rank: 0, popularity: 100)
        let model = UnresolvedMatchViewModel()

        let matched = await model.apply(candidate, to: incorrect, in: context)

        XCTAssertTrue(matched === correct)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Movie>()), 1)
        XCTAssertTrue(event.movie === correct)
        XCTAssertEqual(event.response, .accepted)
        XCTAssertTrue(correct.isWatched)
        XCTAssertTrue(correct.isLiked)
        XCTAssertEqual(correct.userRating, 4)
        XCTAssertEqual(correct.posterPath, "/poster.jpg")
        XCTAssertNil(model.message)
    }
}
