import Foundation

enum AppleMovieDealPriceEvidence: String, Codable, Sendable {
    case buyCollectionAndLinkContext
}

struct AppleMovieDeal: Codable, Hashable, Identifiable, Sendable {
    let title: String
    let appleURL: URL
    let priceInCents: Int
    let contentIdentifier: String?
    let position: Int
    let retrievedAt: Date
    let priceEvidence: AppleMovieDealPriceEvidence

    var id: String {
        contentIdentifier ?? appleURL.absoluteString
    }

    var formattedPrice: String {
        "$\(priceInCents / 100).\(String(format: "%02d", priceInCents % 100))"
    }
}

enum DealTMDBMatchStatus: String, Codable, Sendable {
    case matched
    case unresolved
    case unavailable
    case failed
}

struct DealMovieMetadata: Codable, Hashable, Sendable {
    let tmdbID: Int
    let title: String
    let originalTitle: String?
    let releaseDate: Date?
    let releaseYear: Int?
    let overviewText: String
    let posterPath: String?
    let backdropPath: String?
    let runtimeMinutes: Int?
    let genres: [String]
    let tmdbVoteAverage: Double?
    let tmdbVoteCount: Int?
    let director: String?
    let primaryCast: [String]
    let originalLanguage: String?

    init(details: TMDBMovieDetailsDTO) {
        tmdbID = details.id
        title = details.title
        originalTitle = details.originalTitle
        releaseDate = MovieDateParser.date(from: details.releaseDate)
        releaseYear = MovieDateParser.year(from: details.releaseDate)
        overviewText = details.overview
        posterPath = details.posterPath
        backdropPath = details.backdropPath
        runtimeMinutes = details.runtime
        genres = details.genres.map(\.name)
        tmdbVoteAverage = details.voteAverage
        tmdbVoteCount = details.voteCount
        director = details.credits?.crew.first(where: { $0.job == "Director" })?.name
        primaryCast = details.credits?.cast
            .sorted { $0.order < $1.order }
            .prefix(8)
            .map(\.name) ?? []
        originalLanguage = details.originalLanguage
    }

    init(movie: Movie) {
        tmdbID = movie.tmdbID ?? 0
        title = movie.title
        originalTitle = movie.originalTitle
        releaseDate = movie.releaseDate
        releaseYear = movie.releaseYear
        overviewText = movie.overviewText
        posterPath = movie.posterPath
        backdropPath = movie.backdropPath
        runtimeMinutes = movie.runtimeMinutes
        genres = movie.genres
        tmdbVoteAverage = movie.tmdbVoteAverage
        tmdbVoteCount = movie.tmdbVoteCount
        director = movie.director
        primaryCast = movie.primaryCast
        originalLanguage = movie.originalLanguage
    }

    func makeTransientMovie(importedTitle: String) -> Movie {
        Movie(
            tmdbID: tmdbID,
            title: title,
            originalTitle: originalTitle,
            importedTitle: importedTitle,
            importedYear: releaseYear,
            releaseDate: releaseDate,
            releaseYear: releaseYear,
            overviewText: overviewText,
            posterPath: posterPath,
            backdropPath: backdropPath,
            runtimeMinutes: runtimeMinutes,
            genres: genres,
            tmdbVoteAverage: tmdbVoteAverage,
            tmdbVoteCount: tmdbVoteCount,
            director: director,
            primaryCast: primaryCast,
            originalLanguage: originalLanguage,
            resolutionStatus: .resolved
        )
    }
}

struct CachedMovieDeal: Codable, Hashable, Identifiable, Sendable {
    let appleDeal: AppleMovieDeal
    let metadata: DealMovieMetadata?
    let matchStatus: DealTMDBMatchStatus
    let matchNote: String?

    var id: String { appleDeal.id }
}

enum DealCatalogEnrichmentState: String, Codable, Sendable {
    case complete
    case partial
    case unavailable
}

struct DealCatalogSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let items: [CachedMovieDeal]
    let lastSuccessfulRefresh: Date
    let enrichmentState: DealCatalogEnrichmentState

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        items: [CachedMovieDeal],
        lastSuccessfulRefresh: Date,
        enrichmentState: DealCatalogEnrichmentState
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.enrichmentState = enrichmentState
    }

    func isFresh(at date: Date, lifetime: TimeInterval) -> Bool {
        date.timeIntervalSince(lastSuccessfulRefresh) < lifetime
    }
}

struct LibraryMovieSnapshot: Hashable, Sendable {
    let normalizedTitle: String
    let metadata: DealMovieMetadata

    init?(movie: Movie) {
        guard movie.resolutionStatus == .resolved, movie.tmdbID != nil else {
            return nil
        }
        normalizedTitle = movie.normalizedTitle
        metadata = DealMovieMetadata(movie: movie)
    }
}

enum DealLibraryMatcher {
    static func movie(for item: CachedMovieDeal, in library: [Movie]) -> Movie? {
        DealLibraryIndex(library).movie(for: item)
    }
}

/// Preserves first exact-ID matching and unique title/year fallback matching.
struct DealLibraryIndex {
    private var byTMDBID: [Int: Movie] = [:]
    private var byTitle: [String: [Movie]] = [:]

    init(_ library: [Movie]) {
        for movie in library {
            if let id = movie.tmdbID, byTMDBID[id] == nil {
                byTMDBID[id] = movie
            }
            byTitle[movie.normalizedTitle, default: []].append(movie)
        }
    }

    func movie(for item: CachedMovieDeal) -> Movie? {
        if let id = item.metadata?.tmdbID, let exact = byTMDBID[id] {
            return exact
        }
        let title = MovieTitleNormalizer.normalize(item.metadata?.title ?? item.appleDeal.title)
        let matches = byTitle[title] ?? []
        guard let year = item.metadata?.releaseYear else {
            return matches.count == 1 ? matches[0] : nil
        }
        let yearMatches = matches.filter { ($0.releaseYear ?? $0.importedYear) == year }
        return yearMatches.count == 1 ? yearMatches[0] : nil
    }
}

struct DealRecommendationCandidate {
    let id: String
    let movie: Movie
}

struct DealRecommendationRank: Identifiable, Equatable {
    let id: String
    let score: Double
    let rationale: String
}
