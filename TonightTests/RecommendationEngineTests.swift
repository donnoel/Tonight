import SwiftData
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
        XCTAssertEqual(chosen.watchedStateModifiedAt, now)
        XCTAssertTrue(RecommendationResponse.accepted.removesMovieFromActivePicks)
    }

    func testActiveEventsHideWatchedMoviesWhenUnwatchedOnlyIsEnabled() {
        let watchedResponseMovie = movie(title: "Already Watched", genres: ["Comedy"])
        watchedResponseMovie.isWatched = true
        let watchedResponse = RecommendationEvent(
            movie: watchedResponseMovie,
            recommendedAt: now,
            kind: .shortAndSharp,
            response: .watched
        )

        let watchedElsewhereMovie = movie(title: "Marked in Details", genres: ["Drama"])
        watchedElsewhereMovie.isWatched = true
        let watchedElsewhere = RecommendationEvent(
            movie: watchedElsewhereMovie,
            recommendedAt: now,
            kind: .hiddenGem
        )

        let unwatchedMovie = movie(title: "Still Unwatched", genres: ["Thriller"])
        let unwatched = RecommendationEvent(
            movie: unwatchedMovie,
            recommendedAt: now,
            kind: .bestMatch
        )

        let active = RecommendationEngine.activeEvents(
            from: [watchedResponse, watchedElsewhere, unwatched],
            preferences: RecommendationPreferences(unwatchedOnly: true)
        )

        XCTAssertEqual(active.map(\.movie?.id), [unwatchedMovie.id])
    }

    func testActiveEventsKeepChosenMovieVisibleAsConfirmation() {
        let chosenMovie = movie(title: "Chosen", genres: ["Drama"])
        chosenMovie.isWatched = true
        let chosen = RecommendationEvent(
            movie: chosenMovie,
            recommendedAt: now,
            kind: .bestMatch,
            response: .accepted
        )

        let active = RecommendationEngine.activeEvents(
            from: [chosen],
            preferences: RecommendationPreferences(unwatchedOnly: true)
        )

        XCTAssertEqual(active.map(\.movie?.id), [chosenMovie.id])
    }

    func testAllSavedSessionsAreExcludedWhenFreshChoicesExist() {
        let recentMovies = (1...20).map {
            movie(title: "Recent \($0)", genres: ["Drama"])
        }
        let freshMovies = (1...3).map {
            movie(title: "Fresh \($0)", genres: ["Comedy"])
        }
        let history = zip(recentMovies, 0..<20).map { movie, offset in
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

    func testNotTonightIsExcludedInsteadOfFillingASparsePool() {
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

        XCTAssertEqual(picks.map(\.movie.id), [alternative.id])
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

    func testMoodSuitabilityUsesToneAndRejectsConflictingMixedGenres() {
        let quietDrama = movie(title: "Reflective Drama", genres: ["Drama"])
        let comedy = movie(title: "Light Comedy", genres: ["Comedy"])
        let thriller = movie(title: "Tense Mystery", genres: ["Mystery", "Thriller"])
        let epic = movie(title: "War Epic", genres: ["Drama", "Action", "Adventure", "War"])
        let violentDrama = movie(title: "Violent Drama", genres: ["Drama"])
        violentDrama.overviewText = "A family faces an invasion as a brutal war begins."
        let darkComedy = movie(title: "Dark Comedy", genres: ["Comedy", "Horror"])
        let comicMystery = movie(title: "Comic Mystery", genres: ["Comedy", "Mystery"])
        let unknown = movie(title: "Unknown Tone", genres: [])
        let fixtures = [quietDrama, comedy, thriller, epic, violentDrama, darkComedy, comicMystery, unknown]
        let expected: [RecommendationMood: Set<String>] = [
            .anything: Set(fixtures.map(\.title)),
            .funAndEasy: ["Light Comedy", "Comic Mystery"],
            .quietAndThoughtful: ["Reflective Drama"],
            .edgeOfYourSeat: ["Tense Mystery", "War Epic", "Dark Comedy"],
            .bigMovieNight: ["War Epic"],
            .comfortWatch: ["Light Comedy", "Comic Mystery"],
            .surpriseMe: Set(fixtures.map(\.title))
        ]
        for mood in RecommendationMood.allCases {
            let matches = fixtures.filter { RecommendationEngine.matchesMood($0, mood: mood) }
            XCTAssertEqual(Set(matches.map(\.title)), expected[mood], mood.title)
        }
    }

    func testExhaustedQuietMoodDoesNotRepeatOrUseOffMoodFiller() {
        let quiet = (1...4).map { movie(title: "Reflective \($0)", genres: ["Drama"]) }
        let spectacle = movie(title: "Spectacle", genres: ["Drama", "Action", "Adventure"])
        spectacle.isLiked = true
        spectacle.userRating = 10
        spectacle.tmdbVoteAverage = 10
        spectacle.tmdbVoteCount = 100_000
        let history = quiet.map {
            RecommendationEvent(movie: $0, recommendedAt: now, kind: .bestMatch)
        }
        for seed in UInt64(0)..<50 {
            let picks = RecommendationEngine.recommendations(
                from: quiet + [spectacle], history: history,
                preferences: RecommendationPreferences(
                    mood: .quietAndThoughtful, somethingOlder: true, moreAdventurous: true
                ), now: now, seed: seed
            )
            XCTAssertTrue(picks.isEmpty)
        }
    }

    func testSparseMoodPoolReturnsFewerPicksWithoutUnrelatedFiller() {
        let quiet = movie(title: "Quiet", genres: ["Drama"])
        let action = movie(title: "Action", genres: ["Action"])
        let preferences = RecommendationPreferences(mood: .quietAndThoughtful)
        let picks = RecommendationEngine.recommendations(
            from: [quiet, action], preferences: preferences, now: now, seed: 4
        )
        XCTAssertEqual(picks.map(\.movie.id), [quiet.id])
        XCTAssertEqual(picks.first?.kind, .bestMatch)
        XCTAssertTrue(RecommendationEngine.recommendations(
            from: [action], preferences: preferences, now: now, seed: 4
        ).isEmpty)
    }

    func testNewMoodDoesNotDisplayPreviousMoodSession() {
        let drama = movie(title: "Drama", genres: ["Drama"])
        let event = RecommendationEvent(movie: drama, recommendedAt: now, kind: .bestMatch)
        XCTAssertTrue(RecommendationEngine.activeEvents(
            from: [event], preferences: RecommendationPreferences(mood: .quietAndThoughtful)
        ).isEmpty)
        event.moodRawValue = RecommendationMood.quietAndThoughtful.rawValue
        XCTAssertEqual(RecommendationEngine.activeEvents(
            from: [event], preferences: RecommendationPreferences(mood: .quietAndThoughtful)
        ).map(\.id), [event.id])
    }

    func testComfortUsesExplicitFavoritesRatherThanEveryWatchedMovie() {
        let horror = movie(title: "Horror", genres: ["Horror"])
        horror.isWatched = true
        XCTAssertFalse(RecommendationEngine.matchesMood(horror, mood: .comfortWatch))
        horror.isLiked = true
        XCTAssertTrue(RecommendationEngine.matchesMood(horror, mood: .comfortWatch))
        XCTAssertFalse(RecommendationEngine.matchesMood(horror, mood: .funAndEasy))
    }

    func testOverviewSignalsUseWholeWordsAndTuningStillApplies() {
        let drama = movie(title: "Quiet Drama", genres: ["Drama"], runtime: 160)
        drama.overviewText = "An award brings a rewarding friendship."
        XCTAssertTrue(RecommendationEngine.matchesMood(drama, mood: .quietAndThoughtful))
        XCTAssertFalse(RecommendationEngine.isEligible(drama, preferences: RecommendationPreferences(
            mood: .quietAndThoughtful, underTwoHours: true
        )))
        drama.overviewText = "A woman is kidnapped and held hostage."
        XCTAssertFalse(RecommendationEngine.matchesMood(drama, mood: .quietAndThoughtful))
    }

    func testBrowsingLargeLibraryShowsEveryMovieBeforeRepeating() {
        let movies = (1...907).map {
            movie(title: "Movie \($0)", genres: $0.isMultiple(of: 2) ? ["Drama"] : ["Comedy"],
                  runtime: 80 + $0 % 90, year: 1960 + $0 % 65,
                  voteAverage: $0 <= 50 ? 10 : 6, voteCount: $0 <= 50 ? 100_000 : 500)
        }
        var history: [RecommendationEvent] = []
        var shownIDs: Set<UUID> = []
        for batch in 0..<303 {
            let date = now.addingTimeInterval(Double(batch))
            let preferences = RecommendationPreferences(mood: batch.isMultiple(of: 2) ? .anything : .surpriseMe)
            let batchResult = RecommendationEngine.nextBatch(
                from: movies, history: history, preferences: preferences, now: date, seed: UInt64(batch)
            )
            let picks = batchResult.picks
            XCTAssertEqual(picks.count, min(3, movies.count - shownIDs.count))
            for pick in picks {
                XCTAssertTrue(shownIDs.insert(pick.movie.id).inserted, "Repeated \(pick.movie.title) in batch \(batch)")
                history.append(RecommendationEvent(movie: pick.movie, recommendedAt: date,
                    kind: pick.kind, mood: preferences.mood,
                    response: batch.isMultiple(of: 2) ? .notTonight : .pending,
                    rotationID: batchResult.rotationID))
            }
        }
        XCTAssertEqual(shownIDs.count, 907)
        let next = RecommendationEngine.nextBatch(from: movies, history: history,
            now: now.addingTimeInterval(86_400 * 365), seed: 42)
        XCTAssertEqual(next.picks.count, 3)
        XCTAssertNotNil(next.rotationID)
    }

    func testTenMoviesAllAppearBeforeAnyRepeatAcrossRepeatedBrowsing() {
        let movies = (1...10).map { movie(title: "Movie \($0)", genres: ["Comedy"]) }
        var history: [RecommendationEvent] = []
        var shown: [UUID] = []
        for refresh in 0..<12 {
            let date = now.addingTimeInterval(Double(refresh) * 86_400)
            let batch = RecommendationEngine.nextBatch(from: movies, history: history,
                preferences: RecommendationPreferences(mood: refresh.isMultiple(of: 2) ? .anything : .funAndEasy),
                now: date, seed: UInt64(refresh))
            XCTAssertEqual(batch.picks.count, refresh % 4 == 3 ? 1 : 3)
            for pick in batch.picks {
                shown.append(pick.movie.id)
                pick.movie.recommendationCount += 1
                pick.movie.lastRecommendedDate = date
                history.append(RecommendationEvent(movie: pick.movie, recommendedAt: date,
                    kind: pick.kind, response: .notTonight, rotationID: batch.rotationID))
            }
        }
        XCTAssertEqual(shown.count, 30)
        for start in stride(from: 0, to: 30, by: 10) {
            XCTAssertEqual(Set(shown[start..<start + 10]), Set(movies.map(\.id)))
        }
    }

    func testSmallLibrariesContinueAutomaticallyAfterAllMoviesWereShown() {
        for count in 1...3 {
            let movies = (1...count).map { movie(title: "Movie \($0)", genres: ["Comedy"]) }
            let history = movies.map { RecommendationEvent(movie: $0, recommendedAt: now,
                kind: .bestMatch, response: .notTonight) }
            let next = RecommendationEngine.nextBatch(from: movies, history: history,
                now: now.addingTimeInterval(1), seed: 1)
            XCTAssertEqual(Set(next.picks.map(\.movie.id)), Set(movies.map(\.id)))
            XCTAssertNotNil(next.rotationID)
        }
    }

    func testMoodAndRuntimeFiltersCannotRecycleMoviesWhileLibraryRemains() {
        let shown = movie(title: "Shown Comedy", genres: ["Comedy"], runtime: 90)
        let remaining = movie(title: "Remaining Action", genres: ["Action"], runtime: 150)
        let history = [RecommendationEvent(movie: shown, recommendedAt: now, kind: .bestMatch)]
        for preferences in [RecommendationPreferences(mood: .funAndEasy),
                            RecommendationPreferences(underTwoHours: true)] {
            let next = RecommendationEngine.nextBatch(from: [shown, remaining], history: history,
                preferences: preferences, now: now.addingTimeInterval(86_400), seed: 1)
            XCTAssertTrue(next.picks.isEmpty)
            XCTAssertNil(next.rotationID)
        }
        XCTAssertEqual(RecommendationEngine.recommendations(from: [shown, remaining], history: history,
            now: now, seed: 1).map(\.movie.id), [remaining.id])
    }

    func testExistingFullHistoryDoesNotExhaustLibraryPermanently() {
        let movies = (1...10).map { movie(title: "Movie \($0)", genres: ["Drama"]) }
        let old = movies.map { movie in
            movie.recommendationCount = 4
            movie.lastRecommendedDate = now.addingTimeInterval(-86_400)
            return RecommendationEvent(movie: movie, recommendedAt: now.addingTimeInterval(-86_400),
                kind: .bestMatch, response: .notTonight)
        }
        let first = RecommendationEngine.nextBatch(from: movies, history: old, now: now, seed: 1)
        XCTAssertEqual(first.picks.count, 3)
        XCTAssertNotNil(first.rotationID)
        let current = first.picks.map { RecommendationEvent(movie: $0.movie, recommendedAt: now,
            kind: $0.kind, rotationID: first.rotationID) }
        let remaining = RecommendationEngine.recommendationPool(from: movies, history: old + current,
            preferences: RecommendationPreferences())
        XCTAssertEqual(remaining.movies.count, 7)
        XCTAssertTrue(Set(remaining.movies.map(\.id)).isDisjoint(with: first.picks.map(\.movie.id)))
        XCTAssertFalse(remaining.startsNewRotation)
    }

    func testEveryResponseStaysExcludedAcrossMoodChangesAndTime() {
        let shown = RecommendationResponse.allCases.map { movie(title: $0.rawValue, genres: ["Comedy"]) }
        let history = zip(shown, RecommendationResponse.allCases).map { movie, response in
            RecommendationEvent(movie: movie, recommendedAt: now.addingTimeInterval(-86_400 * 365),
                kind: .bestMatch, mood: .anything, response: response)
        }
        let fresh = (1...2).map { movie(title: "Unseen \($0)", genres: ["Comedy"]) }
        let preferences = RecommendationPreferences(mood: .funAndEasy, underTwoHours: true)
        let picks = RecommendationEngine.recommendations(from: shown + fresh, history: history,
            preferences: preferences, now: now, seed: 9)
        XCTAssertEqual(Set(picks.map(\.movie.id)), Set(fresh.map(\.id)))
    }

    func testLifetimeCountersDoNotPermanentlyExcludeMoviesAndTMDBIdentityPreventsRepeats() {
        let original = movie(title: "Original", genres: ["Drama"])
        original.tmdbID = 123
        let restored = movie(title: "Restored", genres: ["Drama"])
        restored.tmdbID = 123
        let counted = movie(title: "Counted", genres: ["Drama"])
        counted.recommendationCount = 1
        let dated = movie(title: "Dated", genres: ["Drama"])
        dated.lastRecommendedDate = now.addingTimeInterval(-86_400 * 365)
        let fresh = movie(title: "Fresh", genres: ["Drama"])
        let history = [RecommendationEvent(movie: original, recommendedAt: now, kind: .bestMatch)]
        XCTAssertEqual(Set(RecommendationEngine.recommendations(from: [restored, counted, dated, fresh],
            history: history, now: now, seed: 1).map(\.movie.id)), Set([counted.id, dated.id, fresh.id]))
    }

    func testNotTonightImmediatelyLeavesActivePicksAndWidget() {
        let skipped = RecommendationEvent(movie: movie(title: "Skipped", genres: ["Drama"]),
            recommendedAt: now, kind: .bestMatch, response: .notTonight)
        XCTAssertTrue(RecommendationEngine.activeEvents(from: [skipped],
            preferences: RecommendationPreferences()).isEmpty)
        XCTAssertTrue(RecommendationResponse.notTonight.removesMovieFromActivePicks)
    }

    func testRemoteBrowsingProgressHidesAStaleLocalRecommendationCard() {
        let film = movie(title: "Shown Elsewhere", genres: ["Drama"])
        let event = RecommendationEvent(movie: film, recommendedAt: now, kind: .bestMatch)
        film.browsingProgress = LibraryBrowsingProgress(generation: 0,
            shownAt: now.addingTimeInterval(1), eventID: UUID())
        XCTAssertTrue(RecommendationEngine.activeEvents(from: [event],
            preferences: RecommendationPreferences()).isEmpty)
        film.browsingProgress = LibraryBrowsingProgress(generation: 0, shownAt: now, eventID: event.id)
        XCTAssertEqual(RecommendationEngine.activeEvents(from: [event],
            preferences: RecommendationPreferences()).map(\.id), [event.id])
    }

    @MainActor
    func testSavedExposureSurvivesReopeningLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("library.store"),
                                               cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: Movie.self, RecommendationEvent.self,
                                               configurations: configuration)
            let shown = movie(title: "Already Shown", genres: ["Drama"])
            let fresh = movie(title: "Unseen", genres: ["Drama"])
            container.mainContext.insert(shown)
            container.mainContext.insert(fresh)
            for movie in [shown, fresh] {
                container.mainContext.insert(RecommendationEvent(movie: movie,
                    recommendedAt: now.addingTimeInterval(-86_400), kind: .bestMatch,
                    response: .notTonight))
            }
            container.mainContext.insert(RecommendationEvent(movie: shown, recommendedAt: now,
                kind: .bestMatch, response: .notTonight, rotationID: UUID()))
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: Movie.self, RecommendationEvent.self,
                                          configurations: configuration)
        let movies = try reopened.mainContext.fetch(FetchDescriptor<Movie>())
        let history = try reopened.mainContext.fetch(FetchDescriptor<RecommendationEvent>())
        XCTAssertEqual(history.compactMap(\.rotationID).count, 1)
        let picks = RecommendationEngine.recommendations(from: movies, history: history,
            now: now.addingTimeInterval(86_400 * 365), seed: 5)
        XCTAssertEqual(picks.map(\.movie.title), ["Unseen"])
        XCTAssertTrue(RecommendationEngine.activeEvents(from: history,
            preferences: RecommendationPreferences()).isEmpty)
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
