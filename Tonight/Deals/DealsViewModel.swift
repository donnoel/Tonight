import Foundation
import Observation

@MainActor
@Observable
final class DealsViewModel {
    static let cacheLifetime: TimeInterval = 6 * 60 * 60

    private(set) var snapshot: DealCatalogSnapshot?
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var notice: String?
    private(set) var recommendations: [DealRecommendationRank] = []

    private let client: MovieDealsClient
    private let now: () -> Date

    init(
        client: MovieDealsClient,
        now: @escaping () -> Date = { .now }
    ) {
        self.client = client
        self.now = now
    }

    func load(
        library: [LibraryMovieSnapshot],
        forceRefresh: Bool = false
    ) async {
        guard !isLoading, !isRefreshing else { return }

        if snapshot == nil {
            isLoading = true
            snapshot = await client.loadCached()
            isLoading = false
        }

        if !forceRefresh,
           let snapshot,
           snapshot.isFresh(at: now(), lifetime: Self.cacheLifetime) {
            return
        }

        isRefreshing = true
        errorMessage = nil
        notice = nil
        defer { isRefreshing = false }

        do {
            let refreshed = try await client.refresh(library)
            try Task.checkCancellation()
            snapshot = refreshed
        } catch is CancellationError {
            return
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription
                ?? "Tonight could not retrieve Apple’s movie deals."
            if let snapshot {
                notice = "Showing deals last updated \(snapshot.lastSuccessfulRefresh.formatted(date: .abbreviated, time: .shortened)). \(detail)"
            } else {
                errorMessage = detail
            }
        }
    }

    func updateRecommendations(
        library: [Movie],
        history: [RecommendationEvent]
    ) {
        let candidates = (snapshot?.items ?? []).compactMap { item -> DealRecommendationCandidate? in
            if let libraryMovie = DealLibraryMatcher.movie(for: item, in: library) {
                return DealRecommendationCandidate(id: item.id, movie: libraryMovie)
            }
            guard let metadata = item.metadata else { return nil }
            return DealRecommendationCandidate(
                id: item.id,
                movie: metadata.makeTransientMovie(importedTitle: item.appleDeal.title)
            )
        }
        recommendations = RecommendationEngine.rankDeals(
            candidates: candidates,
            tasteLibrary: library,
            history: history,
            now: now()
        )
    }
}
