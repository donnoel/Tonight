import Foundation

struct RecommendationPick: Identifiable {
    let kind: RecommendationKind
    let movie: Movie
    let rationale: String

    var id: UUID { movie.id }
}

enum RecommendationEngine {
    static func recommendations(
        from movies: [Movie],
        preferredGenre: String? = nil,
        now: Date = .now
    ) -> [RecommendationPick] {
        let candidates = movies.filter {
            $0.resolutionStatus == .resolved && !$0.isDisliked
        }
        guard !candidates.isEmpty else { return [] }

        let tasteProfile = genreTasteProfile(from: movies)
        let genreFrequencies = genreFrequencies(in: candidates)
        var remaining = candidates
        var picks: [RecommendationPick] = []

        if let movie = select(from: remaining, score: {
            bestMatchScore(
                for: $0,
                preferredGenre: preferredGenre,
                tasteProfile: tasteProfile,
                now: now
            )
        }) {
            picks.append(
                RecommendationPick(
                    kind: .bestMatch,
                    movie: movie,
                    rationale: rationale(
                        for: movie,
                        kind: .bestMatch,
                        preferredGenre: preferredGenre
                    )
                )
            )
            remaining.removeAll { $0.id == movie.id }
        }

        if let movie = select(from: remaining, score: {
            wildcardScore(
                for: $0,
                bestMatch: picks.first?.movie,
                preferredGenre: preferredGenre,
                genreFrequencies: genreFrequencies,
                now: now
            )
        }) {
            picks.append(
                RecommendationPick(
                    kind: .wildcard,
                    movie: movie,
                    rationale: rationale(
                        for: movie,
                        kind: .wildcard,
                        preferredGenre: preferredGenre
                    )
                )
            )
            remaining.removeAll { $0.id == movie.id }
        }

        if let movie = select(from: remaining, score: {
            forgottenScore(
                for: $0,
                preferredGenre: preferredGenre,
                now: now
            )
        }) {
            picks.append(
                RecommendationPick(
                    kind: .forgottenOne,
                    movie: movie,
                    rationale: rationale(
                        for: movie,
                        kind: .forgottenOne,
                        preferredGenre: preferredGenre
                    )
                )
            )
        }

        return picks
    }

    static func rationale(
        for movie: Movie,
        kind: RecommendationKind,
        preferredGenre: String? = nil
    ) -> String {
        switch kind {
        case .bestMatch:
            if let preferredGenre, movie.hasGenre(preferredGenre) {
                return "A strong \(preferredGenre.lowercased()) fit, balanced with your taste and recommendation history."
            }
            if movie.isLiked || (movie.userRating ?? 0) >= 7.5 {
                return "Your personal taste signals make this one of tonight’s strongest fits."
            }
            if !movie.isWatched {
                return "A highly regarded unwatched movie from your own collection."
            }
            return "The strongest overall fit after balancing quality, taste, and recent recommendations."

        case .wildcard:
            if let preferredGenre, movie.hasGenre(preferredGenre) {
                return "A less obvious \(preferredGenre.lowercased()) choice that still fits tonight’s mood."
            }
            return "A change of pace from the obvious pick, chosen from a less-used corner of your library."

        case .forgottenOne:
            if movie.recommendationCount == 0 {
                return "It has been sitting in your library without ever getting a recommendation."
            }
            return "It has been out of the recommendation rotation long enough to deserve another look."
        }
    }

    private static func bestMatchScore(
        for movie: Movie,
        preferredGenre: String?,
        tasteProfile: [String: Double],
        now: Date
    ) -> Double {
        let learnedTaste = movie.genres.reduce(0.0) {
            $0 + (tasteProfile[$1.lowercased()] ?? 0)
        }
        let popularityConfidence = min(log10(Double((movie.tmdbVoteCount ?? 0) + 1)) * 2, 10)

        return (movie.hasGenre(preferredGenre) ? 60 : 0)
            + (movie.isLiked ? 25 : 0)
            + ((movie.userRating ?? 0) * 2.5)
            + (movie.isWatched ? 0 : 10)
            + ((movie.tmdbVoteAverage ?? 0) * 2)
            + popularityConfidence
            + learnedTaste
            - Double(movie.recommendationCount * 4)
            - recentRecommendationPenalty(for: movie, now: now)
    }

    private static func wildcardScore(
        for movie: Movie,
        bestMatch: Movie?,
        preferredGenre: String?,
        genreFrequencies: [String: Int],
        now: Date
    ) -> Double {
        let rarity = movie.genres.reduce(0.0) { partialResult, genre in
            partialResult + (12 / Double(max(genreFrequencies[genre.lowercased()] ?? 1, 1)))
        }
        let bestGenres = Set(bestMatch?.genres.map { $0.lowercased() } ?? [])
        let candidateGenres = Set(movie.genres.map { $0.lowercased() })
        let changesPace = bestGenres.isDisjoint(with: candidateGenres)

        return (movie.hasGenre(preferredGenre) ? 18 : 0)
            + (movie.isWatched ? 0 : 12)
            + ((movie.tmdbVoteAverage ?? 0) * 1.25)
            + (changesPace ? 18 : 0)
            + rarity
            - Double(movie.recommendationCount * 6)
            - recentRecommendationPenalty(for: movie, now: now)
    }

    private static func forgottenScore(
        for movie: Movie,
        preferredGenre: String?,
        now: Date
    ) -> Double {
        let daysInLibrary = max(now.timeIntervalSince(movie.dateAdded) / 86_400, 0)
        let libraryAge = min(daysInLibrary / 30, 36)
        let timeOutOfRotation: Double
        if let lastRecommendedDate = movie.lastRecommendedDate {
            timeOutOfRotation = min(max(now.timeIntervalSince(lastRecommendedDate) / 86_400, 0), 180) / 3
        } else {
            timeOutOfRotation = 100
        }

        return (movie.hasGenre(preferredGenre) ? 8 : 0)
            + (movie.isWatched ? 0 : 15)
            + libraryAge
            + timeOutOfRotation
            - Double(movie.recommendationCount * 8)
            - recentRecommendationPenalty(for: movie, now: now)
    }

    private static func select(
        from movies: [Movie],
        score: (Movie) -> Double
    ) -> Movie? {
        movies.sorted { left, right in
            let leftScore = score(left)
            let rightScore = score(right)
            if leftScore != rightScore {
                return leftScore > rightScore
            }

            let titleOrder = left.title.localizedStandardCompare(right.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return left.id.uuidString < right.id.uuidString
        }
        .first
    }

    private static func genreTasteProfile(from movies: [Movie]) -> [String: Double] {
        var result: [String: Double] = [:]
        for movie in movies {
            var signal = 0.0
            if movie.isLiked { signal += 5 }
            if movie.isDisliked { signal -= 6 }
            if let rating = movie.userRating {
                signal += (rating - 5) / 2
            }
            guard signal != 0 else { continue }

            for genre in movie.genres {
                result[genre.lowercased(), default: 0] += signal
            }
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
        case 0..<1:
            return 1_000
        case 1..<7:
            return 120 - (days * 10)
        case 7..<30:
            return 45 - days
        default:
            return 0
        }
    }
}

extension RecommendationKind {
    var title: String {
        switch self {
        case .bestMatch: "Best Match"
        case .wildcard: "Wildcard"
        case .forgottenOne: "Forgotten One"
        }
    }

    var systemImage: String {
        switch self {
        case .bestMatch: "sparkles"
        case .wildcard: "shuffle"
        case .forgottenOne: "archivebox"
        }
    }

    var sortOrder: Int {
        switch self {
        case .bestMatch: 0
        case .wildcard: 1
        case .forgottenOne: 2
        }
    }
}

extension RecommendationResponse {
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

private extension Movie {
    func hasGenre(_ genre: String?) -> Bool {
        guard let genre else { return false }
        return genres.contains {
            $0.localizedCaseInsensitiveCompare(genre) == .orderedSame
        }
    }
}
