import Foundation
import Observation
import SwiftData

enum ImportPhase: Equatable, Sendable {
    case editor
    case review
    case importing
    case completed
}

struct ImportSummary: Equatable, Sendable {
    let imported: Int
    let duplicates: Int
    let unresolved: Int
    let failed: Int
}

@MainActor
@Observable
final class ImportViewModel {
    var input = ""
    private(set) var entries: [LibraryImportEntry] = []
    private(set) var phase: ImportPhase = .editor
    private(set) var summary: ImportSummary?
    var message: String?

    var completedCount: Int {
        entries.count { entry in
            switch entry.state {
            case .imported, .duplicate, .unresolved, .failed:
                true
            case .waiting, .searching, .enriching:
                false
            }
        }
    }

    var isImporting: Bool { phase == .importing }

    func prepareReview() {
        let parsed = MovieImportParser.parse(input)
        guard !parsed.isEmpty else {
            message = "Paste at least one movie title to continue."
            return
        }
        entries = parsed
        summary = nil
        message = nil
        phase = .review
    }

    func returnToEditor() {
        guard phase == .review else { return }
        phase = .editor
    }

    func removeEntries(at offsets: IndexSet) {
        guard phase == .review else { return }
        entries.remove(atOffsets: offsets)
        if entries.isEmpty {
            phase = .editor
            message = "No movies remain. Add at least one title to continue."
        }
    }

    func importLibrary(modelContext: ModelContext) async {
        guard !entries.isEmpty else {
            message = "There are no movies to import."
            return
        }
        let token: String
        do {
            guard let savedToken = try await TMDBCredentialStore.shared.readToken() else {
                message = "TMDB is not configured. Add your Read Access Token in Settings, then try again."
                return
            }
            token = savedToken
        } catch {
            message = "Tonight could not read the TMDB credential from Keychain. Open Settings and save it again."
            return
        }

        phase = .importing
        summary = nil
        message = nil

        let existingMovies: [Movie]
        do {
            existingMovies = try modelContext.fetch(FetchDescriptor<Movie>())
        } catch {
            phase = .review
            message = "Tonight could not read the local library. No import was started."
            return
        }

        var identities = existingMovies.map(MovieIdentity.init(movie:))
        let client = TMDBClient(token: token)
        let resolver = TMDBMatchResolver(client: client)

        for index in entries.indices {
            if Task.isCancelled {
                phase = .review
                message = "Import stopped. Movies already completed remain in your library."
                return
            }

            let entry = entries[index]
            let fallbackIdentity = MovieIdentity(
                tmdbID: nil,
                title: entry.title,
                releaseYear: entry.year
            )
            if LibraryDuplicateDetector.contains(fallbackIdentity, in: identities) {
                setState(.duplicate, at: index, message: "Already in Library")
                continue
            }

            setState(.searching, at: index)

            do {
                let searchTitle = MovieSearchQuery.title(from: entry.title)
                let candidates = try await client.searchMovies(title: searchTitle, year: entry.year)
                switch try await resolver.resolve(
                    title: searchTitle,
                    year: entry.year,
                    candidates: candidates
                ) {
                case .noMatch:
                    let note = "No confident TMDB match was found."
                    let unresolved = MovieFactory.unresolvedMovie(
                        from: entry,
                        status: .unresolved,
                        note: note
                    )
                    if persist(unresolved, in: modelContext, index: index) {
                        identities.append(MovieIdentity(movie: unresolved))
                        setState(.unresolved, at: index, message: note)
                    }

                case .ambiguous:
                    let note = "More than one plausible TMDB match was found."
                    let unresolved = MovieFactory.unresolvedMovie(
                        from: entry,
                        status: .unresolved,
                        note: note
                    )
                    if persist(unresolved, in: modelContext, index: index) {
                        identities.append(MovieIdentity(movie: unresolved))
                        setState(.unresolved, at: index, message: note)
                    }

                case .matched(let candidate, let details):
                    let matchedIdentity = MovieIdentity(
                        tmdbID: candidate.id,
                        title: candidate.title,
                        releaseYear: candidate.releaseYear
                    )
                    if LibraryDuplicateDetector.contains(matchedIdentity, in: identities) {
                        setState(
                            .duplicate,
                            at: index,
                            matchedTitle: candidate.title,
                            message: "Already in Library"
                        )
                        continue
                    }

                    setState(.enriching, at: index, matchedTitle: candidate.title)
                    let movie = MovieFactory.enrichedMovie(
                        from: details,
                        importedEntry: entry
                    )
                    let enrichedIdentity = MovieIdentity(movie: movie)
                    if LibraryDuplicateDetector.contains(enrichedIdentity, in: identities) {
                        setState(
                            .duplicate,
                            at: index,
                            matchedTitle: movie.title,
                            message: "Already in Library"
                        )
                        continue
                    }

                    if persist(movie, in: modelContext, index: index) {
                        identities.append(enrichedIdentity)
                        setState(.imported, at: index, matchedTitle: movie.title)
                    }
                }
            } catch is CancellationError {
                phase = .review
                message = "Import stopped. Movies already completed remain in your library."
                return
            } catch TMDBClientError.invalidCredential {
                phase = .review
                message = "TMDB rejected the saved credential. Update the Read Access Token in Settings, then retry."
                return
            } catch TMDBClientError.rateLimited {
                phase = .review
                message = "TMDB is receiving too many requests. Wait a moment, then retry the remaining movies."
                return
            } catch {
                if Task.isCancelled {
                    phase = .review
                    message = "Import stopped. Movies already completed remain in your library."
                    return
                }
                let note = (error as? LocalizedError)?.errorDescription
                    ?? "This movie could not be imported."
                let failedMovie = MovieFactory.unresolvedMovie(
                    from: entry,
                    status: .failed,
                    note: note
                )
                if persist(failedMovie, in: modelContext, index: index) {
                    identities.append(MovieIdentity(movie: failedMovie))
                    setState(.failed, at: index, message: note)
                }
            }
        }

        summary = ImportSummary(
            imported: entries.count { $0.state == .imported },
            duplicates: entries.count { $0.state == .duplicate },
            unresolved: entries.count { $0.state == .unresolved },
            failed: entries.count { $0.state == .failed }
        )
        phase = .completed
        LibrarySyncCoordinator.shared.localDidSave()
    }

    private func persist(_ movie: Movie, in context: ModelContext, index: Int) -> Bool {
        context.insert(movie)
        do {
            try LibrarySyncStore.save(context)
            return true
        } catch {
            context.rollback()
            setState(
                .failed,
                at: index,
                message: "Tonight could not save this movie locally."
            )
            return false
        }
    }

    private func setState(
        _ state: LibraryImportState,
        at index: Int,
        matchedTitle: String? = nil,
        message: String? = nil
    ) {
        entries[index].state = state
        if let matchedTitle {
            entries[index].matchedTitle = matchedTitle
        }
        entries[index].message = message
    }
}
