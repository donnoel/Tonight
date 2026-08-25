import Foundation

enum LibrarySortOption: String, CaseIterable {
    case titleAscending
    case titleDescending
    case releaseYear
    case shuffled

    var title: String {
        switch self {
        case .titleAscending:
            "A to Z"
        case .titleDescending:
            "Z to A"
        case .releaseYear:
            "Year (Oldest First)"
        case .shuffled:
            "Shuffle"
        }
    }

    var systemImage: String {
        switch self {
        case .titleAscending:
            "textformat"
        case .titleDescending:
            "textformat"
        case .releaseYear:
            "calendar"
        case .shuffled:
            "shuffle"
        }
    }
}

enum LibrarySort {
    static func movies(
        _ movies: [Movie],
        by option: LibrarySortOption,
        shuffleRanks: [UUID: Int] = [:]
    ) -> [Movie] {
        movies.sorted { lhs, rhs in
            switch option {
            case .titleAscending:
                return compareTitles(lhs, rhs) == .orderedAscending

            case .titleDescending:
                return compareTitles(lhs, rhs) == .orderedDescending

            case .releaseYear:
                switch (lhs.releaseYear, rhs.releaseYear) {
                case let (leftYear?, rightYear?) where leftYear != rightYear:
                    return leftYear < rightYear
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return compareTitles(lhs, rhs) == .orderedAscending
                }

            case .shuffled:
                let leftRank = shuffleRanks[lhs.id] ?? .max
                let rightRank = shuffleRanks[rhs.id] ?? .max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return compareTitles(lhs, rhs) == .orderedAscending
            }
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
