import CloudKit
import Observation
import SwiftData

/// UI/persistence stay on the main actor. CKSyncEngine owns network scheduling;
/// its delegate enters this actor only to commit small batches to the local store.
@MainActor @Observable
final class LibrarySyncCoordinator: CKSyncEngineDelegate {
    static let shared = LibrarySyncCoordinator()
    static let zoneID = CKRecordZone.ID(zoneName: "TonightLibraryV1")
    private(set) var status = "Preparing library sync…"
    private(set) var pendingCount = 0
    private(set) var lastSync: Date?
    private var isManualSyncing = false
    private var isFetching = false
    private var isSending = false
    var isSyncing: Bool { isManualSyncing || isFetching || isSending }
    private(set) var isPaused = false
    private var context: ModelContext?
    private var engine: CKSyncEngine?
    private var syncTask: Task<Void, Never>?
    private var failedThisCycle = false
    private var isApplying = false
    private var accountVerified = false
    private var pausedForAccountChange = false
    private let container = CKContainer(identifier: "iCloud.com.donnoel.Tonight")

    func start(in context: ModelContext) async {
        guard self.context == nil else { return }
        guard LibrarySyncStore.supported(in: context) else {
            status = "Sync unavailable: the local backup could not be created."; isPaused = true; return
        }
        self.context = context
        do {
            let state = try LibrarySyncStore.state(in: context)
            if !state.seeded {
                // Read legacy watched edits once. No further KVS writes after migration.
                try WatchedStateSyncCoordinator.shared.importForLibrarySync(in: context)
                try LibrarySyncStore.seed(in: context)
            }
            try LibrarySyncStore.save(context)
            lastSync = state.lastSync
            try refreshPending()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TonightDisableCloudSync") || NSClassFromString("XCTestCase") != nil {
                status = "Sync paused for local testing."; isPaused = true; return
            }
            #endif
            await syncNow()
        } catch { stopForLocalFailure(error) }
    }

    func localDidSave() {
        guard !isApplying, !isPaused else { return }
        do { try refreshPending(); queuePending() }
        catch { stopForLocalFailure(error); return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func syncNow() async {
        guard let context, !isManualSyncing else { return }
        isManualSyncing = true; failedThisCycle = false
        defer {
            isManualSyncing = false
            updateIdleStatus()

        }
        do {
            guard try await container.accountStatus() == .available else {
                accountVerified = false
                status = "iCloud unavailable. Sign in to iCloud in device Settings. Changes stay saved here."
                return
            }
            let accountID = try await container.userRecordID().recordName
            let state = try LibrarySyncStore.state(in: context)
            guard state.accountID == nil || state.accountID == accountID else { throw LibrarySyncFailure.accountChanged }
            if pausedForAccountChange {
                isPaused = false; pausedForAccountChange = false; engine = nil
            }
            if isPaused { return }
            state.accountID = accountID
            try context.save()
            accountVerified = true
            if engine == nil {
                state.prepareEngineConfiguration()
                if state.engineState == nil {
                    _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: Self.zoneID))
                }
                let serialization = try state.engineState.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
                var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: serialization, delegate: self)
                // Do not reuse the legacy Core Data subscription, which may filter out our records.
                configuration.subscriptionID = "TonightLibraryV1.subscription"
                engine = CKSyncEngine(configuration)
            }
            guard let engine else { return }
            status = "Syncing library…"
            // Fetch before sending initial imports so old copies cannot overwrite new edits.
            try await engine.fetchChanges(.init(scope: .zoneIDs([Self.zoneID])))
            guard !isPaused else { return }
            queuePending()
            try await engine.sendChanges()
            try await engine.fetchChanges(.init(scope: .zoneIDs([Self.zoneID])))
            try refreshPending()
            if !failedThisCycle && pendingCount == 0 && !isPaused {
                state.lastSync = .now; try context.save(); lastSync = state.lastSync
                status = "Up to date"
            }
            startArtworkDownloads()
        } catch let error as LibrarySyncFailure {
            status = error.localizedDescription; isPaused = true; accountVerified = false
            if case .accountChanged = error { pausedForAccountChange = true }
        } catch {
            failedThisCycle = true
            status = "Waiting for iCloud. \(pendingCount) changes saved on this device. \(cloudMessage(error))"
        }
    }

    private func refreshPending() throws {
        guard let context else { return }
        pendingCount = try context.fetchCount(FetchDescriptor<LibrarySyncEntry>(predicate: #Predicate { $0.pendingUpload }))
        updateIdleStatus()
    }

    private func updateIdleStatus() {
        guard pendingCount > 0, !isSyncing, !isPaused else { return }
        // Preserve actionable sign-in, quota, and network errors after a pass ends.
        if status == "Syncing library…" || status == "Up to date" ||
            status == "Preparing library sync…" || status.hasSuffix("changes waiting to sync") {
            status = "\(pendingCount) changes waiting to sync"
        }
    }

    private func queuePending() {
        guard let context, let engine, accountVerified, !isPaused else { return }
        do {
            let entries = try context.fetch(FetchDescriptor<LibrarySyncEntry>(predicate: #Predicate { $0.pendingUpload }))
            engine.state.add(pendingRecordZoneChanges: entries.map { .saveRecord(CKRecord.ID(recordName: $0.recordName, zoneID: Self.zoneID)) })
        } catch { stopForLocalFailure(error) }
    }

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await receive(event, engine: syncEngine)
    }

    private func receive(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        guard let context, !isPaused else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            switch event {
            case .stateUpdate(let update):
                let state = try LibrarySyncStore.state(in: context)
                state.engineState = try LibrarySyncCoding.encode(update.stateSerialization)
                try context.save()
            case .accountChange(let change):
                accountVerified = false
                switch change.changeType {
                case .signIn(let user):
                    let state = try LibrarySyncStore.state(in: context)
                    if let account = state.accountID, account != user.recordName { throw LibrarySyncFailure.accountChanged }
                    accountVerified = true
                case .signOut:
                    status = "Signed out of iCloud. Your local library and pending changes are safe."
                case .switchAccounts:
                    throw LibrarySyncFailure.accountChanged
                @unknown default:
                    throw LibrarySyncFailure.accountChanged
                }
            case .fetchedRecordZoneChanges(let changes):
                // Preserve any UI edits before applying remote fields.
                try LibrarySyncStore.save(context)
                for change in changes.modifications where change.record.recordID.zoneID == Self.zoneID {
                    try merge(change.record, in: context)
                }
                if changes.deletions.contains(where: { $0.recordID.zoneID == Self.zoneID }) {
                    // Tonight uses tombstone records. Unexpected hard deletions need recovery.
                    throw LibrarySyncFailure.cloudReset
                }
                try LibrarySyncStore.reconcile(in: context)
                try context.save()
                let events = try context.fetch(FetchDescriptor<RecommendationEvent>(sortBy: [SortDescriptor(\.recommendedAt, order: .reverse)]))
                TonightWidgetSnapshotPublisher.publish(events: events)
                try refreshPending()
                // Fetching can create merged local changes that still need an upload.
                // Queue them immediately, even when this is the final fetch of a pass.
                queuePending()
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) { throw LibrarySyncFailure.cloudReset }
            case .sentRecordZoneChanges(let changes):
                for record in changes.savedRecords {
                    guard let entry = try entry(named: record.recordID.recordName, in: context) else { continue }
                    entry.systemFields = archive(record)
                    if let data = record["payload"] as? Data, try decode(data) == entry.document() { entry.pendingUpload = false }
                    // A newer edit made during the upload stays pending.
                }
                for failure in changes.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                        try merge(server, in: context)
                    } else if failure.error.code == .zoneNotFound {
                        throw LibrarySyncFailure.cloudReset
                    } else if failure.error.code == .unknownItem {
                        throw LibrarySyncFailure.cloudReset
                    } else {
                        failedThisCycle = true
                        status = "Changes are saved here. " + cloudMessage(failure.error)
                    }
                }
                try LibrarySyncStore.reconcile(in: context)
                try context.save()
                try refreshPending()
                queuePending()
            case .sentDatabaseChanges(let changes):
                if let failure = changes.failedZoneSaves.first {
                    failedThisCycle = true; status = cloudMessage(failure.error)
                }
            case .didFetchRecordZoneChanges(let changes):
                if let error = changes.error, error.code != .zoneNotFound {
                    failedThisCycle = true; status = cloudMessage(error)
                }
            case .willFetchChanges:
                failedThisCycle = false; isFetching = true; status = "Syncing library…"
            case .willSendChanges:
                isSending = true; status = "Syncing library…"
            case .didFetchChanges, .didSendChanges:
                if case .didFetchChanges = event { isFetching = false }
                if case .didSendChanges = event { isSending = false }
                try refreshPending()
                if pendingCount == 0 && !failedThisCycle && accountVerified {
                    let state = try LibrarySyncStore.state(in: context)
                    state.lastSync = .now; try context.save(); lastSync = state.lastSync
                    status = "Up to date"
                    startArtworkDownloads()
                }
            default: break
            }
        } catch {
            context.rollback()
            stopForLocalFailure(error)
        }
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let records = await recordsToSend(engine: syncEngine) else { return nil }
        let changes = LibrarySyncUploadQueue.activeSaves(
            syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) },
            recordNames: Set(records.keys)
        )
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: Array(changes.prefix(100))) { id in records[id.recordName] }
    }

    private func recordsToSend(engine: CKSyncEngine) -> [String: CKRecord]? {
        guard let context, accountVerified, !isPaused else { return nil }
        do {
            let entries = try context.fetch(FetchDescriptor<LibrarySyncEntry>(predicate: #Predicate { $0.pendingUpload }))
            let records = try Dictionary(uniqueKeysWithValues: entries.map { entry in
                let record: CKRecord
                if let data = entry.systemFields {
                    let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
                    decoder.requiresSecureCoding = true
                    guard let decoded = CKRecord(coder: decoder) else { throw LibrarySyncFailure.localStorage }
                    record = decoded
                } else {
                    record = CKRecord(recordType: "LibraryMovieV1", recordID: CKRecord.ID(recordName: entry.recordName, zoneID: Self.zoneID))
                }
                record["payload"] = entry.documentData as NSData
                return (entry.recordName, record)
            })
            // A fetch may already acknowledge a queued record. Remove these stale
            // saves so an empty first batch cannot starve later pending uploads.
            let names = Set(records.keys)
            let stale = engine.state.pendingRecordZoneChanges.filter {
                if case .saveRecord(let id) = $0 { return !names.contains(id.recordName) }
                return false
            }
            engine.state.remove(pendingRecordZoneChanges: stale)
            return records
        } catch { stopForLocalFailure(error); return nil }
    }

    private func merge(_ record: CKRecord, in context: ModelContext) throws {
        guard record.recordType == "LibraryMovieV1", let data = record["payload"] as? Data else { throw LibrarySyncFailure.newerFormat }
        let remote = try decode(data)
        let entry: LibrarySyncEntry
        if let existing = try self.entry(named: record.recordID.recordName, in: context) {
            entry = existing
            try entry.setDocument(try entry.document().merged(with: remote))
        } else {
            entry = try LibrarySyncEntry(name: record.recordID.recordName, document: remote)
            context.insert(entry)
        }
        entry.systemFields = archive(record)
        entry.pendingUpload = try entry.document() != remote
    }

    private func entry(named name: String, in context: ModelContext) throws -> LibrarySyncEntry? {
        try context.fetch(FetchDescriptor<LibrarySyncEntry>(predicate: #Predicate { $0.recordName == name })).first
    }

    private func decode(_ data: Data) throws -> LibrarySyncDocument {
        let result = try JSONDecoder().decode(LibrarySyncDocument.self, from: data)
        guard result.version == 1 else { throw LibrarySyncFailure.newerFormat }
        return result
    }

    private func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding()
        return coder.encodedData
    }

    private func stopForLocalFailure(_ error: Error) {
        isPaused = true; accountVerified = false
        if let failure = error as? LibrarySyncFailure, case .accountChanged = failure { pausedForAccountChange = true }
        status = (error as? LibrarySyncFailure)?.localizedDescription ?? LibrarySyncFailure.localStorage.localizedDescription
        if let engine { Task { await engine.cancelOperations() } }
    }

    private func cloudMessage(_ error: Error) -> String {
        guard let error = error as? CKError else { return "Try Sync Now when your connection is available." }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in device Settings."
        case .quotaExceeded: return "Your iCloud storage is full. Free some space, then try Sync Now."
        case .badContainer, .missingEntitlement, .permissionFailure: return "iCloud library access is unavailable for this build."
        case .networkFailure, .networkUnavailable: return "Waiting for an internet connection."
        default: return "iCloud is temporarily unavailable. Try Sync Now again."
        }
    }

    private func startArtworkDownloads() {
        guard let context, let movies = try? context.fetch(FetchDescriptor<Movie>()) else { return }
        let urls = movies.flatMap { SyncedLibraryMovie(movie: $0).details.artworkURLs }
        Task { await LibraryArtworkCache.shared.prefetch(urls) }
    }
}


enum LibrarySyncUploadQueue {
    static func activeSaves(_ changes: [CKSyncEngine.PendingRecordZoneChange], recordNames: Set<String>) -> [CKSyncEngine.PendingRecordZoneChange] {
        changes.filter {
            if case .saveRecord(let id) = $0 { return recordNames.contains(id.recordName) }
            return false
        }
    }
}
