import Foundation

enum DealTMDBMatchOutcome: Sendable {
    case matched(DealMovieMetadata)
    case unresolved(String)
}

struct DealTMDBEnricher: Sendable {
    let resolve: @Sendable (AppleMovieDeal, String) async throws -> DealTMDBMatchOutcome

    static let live = DealTMDBEnricher { deal, token in
        let client = TMDBClient(token: token)
        let resolver = TMDBMatchResolver(client: client)
        let searchTitle = MovieSearchQuery.title(from: deal.title)
        let candidates = try await client.searchMovies(title: searchTitle, year: nil)

        switch try await resolver.resolve(
            title: searchTitle,
            year: nil,
            candidates: candidates
        ) {
        case .matched(_, let details):
            return .matched(DealMovieMetadata(details: details))
        case .ambiguous:
            return .unresolved("More than one plausible TMDB match was found.")
        case .noMatch:
            return .unresolved("No confident TMDB match was found.")
        }
    }
}

actor MovieDealsRepository {
    private let provider: any AppleMovieDealsProviding
    private let cache: MovieDealsCache
    private let enricher: DealTMDBEnricher
    private let readCredential: @Sendable () async throws -> String?
    private let now: @Sendable () -> Date

    init(
        provider: any AppleMovieDealsProviding = AppleMovieDealsProvider(),
        cache: MovieDealsCache = MovieDealsCache(),
        enricher: DealTMDBEnricher = .live,
        readCredential: @escaping @Sendable () async throws -> String? = {
            try TMDBCredentialStore.shared.readToken()
        },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.provider = provider
        self.cache = cache
        self.enricher = enricher
        self.readCredential = readCredential
        self.now = now
    }

    func loadCached() async -> DealCatalogSnapshot? {
        await cache.load()
    }

    func refresh(library: [LibraryMovieSnapshot]) async throws -> DealCatalogSnapshot {
        let deals = try await provider.fetchDeals()
        try Task.checkCancellation()

        let cached = await cache.load()
        let cachedByID = (cached?.items ?? []).reduce(
            into: [String: CachedMovieDeal]()
        ) { result, item in
            if result[item.id] == nil {
                result[item.id] = item
            }
        }
        let localByTitle = uniqueLocalMetadataByTitle(library)

        var items: [CachedMovieDeal] = []
        var enrichmentTargets: [AppleMovieDeal] = []

        for deal in deals {
            if let cachedItem = cachedByID[deal.id], let metadata = cachedItem.metadata {
                items.append(
                    CachedMovieDeal(
                        appleDeal: deal,
                        metadata: metadata,
                        matchStatus: .matched,
                        matchNote: nil
                    )
                )
            } else if let metadata = localByTitle[MovieTitleNormalizer.normalize(deal.title)] {
                items.append(
                    CachedMovieDeal(
                        appleDeal: deal,
                        metadata: metadata,
                        matchStatus: .matched,
                        matchNote: nil
                    )
                )
            } else {
                enrichmentTargets.append(deal)
            }
        }

        let token: String?
        do {
            token = try await readCredential()
        } catch {
            token = nil
        }

        if let token {
            let enriched = try await enrich(
                enrichmentTargets,
                token: token
            )
            items.append(contentsOf: enriched)
        } else {
            items.append(contentsOf: enrichmentTargets.map {
                CachedMovieDeal(
                    appleDeal: $0,
                    metadata: nil,
                    matchStatus: .unavailable,
                    matchNote: "Add a TMDB Read Access Token in Settings to enrich this deal."
                )
            })
        }

        items.sort { $0.appleDeal.position < $1.appleDeal.position }
        let snapshot = DealCatalogSnapshot(
            items: items,
            lastSuccessfulRefresh: now(),
            enrichmentState: enrichmentState(for: items)
        )
        try await cache.save(snapshot)
        return snapshot
    }

    private func enrich(
        _ deals: [AppleMovieDeal],
        token: String
    ) async throws -> [CachedMovieDeal] {
        var result: [CachedMovieDeal] = []
        var startIndex = deals.startIndex

        while startIndex < deals.endIndex {
            try Task.checkCancellation()
            let endIndex = min(startIndex + 4, deals.endIndex)
            let batch = Array(deals[startIndex..<endIndex])

            let batchResults = await withTaskGroup(
                of: EnrichmentAttempt.self,
                returning: [EnrichmentAttempt].self
            ) { group in
                for deal in batch {
                    group.addTask { [enricher] in
                        do {
                            let outcome = try await enricher.resolve(deal, token)
                            return EnrichmentAttempt(deal: deal, outcome: .success(outcome))
                        } catch is CancellationError {
                            return EnrichmentAttempt(
                                deal: deal,
                                outcome: .failure(.cancelled)
                            )
                        } catch TMDBClientError.invalidCredential {
                            return EnrichmentAttempt(
                                deal: deal,
                                outcome: .failure(.invalidCredential)
                            )
                        } catch TMDBClientError.rateLimited {
                            return EnrichmentAttempt(
                                deal: deal,
                                outcome: .failure(.rateLimited)
                            )
                        } catch {
                            let message = (error as? LocalizedError)?.errorDescription
                                ?? "TMDB metadata could not be retrieved for this title."
                            return EnrichmentAttempt(
                                deal: deal,
                                outcome: .failure(.other(message))
                            )
                        }
                    }
                }

                var attempts: [EnrichmentAttempt] = []
                for await attempt in group {
                    attempts.append(attempt)
                }
                return attempts
            }

            if batchResults.contains(where: { $0.isCancelled }) {
                throw CancellationError()
            }

            let hasFatalError = batchResults.contains { $0.isFatal }

            for attempt in batchResults {
                result.append(attempt.cachedItem)
            }

            if hasFatalError {
                let remainingStart = endIndex
                if remainingStart < deals.endIndex {
                    result.append(contentsOf: deals[remainingStart...].map {
                        CachedMovieDeal(
                            appleDeal: $0,
                            metadata: nil,
                            matchStatus: .unavailable,
                            matchNote: "TMDB enrichment paused. Try refreshing again later."
                        )
                    })
                }
                break
            }

            startIndex = endIndex
        }

        return result
    }

    private func uniqueLocalMetadataByTitle(
        _ library: [LibraryMovieSnapshot]
    ) -> [String: DealMovieMetadata] {
        let grouped = Dictionary(grouping: library, by: \.normalizedTitle)
        return grouped.reduce(into: [:]) { result, entry in
            guard entry.value.count == 1, let movie = entry.value.first else { return }
            result[entry.key] = movie.metadata
        }
    }

    private func enrichmentState(
        for items: [CachedMovieDeal]
    ) -> DealCatalogEnrichmentState {
        guard !items.isEmpty else { return .complete }
        let matched = items.count { $0.matchStatus == .matched }
        if matched == items.count { return .complete }
        if matched == 0, items.allSatisfy({ $0.matchStatus == .unavailable }) {
            return .unavailable
        }
        return .partial
    }
}

private enum EnrichmentAttemptOutcome: Sendable {
    case success(DealTMDBMatchOutcome)
    case failure(EnrichmentFailure)
}

private enum EnrichmentFailure: Sendable {
    case invalidCredential
    case rateLimited
    case other(String)
    case cancelled

    var isFatal: Bool {
        switch self {
        case .invalidCredential, .rateLimited: true
        case .other, .cancelled: false
        }
    }

    var message: String {
        switch self {
        case .invalidCredential:
            "TMDB rejected the saved credential. Update it in Settings."
        case .rateLimited:
            "TMDB asked Tonight to slow down. Try refreshing again later."
        case .other(let message):
            message
        case .cancelled:
            "TMDB enrichment was cancelled."
        }
    }
}

private struct EnrichmentAttempt: Sendable {
    let deal: AppleMovieDeal
    let outcome: EnrichmentAttemptOutcome

    var isCancelled: Bool {
        guard case .failure(.cancelled) = outcome else { return false }
        return true
    }

    var isFatal: Bool {
        guard case .failure(let failure) = outcome else { return false }
        return failure.isFatal
    }

    var cachedItem: CachedMovieDeal {
        switch outcome {
        case .success(.matched(let metadata)):
            CachedMovieDeal(
                appleDeal: deal,
                metadata: metadata,
                matchStatus: .matched,
                matchNote: nil
            )
        case .success(.unresolved(let note)):
            CachedMovieDeal(
                appleDeal: deal,
                metadata: nil,
                matchStatus: .unresolved,
                matchNote: note
            )
        case .failure(let failure):
            CachedMovieDeal(
                appleDeal: deal,
                metadata: nil,
                matchStatus: failure.isFatal ? .unavailable : .failed,
                matchNote: failure.message
            )
        }
    }
}

struct MovieDealsClient: Sendable {
    let loadCached: @Sendable () async -> DealCatalogSnapshot?
    let refresh: @Sendable ([LibraryMovieSnapshot]) async throws -> DealCatalogSnapshot

    static func live() -> MovieDealsClient {
        let repository = MovieDealsRepository()
        return MovieDealsClient(
            loadCached: {
                await repository.loadCached()
            },
            refresh: { library in
                try await repository.refresh(library: library)
            }
        )
    }
}
