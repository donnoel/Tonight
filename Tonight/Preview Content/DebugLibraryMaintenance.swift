#if DEBUG
import Foundation
import SwiftData

/// Explicit operator requests only; normal launches never modify library membership.
@MainActor
enum DebugLibraryMaintenance {
    enum Failure: Error { case invalidRequest, missingMovies, syncNotSeeded, matchUnavailable }

    static func performIfRequested(in context: ModelContext) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-TonightImportMovies") {
            guard arguments.indices.contains(index + 1) else { throw Failure.invalidRequest }
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let url = directory.appendingPathComponent(URL(fileURLWithPath: arguments[index + 1]).lastPathComponent)
            let model = ImportViewModel()
            model.input = try String(contentsOf: url, encoding: .utf8)
            model.prepareReview()
            await model.importLibrary(modelContext: context)
            guard model.summary != nil,
                  model.entries.allSatisfy({ $0.state == .imported || $0.state == .duplicate }) else {
                throw Failure.matchUnavailable
            }
        }
        if let index = arguments.firstIndex(of: "-TonightEditionRuntimes") {
            guard arguments.indices.contains(index + 1) else { throw Failure.invalidRequest }
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let url = directory.appendingPathComponent(URL(fileURLWithPath: arguments[index + 1]).lastPathComponent)
            let edits = try JSONDecoder().decode([EditionRuntime].self, from: Data(contentsOf: url))
            let movies = try context.fetch(FetchDescriptor<Movie>())
            var changes: [(Movie, Int)] = []
            for edit in edits {
                let matches = movies.filter { $0.tmdbID == edit.tmdbID && $0.edition == edit.edition }
                guard matches.count == 1, let movie = matches.first, (1...1440).contains(edit.minutes) else {
                    throw Failure.invalidRequest
                }
                changes.append((movie, edit.minutes))
            }
            for (movie, minutes) in changes { movie.runtimeMinutes = minutes }
            try LibrarySyncStore.save(context)
        }
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

    private struct EditionRuntime: Decodable {
        let tmdbID: Int
        let edition: MovieEdition
        let minutes: Int
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
