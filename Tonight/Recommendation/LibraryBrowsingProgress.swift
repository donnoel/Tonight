import Foundation

/// A monotonic exposure marker. Concurrent devices combine progress without
/// syncing their selected mood, recommendation cards, or personal responses.
struct LibraryBrowsingProgress: Codable, Equatable, Sendable, Comparable {
    let generation: Int
    let shownAt: Date
    let eventID: UUID

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.generation != rhs.generation { return lhs.generation < rhs.generation }
        if lhs.shownAt != rhs.shownAt { return lhs.shownAt < rhs.shownAt }
        return lhs.eventID.uuidString < rhs.eventID.uuidString
    }

    static func merged(_ lhs: Self?, _ rhs: Self?) -> Self? {
        [lhs, rhs].compactMap { $0 }.max()
    }
}
