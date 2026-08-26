import Foundation
import SwiftData

struct LocalLibraryDuplicateRepairSummary: Equatable, Sendable {
    let consolidatedMovies: Int
}

@MainActor
enum LocalLibraryDuplicateRepair {
    static func repair(in modelContext: ModelContext) throws -> LocalLibraryDuplicateRepairSummary {
        let movies = try modelContext.fetch(FetchDescriptor<Movie>())
        let events = try modelContext.fetch(FetchDescriptor<RecommendationEvent>())
        let resolvedMovies = movies.filter { $0.resolutionStatus == .resolved }
        var consolidatedMovies = 0

        for duplicate in movies where duplicate.resolutionStatus != .resolved {
            let candidates = resolvedMovies.filter {
                isSameImportedMovie(duplicate, $0)
            }
            guard candidates.count == 1, let canonical = candidates.first else { continue }

            consolidate(
                duplicate,
                into: canonical,
                events: events,
                in: modelContext
            )
            consolidatedMovies += 1
        }

        if consolidatedMovies > 0 {
            try modelContext.save()
        }

        return LocalLibraryDuplicateRepairSummary(
            consolidatedMovies: consolidatedMovies
        )
    }

    static func consolidate(
        _ duplicate: Movie,
        into canonical: Movie,
        in modelContext: ModelContext
    ) throws {
        let events = try modelContext.fetch(FetchDescriptor<RecommendationEvent>())
        consolidate(
            duplicate,
            into: canonical,
            events: events,
            in: modelContext
        )
        try modelContext.save()
    }

    private static func consolidate(
        _ duplicate: Movie,
        into canonical: Movie,
        events: [RecommendationEvent],
        in modelContext: ModelContext
    ) {
        canonical.importedTitle = preferredText(canonical.importedTitle, duplicate.importedTitle)
        canonical.importedYear = canonical.importedYear ?? duplicate.importedYear
        mergeWatchedState(from: duplicate, into: canonical)
        canonical.userRating = canonical.userRating ?? duplicate.userRating
        canonical.isDisliked = canonical.isDisliked || duplicate.isDisliked
        canonical.isLiked = !canonical.isDisliked && (canonical.isLiked || duplicate.isLiked)
        canonical.dateAdded = min(canonical.dateAdded, duplicate.dateAdded)
        canonical.lastRecommendedDate = latest(
            canonical.lastRecommendedDate,
            duplicate.lastRecommendedDate
        )
        canonical.recommendationCount = max(
            canonical.recommendationCount,
            duplicate.recommendationCount
        )

        for event in events where event.movie === duplicate {
            event.movie = canonical
        }
        modelContext.delete(duplicate)
    }

    private static func isSameImportedMovie(_ lhs: Movie, _ rhs: Movie) -> Bool {
        let leftTitle = MovieTitleNormalizer.normalize(lhs.importedTitle)
        let rightTitle = MovieTitleNormalizer.normalize(rhs.importedTitle)
        guard !leftTitle.isEmpty, leftTitle == rightTitle else { return false }

        let leftYear = lhs.importedYear ?? lhs.releaseYear
        let rightYear = rhs.importedYear ?? rhs.releaseYear
        guard let leftYear, let rightYear else {
            return true
        }
        return leftYear == rightYear
    }

    private static func preferredText(_ lhs: String, _ rhs: String) -> String {
        lhs.isEmpty ? rhs : lhs
    }

    private static func mergeWatchedState(from source: Movie, into destination: Movie) {
        let sourceTimestamp = watchedStateTimestamp(for: source)
        let destinationTimestamp = watchedStateTimestamp(for: destination)

        if let sourceTimestamp {
            if let destinationTimestamp {
                if sourceTimestamp > destinationTimestamp {
                    copyWatchedState(from: source, to: destination, modifiedAt: sourceTimestamp)
                    return
                }
            } else {
                copyWatchedState(from: source, to: destination, modifiedAt: sourceTimestamp)
                return
            }
        }
        if let destinationTimestamp {
            destination.watchedStateModifiedAt = destinationTimestamp
            return
        }

        destination.isWatched = destination.isWatched || source.isWatched
        destination.dateWatched = latest(destination.dateWatched, source.dateWatched)
        destination.lastWatchedDate = latest(destination.lastWatchedDate, source.lastWatchedDate)
    }

    private static func watchedStateTimestamp(for movie: Movie) -> Date? {
        movie.watchedStateModifiedAt
            ?? (movie.isWatched ? movie.lastWatchedDate ?? movie.dateWatched : nil)
    }

    private static func copyWatchedState(
        from source: Movie,
        to destination: Movie,
        modifiedAt: Date
    ) {
        destination.isWatched = source.isWatched
        destination.dateWatched = source.isWatched ? source.dateWatched : nil
        destination.lastWatchedDate = source.isWatched ? source.lastWatchedDate : nil
        destination.watchedStateModifiedAt = modifiedAt
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
