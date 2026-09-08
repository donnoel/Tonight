import Foundation

enum RecommendationMood: String, Codable, CaseIterable, Identifiable, Sendable {
    case anything
    case funAndEasy
    case edgeOfYourSeat
    case quietAndThoughtful
    case bigMovieNight
    case comfortWatch
    case surpriseMe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anything: "Anything"
        case .funAndEasy: "Fun & Easy"
        case .edgeOfYourSeat: "Edge of Your Seat"
        case .quietAndThoughtful: "Quiet & Thoughtful"
        case .bigMovieNight: "Big Movie Night"
        case .comfortWatch: "Comfort Watch"
        case .surpriseMe: "Surprise Me"
        }
    }

    var systemImage: String {
        switch self {
        case .anything: "sparkles"
        case .funAndEasy: "face.smiling"
        case .edgeOfYourSeat: "bolt.fill"
        case .quietAndThoughtful: "brain.head.profile"
        case .bigMovieNight: "popcorn.fill"
        case .comfortWatch: "sofa.fill"
        case .surpriseMe: "dice.fill"
        }
    }

    var detail: String {
        switch self {
        case .anything:
            "A balanced mix shaped by your taste and recent choices."
        case .funAndEasy:
            "Lighter, approachable movies with an easy pace and upbeat energy."
        case .edgeOfYourSeat:
            "Tense, propulsive movies with momentum and suspense."
        case .quietAndThoughtful:
            "Reflective stories that reward attention without needing spectacle."
        case .bigMovieNight:
            "Ambitious, crowd-pleasing movies that feel like an event."
        case .comfortWatch:
            "Familiar, well-liked choices and warm movies that are easy to settle into."
        case .surpriseMe:
            "Credible left-field choices from less-used corners of your library."
        }
    }
}

struct RecommendationPreferences: Equatable, Sendable {
    var mood: RecommendationMood = .anything
    var underTwoHours = false
    var unwatchedOnly = false
    var somethingOlder = false
    var moreAdventurous = false

    var activeModifierCount: Int {
        [underTwoHours, unwatchedOnly, somethingOlder, moreAdventurous]
            .filter { $0 }
            .count
    }
}

struct RecommendationPick: Identifiable {
    let kind: RecommendationKind
    let movie: Movie
    let rationale: String

    var id: UUID { movie.id }
}

struct RecommendationBatch {
    let picks: [RecommendationPick]
    let rotationID: UUID?
    let browsingGeneration: Int
}

struct RecommendationPool {
    let movies: [Movie]
    let rotationID: UUID?
    let startsNewRotation: Bool
    let browsingGeneration: Int
}

enum RecommendationEngine {
    static func rankDeals(
        candidates: [DealRecommendationCandidate],
        tasteLibrary: [Movie],
        history: [RecommendationEvent] = [],
        now: Date = .now
    ) -> [DealRecommendationRank] {
        let eligible = candidates.filter {
            $0.movie.resolutionStatus == .resolved && !$0.movie.isDisliked
        }
        guard !eligible.isEmpty else { return [] }

        let profile = tasteProfile(
            from: tasteLibrary,
            history: history,
            mood: .anything
        )
        let movies = eligible.map(\.movie)
        let genreFrequencies = genreFrequencies(in: movies)
        let preferences = RecommendationPreferences()

        return eligible.map { candidate in
            let score = baseScore(
                for: candidate.movie,
                profile: profile,
                genreFrequencies: genreFrequencies,
                preferences: preferences,
                historyPenalty: 0,
                now: now
            )
            return DealRecommendationRank(
                id: candidate.id,
                score: score,
                rationale: dealRationale(
                    for: candidate.movie,
                    profile: profile
                )
            )
        }
        .sorted { left, right in
            if left.score != right.score { return left.score > right.score }
            return left.id < right.id
        }
    }

    static func recommendations(
        from movies: [Movie],
        history: [RecommendationEvent] = [],
        preferences: RecommendationPreferences = RecommendationPreferences(),
        now: Date = .now,
        seed: UInt64? = nil
    ) -> [RecommendationPick] {
        nextBatch(from: movies, history: history, preferences: preferences, now: now, seed: seed).picks
    }

    static func nextBatch(
        from movies: [Movie],
        history: [RecommendationEvent] = [],
        preferences: RecommendationPreferences = RecommendationPreferences(),
        now: Date = .now,
        seed: UInt64? = nil
    ) -> RecommendationBatch {
        let pool = recommendationPool(from: movies, history: history, preferences: preferences)
        let rotationID = pool.startsNewRotation ? UUID() : pool.rotationID
        return RecommendationBatch(
            picks: selectRecommendations(from: movies, candidates: pool.movies, history: history,
                                         preferences: preferences, now: now, seed: seed),
            rotationID: rotationID,
            browsingGeneration: pool.browsingGeneration
        )
    }

    private static func selectRecommendations(
        from movies: [Movie],
        candidates availableMovies: [Movie],
        history: [RecommendationEvent],
        preferences: RecommendationPreferences,
        now: Date,
        seed: UInt64?
    ) -> [RecommendationPick] {
        let eligible = movies.filter { isEligible($0, preferences: preferences) }
        var remaining = availableMovies
        guard !remaining.isEmpty else { return [] }
        let desiredCount = min(3, remaining.count)

        let profile = tasteProfile(
            from: movies,
            history: history,
            mood: preferences.mood
        )
        let genreFrequencies = genreFrequencies(in: eligible)
        let historyPenalties = historyPenalties(
            from: history,
            mood: preferences.mood,
            now: now
        )
        let baseScores = Dictionary(uniqueKeysWithValues: remaining.map { movie in
            (movie.id, baseScore(
                for: movie,
                profile: profile,
                genreFrequencies: genreFrequencies,
                preferences: preferences,
                historyPenalty: historyPenalties[movie.id, default: 0],
                now: now
            ))
        })
        var generator = SeededGenerator(seed: seed ?? defaultSeed(for: now))
        var kinds = recommendationKinds(
            for: remaining,
            preferences: preferences,
            now: now,
            generator: &generator
        )
        for fallback in [RecommendationKind.hiddenGem, .deepCut, .wildcard]
            where !kinds.contains(fallback) {
            kinds.append(fallback)
        }
        var chosen: [Movie] = []
        var picks: [RecommendationPick] = []

        for (index, kind) in kinds.enumerated() {
            if picks.count == desiredCount { break }

            var selectionPool = candidates(
                in: remaining,
                for: kind,
                now: now
            )
            guard !selectionPool.isEmpty else { continue }

            let reservedIDs = Set(
                kinds.dropFirst(index + 1).compactMap { futureKind -> UUID? in
                    guard futureKind.requiresSpecificCandidate else { return nil }
                    let futureCandidates = candidates(
                        in: remaining,
                        for: futureKind,
                        now: now
                    )
                    return futureCandidates.count == 1 ? futureCandidates[0].id : nil
                }
            )
            let unreserved = selectionPool.filter { !reservedIDs.contains($0.id) }
            if !unreserved.isEmpty {
                selectionPool = unreserved
            }

            guard let movie = weightedSelection(
                from: selectionPool,
                generator: &generator,
                score: {
                    baseScores[$0.id, default: 0]
                    + laneScore(
                        for: $0,
                        kind: kind,
                        genreFrequencies: genreFrequencies,
                        now: now
                    )
                    - diversityPenalty(for: $0, comparedWith: chosen)
                }
            ) else { continue }

            chosen.append(movie)
            remaining.removeAll { $0.id == movie.id }
            picks.append(
                RecommendationPick(
                    kind: kind,
                    movie: movie,
                    rationale: rationale(
                        for: movie,
                        kind: kind,
                        mood: preferences.mood
                    )
                )
            )

            if remaining.isEmpty { break }
        }

        return picks
    }

    /// Complete the library before allowing repeats. Mood/runtime changes cannot reset progress.
    /// Shared exposure markers are monotonic; legacy local history supplies initial progress only.
    static func recommendationPool(
        from movies: [Movie],
        history: [RecommendationEvent],
        preferences: RecommendationPreferences
    ) -> RecommendationPool {
        let rotationID = history.max { $0.recommendedAt < $1.recommendedAt }?.rotationID
        let generation = (movies.compactMap(\.browsingGeneration) + history.compactMap(\.browsingGeneration)).max() ?? 0
        let rotationHistory = history.filter {
            if let value = $0.browsingGeneration { return value == generation }
            return generation == 0 && $0.rotationID == rotationID
        }
        let libraryPreferences = RecommendationPreferences(unwatchedOnly: preferences.unwatchedOnly)
        let library = movies.filter { isEligible($0, preferences: libraryPreferences) }
        let unseenLibrary = unseenMovies(from: library, history: rotationHistory).filter {
            ($0.browsingGeneration ?? -1) < generation
        }
        let startsNewRotation = !library.isEmpty && unseenLibrary.isEmpty
        return RecommendationPool(
            movies: (startsNewRotation ? library : unseenLibrary).filter {
                isEligible($0, preferences: preferences)
            },
            rotationID: rotationID,
            startsNewRotation: startsNewRotation,
            browsingGeneration: generation + (startsNewRotation ? 1 : 0)
        )
    }

    private static func unseenMovies(
        from movies: [Movie],
        history: [RecommendationEvent]
    ) -> [Movie] {
        let shownMovies = history.compactMap(\.movie)
        let shownIDs = Set(shownMovies.map(\.id))
        let shownTMDBIDs = Set(shownMovies.compactMap(\.tmdbID))
        return movies.filter { movie in
            !shownIDs.contains(movie.id)
                && !(movie.tmdbID.map { shownTMDBIDs.contains($0) } ?? false)
        }
    }

    static func isEligible(
        _ movie: Movie,
        preferences: RecommendationPreferences
    ) -> Bool {
        movie.resolutionStatus == .resolved
            && !movie.isDisliked
            && matchesMood(movie, mood: preferences.mood)
            && (!preferences.underTwoHours || (movie.runtimeMinutes ?? .max) <= 120)
            && (!preferences.unwatchedOnly || !movie.isWatched)
    }

    /// Establish mood suitability before taste, cooldown, lanes, or randomness can rank a film.
    /// These conservative rules use local metadata, not a claim to understand every story.
    static func matchesMood(_ movie: Movie, mood: RecommendationMood) -> Bool {
        let genres = Set(movie.genres.map { $0.lowercased() })
        func has(_ values: Set<String>) -> Bool { !genres.isDisjoint(with: values) }
        let words = Set(movie.overviewText.lowercased().split { !$0.isLetter }.map(String.init))
        let violentStory = !words.isDisjoint(with: [
            "war", "wars", "warfare", "battle", "battles", "combat", "invasion",
            "murder", "murders", "killer", "killers", "assassin", "assassins",
            "massacre", "terrorist", "terrorists", "torture", "slasher"
        ])
        let tenseStory = violentStory || !words.isDisjoint(with: [
            "kidnapped", "abducted", "hostage", "hostages", "hunted", "terrifying"
        ])
        let intenseGenres = has(["action", "war", "horror", "thriller", "crime"])
        let lightGenres = has(["comedy", "family", "animation", "music", "romance"])

        switch mood {
        case .anything, .surpriseMe:
            // Surprise is a discovery preference, not a particular emotional tone.
            return true
        case .quietAndThoughtful:
            return !intenseGenres && !tenseStory
                && !has(["adventure"])
                && has(["drama", "documentary", "history", "romance"])
        case .funAndEasy:
            return lightGenres && !intenseGenres && !tenseStory
                && (movie.runtimeMinutes.map { $0 <= 140 } ?? true)
        case .edgeOfYourSeat:
            return has(["thriller", "horror", "action", "crime"])
                || (has(["mystery", "adventure", "science fiction"]) && tenseStory)
        case .bigMovieNight:
            return has(["action", "adventure", "fantasy", "science fiction", "war"])
                || (has(["drama", "history", "music"])
                    && (movie.runtimeMinutes ?? 0) >= 150
                    && (movie.tmdbVoteAverage ?? 0) >= 7)
        case .comfortWatch:
            // Explicit favorites are personal comfort choices, even in intense genres.
            return movie.isLiked || (lightGenres && !intenseGenres && !tenseStory)
        }
    }

    static func activeEvents(
        from events: [RecommendationEvent],
        preferences: RecommendationPreferences
    ) -> [RecommendationEvent] {
        guard let latestDate = events.compactMap({ event in
            event.movie == nil ? nil : event.recommendedAt
        }).max() else {
            return []
        }

        return events
            .filter { event in
                guard event.recommendedAt == latestDate,
                      event.mood == preferences.mood,
                      let movie = event.movie else {
                    return false
                }

                if event.response == .accepted {
                    return true
                }

                guard event.response != .watched,
                      event.response != .rejected,
                      event.response != .notTonight else {
                    return false
                }

                if let shownEvent = movie.browsingEventID, shownEvent != event.id {
                    return false
                }

                return isEligible(movie, preferences: preferences)
            }
            .sorted { $0.kind.sortOrder < $1.kind.sortOrder }
    }

    static func rationale(
        for movie: Movie,
        kind: RecommendationKind,
        mood: RecommendationMood = .anything
    ) -> String {
        switch kind {
        case .bestMatch:
            let detail = movie.isWatched ? "a familiar option" : "an unwatched option"
            return "The strongest \(mood.title.lowercased()) fit tonight, balancing your taste, quality, and \(detail)."

        case .hiddenGem:
            if let rating = movie.tmdbVoteAverage {
                return "A less obvious library pick that still carries a solid \(rating.formatted(.number.precision(.fractionLength(1)))) rating."
            }
            return "A less obvious, under-recommended title that deserves a closer look."

        case .shortAndSharp:
            if let runtime = movie.runtimeMinutes {
                return "A complete movie-night option in a focused \(runtime)-minute package."
            }
            return "A brisker choice that keeps tonight’s commitment manageable."

        case .comfortRewatch:
            if movie.isLiked {
                return "A familiar favorite that fits a low-friction comfort-watch night."
            }
            return "A familiar choice from your watch history that is easy to settle back into."

        case .differentDecade:
            if let year = movie.releaseYear {
                return "A strong change of era from \(year), selected to keep tonight’s choices from feeling too similar."
            }
            return "A change of era that broadens tonight’s recommendation mix."

        case .deepCut, .forgottenOne:
            if movie.recommendationCount == 0 {
                return "It has been sitting in your library without ever getting a recommendation."
            }
            return "It has been out of the recommendation rotation long enough to deserve another look."

        case .wildcard:
            return "A credible left-field choice selected to break up familiar genres, eras, and recent recommendation patterns."
        }
    }

    private static func recommendationKinds(
        for movies: [Movie],
        preferences: RecommendationPreferences,
        now: Date,
        generator: inout SeededGenerator
    ) -> [RecommendationKind] {
        var result: [RecommendationKind] = [.bestMatch]
        var preferred: [RecommendationKind] = []

        if preferences.underTwoHours, movies.contains(where: { ($0.runtimeMinutes ?? .max) <= 120 }) {
            preferred.append(.shortAndSharp)
        }
        if preferences.somethingOlder, movies.contains(where: { isOlder($0, now: now) }) {
            preferred.append(.differentDecade)
        }
        if preferences.mood == .comfortWatch,
           movies.contains(where: { $0.isWatched || $0.isLiked }) {
            preferred.append(.comfortRewatch)
        }
        if preferences.moreAdventurous || preferences.mood == .surpriseMe {
            preferred.append(.wildcard)
        }

        for kind in preferred where result.count < min(3, movies.count) && !result.contains(kind) {
            result.append(kind)
        }

        var available: [RecommendationKind] = [.hiddenGem, .deepCut, .wildcard]
        if movies.contains(where: { ($0.runtimeMinutes ?? .max) <= 120 }) {
            available.append(.shortAndSharp)
        }
        if movies.contains(where: { $0.isWatched || $0.isLiked }) {
            available.append(.comfortRewatch)
        }
        if movies.contains(where: { isOlder($0, now: now) }) {
            available.append(.differentDecade)
        }
        available.shuffle(using: &generator)

        for kind in available where result.count < min(3, movies.count) && !result.contains(kind) {
            result.append(kind)
        }

        return result
    }

    private static func candidates(
        in movies: [Movie],
        for kind: RecommendationKind,
        now: Date
    ) -> [Movie] {
        switch kind {
        case .shortAndSharp:
            movies.filter { ($0.runtimeMinutes ?? .max) <= 120 }
        case .comfortRewatch:
            movies.filter { $0.isWatched || $0.isLiked }
        case .differentDecade:
            movies.filter { isOlder($0, now: now) }
        case .bestMatch, .hiddenGem, .deepCut, .wildcard, .forgottenOne:
            movies
        }
    }

    private static func baseScore(
        for movie: Movie,
        profile: TasteProfile,
        genreFrequencies: [String: Int],
        preferences: RecommendationPreferences,
        historyPenalty: Double,
        now: Date
    ) -> Double {
        let genreTaste = movie.genres.reduce(0.0) {
            $0 + profile.genres[$1.lowercased(), default: 0]
        }
        let castTaste = movie.primaryCast.prefix(4).reduce(0.0) {
            $0 + profile.people[$1.lowercased(), default: 0]
        }
        let directorTaste = movie.director.map {
            profile.people[$0.lowercased(), default: 0]
        } ?? 0
        let languageTaste = movie.originalLanguage.map {
            profile.languages[$0.lowercased(), default: 0]
        } ?? 0
        let decadeTaste = movie.releaseYear.map {
            profile.decades[($0 / 10) * 10, default: 0]
        } ?? 0
        let popularityConfidence = min(log10(Double((movie.tmdbVoteCount ?? 0) + 1)) * 1.5, 8)
        let adventurousBonus = preferences.moreAdventurous
            ? adventurousScore(for: movie, genreFrequencies: genreFrequencies)
            : 0

        return moodScore(for: movie, mood: preferences.mood, now: now)
            + min(genreTaste, 24)
            + min(castTaste, 8)
            + min(directorTaste, 8)
            + min(languageTaste, 5)
            + min(decadeTaste, 6)
            + (movie.isLiked ? 18 : 0)
            + ((movie.userRating ?? 0) * 1.6)
            + (movie.isWatched ? 0 : 7)
            + ((movie.tmdbVoteAverage ?? 0) * 1.7)
            + popularityConfidence
            + (preferences.somethingOlder && isOlder(movie, now: now) ? 18 : 0)
            + adventurousBonus
            - Double(movie.recommendationCount * 3)
            - recentRecommendationPenalty(for: movie, now: now)
            - historyPenalty
    }

    private static func moodScore(
        for movie: Movie,
        mood: RecommendationMood,
        now: Date
    ) -> Double {
        let genres = Set(movie.genres.map { $0.lowercased() })
        let runtime = movie.runtimeMinutes ?? 120
        let voteAverage = movie.tmdbVoteAverage ?? 0
        let voteCount = movie.tmdbVoteCount ?? 0

        switch mood {
        case .anything:
            return 0
        case .funAndEasy:
            return overlapScore(genres, ["comedy", "animation", "family", "music", "adventure"], weight: 15)
                + (runtime <= 120 ? 12 : -8)
                + (voteAverage >= 6.5 ? 5 : 0)
        case .edgeOfYourSeat:
            return overlapScore(genres, ["thriller", "action", "crime", "mystery", "horror", "adventure"], weight: 14)
                + (runtime <= 150 ? 6 : 0)
                + (voteAverage >= 7 ? 6 : 0)
        case .quietAndThoughtful:
            return overlapScore(genres, ["drama", "documentary", "history", "romance", "mystery"], weight: 13)
                + (runtime <= 145 ? 4 : 0)
                + (voteAverage >= 7 ? 10 : 0)
                + (voteCount < 20_000 ? 5 : 0)
        case .bigMovieNight:
            return overlapScore(genres, ["action", "adventure", "fantasy", "science fiction", "war"], weight: 12)
                + (runtime >= 120 ? 13 : 0)
                + (voteCount >= 5_000 ? 10 : 0)
                + (voteAverage >= 7 ? 8 : 0)
        case .comfortWatch:
            return overlapScore(genres, ["comedy", "family", "animation", "romance", "music"], weight: 10)
                + (movie.isWatched ? 24 : 0)
                + (movie.isLiked ? 18 : 0)
                + (runtime <= 130 ? 8 : 0)
        case .surpriseMe:
            return (movie.recommendationCount == 0 ? 18 : 0)
                + (movie.isWatched ? 0 : 10)
                + (isOlder(movie, now: now) ? 7 : 0)
                + (movie.originalLanguage?.lowercased() == "en" ? 0 : 8)
        }
    }

    private static func laneScore(
        for movie: Movie,
        kind: RecommendationKind,
        genreFrequencies: [String: Int],
        now: Date
    ) -> Double {
        switch kind {
        case .bestMatch:
            10
        case .hiddenGem:
            (movie.tmdbVoteAverage ?? 0) * 2
                + ((movie.tmdbVoteCount ?? 0) < 10_000 ? 12 : 0)
                + (movie.recommendationCount == 0 ? 12 : 0)
        case .shortAndSharp:
            movie.runtimeMinutes.map { max(125 - Double($0), 0) / 2 } ?? 0
        case .comfortRewatch:
            (movie.isWatched ? 25 : 0) + (movie.isLiked ? 20 : 0)
        case .differentDecade:
            isOlder(movie, now: now) ? 24 : 0
        case .deepCut, .forgottenOne:
            forgottenScore(for: movie, now: now)
        case .wildcard:
            adventurousScore(for: movie, genreFrequencies: genreFrequencies)
                + (movie.recommendationCount == 0 ? 15 : 0)
        }
    }

    private static func adventurousScore(
        for movie: Movie,
        genreFrequencies: [String: Int]
    ) -> Double {
        let rarity = movie.genres.reduce(0.0) { result, genre in
            result + 15 / Double(max(genreFrequencies[genre.lowercased()] ?? 1, 1))
        }
        return rarity
            + (movie.originalLanguage?.lowercased() == "en" ? 0 : 10)
            + ((movie.tmdbVoteCount ?? 0) < 5_000 ? 6 : 0)
    }

    private static func forgottenScore(for movie: Movie, now: Date) -> Double {
        let daysInLibrary = max(now.timeIntervalSince(movie.dateAdded) / 86_400, 0)
        let libraryAge = min(daysInLibrary / 30, 30)
        let timeOutOfRotation: Double
        if let lastRecommendedDate = movie.lastRecommendedDate {
            timeOutOfRotation = min(max(now.timeIntervalSince(lastRecommendedDate) / 86_400, 0), 180) / 4
        } else {
            timeOutOfRotation = 70
        }

        return (movie.isWatched ? 0 : 10)
            + libraryAge
            + timeOutOfRotation
            - Double(movie.recommendationCount * 5)
    }

    private static func weightedSelection(
        from movies: [Movie],
        generator: inout SeededGenerator,
        score: (Movie) -> Double
    ) -> Movie? {
        let ranked = movies.map { ($0, score($0)) }.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            let titleOrder = left.0.title.localizedStandardCompare(right.0.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return left.0.id.uuidString < right.0.id.uuidString
        }
        guard let bestScore = ranked.first?.1 else { return nil }

        let shortlist = ranked.prefix(15).filter { $0.1 >= bestScore - 12 }
        let floor = shortlist.map(\.1).min() ?? bestScore
        let weights = shortlist.map { max($0.1 - floor + 1, 1) }
        let total = weights.reduce(0, +)
        var target = Double.random(in: 0..<total, using: &generator)

        for (candidate, weight) in zip(shortlist, weights) {
            if target < weight { return candidate.0 }
            target -= weight
        }
        return shortlist.first?.0
    }

    private static func diversityPenalty(
        for movie: Movie,
        comparedWith selected: [Movie]
    ) -> Double {
        selected.reduce(0.0) { result, existing in
            let movieGenres = Set(movie.genres.map { $0.lowercased() })
            let existingGenres = Set(existing.genres.map { $0.lowercased() })
            let sharedGenres = movieGenres.intersection(existingGenres).count
            let sameDirector = movie.director?.localizedCaseInsensitiveCompare(existing.director ?? "") == .orderedSame
            let sharedCast = !Set(movie.primaryCast.map { $0.lowercased() })
                .isDisjoint(with: Set(existing.primaryCast.map { $0.lowercased() }))
            let sameDecade = movie.releaseYear.map { ($0 / 10) * 10 }
                == existing.releaseYear.map { ($0 / 10) * 10 }

            return result
                + Double(sharedGenres * 9)
                + (sameDirector ? 24 : 0)
                + (sharedCast ? 14 : 0)
                + (sameDecade ? 7 : 0)
        }
    }

    private static func tasteProfile(
        from movies: [Movie],
        history: [RecommendationEvent],
        mood: RecommendationMood
    ) -> TasteProfile {
        var profile = TasteProfile()

        for movie in movies {
            var signal = 0.0
            if movie.isLiked { signal += 5 }
            if movie.isDisliked { signal -= 6 }
            if let rating = movie.userRating { signal += (rating - 5) / 2 }
            guard signal != 0 else { continue }
            profile.record(movie, signal: signal)
        }

        for event in history where event.response == .accepted {
            guard let movie = event.movie else { continue }
            let signal = event.mood == mood ? 4.5 : 2
            profile.record(movie, signal: signal)
        }

        return profile
    }

    private static func dealRationale(
        for movie: Movie,
        profile: TasteProfile
    ) -> String {
        let favoredGenres = movie.genres
            .filter { profile.genres[$0.lowercased(), default: 0] > 0 }
            .sorted {
                profile.genres[$0.lowercased(), default: 0]
                    > profile.genres[$1.lowercased(), default: 0]
            }
        let directorMatch = movie.director.flatMap { director in
            profile.people[director.lowercased(), default: 0] > 0 ? director : nil
        }
        let decadeMatch = movie.releaseYear.flatMap { year -> Int? in
            let decade = (year / 10) * 10
            return profile.decades[decade, default: 0] > 0 ? decade : nil
        }

        if let directorMatch, let genre = favoredGenres.first {
            return "Recommended because \(genre.lowercased()) and director \(directorMatch) both match movies you have responded to positively."
        }
        if favoredGenres.count >= 2 {
            return "Recommended because its \(favoredGenres[0].lowercased()) and \(favoredGenres[1].lowercased()) signals match movies you have responded to positively."
        }
        if let directorMatch {
            return "Recommended because director \(directorMatch) matches movies you have responded to positively."
        }
        if let genre = favoredGenres.first {
            return "Recommended because its \(genre.lowercased()) profile matches movies you have responded to positively."
        }
        if let decadeMatch {
            return "Recommended because movies from the \(decadeMatch)s have matched your positive taste signals."
        }
        if let rating = movie.tmdbVoteAverage, rating >= 7 {
            return "A strong deal candidate supported by a \(rating.formatted(.number.precision(.fractionLength(1)))) TMDB rating."
        }
        return "A current deal ranked from the metadata available while Tonight learns more about your taste."
    }

    private static func historyPenalties(
        from history: [RecommendationEvent],
        mood: RecommendationMood,
        now: Date
    ) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for event in history where event.response == .notTonight {
            guard let movie = event.movie else { continue }
            let days = max(now.timeIntervalSince(event.recommendedAt) / 86_400, 0)
            guard days < 21 else { continue }
            let decay = 1 - (days / 21)
            let sameMood = event.mood == mood ? 18.0 : 0
            result[movie.id, default: 0] += (42 + sameMood) * decay
        }
        return result
    }

    private static func genreFrequencies(in movies: [Movie]) -> [String: Int] {
        var result: [String: Int] = [:]
        for movie in movies {
            for genre in movie.genres {
                result[genre.lowercased(), default: 0] += 1
            }
        }
        return result
    }

    private static func recentRecommendationPenalty(for movie: Movie, now: Date) -> Double {
        guard let lastRecommendedDate = movie.lastRecommendedDate else { return 0 }
        let days = max(now.timeIntervalSince(lastRecommendedDate) / 86_400, 0)

        switch days {
        case 0..<1: return 1_000
        case 1..<7: return 120 - (days * 10)
        case 7..<30: return 45 - days
        default: return 0
        }
    }

    private static func isOlder(_ movie: Movie, now: Date) -> Bool {
        guard let year = movie.releaseYear else { return false }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: now)
        return year <= currentYear - 25
    }

    private static func overlapScore(
        _ movieGenres: Set<String>,
        _ moodGenres: Set<String>,
        weight: Double
    ) -> Double {
        Double(movieGenres.intersection(moodGenres).count) * weight
    }

    private static func defaultSeed(for date: Date) -> UInt64 {
        UInt64(bitPattern: Int64(date.timeIntervalSinceReferenceDate * 1_000))
    }
}

private struct TasteProfile {
    var genres: [String: Double] = [:]
    var people: [String: Double] = [:]
    var languages: [String: Double] = [:]
    var decades: [Int: Double] = [:]

    mutating func record(_ movie: Movie, signal: Double) {
        for genre in movie.genres {
            genres[genre.lowercased(), default: 0] += signal
        }
        if let director = movie.director {
            people[director.lowercased(), default: 0] += signal
        }
        for person in movie.primaryCast.prefix(4) {
            people[person.lowercased(), default: 0] += signal / 2
        }
        if let language = movie.originalLanguage {
            languages[language.lowercased(), default: 0] += signal / 2
        }
        if let year = movie.releaseYear {
            decades[(year / 10) * 10, default: 0] += signal / 2
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

extension RecommendationKind {
    fileprivate var requiresSpecificCandidate: Bool {
        switch self {
        case .shortAndSharp, .comfortRewatch, .differentDecade: true
        case .bestMatch, .hiddenGem, .deepCut, .wildcard, .forgottenOne: false
        }
    }

    var title: String {
        switch self {
        case .bestMatch: "Best Fit"
        case .hiddenGem: "Hidden Gem"
        case .shortAndSharp: "Short & Sharp"
        case .comfortRewatch: "Comfort Rewatch"
        case .differentDecade: "Different Decade"
        case .deepCut: "Deep Cut"
        case .wildcard: "Wildcard"
        case .forgottenOne: "Forgotten One"
        }
    }

    var systemImage: String {
        switch self {
        case .bestMatch: "sparkles"
        case .hiddenGem: "diamond.fill"
        case .shortAndSharp: "timer"
        case .comfortRewatch: "sofa.fill"
        case .differentDecade: "calendar"
        case .deepCut: "archivebox.fill"
        case .wildcard: "shuffle"
        case .forgottenOne: "archivebox"
        }
    }

    var sortOrder: Int {
        switch self {
        case .bestMatch: 0
        case .hiddenGem: 1
        case .shortAndSharp: 2
        case .comfortRewatch: 3
        case .differentDecade: 4
        case .deepCut: 5
        case .wildcard: 6
        case .forgottenOne: 7
        }
    }
}

extension RecommendationResponse {
    var removesMovieFromActivePicks: Bool {
        switch self {
        case .accepted, .rejected, .watched, .notTonight: true
        case .pending: false
        }
    }

    func applyMovieState(to movie: Movie?, at date: Date) {
        guard let movie else { return }

        switch self {
        case .accepted, .watched:
            movie.isWatched = true
            movie.dateWatched = movie.dateWatched ?? date
            movie.lastWatchedDate = date
            movie.watchedStateModifiedAt = date
        case .rejected:
            movie.isLiked = false
            movie.isDisliked = true
        case .pending, .notTonight:
            break
        }
    }

    var title: String {
        switch self {
        case .pending: "Awaiting your choice"
        case .accepted: "Chosen for tonight"
        case .rejected: "Not interested"
        case .notTonight: "Not tonight"
        case .watched: "Watched"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "hourglass"
        case .accepted: "checkmark.circle.fill"
        case .rejected: "xmark.circle"
        case .notTonight: "moon.zzz"
        case .watched: "eye.circle.fill"
        }
    }
}
