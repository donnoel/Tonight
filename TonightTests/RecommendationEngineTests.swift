import XCTest
@testable import Tonight

final class RecommendationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testReturnsDistinctResolvedPicksWithRotatingLanes() {
        let resolvedMovies = [
            movie(title: "Alpha", genres: ["Drama"]),
            movie(title: "Bravo", genres: ["Comedy"]),
            movie(title: "Charlie", genres: ["Thriller"]),
            movie(title: "Delta", genres: ["Documentary"])
        ]
        let unresolved = movie(
            title: "Unresolved",
            genres: ["Drama"],
            resolutionStatus: .unresolved
        )

        let picks = RecommendationEngine.recommendations(
            from: resolvedMovies + [unresolved],
            now: now,
            seed: 42
        )

        XCTAssertEqual(picks.count, 3)
        XCTAssertEqual(picks.first?.kind, .bestMatch)
        XCTAssertEqual(Set(picks.map(\.kind)).count, 3)
        XCTAssertEqual(Set(picks.map(\.movie.id)).count, 3)
        XCTAssertFalse(picks.contains { $0.movie.id == unresolved.id })
    }

    func testFunAndEasyUsesPaceAndQualityAlongsideGenre() {
        let intenseAction = movie(
            title: "Intense Action",
            genres: ["Action"],
            runtime: 165,
            voteAverage: 9.5,
            voteCount: 50_000
        )
        let briskComedy = movie(
            title: "Brisk Comedy",
            genres: ["Comedy"],
            runtime: 96,
            voteAverage: 6.5,
            voteCount: 500
        )

        let picks = RecommendationEngine.recommendations(
            from: [intenseAction, briskComedy],
            preferences: RecommendationPreferences(mood: .funAndEasy),
            now: now,
            seed: 7
        )

        XCTAssertEqual(picks.first?.movie.id, briskComedy.id)
    }

    func testUnderTwoHoursExcludesLongAndUnknownRuntimeMovies() {
        let short = movie(title: "Short", genres: ["Drama"], runtime: 105)
        let long = movie(title: "Long", genres: ["Drama"], runtime: 145)
        let unknown = movie(title: "Unknown", genres: ["Drama"], runtime: nil)

        let picks = RecommendationEngine.recommendations(
            from: [short, long, unknown],
            preferences: RecommendationPreferences(underTwoHours: true),
            now: now,
            seed: 1
        )

        XCTAssertEqual(picks.map(\.movie.id), [short.id])
    }

    func testUnwatchedOnlyExcludesWatchedMovies() {
        let watched = movie(title: "Watched", genres: ["Drama"])
        watched.isWatched = true
        let unwatched = movie(title: "Unwatched", genres: ["Drama"])

        let picks = RecommendationEngine.recommendations(
            from: [watched, unwatched],
            preferences: RecommendationPreferences(unwatchedOnly: true),
            now: now,
            seed: 2
        )

        XCTAssertEqual(picks.map(\.movie.id), [unwatched.id])
    }

    func testAcceptedRecommendationMarksMovieWatched() {
        let chosen = movie(title: "Chosen", genres: ["Drama"])

        RecommendationResponse.accepted.applyMovieState(to: chosen, at: now)

        XCTAssertTrue(chosen.isWatched)
        XCTAssertEqual(chosen.dateWatched, now)
        XCTAssertEqual(chosen.lastWatchedDate, now)
        XCTAssertTrue(RecommendationResponse.accepted.removesMovieFromActivePicks)
    }

    func testFiveRecentSessionsAreExcludedWhenFreshChoicesExist() {
        let recentMovies = (1...5).map {
            movie(title: "Recent \($0)", genres: ["Drama"])
        }
        let freshMovies = (1...3).map {
            movie(title: "Fresh \($0)", genres: ["Comedy"])
        }
        let history = zip(recentMovies, 0..<5).map { movie, offset in
            RecommendationEvent(
                movie: movie,
                recommendedAt: now.addingTimeInterval(-Double(offset) * 3_600),
                kind: .bestMatch
            )
        }

        let picks = RecommendationEngine.recommendations(
            from: recentMovies + freshMovies,
            history: history,
            now: now,
            seed: 3
        )

        XCTAssertEqual(Set(picks.map(\.movie.id)), Set(freshMovies.map(\.id)))
    }

    func testNotTonightTemporarilyPenalizesMovieWhenCooldownCannotFullyApply() {
        let declined = movie(
            title: "Declined",
            genres: ["Drama"],
            voteAverage: 10,
            voteCount: 100_000
        )
        let alternative = movie(
            title: "Alternative",
            genres: ["Drama"],
            voteAverage: 7,
            voteCount: 1_000
        )
        let event = RecommendationEvent(
            movie: declined,
            recommendedAt: now.addingTimeInterval(-86_400),
            kind: .bestMatch,
            mood: .quietAndThoughtful,
            response: .notTonight
        )

        let picks = RecommendationEngine.recommendations(
            from: [declined, alternative],
            history: [event],
            preferences: RecommendationPreferences(mood: .quietAndThoughtful),
            now: now,
            seed: 4
        )

        XCTAssertEqual(picks.first?.movie.id, alternative.id)
    }

    func testTuningChoicesProduceMatchingRecommendationLanes() {
        let modern = movie(
            title: "Modern",
            genres: ["Drama"],
            runtime: 100,
            year: 2025
        )
        let older = movie(
            title: "Older",
            genres: ["Drama"],
            runtime: 90,
            year: 1965
        )
        let third = movie(
            title: "Third",
            genres: ["Comedy"],
            runtime: 110,
            year: 1990
        )

        let picks = RecommendationEngine.recommendations(
            from: [modern, older, third],
            preferences: RecommendationPreferences(
                underTwoHours: true,
                somethingOlder: true
            ),
            now: now,
            seed: 5
        )

        XCTAssertEqual(picks.map(\.kind), [.bestMatch, .shortAndSharp, .differentDecade])
        XCTAssertTrue(picks.allSatisfy { ($0.movie.runtimeMinutes ?? .max) <= 120 })
        XCTAssertTrue(
            picks.contains {
                $0.kind == .differentDecade && $0.movie.releaseYear == older.releaseYear
            }
        )
    }

    func testComfortMoodAddsAComfortLaneUsingFamiliarMovies() {
        let familiar = movie(title: "Familiar", genres: ["Comedy"])
        familiar.isWatched = true
        let freshOne = movie(title: "Fresh One", genres: ["Comedy"])
        let freshTwo = movie(title: "Fresh Two", genres: ["Drama"])

        let picks = RecommendationEngine.recommendations(
            from: [familiar, freshOne, freshTwo],
            preferences: RecommendationPreferences(mood: .comfortWatch),
            now: now,
            seed: 6
        )

        let comfortPick = picks.first { $0.kind == .comfortRewatch }
        XCTAssertEqual(comfortPick?.movie.id, familiar.id)
    }

    func testAcceptedChoicesTeachTheSelectedMood() {
        let acceptedComedy = movie(title: "Accepted Comedy", genres: ["Comedy"])
        let history = (1...3).map { offset in
            RecommendationEvent(
                movie: acceptedComedy,
                recommendedAt: now.addingTimeInterval(-Double(offset) * 86_400),
                kind: .bestMatch,
                mood: .anything,
                response: .accepted
            )
        }
        let similar = movie(title: "Similar Comedy", genres: ["Comedy"])
        let different = movie(title: "Different Action", genres: ["Action"])

        let picks = RecommendationEngine.recommendations(
            from: [similar, different],
            history: history,
            preferences: RecommendationPreferences(mood: .anything),
            now: now,
            seed: 10
        )

        XCTAssertEqual(picks.first?.movie.id, similar.id)
    }

    func testDifferentSeedsRotateThroughMoreThanThreeLaneTypes() {
        let movies = [
            movie(title: "A", genres: ["Drama"], runtime: 90, year: 1960),
            movie(title: "B", genres: ["Comedy"], runtime: 100, year: 1980),
            movie(title: "C", genres: ["Action"], runtime: 130, year: 2000),
            movie(title: "D", genres: ["Documentary"], runtime: 80, year: 2010),
            movie(title: "E", genres: ["Thriller"], runtime: 115, year: 2020)
        ]
        movies[0].isWatched = true

        var kinds: Set<RecommendationKind> = []
        for seed in 1...20 {
            let picks = RecommendationEngine.recommendations(
                from: movies,
                now: now,
                seed: UInt64(seed)
            )
            kinds.formUnion(picks.map(\.kind))
        }

        XCTAssertGreaterThan(kinds.count, 3)
        XCTAssertTrue(kinds.contains(.bestMatch))
    }

    func testFixedSeedMakesSelectionReproducible() {
        let movies = (1...8).map {
            movie(
                title: "Movie \($0)",
                genres: $0.isMultiple(of: 2) ? ["Comedy"] : ["Drama"],
                runtime: 90 + $0,
                year: 1980 + $0
            )
        }

        let first = RecommendationEngine.recommendations(
            from: movies,
            preferences: RecommendationPreferences(mood: .surpriseMe),
            now: now,
            seed: 99
        )
        let second = RecommendationEngine.recommendations(
            from: movies,
            preferences: RecommendationPreferences(mood: .surpriseMe),
            now: now,
            seed: 99
        )

        XCTAssertEqual(first.map(\.kind), second.map(\.kind))
        XCTAssertEqual(first.map(\.movie.id), second.map(\.movie.id))
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
            now: now,
            seed: 8
        )

        XCTAssertEqual(picks.map(\.movie.id), [eligible.id])
    }

    func testRecommendationEventPersistsMoodAndFallsBackForOldHistory() {
        let event = RecommendationEvent(
            kind: .bestMatch,
            mood: .bigMovieNight
        )
        XCTAssertEqual(event.mood, .bigMovieNight)

        event.moodRawValue = nil
        XCTAssertEqual(event.mood, .anything)
    }

    func testDealRankingUsesThePersonalLibraryAsItsTasteProfile() {
        let likedThriller = movie(title: "Liked Thriller", genres: ["Thriller"])
        likedThriller.isLiked = true
        let matchingDeal = movie(
            title: "Matching Deal",
            genres: ["Thriller"],
            voteAverage: 6.5
        )
        let unrelatedDeal = movie(
            title: "Unrelated Deal",
            genres: ["Comedy"],
            voteAverage: 8.5
        )

        let rankings = RecommendationEngine.rankDeals(
            candidates: [
                DealRecommendationCandidate(id: "match", movie: matchingDeal),
                DealRecommendationCandidate(id: "other", movie: unrelatedDeal)
            ],
            tasteLibrary: [likedThriller],
            now: now
        )

        XCTAssertEqual(rankings.first?.id, "match")
        XCTAssertTrue(rankings.first?.rationale.contains("thriller") == true)
    }

    func testDealRankingExcludesADealTheUserMarkedNotInterested() {
        let dislikedDeal = movie(title: "Disliked Deal", genres: ["Drama"])
        dislikedDeal.isDisliked = true
        let eligibleDeal = movie(title: "Eligible Deal", genres: ["Drama"])

        let rankings = RecommendationEngine.rankDeals(
            candidates: [
                DealRecommendationCandidate(id: "disliked", movie: dislikedDeal),
                DealRecommendationCandidate(id: "eligible", movie: eligibleDeal)
            ],
            tasteLibrary: [dislikedDeal],
            now: now
        )

        XCTAssertEqual(rankings.map(\.id), ["eligible"])
    }

    private func movie(
        title: String,
        genres: [String],
        runtime: Int? = 110,
        year: Int = 2000,
        voteAverage: Double = 7,
        voteCount: Int = 500,
        dateAdded: Date = Date(timeIntervalSince1970: 1_900_000_000),
        resolutionStatus: MovieResolutionStatus = .resolved
    ) -> Movie {
        Movie(
            title: title,
            releaseYear: year,
            overviewText: "Overview",
            posterPath: "/poster.jpg",
            runtimeMinutes: runtime,
            genres: genres,
            tmdbVoteAverage: voteAverage,
            tmdbVoteCount: voteCount,
            director: "Director \(title)",
            primaryCast: ["Actor \(title)"],
            originalLanguage: "en",
            resolutionStatus: resolutionStatus,
            dateAdded: dateAdded
        )
    }
}
