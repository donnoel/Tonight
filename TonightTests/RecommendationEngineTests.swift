import XCTest
@testable import Tonight

final class RecommendationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testReturnsDistinctRecommendationKindsFromResolvedLibraryOnly() {
        let resolvedMovies = [
            movie(title: "Alpha", genres: ["Drama"]),
            movie(title: "Bravo", genres: ["Comedy"]),
            movie(title: "Charlie", genres: ["Thriller"])
        ]
        let unresolved = movie(
            title: "Unresolved",
            genres: ["Drama"],
            resolutionStatus: .unresolved
        )

        let picks = RecommendationEngine.recommendations(
            from: resolvedMovies + [unresolved],
            now: now
        )

        XCTAssertEqual(picks.map(\.kind), [.bestMatch, .wildcard, .forgottenOne])
        XCTAssertEqual(Set(picks.map(\.movie.id)).count, 3)
        XCTAssertFalse(picks.contains { $0.movie.id == unresolved.id })
    }

    func testPreferredGenreInfluencesBestMatch() {
        let action = movie(
            title: "Action Favorite",
            genres: ["Action"],
            voteAverage: 9.5,
            voteCount: 50_000
        )
        let comedy = movie(
            title: "Comedy Choice",
            genres: ["Comedy"],
            voteAverage: 6.0,
            voteCount: 100
        )

        let picks = RecommendationEngine.recommendations(
            from: [action, comedy],
            preferredGenre: "Comedy",
            now: now
        )

        XCTAssertEqual(picks.first?.movie.id, comedy.id)
    }

    func testImmediateRefreshRotatesRecentlyRecommendedMovieOut() {
        let recent = movie(
            title: "Recent Favorite",
            genres: ["Drama"],
            voteAverage: 10,
            voteCount: 100_000
        )
        recent.lastRecommendedDate = now
        recent.recommendationCount = 1

        let available = movie(
            title: "Available Choice",
            genres: ["Drama"],
            voteAverage: 7,
            voteCount: 1_000
        )

        let picks = RecommendationEngine.recommendations(
            from: [recent, available],
            now: now
        )

        XCTAssertEqual(picks.first?.movie.id, available.id)
    }

    func testDislikedMoviesAreExcluded() {
        let disliked = movie(
            title: "Disliked",
            genres: ["Drama"],
            voteAverage: 10,
            voteCount: 100_000
        )
        disliked.isDisliked = true
        let eligible = movie(title: "Eligible", genres: ["Comedy"])

        let picks = RecommendationEngine.recommendations(
            from: [disliked, eligible],
            now: now
        )

        XCTAssertEqual(picks.map(\.movie.id), [eligible.id])
    }

    func testForgottenOneFavorsMovieThatHasWaitedLonger() {
        let best = movie(
            title: "Best",
            genres: ["Drama"],
            voteAverage: 9.5,
            voteCount: 100_000
        )
        best.isLiked = true
        let wildcard = movie(
            title: "Wildcard",
            genres: ["Documentary"],
            voteAverage: 8,
            voteCount: 1_000
        )
        let older = movie(
            title: "Older",
            genres: ["Drama"],
            dateAdded: now.addingTimeInterval(-400 * 86_400)
        )
        let newer = movie(
            title: "Newer",
            genres: ["Drama"],
            dateAdded: now.addingTimeInterval(-5 * 86_400)
        )

        let picks = RecommendationEngine.recommendations(
            from: [best, wildcard, newer, older],
            now: now
        )

        XCTAssertEqual(
            picks.first(where: { $0.kind == .forgottenOne })?.movie.id,
            older.id
        )
    }

    private func movie(
        title: String,
        genres: [String],
        voteAverage: Double = 7,
        voteCount: Int = 500,
        dateAdded: Date = Date(timeIntervalSince1970: 1_900_000_000),
        resolutionStatus: MovieResolutionStatus = .resolved
    ) -> Movie {
        Movie(
            title: title,
            releaseYear: 2000,
            overviewText: "Overview",
            posterPath: "/poster.jpg",
            genres: genres,
            tmdbVoteAverage: voteAverage,
            tmdbVoteCount: voteCount,
            resolutionStatus: resolutionStatus,
            dateAdded: dateAdded
        )
    }
}
