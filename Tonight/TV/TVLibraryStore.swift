import Foundation
import Observation

@MainActor @Observable
final class TVLibraryStore {
    static let shared = TVLibraryStore()
    private(set) var document = TVLibraryDocument()
    private(set) var isBusy = false
    private(set) var progress = ""
    private(set) var storageReady = false
    var notice: String?
    var errorMessage: String?
    private let file: TVLibraryFile
    private var stopRequested = false
    @ObservationIgnored var syncDidSave: (() -> Void)?

    init(file: TVLibraryFile = .live) {
        self.file = file
        do {
            document = try file.load()
            storageReady = true
        } catch { errorMessage = error.localizedDescription }
    }

    var shows: [TVShow] { document.shows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
    var needsDetails: Int { document.shows.count { !$0.metadataComplete } }
    func show(_ id: UUID) -> TVShow? { document.shows.first { $0.id == id } }

    @discardableResult
    func importTitles(_ text: String, seenBefore: Bool = true) -> Bool {
        do {
            let entries = try TVImportParser.parse(text)
            guard !entries.isEmpty else { return false }
            return change { doc in
                for entry in entries {
                    let existing = doc.shows.firstIndex {
                        (MovieTitleNormalizer.normalize($0.importedTitle) == MovieTitleNormalizer.normalize(entry.title)
                         || MovieTitleNormalizer.normalize($0.title) == MovieTitleNormalizer.normalize(entry.title)) &&
                        (entry.year == nil || $0.requestedYear == entry.year || $0.firstAirYear == entry.year ||
                         ($0.tmdbID == nil && $0.requestedYear == nil))
                    }
                    if let existing {
                        // A more specific reimport can resolve an unknown version, but never widen ownership.
                        if doc.shows[existing].tmdbID == nil, let year = entry.year {
                            doc.shows[existing].requestedYear = year
                        }
                        continue
                    }
                    var show = TVShow(importedTitle: entry.title, requestedYear: entry.year,
                                      ownedSeasons: entry.seasons, title: entry.title)
                    show.viewingStyle = TVStarterLibrary.viewingStyle(for: entry.title)
                    show.seenBefore = seenBefore
                    doc.shows.append(show)
                }
                refreshSuggestions(&doc)
            }
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func updateShow(_ show: TVShow) {
        guard !isBusy else { return }
        _ = change { doc in
            guard let index = doc.shows.firstIndex(where: { $0.id == show.id }) else { return }
            doc.shows[index] = show
            // Any changed ownership or position invalidates plans made using the old selection.
            if doc.activeSession?.showID == show.id { doc.activeSession = nil }
            refreshSuggestions(&doc)
        }
    }

    func removeShow(_ id: UUID) {
        guard !isBusy else { return }
        _ = change { doc in
            doc.shows.removeAll { $0.id == id }
            if doc.activeSession?.showID == id { doc.activeSession = nil }
            refreshSuggestions(&doc)
        }
    }

    func setPreferences(minutes: Int, mood: TVSessionMood, unseenOnly: Bool) {
        _ = change { doc in
            doc.minutes = minutes
            doc.mood = mood
            doc.unseenOnly = unseenOnly
            refreshSuggestions(&doc)
        }
    }

    func refresh() { _ = change { refreshSuggestions(&$0) } }

    func setSessionCount(_ count: Int?) {
        guard document.sessionCount != count else { return }
        _ = change { doc in
            doc.sessionCount = count
            refreshSuggestions(&doc)
        }
    }

    func start(_ session: TVViewingSession) {
        _ = change { doc in
            guard valid(session, in: doc) else { return }
            doc.activeSession = session
        }
    }

    func dismissSession() { _ = change { $0.activeSession = nil } }

    func markWatched(_ session: TVViewingSession, episodeCount: Int? = nil, now: Date = .now) {
        _ = change { doc in
            guard valid(session, in: doc), !doc.history.contains(where: { $0.id == session.id }),
                  let index = doc.shows.firstIndex(where: { $0.id == session.showID }) else { return }
            let episodes = Array(session.episodes.prefix(episodeCount ?? session.episodes.count))
            guard !episodes.isEmpty else { return }
            let previous = doc.shows[index].resumeAfter
            doc.history.append(TVWatchSession(id: session.id, showID: session.showID,
                showTitle: doc.shows[index].title, episodes: episodes, watchedAt: now, previousResume: previous))
            if doc.shows[index].viewingStyle != .anyEpisode {
                doc.shows[index].resumeAfter = episodes.last?.position
            }
            // Keep the rest of a session available when only its first episode was watched.
            let remaining = Array(session.episodes.dropFirst(episodes.count))
            if remaining.isEmpty { doc.activeSession = nil }
            else {
                var continuation = session
                continuation.id = UUID()
                continuation.episodes = remaining
                let durations = remaining.map { TVSessionEngine.duration(of: $0, show: doc.shows[index]) }
                continuation.estimatedMinutes = durations.reduce(0) { $0 + $1.minutes }
                continuation.usesEstimatedRuntime = durations.contains { $0.estimated }
                doc.activeSession = continuation
            }
            refreshSuggestions(&doc)
        }
    }

    func undoLastWatch() {
        _ = change { doc in
            guard let last = doc.history.last else { return }
            if let index = doc.shows.firstIndex(where: { $0.id == last.showID }) {
                doc.shows[index].resumeAfter = last.previousResume
            }
            doc.history.removeLast()
            doc.activeSession = nil
            refreshSuggestions(&doc)
        }
    }

    func stopMatching() { stopRequested = true }

    func loadDetails() async {
        guard !isBusy, storageReady else { return }
        do {
            guard let token = try await TMDBCredentialStore.shared.readToken() else {
                notice = "Your shows are saved. Add your TMDB Read Access Token in Settings, then load TV details."
                return
            }
            await enrich(using: TVMetadataService(client: TMDBClient(token: token)))
        } catch { errorMessage = error.localizedDescription }
    }

    func enrich(using service: any TVMetadataProviding, only showID: UUID? = nil) async {
        guard !isBusy, storageReady else { return }
        isBusy = true
        stopRequested = false
        notice = nil
        let targets = document.shows.filter { (showID == nil || $0.id == showID) && !$0.metadataComplete }.map(\.id)
        var failures = 0
        defer {
            isBusy = false
            progress = ""
            refresh()
        }
        for (offset, id) in targets.enumerated() {
            guard !Task.isCancelled, !stopRequested else { break }
            guard let original = show(id) else { continue }
            progress = "\(offset + 1) of \(targets.count) · \(original.title)"
            do {
                try await enrichShow(id, using: service)
            } catch is CancellationError { break }
            catch {
                if Task.isCancelled { break }
                failures += 1
                _ = change { doc in
                    guard let index = doc.shows.firstIndex(where: { $0.id == id }) else { return }
                    doc.shows[index].note = error.localizedDescription
                }
                if let error = error as? TMDBClientError {
                    switch error {
                    case .invalidCredential, .missingCredential, .rateLimited:
                        notice = error.localizedDescription
                        return
                    default: break
                    }
                }
            }
        }
        if stopRequested || Task.isCancelled { notice = "Matching paused. Saved progress will be reused next time." }
        else if failures > 0 { notice = "Some details couldn’t load. Your shows and completed seasons are saved; try loading details again." }
        else if document.shows.contains(where: { $0.tmdbID == nil }) {
            notice = "Some titles need you to choose a match. Open them in TV Library."
        }
    }

    func searchMatches(for id: UUID, query: String) async {
        guard !isBusy else { return }
        do {
            guard let token = try await TMDBCredentialStore.shared.readToken() else { throw TMDBClientError.missingCredential }
            let matches = try await TVMetadataService(client: TMDBClient(token: token)).search(title: query, year: nil)
            _ = change { doc in
                guard let index = doc.shows.firstIndex(where: { $0.id == id }) else { return }
                doc.shows[index].candidates = matches
                doc.shows[index].note = matches.isEmpty ? "No matches found. Try another title." : "Choose your version of the show."
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func chooseMatch(_ candidate: TVSearchCandidate, for id: UUID) async {
        guard !isBusy else { return }
        let anotherShow = document.shows.contains { $0.id != id && $0.tmdbID == candidate.id }
        guard !anotherShow else {
            errorMessage = "That show is already in your TV library. Your imported entry has been preserved."
            return
        }
        let saved = change { doc in
            guard let index = doc.shows.firstIndex(where: { $0.id == id }) else { return }
            doc.shows[index].tmdbID = candidate.id
            doc.shows[index].title = candidate.name
            doc.shows[index].firstAirYear = candidate.year
            doc.shows[index].posterPath = candidate.posterPath
            doc.shows[index].episodes = []
            doc.shows[index].loadedSeasons = []
            doc.shows[index].seasons = []
            doc.shows[index].candidates = []
            doc.shows[index].note = nil
            refreshSuggestions(&doc)
        }
        guard saved else { return }
        do {
            guard let token = try await TMDBCredentialStore.shared.readToken() else { throw TMDBClientError.missingCredential }
            await enrich(using: TVMetadataService(client: TMDBClient(token: token)), only: id)
        } catch { errorMessage = error.localizedDescription }
    }

    private func enrichShow(_ id: UUID, using service: any TVMetadataProviding) async throws {
        guard var original = show(id) else { return }
        if original.tmdbID == nil {
            let entry = TVImportEntry(title: original.importedTitle, year: original.requestedYear,
                                      seasons: original.ownedSeasons)
            let candidates = try await service.search(title: entry.title, year: entry.year)
            guard let match = TVShowMatching.confidentMatch(candidates, entry: entry) else {
                _ = change { doc in
                    guard let index = doc.shows.firstIndex(where: { $0.id == id }) else { return }
                    doc.shows[index].candidates = candidates
                    doc.shows[index].note = "Choose your version of the show."
                }
                return
            }
            guard !document.shows.contains(where: { $0.id != id && $0.tmdbID == match.id }) else {
                _ = change { doc in
                    guard let index = doc.shows.firstIndex(where: { $0.id == id }) else { return }
                    doc.shows[index].note = "This match is already in your TV library. Review this imported entry."
                }
                return
            }
            original.tmdbID = match.id
        }
        guard let tmdbID = original.tmdbID else { return }
        let details = try await service.details(id: tmdbID)
        let today = Date.now
        let available = details.seasons.filter {
            $0.seasonNumber > 0 && $0.episodeCount > 0 &&
            MovieDateParser.date(from: $0.airDate).map { $0 <= today } == true
        }
        let saved = change { doc in
            guard let index = doc.shows.firstIndex(where: { $0.id == id }) else { return }
            doc.shows[index].tmdbID = tmdbID
            doc.shows[index].title = details.name
            doc.shows[index].firstAirYear = MovieDateParser.year(from: details.firstAirDate)
            doc.shows[index].overview = details.overview ?? ""
            doc.shows[index].posterPath = details.posterPath
            doc.shows[index].backdropPath = details.backdropPath
            doc.shows[index].genres = details.genres.map(\.name)
            doc.shows[index].episodeRuntime = details.episodeRunTime?.first { $0 > 0 }
            doc.shows[index].seasons = available.map {
                TVSeason(number: $0.seasonNumber, name: $0.name, episodeCount: $0.episodeCount, airDate: $0.airDate)
            }
            if doc.shows[index].ownedSeasons == nil {
                doc.shows[index].ownedSeasons = available.map(\.seasonNumber).sorted()
            }
            doc.shows[index].candidates = []
            doc.shows[index].note = nil
        }
        guard saved else { return }
        let seasons = show(id)?.ownedSeasons ?? []
        let seasonSet = Set(available.map(\.seasonNumber))
        guard Set(seasons).isSubset(of: seasonSet) else { throw TVLibraryError.missingEpisodes }
        // Fetch at most three seasons at a time; completed seasons persist independently.
        let missing = seasons.filter { !(show(id)?.loadedSeasons.contains($0) ?? false) }
        for start in stride(from: 0, to: missing.count, by: 3) {
            try Task.checkCancellation()
            if stopRequested { return }
            let group = Array(missing[start..<min(start + 3, missing.count)])
            let results = await withTaskGroup(of: (Int, Result<[TVEpisode], Error>).self) { tasks in
                for season in group {
                    tasks.addTask {
                        do { return (season, .success(try await service.episodes(id: tmdbID, season: season))) }
                        catch { return (season, .failure(error)) }
                    }
                }
                var results: [(Int, Result<[TVEpisode], Error>)] = []
                for await result in tasks { results.append(result) }
                return results
            }
            var failure: Error?
            for (season, result) in results {
                switch result {
                case .success(let episodes):
                    let aired = episodes.filter {
                        $0.seasonNumber == season && $0.episodeNumber > 0 &&
                        MovieDateParser.date(from: $0.airDate).map { $0 <= today } == true
                    }
                    guard !aired.isEmpty else { failure = TVLibraryError.missingEpisodes; continue }
                    _ = change { doc in
                        guard let index = doc.shows.firstIndex(where: { $0.id == id }) else { return }
                        doc.shows[index].episodes.removeAll { $0.seasonNumber == season }
                        doc.shows[index].episodes.append(contentsOf: aired)
                        if !doc.shows[index].loadedSeasons.contains(season) { doc.shows[index].loadedSeasons.append(season) }
                    }
                case .failure(let error): failure = error
                }
            }
            if let failure { throw failure }
        }
    }

    private func valid(_ session: TVViewingSession, in doc: TVLibraryDocument) -> Bool {
        guard let show = doc.shows.first(where: { $0.id == session.showID }), !session.episodes.isEmpty else { return false }
        let eligible = Set(show.eligibleEpisodes.map(\.id))
        return session.episodes.allSatisfy { eligible.contains($0.id) }
    }

    private func refreshSuggestions(_ doc: inout TVLibraryDocument) {
        doc.generation &+= 1
        let eligibleIDs = Set(doc.shows.filter { !$0.isPaused && $0.metadataComplete && doc.mood.accepts($0) }.map(\.id))
        if eligibleIDs.isSubset(of: Set(doc.suggestedShowIDs)) { doc.suggestedShowIDs = [] }
        doc.suggestions = TVSessionEngine.suggestions(document: doc)
        doc.suggestedShowIDs = Array(Set(doc.suggestedShowIDs + doc.suggestions.map(\.showID)))
    }

    func prepareSync() throws {
        guard storageReady else { throw TVSyncError.localStorage }
        guard document.sync == nil else { return }
        try file.backupBeforeSync()
        var next = document
        TVSyncStore.seed(&next)
        try file.save(next)
        document = next
    }

    /// Sync metadata and received edits commit atomically without echoing a local-save callback.
    func saveSyncChanges(reconcile: Bool = false, _ edit: (inout TVLibraryDocument) throws -> Void) throws {
        guard storageReady else { throw TVSyncError.localStorage }
        var next = document
        try edit(&next)
        if reconcile {
            TVSyncStore.reconcile(&next)
            if next.shows != document.shows || next.history != document.history { refreshSuggestions(&next) }
        }
        try file.save(next)
        document = next
    }

    @discardableResult
    private func change(_ edit: (inout TVLibraryDocument) -> Void) -> Bool {
        guard storageReady else { return false }
        var next = document
        edit(&next)
        let syncChanged = TVSyncStore.capture(previous: document, next: &next)
        do {
            try file.save(next)
            document = next
            if syncChanged { syncDidSave?() }
            return true
        }
        catch { errorMessage = "Your TV change couldn’t be saved. \(error.localizedDescription)"; return false }
    }
}
