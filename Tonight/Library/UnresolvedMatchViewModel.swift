import Foundation
import Observation
import SwiftData

struct AutomaticMatchSummary: Equatable, Sendable {
    let matched: Int
    let remaining: Int
    let errors: Int
}

private enum UnresolvedMatchError: LocalizedError {
    case missingCredential
    case localSave

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            "Add your TMDB Read Access Token in Settings before matching movies."
        case .localSave:
            "Tonight could not save this match to the local library."
        }
    }
}

@MainActor
@Observable
final class UnresolvedMatchViewModel {
    var query = ""
    var yearText = ""
    private(set) var candidates: [TMDBSearchCandidate] = []
    private(set) var isSearching = false
    private(set) var isApplying = false
    private(set) var isRetryingAutomatically = false
    private(set) var retryCompleted = 0
    private(set) var retryTotal = 0
    private(set) var currentRetryTitle: String?
    private(set) var automaticSummary: AutomaticMatchSummary?
    var message: String?

    var isWorking: Bool {
        isSearching || isApplying || isRetryingAutomatically
    }

    func prepare(for movie: Movie) {
        query = MovieSearchQuery.title(from: movie.importedTitle)
        yearText = (movie.importedYear ?? movie.releaseYear).map(String.init) ?? ""
        candidates = []
        message = nil
    }

    func search() async {
        let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            message = "Enter a movie title to search TMDB."
            return
        }

        isSearching = true
        candidates = []
        message = nil
        defer { isSearching = false }

        do {
            let client = try await makeClient()
            candidates = try await client.searchMovies(
                title: title,
                year: parsedYear
            )
            if candidates.isEmpty {
                message = "No TMDB movies matched that search. Try changing the title or removing the year."
            }
        } catch is CancellationError {
            return
        } catch {
            message = userMessage(for: error)
        }
    }

    func apply(
        _ candidate: TMDBSearchCandidate,
        to movie: Movie,
        in modelContext: ModelContext
    ) async -> Bool {
        isApplying = true
        message = nil
        defer { isApplying = false }

        do {
            let allMovies = try modelContext.fetch(FetchDescriptor<Movie>())
            if let existingMatch = allMovies.first(where: {
                $0.id != movie.id && $0.tmdbID == candidate.id
            }) {
                do {
                    try LocalLibraryDuplicateRepair.consolidate(
                        movie,
                        into: existingMatch,
                        in: modelContext
                    )
                } catch {
                    modelContext.rollback()
                    throw UnresolvedMatchError.localSave
                }
                candidates = []
                return true
            }

            let client = try await makeClient()
            let details = try await client.movieDetails(id: candidate.id)
            MovieFactory.enrich(movie, from: details)
            do {
                try LibrarySyncStore.save(modelContext)
            } catch {
                modelContext.rollback()
                throw UnresolvedMatchError.localSave
            }
            candidates = []
            return true
        } catch is CancellationError {
            return false
        } catch {
            message = userMessage(for: error)
            return false
        }
    }

    func retryAutomatically(
        movies: [Movie],
        in modelContext: ModelContext
    ) async {
        guard !movies.isEmpty else { return }

        isRetryingAutomatically = true
        retryCompleted = 0
        retryTotal = movies.count
        currentRetryTitle = nil
        automaticSummary = nil
        message = nil

        var matched = 0
        var errors = 0

        do {
            let client = try await makeClient()
            let resolver = TMDBMatchResolver(client: client)
            let allMovies = try modelContext.fetch(FetchDescriptor<Movie>())
            var matchedTMDBIDs = Set(allMovies.compactMap(\.tmdbID))

            for movie in movies where movie.resolutionStatus != .resolved {
                if Task.isCancelled {
                    message = "Automatic matching stopped. Matches already completed were saved."
                    break
                }

                currentRetryTitle = movie.importedTitle
                let title = MovieSearchQuery.title(from: movie.importedTitle)

                do {
                    let candidates = try await client.searchMovies(
                        title: title,
                        year: movie.importedYear ?? movie.releaseYear
                    )
                    guard case .matched(let candidate, let details) = try await resolver.resolve(
                        title: title,
                        year: movie.importedYear ?? movie.releaseYear,
                        candidates: candidates
                    ), !matchedTMDBIDs.contains(candidate.id) else {
                        retryCompleted += 1
                        continue
                    }

                    MovieFactory.enrich(movie, from: details)
                    do {
                        try LibrarySyncStore.save(modelContext)
                        matchedTMDBIDs.insert(candidate.id)
                        matched += 1
                    } catch {
                        modelContext.rollback()
                        errors += 1
                    }
                } catch TMDBClientError.invalidCredential {
                    message = "TMDB rejected the saved credential. Update it in Settings before retrying."
                    break
                } catch TMDBClientError.rateLimited {
                    message = "TMDB asked Tonight to slow down. Wait a moment, then retry the remaining movies."
                    break
                } catch is CancellationError {
                    message = "Automatic matching stopped. Matches already completed were saved."
                    break
                } catch {
                    errors += 1
                }

                retryCompleted += 1
            }
        } catch is CancellationError {
            message = "Automatic matching stopped. Matches already completed were saved."
        } catch {
            message = userMessage(for: error)
        }

        currentRetryTitle = nil
        automaticSummary = AutomaticMatchSummary(
            matched: matched,
            remaining: movies.count { $0.resolutionStatus != .resolved },
            errors: errors
        )
        isRetryingAutomatically = false
    }

    private var parsedYear: Int? {
        let trimmed = yearText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private func makeClient() async throws -> TMDBClient {
        guard let token = try await TMDBCredentialStore.shared.readToken() else {
            throw UnresolvedMatchError.missingCredential
        }
        return TMDBClient(token: token)
    }

    private func userMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "Tonight could not complete this TMDB request. Try again."
    }
}
