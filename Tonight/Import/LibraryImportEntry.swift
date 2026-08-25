import Foundation

enum LibraryImportState: String, Sendable {
    case waiting
    case searching
    case enriching
    case imported
    case duplicate
    case unresolved
    case failed
}

struct LibraryImportEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let year: Int?
    var state: LibraryImportState
    var matchedTitle: String?
    var message: String?

    init(
        id: UUID = UUID(),
        title: String,
        year: Int?,
        state: LibraryImportState = .waiting,
        matchedTitle: String? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.state = state
        self.matchedTitle = matchedTitle
        self.message = message
    }

    var normalizedTitle: String { MovieTitleNormalizer.normalize(title) }
}

