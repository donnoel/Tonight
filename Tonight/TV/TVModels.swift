import Foundation

enum TVViewingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case inOrder, anyEpisode, bySeason
    var id: Self { self }
    var title: String {
        switch self {
        case .inOrder: "Watch in order"
        case .anyEpisode: "Pick any episode"
        case .bySeason: "Season stories"
        }
    }
    var explanation: String {
        switch self {
        case .inOrder: "Begin a rewatch or continue from your place, in episode order."
        case .anyEpisode: "Drop into an episode, favoring ones you haven’t revisited lately."
        case .bySeason: "Start a season’s story at episode one, then continue in order."
        }
    }
}

struct TVEpisodePosition: Codable, Hashable, Comparable, Sendable {
    var season: Int
    var episode: Int
    var label: String { "S\(season) · E\(episode)" }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.season, lhs.episode) < (rhs.season, rhs.episode)
    }
}

struct TVEpisode: Codable, Identifiable, Equatable, Sendable {
    var id: Int
    var name: String
    var seasonNumber: Int
    var episodeNumber: Int
    var runtime: Int?
    var airDate: String?
    var overview: String
    var stillPath: String?
    var position: TVEpisodePosition { .init(season: seasonNumber, episode: episodeNumber) }
}

struct TVSeason: Codable, Identifiable, Equatable, Sendable {
    var number: Int
    var name: String
    var episodeCount: Int
    var airDate: String?
    var id: Int { number }
}

struct TVShow: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var importedTitle: String
    var requestedYear: Int?
    /// nil means ownership has not yet been frozen to the initially matched season list.
    var ownedSeasons: [Int]?
    var title: String
    var tmdbID: Int?
    var firstAirYear: Int?
    var overview = ""
    var posterPath: String?
    var backdropPath: String?
    var genres: [String] = []
    var episodeRuntime: Int?
    var seasons: [TVSeason] = []
    var episodes: [TVEpisode] = []
    var loadedSeasons: [Int] = []
    var viewingStyle: TVViewingStyle = .inOrder
    var seenBefore = true
    var isFavorite = false
    var isPaused = false
    var resumeAfter: TVEpisodePosition?
    var note: String?
    var candidates: [TVSearchCandidate] = []

    var ownershipLabel: String {
        guard let ownedSeasons else { return "Seasons confirmed when matched" }
        return TVSeasonSelection.label(ownedSeasons)
    }
    var eligibleEpisodes: [TVEpisode] {
        let owned = Set(ownedSeasons ?? [])
        return episodes.filter { owned.contains($0.seasonNumber) && $0.episodeNumber > 0 }
            .sorted { $0.position < $1.position }
    }
    var metadataComplete: Bool {
        guard let ownedSeasons, !ownedSeasons.isEmpty else { return false }
        return Set(ownedSeasons).isSubset(of: Set(loadedSeasons))
    }
}

enum TVSessionMood: String, Codable, CaseIterable, Identifiable, Sendable {
    case anything, light, gripping, strange
    var id: Self { self }
    var title: String {
        switch self {
        case .anything: "Anything"
        case .light: "Light & Funny"
        case .gripping: "Get Absorbed"
        case .strange: "Something Strange"
        }
    }
    func accepts(_ show: TVShow) -> Bool {
        let genres = Set(show.genres)
        switch self {
        case .anything: return true
        case .light: return genres.contains("Comedy")
        case .gripping: return !genres.isDisjoint(with: ["Drama", "Crime", "Mystery", "War & Politics", "Documentary"])
        case .strange: return !genres.isDisjoint(with: ["Sci-Fi & Fantasy", "Mystery", "Animation"])
        }
    }
}

enum TVSessionLane: String, Codable, Sendable {
    case keepGoing, changePace, rediscover
    var title: String {
        switch self {
        case .keepGoing: "Keep Going"
        case .changePace: "Change the Pace"
        case .rediscover: "Rediscover"
        }
    }
    var symbol: String {
        switch self {
        case .keepGoing: "play.circle.fill"
        case .changePace: "shuffle"
        case .rediscover: "sparkles"
        }
    }
}

struct TVViewingSession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var showID: UUID
    var lane: TVSessionLane
    var episodes: [TVEpisode]
    var estimatedMinutes: Int
    var usesEstimatedRuntime: Bool
    var rationale: String
    var createdAt: Date
    var durationLabel: String { "\(usesEstimatedRuntime ? "About " : "")\(estimatedMinutes) min" }
}

struct TVWatchSession: Codable, Identifiable, Sendable {
    var id: UUID
    var showID: UUID
    var showTitle: String
    var episodes: [TVEpisode]
    var watchedAt: Date
    var previousResume: TVEpisodePosition?
}

struct TVLibraryDocument: Codable, Sendable {
    var version = 1
    var shows: [TVShow] = []
    var history: [TVWatchSession] = []
    var suggestions: [TVViewingSession] = []
    var activeSession: TVViewingSession?
    var minutes = 60
    var mood = TVSessionMood.anything
    var unseenOnly = false
    var generation: UInt64 = 0
    var suggestedShowIDs: [UUID] = []
    /// iPad's current orientation determines the row size. nil keeps the compact presentation.
    var sessionCount: Int?
}

enum TVSeasonSelection {
    static func label(_ seasons: [Int]) -> String {
        let sorted = Set(seasons).sorted()
        guard let first = sorted.first, let last = sorted.last else { return "No seasons selected" }
        if sorted.count == 1 { return "Season \(first)" }
        if sorted.count == last - first + 1 { return "Seasons \(first)–\(last)" }
        return "Seasons " + sorted.map(String.init).joined(separator: ", ")
    }
}
