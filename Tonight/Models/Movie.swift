import Foundation
import SwiftData

enum MovieResolutionStatus: String, Codable, CaseIterable, Sendable {
    case resolved
    case unresolved
    case failed
}

@Model
final class Movie {
    var id: UUID = UUID()
    var tmdbID: Int?
    var title: String = ""
    var originalTitle: String?
    var normalizedTitle: String = ""
    var importedTitle: String = ""
    var importedYear: Int?
    var releaseDate: Date?
    var releaseYear: Int?
    var overviewText: String = ""
    var posterPath: String?
    var backdropPath: String?
    var runtimeMinutes: Int?
    var genres: [String] = []
    var tmdbVoteAverage: Double?
    var tmdbVoteCount: Int?
    var director: String?
    var primaryCast: [String] = []
    var originalLanguage: String?
    var resolutionStatusRawValue: String = MovieResolutionStatus.unresolved.rawValue
    var resolutionNote: String?

    var isWatched: Bool = false
    var dateWatched: Date?
    var userRating: Double?
    var isLiked: Bool = false
    var isDisliked: Bool = false
    var dateAdded: Date = Date.now
    var lastWatchedDate: Date?
    var recommendationCount: Int = 0
    var lastRecommendedDate: Date?

    @Relationship(deleteRule: .nullify, inverse: \RecommendationEvent.movie)
    var recommendationEvents: [RecommendationEvent]? = []

    var resolutionStatus: MovieResolutionStatus {
        get { MovieResolutionStatus(rawValue: resolutionStatusRawValue) ?? .unresolved }
        set { resolutionStatusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        tmdbID: Int? = nil,
        title: String,
        originalTitle: String? = nil,
        importedTitle: String? = nil,
        importedYear: Int? = nil,
        releaseDate: Date? = nil,
        releaseYear: Int? = nil,
        overviewText: String = "",
        posterPath: String? = nil,
        backdropPath: String? = nil,
        runtimeMinutes: Int? = nil,
        genres: [String] = [],
        tmdbVoteAverage: Double? = nil,
        tmdbVoteCount: Int? = nil,
        director: String? = nil,
        primaryCast: [String] = [],
        originalLanguage: String? = nil,
        resolutionStatus: MovieResolutionStatus = .unresolved,
        resolutionNote: String? = nil,
        dateAdded: Date = .now
    ) {
        self.id = id
        self.tmdbID = tmdbID
        self.title = title
        self.originalTitle = originalTitle
        self.normalizedTitle = MovieTitleNormalizer.normalize(title)
        self.importedTitle = importedTitle ?? title
        self.importedYear = importedYear
        self.releaseDate = releaseDate
        self.releaseYear = releaseYear
        self.overviewText = overviewText
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.runtimeMinutes = runtimeMinutes
        self.genres = genres
        self.tmdbVoteAverage = tmdbVoteAverage
        self.tmdbVoteCount = tmdbVoteCount
        self.director = director
        self.primaryCast = primaryCast
        self.originalLanguage = originalLanguage
        self.resolutionStatusRawValue = resolutionStatus.rawValue
        self.resolutionNote = resolutionNote
        self.isWatched = false
        self.dateWatched = nil
        self.userRating = nil
        self.isLiked = false
        self.isDisliked = false
        self.dateAdded = dateAdded
        self.lastWatchedDate = nil
        self.recommendationCount = 0
        self.lastRecommendedDate = nil
    }
}
