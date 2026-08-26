import Foundation

enum LibrarySortField: String, CaseIterable, Identifiable {
    case title
    case releaseYear
    case dateAdded
    case runtime
    case rating
    case lastWatched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: "Title"
        case .releaseYear: "Release Year"
        case .dateAdded: "Date Added"
        case .runtime: "Runtime"
        case .rating: "Rating"
        case .lastWatched: "Last Watched"
        }
    }

    var systemImage: String {
        switch self {
        case .title: "textformat"
        case .releaseYear: "calendar"
        case .dateAdded: "clock.badge.plus"
        case .runtime: "timer"
        case .rating: "star"
        case .lastWatched: "eye"
        }
    }

    var defaultDirection: LibrarySortDirection {
        switch self {
        case .title, .runtime: .ascending
        case .releaseYear, .dateAdded, .rating, .lastWatched: .descending
        }
    }

    func directionTitle(for direction: LibrarySortDirection) -> String {
        switch (self, direction) {
        case (.title, .ascending): "A–Z"
        case (.title, .descending): "Z–A"
        case (.releaseYear, .ascending), (.dateAdded, .ascending): "Oldest"
        case (.releaseYear, .descending), (.dateAdded, .descending): "Newest"
        case (.runtime, .ascending): "Shortest"
        case (.runtime, .descending): "Longest"
        case (.rating, .ascending): "Lowest"
        case (.rating, .descending): "Highest"
        case (.lastWatched, .ascending): "Oldest"
        case (.lastWatched, .descending): "Most Recent"
        }
    }
}

enum LibrarySortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
}

enum LibraryFilterOption: String, CaseIterable, Identifiable {
    case all
    case unwatched
    case watched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .unwatched: "Unwatched"
        case .watched: "Watched"
        }
    }
}

enum LibrarySort {
    static func movies(
        _ movies: [Movie],
        by field: LibrarySortField,
        direction: LibrarySortDirection
    ) -> [Movie] {
        movies.sorted { lhs, rhs in
            let fieldOrder: Bool?

            switch field {
            case .title:
                return ordered(
                    comparison: compareTitles(lhs, rhs),
                    direction: direction
                )
            case .releaseYear:
                fieldOrder = ordered(
                    lhs.releaseYear,
                    rhs.releaseYear,
                    direction: direction
                )
            case .dateAdded:
                fieldOrder = ordered(
                    lhs.dateAdded,
                    rhs.dateAdded,
                    direction: direction
                )
            case .runtime:
                fieldOrder = ordered(
                    lhs.runtimeMinutes,
                    rhs.runtimeMinutes,
                    direction: direction
                )
            case .rating:
                fieldOrder = ordered(
                    lhs.userRating ?? lhs.tmdbVoteAverage,
                    rhs.userRating ?? rhs.tmdbVoteAverage,
                    direction: direction
                )
            case .lastWatched:
                fieldOrder = ordered(
                    lhs.lastWatchedDate ?? lhs.dateWatched,
                    rhs.lastWatchedDate ?? rhs.dateWatched,
                    direction: direction
                )
            }

            return fieldOrder ?? (compareTitles(lhs, rhs) == .orderedAscending)
        }
    }

    static func shuffledMovies(
        _ movies: [Movie],
        shuffleRanks: [UUID: Int]
    ) -> [Movie] {
        movies.sorted { lhs, rhs in
            let leftRank = shuffleRanks[lhs.id] ?? .max
            let rightRank = shuffleRanks[rhs.id] ?? .max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return compareTitles(lhs, rhs) == .orderedAscending
        }
    }

    private static func ordered<Value: Comparable>(
        _ lhs: Value?,
        _ rhs: Value?,
        direction: LibrarySortDirection
    ) -> Bool? {
        switch (lhs, rhs) {
        case let (left?, right?) where left != right:
            return direction == .ascending ? left < right : left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return nil
        }
    }

    private static func ordered(
        comparison: ComparisonResult,
        direction: LibrarySortDirection
    ) -> Bool {
        switch direction {
        case .ascending:
            comparison == .orderedAscending
        case .descending:
            comparison == .orderedDescending
        }
    }

    private static func compareTitles(_ lhs: Movie, _ rhs: Movie) -> ComparisonResult {
        let result = lhs.title.localizedStandardCompare(rhs.title)
        if result != .orderedSame {
            return result
        }
        return lhs.id.uuidString.compare(rhs.id.uuidString)
    }
}

enum LibraryFilter {
    static func movies(
        _ movies: [Movie],
        showing filter: LibraryFilterOption,
        matching searchText: String
    ) -> [Movie] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return movies.filter { movie in
            let matchesFilter = switch filter {
            case .all: true
            case .unwatched: !movie.isWatched
            case .watched: movie.isWatched
            }

            guard matchesFilter, !query.isEmpty else {
                return matchesFilter
            }

            let searchableValues = [
                movie.title,
                movie.importedTitle,
                movie.director,
                movie.releaseYear.map(String.init)
            ].compactMap { $0 } + movie.genres + movie.primaryCast

            return searchableValues.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }
}
