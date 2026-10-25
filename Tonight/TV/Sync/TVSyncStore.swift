import Foundation

/// Pure reconciliation shared by local saves, CloudKit fetches, and regression tests.
enum TVSyncStore {
    static func seed(_ document: inout TVLibraryDocument) {
        guard document.sync == nil else { return }
        var state = TVSyncState()
        for show in document.shows {
            let key = TVSyncIdentity.key(show)
            let record = TVSyncRecord(recordName: key, show: TVSyncShow(show, history: document.history))
            if let entry = state.entries[key], let merged = try? entry.record.merged(with: record) {
                state.entries[key]?.record = merged
            } else { state.entries[key] = TVSyncEntry(record: record) }
            state.localShowKeys[show.id.uuidString] = key
        }
        for watch in document.history {
            let key = state.localShowKeys[watch.showID.uuidString] ?? orphanKey(watch)
            let record = watchRecord(watch, showKey: key,
                revision: LibraryRevision(date: watch.watchedAt, device: ""))
            state.entries[record.recordName] = TVSyncEntry(record: record)
        }
        state.clock = document.history.map(\.watchedAt).max() ?? .distantPast
        document.sync = state
        reconcile(&document)
    }

    /// Mutations and their outbound records are saved in the same atomic TV file.
    @discardableResult
    static func capture(previous: TVLibraryDocument, next: inout TVLibraryDocument, now: Date = .now) -> Bool {
        guard var state = next.sync else { return false }
        let originalEntries = state.entries
        let revision = LibraryRevision(date: max(now, state.clock.addingTimeInterval(0.001)), device: state.deviceID)
        let oldShows = Dictionary(uniqueKeysWithValues: previous.shows.map { ($0.id, $0) })
        for show in next.shows {
            let key = TVSyncIdentity.key(show)
            let old = oldShows[show.id]
            let oldKey = state.localShowKeys[show.id.uuidString]
            var value = state.entries[key]?.record.show ?? TVSyncShow(show)
            if let oldKey, oldKey != key, var oldEntry = state.entries[oldKey], var oldValue = oldEntry.record.show {
                var transferred = oldValue
                transferred.redirectTo = nil
                value = value.merged(with: transferred)
                oldValue.redirectTo = key
                oldValue.revisions["membership"] = revision
                oldEntry.record.show = oldValue
                oldEntry.pendingUpload = true
                state.entries[oldKey] = oldEntry
            }
            if old != show || oldKey != key {
                value.update(show, previous: old, revision: revision)
                value.value.id = TVSyncIdentity.localID(key)
                let record = TVSyncRecord(recordName: key, show: value)
                set(record, in: &state)
            }
            state.localShowKeys[show.id.uuidString] = key
        }
        let currentIDs = Set(next.shows.map(\.id))
        for show in previous.shows where !currentIDs.contains(show.id) {
            let key = resolvedKey(state.localShowKeys[show.id.uuidString] ?? TVSyncIdentity.key(show), in: state)
            if var entry = state.entries[key], var value = entry.record.show {
                value.deleted = true; value.redirectTo = nil; value.revisions["membership"] = revision
                entry.record.show = value; entry.pendingUpload = true; state.entries[key] = entry
            }
        }
        let oldHistory = Dictionary(uniqueKeysWithValues: previous.history.map { ($0.id, $0) })
        for watch in next.history where oldHistory[watch.id] != watch {
            let key = state.localShowKeys[watch.showID.uuidString] ?? orphanKey(watch)
            set(watchRecord(watch, showKey: key, revision: revision), in: &state)
        }
        let currentWatches = Set(next.history.map(\.id))
        for watch in previous.history where !currentWatches.contains(watch.id) {
            let key = "tv-watch-\(watch.id.uuidString)"
            if var entry = state.entries[key], var value = entry.record.watch {
                value.deleted = true; value.revision = revision
                entry.record.watch = value; entry.pendingUpload = true; state.entries[key] = entry
            }
        }
        let changed = originalEntries != state.entries
        if changed { state.clock = revision.date }
        next.sync = state
        return changed
    }

    static func receive(_ record: TVSyncRecord, systemFields: Data? = nil, in document: inout TVLibraryDocument) throws {
        _ = try record.validated()
        guard var state = document.sync else { throw TVSyncError.localStorage }
        let merged = try state.entries[record.recordName]?.record.merged(with: record) ?? record
        state.entries[record.recordName] = TVSyncEntry(record: merged, systemFields: systemFields,
                                                       pendingUpload: merged != record)
        if let show = record.show {
            state.clock = max(state.clock, show.revisions.values.map(\.date).max() ?? .distantPast)
        }
        if let watch = record.watch { state.clock = max(state.clock, watch.revision.date) }
        document.sync = state
    }

    static func acknowledge(_ record: TVSyncRecord, systemFields: Data, in document: inout TVLibraryDocument) {
        guard var entry = document.sync?.entries[record.recordName] else { return }
        entry.systemFields = systemFields
        // An edit committed while this upload was in flight must remain queued.
        entry.pendingUpload = entry.record != record
        document.sync?.entries[record.recordName] = entry
    }

    static func reconcile(_ document: inout TVLibraryDocument) {
        guard var state = document.sync else { return }
        resolveUnmatchedAliases(in: &state)
        let previousShows = document.shows
        var projected: [TVShow] = []
        var idForKey: [String: UUID] = [:]
        for (key, entry) in state.entries.sorted(by: { $0.key < $1.key }) {
            guard let value = entry.record.show, !value.deleted, value.redirectTo == nil else { continue }
            let local = previousShows.first {
                resolvedKey(state.localShowKeys[$0.id.uuidString] ?? TVSyncIdentity.key($0), in: state) == key
            }
            var show = value.value
            show.id = local?.id ?? TVSyncIdentity.localID(key)
            if let position = show.resumeAfter, !(show.ownedSeasons ?? []).contains(position.season) {
                show.resumeAfter = nil
            }
            idForKey[key] = show.id
            state.localShowKeys[show.id.uuidString] = key
            projected.append(show)
        }
        for (id, key) in state.localShowKeys { state.localShowKeys[id] = resolvedKey(key, in: state) }
        document.shows = projected
        document.history = state.entries.values.compactMap { entry -> TVWatchSession? in
            guard let value = entry.record.watch, !value.deleted else { return nil }
            var watch = value.value
            let key = resolvedKey(value.showKey, in: state)
            watch.showID = idForKey[key] ?? TVSyncIdentity.localID(key)
            return watch
        }.sorted { $0.watchedAt == $1.watchedAt ? $0.id.uuidString < $1.id.uuidString : $0.watchedAt < $1.watchedAt }

        if var active = document.activeSession {
            let key = resolvedKey(state.localShowKeys[active.showID.uuidString] ?? "", in: state)
            if let localID = idForKey[key], let show = projected.first(where: { $0.id == localID }) {
                active.showID = localID
                let available = Set(show.eligibleEpisodes.map(\.id))
                let alreadyWatched = document.history.contains { watch in
                    watch.showID == localID && watch.watchedAt >= active.createdAt &&
                        !Set(watch.episodes.map(\.id)).isDisjoint(with: active.episodes.map(\.id))
                }
                document.activeSession = !alreadyWatched && active.episodes.allSatisfy { available.contains($0.id) } ? active : nil
            } else { document.activeSession = nil }
        }
        document.sync = state
    }

    static func resolvedKey(_ key: String, in state: TVSyncState) -> String {
        var current = key
        var visited = Set<String>()
        while visited.insert(current).inserted, let next = state.entries[current]?.record.show?.redirectTo {
            current = next
        }
        return current
    }

    private static func resolveUnmatchedAliases(in state: inout TVSyncState) {
        let resolved = state.entries.filter { $0.value.record.show?.value.tmdbID != nil && $0.value.record.show?.redirectTo == nil }
        for (key, entry) in state.entries where entry.record.show?.value.tmdbID == nil {
            guard var source = entry.record.show, source.redirectTo == nil else { continue }
            let candidates = resolved.filter { _, targetEntry in
                guard let target = targetEntry.record.show else { return false }
                let titleMatches = MovieTitleNormalizer.normalize(source.value.importedTitle) == MovieTitleNormalizer.normalize(target.value.importedTitle)
                let sourceYear = source.value.requestedYear
                let targetYear = target.value.requestedYear ?? target.value.firstAirYear
                return titleMatches && (sourceYear == nil || targetYear == nil || sourceYear == targetYear)
            }
            guard candidates.count == 1, let (targetKey, targetEntry) = candidates.first,
                  let target = targetEntry.record.show else { continue }
            var merged = target.merged(with: source)
            merged.value.id = TVSyncIdentity.localID(targetKey)
            set(TVSyncRecord(recordName: targetKey, show: merged), in: &state)
            source.redirectTo = targetKey
            source.revisions["membership"] = max(source.revision("membership"), target.revision("membership"))
            set(TVSyncRecord(recordName: key, show: source), in: &state)
        }
    }

    private static func set(_ record: TVSyncRecord, in state: inout TVSyncState) {
        if var entry = state.entries[record.recordName] {
            guard entry.record != record else { return }
            entry.record = record; entry.pendingUpload = true; state.entries[record.recordName] = entry
        } else { state.entries[record.recordName] = TVSyncEntry(record: record) }
    }

    private static func watchRecord(_ watch: TVWatchSession, showKey: String, revision: LibraryRevision) -> TVSyncRecord {
        var value = watch
        value.showID = TVSyncIdentity.localID(showKey)
        return TVSyncRecord(recordName: "tv-watch-\(watch.id.uuidString)",
                            watch: TVSyncWatch(value: value, showKey: showKey, revision: revision))
    }

    private static func orphanKey(_ watch: TVWatchSession) -> String {
        "tv-title-" + TVSyncIdentity.digest("removed|" + MovieTitleNormalizer.normalize(watch.showTitle))
    }
}
