#if DEBUG
import Foundation
import SwiftData

/// Explicit operator requests only; normal launches never modify library membership.
@MainActor
enum DebugLibraryMaintenance {
    enum Failure: Error { case invalidRequest, missingMovies, syncNotSeeded, matchUnavailable }

    static func performIfRequested(in context: ModelContext) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-TonightRemoveMovies") {
            guard arguments.indices.contains(index + 1) else { throw Failure.invalidRequest }
            let values = arguments[index + 1].split(separator: ",", omittingEmptySubsequences: false)
            let ids = values.compactMap { UUID(uuidString: String($0)) }
            guard !ids.isEmpty, ids.count == values.count else { throw Failure.invalidRequest }
            try removeMovies(ids: Set(ids), in: context)
        }
        if let index = arguments.firstIndex(of: "-TonightCorrectMovie") {
            guard arguments.indices.contains(index + 3),
                  let id = UUID(uuidString: arguments[index + 1]),
                  let tmdbID = Int(arguments[index + 2]) else { throw Failure.invalidRequest }
            let movies = try context.fetch(FetchDescriptor<Movie>())
            guard let movie = movies.first(where: { $0.id == id }) else { throw Failure.missingMovies }
            guard movie.tmdbID != tmdbID else { return }
            guard let token = try await TMDBCredentialStore.shared.readToken() else {
                throw TMDBClientError.missingCredential
            }
            let candidates = try await TMDBClient(token: token).searchMovies(
                title: arguments[index + 3], year: nil)
            guard let candidate = candidates.first(where: { $0.id == tmdbID }) else {
                throw Failure.matchUnavailable
            }
            guard await UnresolvedMatchViewModel().apply(candidate, to: movie, in: context) != nil else {
                throw Failure.matchUnavailable
            }
        }
    }

    static func removeMovies(ids: Set<UUID>, in context: ModelContext) throws {
        guard !ids.isEmpty else { throw Failure.invalidRequest }
        let movies = try context.fetch(FetchDescriptor<Movie>()).filter { ids.contains($0.id) }
        guard !movies.isEmpty else { return } // Repeating the same explicit request is harmless.
        guard movies.count == ids.count else { throw Failure.missingMovies }
        guard try LibrarySyncStore.state(in: context).seeded else { throw Failure.syncNotSeeded }
        do {
            let modelIDs = Set(movies.map(\.persistentModelID))
            for event in try context.fetch(FetchDescriptor<RecommendationEvent>())
                where event.movie.map({ modelIDs.contains($0.persistentModelID) }) == true {
                event.movie = nil
            }
            for movie in movies { context.delete(movie) }
            try LibrarySyncStore.save(context)
            TonightWidgetSnapshotPublisher.removeMovies(ids: ids)
        } catch {
            context.rollback()
            throw error
        }
    }
}
#endif
