import CryptoKit
import Foundation

/// Separate field revisions prevent metadata enrichment from undoing a watch edit.
struct LibraryRevision: Codable, Equatable, Comparable, Sendable {
    var date: Date
    var device: String
    static let initial = LibraryRevision(date: .distantPast, device: "")
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.date == rhs.date ? lhs.device < rhs.device : lhs.date < rhs.date
    }
}

struct LibraryMovieDetails: Codable, Equatable, Sendable {
    var tmdbID: Int?
    var title: String
    var originalTitle: String?
    var importedTitle: String
    var importedYear: Int?
    var releaseDate: Date?
    var releaseYear: Int?
    var overviewText: String
    var posterPath: String?
    var backdropPath: String?
    var runtimeMinutes: Int?
    var genres: [String]
    var tmdbVoteAverage: Double?
    var tmdbVoteCount: Int?
    var director: String?
    var primaryCast: [String]
    var originalLanguage: String?
    var resolutionStatusRawValue: String
    var resolutionNote: String?

    var recordName: String {
        if let tmdbID { return "tmdb-\(tmdbID)" }
        let identity = MovieTitleNormalizer.normalize(importedTitle) + "|" + (importedYear ?? releaseYear).map(String.init, default: "unknown")
        return "title-" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var completeness: Int {
        (resolutionStatusRawValue == MovieResolutionStatus.resolved.rawValue ? 100 : 0)
        + (posterPath == nil ? 0 : 1) + (backdropPath == nil ? 0 : 1)
        + (runtimeMinutes == nil ? 0 : 1) + (overviewText.isEmpty ? 0 : 1)
        + primaryCast.count + genres.count + (director == nil ? 0 : 1)
    }

    var artworkURLs: [URL] {
        [TMDBImageURL.make(path: posterPath, size: .posterCard),
         TMDBImageURL.make(path: posterPath, size: .posterDetail),
         TMDBImageURL.make(path: backdropPath, size: .backdrop)].compactMap { $0 }
    }
}

private extension Optional {
    func map<T>(_ transform: (Wrapped) -> T, default fallback: T) -> T {
        map(transform) ?? fallback
    }
}

struct LibraryWatchState: Codable, Equatable, Sendable {
    var isWatched: Bool
    var dateWatched: Date?
    var lastWatchedDate: Date?
    var modifiedAt: Date?
}

struct LibraryTaste: Codable, Equatable, Sendable {
    var userRating: Double?
    var isLiked: Bool
    var isDisliked: Bool
}

struct SyncedLibraryMovie: Codable, Equatable, Sendable {
    var details: LibraryMovieDetails
    var watched: LibraryWatchState
    var taste: LibraryTaste
    var dateAdded: Date
    var browsing: LibraryBrowsingProgress?

    init(movie: Movie) {
        details = LibraryMovieDetails(
            tmdbID: movie.tmdbID, title: movie.title, originalTitle: movie.originalTitle,
            importedTitle: movie.importedTitle, importedYear: movie.importedYear,
            releaseDate: movie.releaseDate, releaseYear: movie.releaseYear,
            overviewText: movie.overviewText, posterPath: movie.posterPath,
            backdropPath: movie.backdropPath, runtimeMinutes: movie.runtimeMinutes,
            genres: movie.genres, tmdbVoteAverage: movie.tmdbVoteAverage,
            tmdbVoteCount: movie.tmdbVoteCount, director: movie.director,
            primaryCast: movie.primaryCast, originalLanguage: movie.originalLanguage,
            resolutionStatusRawValue: movie.resolutionStatusRawValue,
            resolutionNote: movie.resolutionNote
        )
        watched = LibraryWatchState(isWatched: movie.isWatched, dateWatched: movie.dateWatched,
                                    lastWatchedDate: movie.lastWatchedDate, modifiedAt: movie.watchedStateModifiedAt)
        taste = LibraryTaste(userRating: movie.userRating, isLiked: movie.isLiked, isDisliked: movie.isDisliked)
        dateAdded = movie.dateAdded
        browsing = movie.browsingProgress
    }

    func apply(to movie: Movie) {
        movie.tmdbID = details.tmdbID
        movie.title = details.title
        movie.normalizedTitle = MovieTitleNormalizer.normalize(details.title)
        movie.originalTitle = details.originalTitle
        movie.importedTitle = details.importedTitle
        movie.importedYear = details.importedYear
        movie.releaseDate = details.releaseDate
        movie.releaseYear = details.releaseYear
        movie.overviewText = details.overviewText
        movie.posterPath = details.posterPath
        movie.backdropPath = details.backdropPath
        movie.runtimeMinutes = details.runtimeMinutes
        movie.genres = details.genres
        movie.tmdbVoteAverage = details.tmdbVoteAverage
        movie.tmdbVoteCount = details.tmdbVoteCount
        movie.director = details.director
        movie.primaryCast = details.primaryCast
        movie.originalLanguage = details.originalLanguage
        movie.resolutionStatusRawValue = details.resolutionStatusRawValue
        movie.resolutionNote = details.resolutionNote
        movie.isWatched = watched.isWatched
        movie.dateWatched = watched.dateWatched
        movie.lastWatchedDate = watched.lastWatchedDate
        movie.watchedStateModifiedAt = watched.modifiedAt
        movie.userRating = taste.userRating
        movie.isLiked = taste.isLiked
        movie.isDisliked = taste.isDisliked
        movie.dateAdded = dateAdded
        movie.browsingProgress = browsing
    }
}

struct LibrarySyncDocument: Codable, Equatable, Sendable {
    var version = 1
    var movie: SyncedLibraryMovie
    var detailsRevision: LibraryRevision
    var watchRevision: LibraryRevision
    var tasteRevision: LibraryRevision
    var membershipRevision: LibraryRevision
    var deleted = false
    var redirectTo: String?

    init(movie: SyncedLibraryMovie, revision: LibraryRevision, initial: Bool) {
        self.movie = movie
        detailsRevision = initial ? .initial : revision
        tasteRevision = initial ? .initial : revision
        membershipRevision = initial ? .initial : revision
        watchRevision = LibraryRevision(
            date: movie.watched.modifiedAt ?? (movie.watched.isWatched ? movie.watched.lastWatchedDate ?? movie.watched.dateWatched ?? .distantPast : .distantPast),
            device: ""
        )
    }

    mutating func update(_ snapshot: SyncedLibraryMovie, previous: SyncedLibraryMovie?, revision: LibraryRevision) {
        movie.browsing = LibraryBrowsingProgress.merged(movie.browsing, snapshot.browsing)
        if previous?.details != snapshot.details { movie.details = snapshot.details; detailsRevision = revision }
        if previous?.watched != snapshot.watched { movie.watched = snapshot.watched; watchRevision = revision }
        if previous?.taste != snapshot.taste { movie.taste = snapshot.taste; tasteRevision = revision }
        movie.dateAdded = min(movie.dateAdded, snapshot.dateAdded)
        if deleted || redirectTo != nil { deleted = false; redirectTo = nil; membershipRevision = revision }
    }

    func merged(with other: Self) -> Self {
        var result = self
        result.movie.browsing = LibraryBrowsingProgress.merged(movie.browsing, other.movie.browsing)
        // Initial imports prefer complete metadata. Later explicit corrections use their revision.
        if other.detailsRevision > detailsRevision || (other.detailsRevision == detailsRevision &&
            (other.movie.details.completeness > movie.details.completeness ||
             (other.movie.details.completeness == movie.details.completeness && Self.stableKey(other.movie.details) > Self.stableKey(movie.details)))) {
            result.movie.details = other.movie.details; result.detailsRevision = other.detailsRevision
        }
        if other.watchRevision > watchRevision || (other.watchRevision == watchRevision && Self.stableKey(other.movie.watched) > Self.stableKey(movie.watched)) {
            result.movie.watched = other.movie.watched; result.watchRevision = other.watchRevision
        }
        if other.tasteRevision > tasteRevision || (other.tasteRevision == tasteRevision && Self.stableKey(other.movie.taste) > Self.stableKey(movie.taste)) {
            result.movie.taste = other.movie.taste; result.tasteRevision = other.tasteRevision
        }
        if other.membershipRevision > membershipRevision || (other.membershipRevision == membershipRevision &&
            (other.deleted && !deleted || (other.deleted == deleted && (other.redirectTo ?? "") > (redirectTo ?? "")))) {
            result.deleted = other.deleted; result.redirectTo = other.redirectTo
            result.membershipRevision = other.membershipRevision
        }
        result.movie.dateAdded = min(movie.dateAdded, other.movie.dateAdded)
        return result
    }

    static func stableKey<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

/// Stable encoding keeps an unchanged record from being marked dirty again.
enum LibrarySyncCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
