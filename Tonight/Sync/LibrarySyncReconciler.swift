import Foundation
import SwiftData

@MainActor
enum LibrarySyncReconciler {
    @discardableResult
    static func reconcile(in modelContext: ModelContext) throws -> Bool {
        let movies = try modelContext.fetch(FetchDescriptor<Movie>())
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let events = try modelContext.fetch(FetchDescriptor<RecommendationEvent>())
        var canonicalMovies: [Movie] = []
        var didChange = false

        for movie in movies {
            guard let winner = canonicalMovies.first(where: { isSameMovie($0, movie) }) else {
                canonicalMovies.append(movie)
                continue
            }

            consolidate(movie, into: winner, events: events, modelContext: modelContext)
            didChange = true
        }

        var winnerIndex = 0
        while winnerIndex < canonicalMovies.count {
            var candidateIndex = winnerIndex + 1
            while candidateIndex < canonicalMovies.count {
                let winner = canonicalMovies[winnerIndex]
                let candidate = canonicalMovies[candidateIndex]
                if isSameMovie(winner, candidate) {
                    consolidate(
                        candidate,
                        into: winner,
                        events: events,
                        modelContext: modelContext
                    )
                    canonicalMovies.remove(at: candidateIndex)
                    didChange = true
                } else {
                    candidateIndex += 1
                }
            }
            winnerIndex += 1
        }

        var eventByID: [UUID: RecommendationEvent] = [:]
        for event in events.sorted(by: eventSort) {
            guard let winner = eventByID[event.id] else {
                eventByID[event.id] = event
                continue
            }
            merge(event, into: winner)
            modelContext.delete(event)
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
        return didChange
    }

    private static func consolidate(
        _ source: Movie,
        into destination: Movie,
        events: [RecommendationEvent],
        modelContext: ModelContext
    ) {
        merge(source, into: destination)
        for event in events where event.movie === source {
            event.movie = destination
        }
        modelContext.delete(source)
    }

    private static func isSameMovie(_ lhs: Movie, _ rhs: Movie) -> Bool {
        if lhs.id == rhs.id { return true }
        if let leftTMDBID = lhs.tmdbID, let rightTMDBID = rhs.tmdbID {
            return leftTMDBID == rightTMDBID
        }

        guard lhs.tmdbID == nil || rhs.tmdbID == nil else { return false }
        let leftTitle = canonicalTitle(for: lhs)
        let rightTitle = canonicalTitle(for: rhs)
        guard !leftTitle.isEmpty, leftTitle == rightTitle else { return false }

        let leftYear = lhs.importedYear ?? lhs.releaseYear
        let rightYear = rhs.importedYear ?? rhs.releaseYear
        return leftYear == rightYear
    }

    private static func canonicalTitle(for movie: Movie) -> String {
        if !movie.normalizedTitle.isEmpty { return movie.normalizedTitle }
        return MovieTitleNormalizer.normalize(movie.importedTitle)
    }

    private static func merge(_ source: Movie, into destination: Movie) {
        if metadataScore(source) > metadataScore(destination) {
            copyMetadata(from: source, to: destination)
        }

        destination.importedTitle = preferredText(destination.importedTitle, source.importedTitle)
        destination.importedYear = destination.importedYear ?? source.importedYear
        destination.isWatched = destination.isWatched || source.isWatched
        destination.dateWatched = latest(destination.dateWatched, source.dateWatched)
        destination.lastWatchedDate = latest(destination.lastWatchedDate, source.lastWatchedDate)
        destination.userRating = destination.userRating ?? source.userRating
        destination.isDisliked = destination.isDisliked || source.isDisliked
        destination.isLiked = !destination.isDisliked && (destination.isLiked || source.isLiked)
        destination.dateAdded = min(destination.dateAdded, source.dateAdded)
        destination.lastRecommendedDate = latest(
            destination.lastRecommendedDate,
            source.lastRecommendedDate
        )
        destination.recommendationCount = max(
            destination.recommendationCount,
            source.recommendationCount
        )
    }

    private static func metadataScore(_ movie: Movie) -> Int {
        var score = movie.resolutionStatus == .resolved ? 100 : 0
        if movie.tmdbID != nil { score += 20 }
        if movie.posterPath != nil { score += 5 }
        if !movie.overviewText.isEmpty { score += 3 }
        if movie.runtimeMinutes != nil { score += 1 }
        if !movie.genres.isEmpty { score += 1 }
        return score
    }

    private static func copyMetadata(from source: Movie, to destination: Movie) {
        destination.tmdbID = source.tmdbID
        destination.title = source.title
        destination.originalTitle = source.originalTitle
        destination.normalizedTitle = source.normalizedTitle
        destination.releaseDate = source.releaseDate
        destination.releaseYear = source.releaseYear
        destination.overviewText = source.overviewText
        destination.posterPath = source.posterPath
        destination.backdropPath = source.backdropPath
        destination.runtimeMinutes = source.runtimeMinutes
        destination.genres = source.genres
        destination.tmdbVoteAverage = source.tmdbVoteAverage
        destination.tmdbVoteCount = source.tmdbVoteCount
        destination.director = source.director
        destination.primaryCast = source.primaryCast
        destination.originalLanguage = source.originalLanguage
        destination.resolutionStatus = source.resolutionStatus
        destination.resolutionNote = source.resolutionNote
    }

    private static func merge(
        _ source: RecommendationEvent,
        into destination: RecommendationEvent
    ) {
        if responsePriority(source.response) > responsePriority(destination.response) {
            destination.response = source.response
        }
        destination.movie = destination.movie ?? source.movie
        destination.recommendedAt = min(destination.recommendedAt, source.recommendedAt)
    }

    private static func responsePriority(_ response: RecommendationResponse) -> Int {
        switch response {
        case .pending: 0
        case .notTonight: 1
        case .rejected: 2
        case .accepted: 3
        case .watched: 4
        }
    }

    private static func eventSort(
        _ lhs: RecommendationEvent,
        _ rhs: RecommendationEvent
    ) -> Bool {
        if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.recommendedAt < rhs.recommendedAt
    }

    private static func preferredText(_ lhs: String, _ rhs: String) -> String {
        lhs.isEmpty ? rhs : lhs
    }

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }
}
