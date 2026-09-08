import Foundation
import SwiftData

@Model
final class LibrarySyncEntry {
    @Attribute(.unique) var recordName: String
    var documentData: Data
    var systemFields: Data?
    var pendingUpload: Bool
    var localMovieID: UUID?
    var localSnapshotData: Data?

    init(name: String, document: LibrarySyncDocument) throws {
        recordName = name
        documentData = try LibrarySyncCoding.encode(document)
        pendingUpload = true
    }

    func document() throws -> LibrarySyncDocument {
        let result = try JSONDecoder().decode(LibrarySyncDocument.self, from: documentData)
        guard result.version == 1 else { throw LibrarySyncFailure.newerFormat }
        return result
    }

    func setDocument(_ document: LibrarySyncDocument) throws {
        let data = try LibrarySyncCoding.encode(document)
        if documentData != data { documentData = data; pendingUpload = true }
    }
}

@Model
final class LibrarySyncState {
    @Attribute(.unique) var key: String = "library-v1"
    var deviceID: String = UUID().uuidString
    var seeded: Bool = false
    var accountID: String?
    var engineState: Data?
    var lastSync: Date?
    var browsingProgressMigrated: Bool?
    var engineConfigurationVersion: Int?
    init() {}

    /// Refresh only the sync engine's cached subscription and download cursors.
    /// Movie documents, pending uploads, and account ownership remain authoritative.
    func prepareEngineConfiguration() {
        guard engineConfigurationVersion != 1 else { return }
        engineState = nil
        engineConfigurationVersion = 1
    }
}

enum LibrarySyncFailure: LocalizedError {
    case newerFormat, accountChanged, cloudReset, localStorage
    var errorDescription: String? {
        switch self {
        case .newerFormat: "Update Tonight on this device to read the newer iCloud library format. Your local library is safe."
        case .accountChanged: "This library belongs to a different iCloud account. Sign back into the original account to resume sync. Your local library is safe."
        case .cloudReset: "The iCloud library was removed outside Tonight. Sync is paused to protect your local library."
        case .localStorage: "Tonight could not save sync progress. Free some device storage and try again. Your saved library is still available."
        }
    }
}

/// Movie edits and their outbox entries commit in the same local transaction.
@MainActor
enum LibrarySyncStore {
    static let didSave = Notification.Name("TonightLibraryDidSave")

    static func supported(in context: ModelContext) -> Bool {
        context.container.schema.entities.contains { $0.name == "LibrarySyncEntry" }
    }

    static func state(in context: ModelContext) throws -> LibrarySyncState {
        if let state = try context.fetch(FetchDescriptor<LibrarySyncState>()).first { return state }
        let state = LibrarySyncState(); context.insert(state); return state
    }

    static func save(_ context: ModelContext) throws {
        if supported(in: context) {
            let state = try state(in: context)
            try migrateBrowsingProgress(state: state, in: context)
            if state.seeded {
                let changed = (context.insertedModelsArray + context.changedModelsArray).compactMap { $0 as? Movie }
                let deleted = context.deletedModelsArray.compactMap { $0 as? Movie }
                try capture(changed, deleted: deleted, initial: false, state: state, in: context)
            }
        }
        try context.save()
        NotificationCenter.default.post(name: didSave, object: context)
    }

    static func seed(in context: ModelContext) throws {
        let state = try state(in: context)
        try migrateBrowsingProgress(state: state, in: context)
        guard !state.seeded else { return }
        let movies = try context.fetch(FetchDescriptor<Movie>())
        // A portable second backup, in addition to the raw store backup before migration.
        let backup = try LibrarySyncCoding.encode(movies.map(SyncedLibraryMovie.init(movie:)))
        let url = try backupDirectory().appendingPathComponent("library-before-sync.json")
        if !FileManager.default.fileExists(atPath: url.path) { try backup.write(to: url, options: .atomic) }
        try capture(movies, deleted: [], initial: true, state: state, in: context)
        state.seeded = true
        try reconcile(in: context)
        try context.save()
    }

    /// Import only this device's current position, not its lifetime exposure counts.
    static func migrateBrowsingProgress(state: LibrarySyncState, in context: ModelContext) throws {
        guard state.browsingProgressMigrated != true else { return }
        let events = try context.fetch(FetchDescriptor<RecommendationEvent>())
        let rotationID = events.max { $0.recommendedAt < $1.recommendedAt }?.rotationID
        for event in events where event.rotationID == rotationID {
            guard let movie = event.movie else { continue }
            let progress = LibraryBrowsingProgress(generation: event.browsingGeneration ?? 0,
                shownAt: event.recommendedAt, eventID: event.id)
            movie.browsingProgress = LibraryBrowsingProgress.merged(movie.browsingProgress, progress)
        }
        state.browsingProgressMigrated = true
    }

    static func capture(_ movies: [Movie], deleted: [Movie], initial: Bool, state: LibrarySyncState, in context: ModelContext) throws {
        guard !movies.isEmpty || !deleted.isEmpty else { return }
        let entries = try context.fetch(FetchDescriptor<LibrarySyncEntry>())
        var byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.recordName, $0) })
        let byLocalID = Dictionary(entries.compactMap { entry in entry.localMovieID.map { ($0, entry) } }, uniquingKeysWith: { first, _ in first })
        let revision = LibraryRevision(date: .now, device: state.deviceID)
        let deletedIDs = Set(deleted.map(\.id))
        for movie in movies where !deletedIDs.contains(movie.id) {
            let snapshot = SyncedLibraryMovie(movie: movie)
            let name = snapshot.details.recordName
            let previousEntry = byLocalID[movie.id]
            let baseline = try previousEntry?.localSnapshotData.map { try JSONDecoder().decode(SyncedLibraryMovie.self, from: $0) }
            if baseline == snapshot { continue }
            var document: LibrarySyncDocument
            if let previousEntry {
                document = try previousEntry.document()
                document.update(snapshot, previous: baseline, revision: revision)
                if previousEntry.recordName != name {
                    var redirect = try previousEntry.document()
                    redirect.redirectTo = name; redirect.membershipRevision = revision
                    try previousEntry.setDocument(redirect)
                    previousEntry.localMovieID = nil; previousEntry.localSnapshotData = nil
                }
            } else {
                document = LibrarySyncDocument(movie: snapshot, revision: revision, initial: initial)
            }
            let entry: LibrarySyncEntry
            if let existing = byName[name] {
                entry = existing
                document = try existing.document().merged(with: document)
                try entry.setDocument(document)
            } else {
                entry = try LibrarySyncEntry(name: name, document: document)
                context.insert(entry); byName[name] = entry
            }
            // Preserve this device's Movie identity and event relationships.
            if entry.localMovieID == nil { entry.localMovieID = movie.id }
            if entry.localMovieID == movie.id { entry.localSnapshotData = try LibrarySyncCoding.encode(snapshot) }
        }
        for movie in deleted {
            guard let entry = byLocalID[movie.id] else { continue }
            var document = try entry.document()
            document.deleted = true; document.redirectTo = nil; document.membershipRevision = revision
            try entry.setDocument(document)
            entry.localMovieID = nil; entry.localSnapshotData = nil
        }
    }

    /// Resolve only unique title/year fallbacks, and retain redirect records so an
    /// offline device cannot reintroduce the old unresolved copy.
    static func reconcile(in context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<LibrarySyncEntry>())
        var documents = try Dictionary(uniqueKeysWithValues: entries.map { ($0.recordName, try $0.document()) })
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.recordName, $0) })
        let resolvedByTitle = Dictionary(grouping: documents.filter { $0.value.movie.details.tmdbID != nil && $0.value.redirectTo == nil }) {
            MovieTitleNormalizer.normalize($0.value.movie.details.importedTitle)
        }
        for entry in entries {
            guard var unknown = documents[entry.recordName], unknown.movie.details.tmdbID == nil,
                  unknown.redirectTo == nil else { continue }
            let details = unknown.movie.details
            let title = MovieTitleNormalizer.normalize(details.importedTitle)
            let year = details.importedYear ?? details.releaseYear
            let matches = resolvedByTitle[title, default: []].filter { _, candidate in
                year == nil || (candidate.movie.details.importedYear ?? candidate.movie.details.releaseYear) == nil ||
                (candidate.movie.details.importedYear ?? candidate.movie.details.releaseYear) == year
            }
            guard !title.isEmpty, matches.count == 1, let match = matches.first else { continue }
            let merged = (documents[match.key] ?? match.value).merged(with: unknown)
            // A fallback may contribute personal state, but cannot replace a confirmed match.
            var canonical = merged
            canonical.movie.details = match.value.movie.details
            canonical.detailsRevision = match.value.detailsRevision
            documents[match.key] = canonical
            unknown.redirectTo = match.key
            unknown.membershipRevision = max(unknown.membershipRevision, match.value.membershipRevision)
            documents[entry.recordName] = unknown
        }
        // Follow resolution chains and carry edits made on an offline alias to
        // its final movie, without allowing an alias to change membership again.
        for name in documents.keys.sorted() {
            guard var alias = documents[name], var target = alias.redirectTo else { continue }
            var visited: Set<String> = [name]
            while let next = documents[target]?.redirectTo {
                guard visited.insert(target).inserted else { throw LibrarySyncFailure.newerFormat }
                target = next
            }
            guard target != name, var canonical = documents[target] else { continue }
            let membership = canonical.membershipRevision
            let deleted = canonical.deleted
            let details = canonical.movie.details
            let detailsRevision = canonical.detailsRevision
            canonical = canonical.merged(with: alias)
            canonical.movie.details = details; canonical.detailsRevision = detailsRevision
            canonical.membershipRevision = membership; canonical.deleted = deleted; canonical.redirectTo = nil
            documents[target] = canonical
            alias.redirectTo = target
            documents[name] = alias
        }
        let movies = try context.fetch(FetchDescriptor<Movie>())
        var byID = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
        let events = try context.fetch(FetchDescriptor<RecommendationEvent>())
        var removedIDs = Set<UUID>()
        let localAliases = Dictionary(entries.compactMap { entry -> (String, UUID)? in
            guard let target = documents[entry.recordName]?.redirectTo, let id = entry.localMovieID else { return nil }
            return (target, id)
        }, uniquingKeysWith: { first, _ in first })
        // Materialize canonical records before resolving aliases.
        for entry in entries {
            guard let document = documents[entry.recordName] else { continue }
            try entry.setDocument(document)
            guard document.redirectTo == nil else { continue }
            let aliasID = localAliases[entry.recordName]
            let existing = (entry.localMovieID ?? aliasID).flatMap { byID[$0] }
            if document.deleted {
                if let existing { context.delete(existing); removedIDs.insert(existing.id); byID[existing.id] = nil }
                entry.localMovieID = nil; entry.localSnapshotData = nil
                continue
            }
            let movie: Movie
            if let existing { movie = existing; entry.localMovieID = existing.id }
            else {
                movie = Movie(title: document.movie.details.title)
                context.insert(movie); byID[movie.id] = movie; entry.localMovieID = movie.id
            }
            if SyncedLibraryMovie(movie: movie) != document.movie { document.movie.apply(to: movie) }
            let snapshotData = try LibrarySyncCoding.encode(document.movie)
            if entry.localSnapshotData != snapshotData { entry.localSnapshotData = snapshotData }
        }
        for entry in entries {
            guard let target = documents[entry.recordName]?.redirectTo else { continue }
            if documents[target]?.deleted == true {
                if let oldID = entry.localMovieID, let movie = byID[oldID] {
                    context.delete(movie); removedIDs.insert(oldID); byID[oldID] = nil
                }
                entry.localMovieID = nil; entry.localSnapshotData = nil
                continue
            }
            guard let canonicalID = byName[target]?.localMovieID,
                  let canonical = byID[canonicalID] else { continue }
            if let oldID = entry.localMovieID, oldID != canonicalID, let duplicate = byID[oldID] {
                for event in events where event.movie?.id == oldID { event.movie = canonical }
                context.delete(duplicate); removedIDs.insert(oldID); byID[oldID] = nil
            }
            entry.localMovieID = nil; entry.localSnapshotData = nil
        }
        // Same-TMDB imports from before sync retain only one visible movie.
        let boundIDs = Set(entries.compactMap(\.localMovieID))
        for movie in movies where !boundIDs.contains(movie.id) && !removedIDs.contains(movie.id) {
            guard let canonicalID = byName[SyncedLibraryMovie(movie: movie).details.recordName]?.localMovieID,
                  canonicalID != movie.id, let canonical = byID[canonicalID] else { continue }
            for event in events where event.movie?.id == movie.id { event.movie = canonical }
            context.delete(movie); removedIDs.insert(movie.id)
        }
        if !removedIDs.isEmpty { TonightWidgetSnapshotPublisher.removeMovies(ids: removedIDs) }
    }

    static func backupDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("PreLibrarySyncBackup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func backupBeforeOpeningStore() throws {
        let directory = try backupDirectory()
        let marker = directory.appendingPathComponent("complete")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let storeURL = ModelConfiguration(cloudKitDatabase: .none).url
        let base = storeURL.deletingLastPathComponent()
        for source in try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) where source.lastPathComponent.hasPrefix(storeURL.lastPathComponent) {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
        }
        try Data("Backup completed before opening the local store".utf8).write(to: marker, options: .atomic)
    }
}
