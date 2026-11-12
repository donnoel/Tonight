import Foundation

/// A display projection, separate from recommendation exposure and rotation history.
struct MovieViewingHistory: Identifiable {
    let id: String
    let movie: Movie?
    let date: Date
    let response: RecommendationResponse

    static func entries(events: [RecommendationEvent], watchedMovies: [Movie]) -> [Self] {
        let viewingEvents = events.filter { $0.response == .accepted || $0.response == .watched }
        var result = viewingEvents.map {
            Self(id: "event-\($0.id)", movie: $0.movie,
                 date: $0.respondedAt ?? $0.recommendedAt, response: $0.response)
        }
        let eventsByMovie = Dictionary(grouping: viewingEvents.compactMap { event in
            event.movie.map { ($0.id, event) }
        }, by: { $0.0 })

        for movie in watchedMovies where movie.isWatched {
            guard let date = movie.lastWatchedDate ?? movie.dateWatched else { continue }
            let existing = eventsByMovie[movie.id]?.map { $0.1 } ?? []
            // Older events did not capture response time. Avoid making a duplicate from
            // their movie's mutable watch date; retain the original event's known date.
            guard !existing.contains(where: { $0.respondedAt == nil ||
                abs(($0.respondedAt ?? $0.recommendedAt).timeIntervalSince(date)) < 1 }) else { continue }
            result.append(Self(id: "movie-\(movie.id)", movie: movie, date: date, response: .watched))
        }
        return result.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
        }
    }
}
