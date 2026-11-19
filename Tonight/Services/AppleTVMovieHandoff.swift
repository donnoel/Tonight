import Foundation

/// Save an explicit movie choice before handing its verified display URL to Apple TV.
@MainActor
enum AppleTVMovieHandoff {
    enum Outcome: Equatable {
        case opened, unavailable, saveFailed, openFailed
    }

    static func open(
        query: AppleTVMovieLinkQuery,
        resolve: (AppleTVMovieLinkQuery) async throws -> URL?,
        choose: () -> Bool,
        launch: (URL) async -> Bool
    ) async throws -> Outcome {
        let url = try await resolve(query)
        try Task.checkCancellation()
        guard let url else { return .unavailable }
        guard choose() else { return .saveFailed }
        return await launch(url) ? .opened : .openFailed
    }
}
