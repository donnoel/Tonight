import Foundation
import OSLog
import SwiftData

struct WatchedStateIdentity: Codable, Equatable, Sendable {
    let tmdbID: Int?
    let normalizedTitle: String
    let releaseYear: Int?

    init(tmdbID: Int?, title: String, releaseYear: Int?) {
        self.tmdbID = tmdbID
        self.normalizedTitle = MovieTitleNormalizer.normalize(title)
        self.releaseYear = releaseYear
    }

    init(movie: Movie) {
        self.init(
            tmdbID: movie.tmdbID,
            title: movie.importedTitle.isEmpty ? movie.title : movie.importedTitle,
            releaseYear: movie.importedYear ?? movie.releaseYear
        )
    }

    func matches(_ other: WatchedStateIdentity) -> Bool {
        if let tmdbID, let otherTMDBID = other.tmdbID {
            return tmdbID == otherTMDBID
        }
        return !normalizedTitle.isEmpty
            && normalizedTitle == other.normalizedTitle
            && releaseYear == other.releaseYear
    }

    var sortKey: String {
        if let tmdbID {
            return "tmdb:\(tmdbID)"
        }
        return "title:\(normalizedTitle)|year:\(releaseYear.map(String.init) ?? "unknown")"
    }
}

struct SyncedWatchedState: Codable, Equatable, Sendable {
    let identity: WatchedStateIdentity
    let isWatched: Bool
    let dateWatched: Date?
    let lastWatchedDate: Date?
    let modifiedAt: Date
}

struct WatchedStateSyncSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var records: [SyncedWatchedState]

    init(version: Int = currentVersion, records: [SyncedWatchedState] = []) {
        self.version = version
        self.records = records
    }
}

struct LocalWatchedState: Equatable, Sendable {
    private static let legacyWatchedDate = Date(timeIntervalSince1970: 0)

    let movieID: UUID
    let identity: WatchedStateIdentity
    let isWatched: Bool
    let dateWatched: Date?
    let lastWatchedDate: Date?
    let modifiedAt: Date?

    init(movie: Movie) {
        movieID = movie.id
        identity = WatchedStateIdentity(movie: movie)
        isWatched = movie.isWatched
        dateWatched = movie.dateWatched
        lastWatchedDate = movie.lastWatchedDate
        modifiedAt = movie.watchedStateModifiedAt
    }

    var syncRecord: SyncedWatchedState? {
        let effectiveModifiedAt = modifiedAt
            ?? (isWatched ? lastWatchedDate ?? dateWatched ?? Self.legacyWatchedDate : nil)
        guard let effectiveModifiedAt else { return nil }

        return SyncedWatchedState(
            identity: identity,
            isWatched: isWatched,
            dateWatched: isWatched ? dateWatched : nil,
            lastWatchedDate: isWatched ? lastWatchedDate : nil,
            modifiedAt: effectiveModifiedAt
        )
    }
}

struct WatchedStateLocalUpdate: Equatable, Sendable {
    let movieID: UUID
    let state: SyncedWatchedState
}

struct WatchedStateSyncResolution: Equatable, Sendable {
    let snapshot: WatchedStateSyncSnapshot
    let localUpdates: [WatchedStateLocalUpdate]
}

enum WatchedStateSyncResolver {
    static func resolve(
        remoteSnapshot: WatchedStateSyncSnapshot,
        localStates: [LocalWatchedState]
    ) -> WatchedStateSyncResolution {
        var mergedRecords = RecordIndex()
        for record in remoteSnapshot.records {
            upsert(record, into: &mergedRecords)
        }

        var localUpdates: [WatchedStateLocalUpdate] = []
        for localState in localStates.sorted(by: { $0.movieID.uuidString < $1.movieID.uuidString }) {
            let matchingRemote = preferredUnambiguousRecord(
                matching: localState.identity,
                in: mergedRecords
            )

            guard let localRecord = localState.syncRecord else {
                if let matchingRemote {
                    localUpdates.append(
                        WatchedStateLocalUpdate(
                            movieID: localState.movieID,
                            state: matchingRemote
                        )
                    )
                }
                continue
            }

            guard let matchingRemote else {
                upsert(localRecord, into: &mergedRecords)
                continue
            }

            if prefers(matchingRemote, over: localRecord) {
                localUpdates.append(
                    WatchedStateLocalUpdate(
                        movieID: localState.movieID,
                        state: matchingRemote
                    )
                )
            } else {
                upsert(localRecord, into: &mergedRecords)
            }
        }

        let sortedRecords = mergedRecords.orderedRecords.sorted {
            if $0.identity.sortKey != $1.identity.sortKey {
                return $0.identity.sortKey < $1.identity.sortKey
            }
            return $0.modifiedAt < $1.modifiedAt
        }

        return WatchedStateSyncResolution(
            snapshot: WatchedStateSyncSnapshot(records: sortedRecords),
            localUpdates: localUpdates
        )
    }

    private static func upsert(
        _ incoming: SyncedWatchedState,
        into records: inout RecordIndex
    ) {
        let matchingIndices = records.matchingIndices(for: incoming.identity)
        guard !matchingIndices.isEmpty else {
            records.append(incoming)
            return
        }

        let knownTMDBIDs = Set(
            matchingIndices.compactMap { records[$0].identity.tmdbID }
                + [incoming.identity.tmdbID].compactMap { $0 }
        )
        guard knownTMDBIDs.count <= 1 else {
            records.append(incoming)
            return
        }

        var preferred = incoming
        for index in matchingIndices where prefers(records[index], over: preferred) {
            preferred = records[index]
        }
        for index in matchingIndices.reversed() {
            records.remove(at: index)
        }
        records.append(preferred)
    }

    private static func preferredUnambiguousRecord(
        matching identity: WatchedStateIdentity,
        in records: RecordIndex
    ) -> SyncedWatchedState? {
        let candidates = records.matchingIndices(for: identity).map { records[$0] }
        let knownTMDBIDs = Set(candidates.compactMap(\.identity.tmdbID))
        guard identity.tmdbID != nil || knownTMDBIDs.count <= 1 else { return nil }
        return candidates.max(by: { prefers($1, over: $0) })
    }

    /// Integer slots retain insertion order for otherwise tied records. Title buckets
    /// keep unknown-ID fallback matches separate from conflicting known identities.
    private struct RecordIndex {
        private struct TitleKey: Hashable {
            let title: String
            let year: Int?

            init(_ identity: WatchedStateIdentity) {
                title = identity.normalizedTitle
                year = identity.releaseYear
            }
        }

        private var records: [Int: SyncedWatchedState] = [:]
        private var byID: [Int: Set<Int>] = [:]
        private var byTitle: [TitleKey: Set<Int>] = [:]
        private var unknownByTitle: [TitleKey: Set<Int>] = [:]
        private var nextSlot = 0

        var orderedRecords: [SyncedWatchedState] {
            records.keys.sorted().map { records[$0]! }
        }

        subscript(slot: Int) -> SyncedWatchedState { records[slot]! }

        func matchingIndices(for identity: WatchedStateIdentity) -> [Int] {
            let key = TitleKey(identity)
            if let id = identity.tmdbID {
                let fallback = identity.normalizedTitle.isEmpty
                    ? Set<Int>() : unknownByTitle[key, default: []]
                return byID[id, default: []].union(fallback).sorted()
            }
            guard !identity.normalizedTitle.isEmpty else { return [] }
            return byTitle[key, default: []].sorted()
        }

        mutating func append(_ record: SyncedWatchedState) {
            let slot = nextSlot
            nextSlot += 1
            records[slot] = record
            let key = TitleKey(record.identity)
            byTitle[key, default: []].insert(slot)
            if let id = record.identity.tmdbID {
                byID[id, default: []].insert(slot)
            } else {
                unknownByTitle[key, default: []].insert(slot)
            }
        }

        mutating func remove(at slot: Int) {
            guard let record = records.removeValue(forKey: slot) else { return }
            let key = TitleKey(record.identity)
            byTitle[key]?.remove(slot)
            if let id = record.identity.tmdbID {
                byID[id]?.remove(slot)
            } else {
                unknownByTitle[key]?.remove(slot)
            }
        }
    }

    private static func prefers(
        _ candidate: SyncedWatchedState,
        over current: SyncedWatchedState
    ) -> Bool {
        if candidate.modifiedAt != current.modifiedAt {
            return candidate.modifiedAt > current.modifiedAt
        }
        if candidate.isWatched != current.isWatched {
            return !candidate.isWatched
        }
        if (candidate.identity.tmdbID != nil) != (current.identity.tmdbID != nil) {
            return candidate.identity.tmdbID != nil
        }
        return candidate.identity.sortKey > current.identity.sortKey
    }
}

nonisolated protocol WatchedStateKeyValueStore: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    @discardableResult
    func synchronize() -> Bool
}

nonisolated extension NSUbiquitousKeyValueStore: WatchedStateKeyValueStore {}

@MainActor
final class WatchedStateSyncCoordinator {
    static let shared = WatchedStateSyncCoordinator()

    private static let snapshotKey = "tonight.watchedState.v1"
    private static let logger = Logger(
        subsystem: "com.donnoel.Tonight",
        category: "WatchedStateSync"
    )

    private let keyValueStore: WatchedStateKeyValueStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(keyValueStore: WatchedStateKeyValueStore = NSUbiquitousKeyValueStore.default) {
        self.keyValueStore = keyValueStore

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func start(in modelContext: ModelContext) {
        keyValueStore.synchronize()
        reconcile(in: modelContext)
    }

    func localStateDidSave(for movie: Movie) {
        guard LocalWatchedState(movie: movie).syncRecord != nil else { return }

        do {
            let remoteSnapshot = try loadSnapshot()
            let resolution = WatchedStateSyncResolver.resolve(
                remoteSnapshot: remoteSnapshot,
                localStates: [LocalWatchedState(movie: movie)]
            )
            try saveIfNeeded(resolution.snapshot, replacing: remoteSnapshot)
        } catch {
            Self.logger.error(
                "Could not publish watched state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func reconcile(in modelContext: ModelContext) {
        do {
            let movies = try modelContext.fetch(FetchDescriptor<Movie>())
            let remoteSnapshot = try loadSnapshot()
            let resolution = WatchedStateSyncResolver.resolve(
                remoteSnapshot: remoteSnapshot,
                localStates: movies.map(LocalWatchedState.init(movie:))
            )

            var movieByID = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
            var changedMovies: [Movie] = []
            for update in resolution.localUpdates {
                guard let movie = movieByID.removeValue(forKey: update.movieID) else { continue }
                apply(update.state, to: movie)
                changedMovies.append(movie)
            }

            if !changedMovies.isEmpty {
                try modelContext.save()
                TonightWidgetSnapshotPublisher.removeMovies(
                    ids: Set(changedMovies.filter(\.isWatched).map(\.id))
                )
            }

            try saveIfNeeded(resolution.snapshot, replacing: remoteSnapshot)
        } catch {
            modelContext.rollback()
            Self.logger.error(
                "Could not reconcile watched state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func apply(_ state: SyncedWatchedState, to movie: Movie) {
        movie.isWatched = state.isWatched
        movie.dateWatched = state.isWatched
            ? state.dateWatched ?? state.modifiedAt
            : nil
        movie.lastWatchedDate = state.isWatched
            ? state.lastWatchedDate ?? state.dateWatched ?? state.modifiedAt
            : nil
        movie.watchedStateModifiedAt = state.modifiedAt
    }

    private func loadSnapshot() throws -> WatchedStateSyncSnapshot {
        guard let data = keyValueStore.data(forKey: Self.snapshotKey), !data.isEmpty else {
            return WatchedStateSyncSnapshot()
        }
        let snapshot = try decoder.decode(WatchedStateSyncSnapshot.self, from: data)
        guard snapshot.version == WatchedStateSyncSnapshot.currentVersion else {
            throw WatchedStateSyncError.unsupportedVersion
        }
        return snapshot
    }

    private func saveIfNeeded(
        _ snapshot: WatchedStateSyncSnapshot,
        replacing existingSnapshot: WatchedStateSyncSnapshot
    ) throws {
        guard snapshot != existingSnapshot else { return }
        keyValueStore.set(try encoder.encode(snapshot), forKey: Self.snapshotKey)
        keyValueStore.synchronize()
    }
}

private enum WatchedStateSyncError: LocalizedError {
    case unsupportedVersion

    var errorDescription: String? {
        "The iCloud watched-state format is newer than this version of Tonight supports."
    }
}
