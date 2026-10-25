import CloudKit
import Observation

/// The TV outbox lives alongside TV data, separate from the existing movie sync zone.
@MainActor @Observable
final class TVSyncCoordinator: CKSyncEngineDelegate {
    static let shared = TVSyncCoordinator()
    static let zoneID = CKRecordZone.ID(zoneName: "TonightTVLibraryV1")
    private(set) var status = "Preparing TV sync…"
    private(set) var lastSync: Date?
    private(set) var pendingCount = 0
    private(set) var isPaused = false
    private var manualSyncing = false
    private var fetching = false
    private var sending = false
    var isSyncing: Bool { manualSyncing || fetching || sending }
    private var store: TVLibraryStore?
    private var engine: CKSyncEngine?
    private var debounce: Task<Void, Never>?
    private var accountVerified = false
    private var failedThisCycle = false
    private let container = CKContainer(identifier: "iCloud.com.donnoel.Tonight")

    func start(store: TVLibraryStore) async {
        guard self.store == nil else { return }
        self.store = store
        do {
            try store.prepareSync()
            lastSync = store.document.sync?.lastSync
            pendingCount = store.document.sync?.pendingCount ?? 0
            store.syncDidSave = { [weak self] in self?.localDidSave() }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TonightDisableCloudSync") || NSClassFromString("XCTestCase") != nil {
                status = "TV sync paused for local testing."
                isPaused = true
                return
            }
            #endif
            await syncNow()
        } catch { stop(error) }
    }

    private func localDidSave() {
        pendingCount = store?.document.sync?.pendingCount ?? 0
        guard !isPaused else { return }
        queuePending()
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func syncNow() async {
        guard let store, store.document.sync != nil, !manualSyncing else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TonightDisableCloudSync") || NSClassFromString("XCTestCase") != nil { return }
        #endif
        manualSyncing = true
        failedThisCycle = false
        defer { manualSyncing = false }
        do {
            guard try await container.accountStatus() == .available else {
                accountVerified = false
                try setStatus("iCloud unavailable. Your TV changes stay saved here. Sign in to iCloud in device Settings.")
                return
            }
            let account = try await container.userRecordID().recordName
            try store.saveSyncChanges { document in try document.sync?.bind(to: account) }
            if store.document.sync?.recoveryRequired == true {
                isPaused = true
                status = store.document.sync?.status ?? TVSyncError.cloudReset.localizedDescription
                return
            }
            if isPaused {
                engine = nil
                try store.saveSyncChanges { $0.sync?.engineState = nil }
                isPaused = false
            }
            accountVerified = true
            if engine == nil {
                if store.document.sync?.zoneEstablished != true {
                    _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: Self.zoneID))
                    try store.saveSyncChanges { $0.sync?.zoneEstablished = true }
                }
                let serialization = try store.document.sync?.engineState.map {
                    try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
                }
                var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                    stateSerialization: serialization, delegate: self)
                configuration.subscriptionID = "TonightTVLibraryV1.subscription"
                engine = CKSyncEngine(configuration)
            }
            guard let engine else { return }
            try setStatus("Syncing TV library…")
            // Initial libraries are merged before any pending local imports are sent.
            try await engine.fetchChanges(.init(scope: .zoneIDs([Self.zoneID])))
            guard accountVerified, !isPaused else { return }
            queuePending()
            try await engine.sendChanges()
            try await engine.fetchChanges(.init(scope: .zoneIDs([Self.zoneID])))
            guard accountVerified, !isPaused else { return }
            try finishIfCurrent()
        } catch let failure as TVSyncError { stop(failure) }
        catch {
            failedThisCycle = true
            do { try setStatus("TV changes are saved here. " + cloudMessage(error)) }
            catch { stop(error) }
        }
    }

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await receive(event, engine: syncEngine)
    }

    private func receive(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        guard let store else { return }
        do {
            if case .accountChange(let change) = event {
                switch change.changeType {
                case .signIn(let account):
                    try store.saveSyncChanges { try $0.sync?.bind(to: account.recordName) }
                    accountVerified = true
                case .signOut:
                    accountVerified = false
                    isPaused = true
                    try setStatus("Signed out of iCloud. Your TV library and pending changes are safe.")
                    Task { await engine.cancelOperations() }
                case .switchAccounts: throw TVSyncError.accountChanged
                @unknown default: throw TVSyncError.accountChanged
                }
                return
            }
            guard accountVerified, !isPaused else { return }
            switch event {
            case .stateUpdate(let update):
                let serialization = try LibrarySyncCoding.encode(update.stateSerialization)
                try store.saveSyncChanges { $0.sync?.engineState = serialization }
            case .fetchedRecordZoneChanges(let changes):
                if changes.deletions.contains(where: { $0.recordID.zoneID == Self.zoneID }) { throw TVSyncError.cloudReset }
                try store.saveSyncChanges(reconcile: true) { document in
                    for change in changes.modifications where change.record.recordID.zoneID == Self.zoneID {
                        try TVSyncStore.receive(try decode(change.record), systemFields: archive(change.record), in: &document)
                    }
                }
                queuePending()
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) { throw TVSyncError.cloudReset }
            case .sentRecordZoneChanges(let changes):
                try store.saveSyncChanges(reconcile: true) { document in
                    for record in changes.savedRecords where record.recordID.zoneID == Self.zoneID {
                        TVSyncStore.acknowledge(try decode(record), systemFields: archive(record), in: &document)
                    }
                    for failure in changes.failedRecordSaves where failure.record.recordID.zoneID == Self.zoneID {
                        if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                            try TVSyncStore.receive(try decode(server), systemFields: archive(server), in: &document)
                        } else if failure.error.code == .zoneNotFound || failure.error.code == .unknownItem {
                            throw TVSyncError.cloudReset
                        } else {
                            failedThisCycle = true
                            status = "TV changes are saved here. " + cloudMessage(failure.error)
                            document.sync?.status = status
                        }
                    }
                }
                queuePending()
            case .sentDatabaseChanges(let changes):
                if let failure = changes.failedZoneSaves.first {
                    failedThisCycle = true
                    try setStatus(cloudMessage(failure.error))
                }
            case .didFetchRecordZoneChanges(let changes):
                if let error = changes.error {
                    if error.code == .zoneNotFound { throw TVSyncError.cloudReset }
                    failedThisCycle = true
                    try setStatus(cloudMessage(error))
                }
            case .willFetchChanges:
                fetching = true
                try setStatus("Syncing TV library…")
            case .willSendChanges:
                sending = true
                try setStatus("Syncing TV library…")
            case .didFetchChanges, .didSendChanges:
                if case .didFetchChanges = event { fetching = false }
                if case .didSendChanges = event { sending = false }
                try finishIfCurrent()
            default: break
            }
        } catch { stop(error) }
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                               syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let records = await recordsToSend(engine: syncEngine) else { return nil }
        let pending = LibrarySyncUploadQueue.activeSaves(
            syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) },
            recordNames: Set(records.keys))
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: Array(pending.prefix(50))) { records[$0.recordName] }
    }

    private func recordsToSend(engine: CKSyncEngine) -> [String: CKRecord]? {
        guard accountVerified, !isPaused, let state = store?.document.sync else { return nil }
        do {
            var result: [String: CKRecord] = [:]
            for (key, entry) in state.entries where entry.pendingUpload {
                let record: CKRecord
                if let fields = entry.systemFields {
                    let decoder = try NSKeyedUnarchiver(forReadingFrom: fields)
                    decoder.requiresSecureCoding = true
                    guard let restored = CKRecord(coder: decoder) else { throw TVSyncError.localStorage }
                    record = restored
                } else {
                    record = CKRecord(recordType: "TVLibraryItemV1", recordID: CKRecord.ID(recordName: key, zoneID: Self.zoneID))
                }
                let payload = try LibrarySyncCoding.encode(entry.record)
                guard payload.count < 900_000 else { throw TVSyncError.oversizedRecord }
                record["payload"] = payload as NSData
                result[key] = record
            }
            let stale = engine.state.pendingRecordZoneChanges.filter {
                if case .saveRecord(let id) = $0 { return result[id.recordName] == nil }
                return false
            }
            engine.state.remove(pendingRecordZoneChanges: stale)
            return result
        } catch { stop(error); return nil }
    }

    private func queuePending() {
        pendingCount = store?.document.sync?.pendingCount ?? 0
        guard accountVerified, !isPaused, let engine, let state = store?.document.sync else { return }
        let changes = state.entries.filter { $0.value.pendingUpload }.keys.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: $0, zoneID: Self.zoneID))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func finishIfCurrent() throws {
        pendingCount = store?.document.sync?.pendingCount ?? 0
        guard accountVerified, !isPaused else { return }
        if pendingCount == 0, !failedThisCycle {
            let now = Date.now
            try store?.saveSyncChanges { $0.sync?.lastSync = now; $0.sync?.status = "Up to date" }
            lastSync = now
            status = "Up to date"
        } else if !failedThisCycle { try setStatus("\(pendingCount) TV changes waiting to sync") }
    }

    private func setStatus(_ message: String) throws {
        status = message
        pendingCount = store?.document.sync?.pendingCount ?? 0
        if store?.document.sync?.status != message { try store?.saveSyncChanges { $0.sync?.status = message } }
    }

    private func decode(_ record: CKRecord) throws -> TVSyncRecord {
        guard record.recordType == "TVLibraryItemV1", record.recordID.zoneID == Self.zoneID,
              let payload = record["payload"] as? Data else { throw TVSyncError.newerFormat }
        let value = try JSONDecoder().decode(TVSyncRecord.self, from: payload).validated()
        guard value.recordName == record.recordID.recordName else { throw TVSyncError.newerFormat }
        return value
    }

    private func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private func stop(_ error: Error) {
        accountVerified = false
        isPaused = true
        fetching = false; sending = false
        let failure = error as? TVSyncError ?? .localStorage
        status = failure.localizedDescription
        do {
            try store?.saveSyncChanges { document in
                document.sync?.status = status
                switch failure {
                case .cloudReset, .newerFormat, .oversizedRecord: document.sync?.recoveryRequired = true
                default: break
                }
            }
        } catch { /* Leave the previous atomic snapshot intact when storage is unavailable. */ }
        if let engine { Task { await engine.cancelOperations() } }
    }

    private func cloudMessage(_ error: Error) -> String {
        guard let error = error as? CKError else { return "Try Sync TV Now when your connection is available." }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in device Settings."
        case .quotaExceeded: return "Your iCloud storage is full. Free some space, then try Sync TV Now."
        case .badContainer, .missingEntitlement, .permissionFailure: return "iCloud TV access is unavailable for this build."
        case .networkFailure, .networkUnavailable: return "Waiting for an internet connection."
        default: return "iCloud is temporarily unavailable. Try Sync TV Now again."
        }
    }
}
