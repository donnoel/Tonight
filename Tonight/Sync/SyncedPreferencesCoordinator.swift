import Foundation

protocol UbiquitousKeyValueStoring: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {}

enum SyncedPreferenceValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case string(String)
}

struct SyncedPreferencesEnvelope: Codable, Equatable, Sendable {
    var updatedAt: Date
    var values: [String: SyncedPreferenceValue]
}

enum SyncedPreferencesResolution: Equatable {
    case useLocal
    case useRemote(SyncedPreferencesEnvelope)
    case unchanged

    static func resolve(
        localUpdatedAt: Date?,
        remote: SyncedPreferencesEnvelope?
    ) -> SyncedPreferencesResolution {
        guard let remote else { return .useLocal }
        guard let localUpdatedAt else { return .useRemote(remote) }
        if remote.updatedAt > localUpdatedAt { return .useRemote(remote) }
        if localUpdatedAt > remote.updatedAt { return .useLocal }
        return .unchanged
    }
}

@MainActor
final class SyncedPreferencesCoordinator: NSObject {
    static let shared = SyncedPreferencesCoordinator()

    private enum Key {
        static let cloudEnvelope = "tonight.syncedPreferences.v1"
        static let localUpdatedAt = "tonight.syncedPreferencesUpdatedAt.v1"
    }

    private static let defaultValues: [String: SyncedPreferenceValue] = [
        "tonightMood": .string(RecommendationMood.anything.rawValue),
        "tonightUnderTwoHours": .bool(false),
        "tonightUnwatchedOnly": .bool(false),
        "tonightSomethingOlder": .bool(false),
        "tonightMoreAdventurous": .bool(false),
        "librarySortField": .string(LibrarySortField.title.rawValue),
        "librarySortDirection": .string(LibrarySortDirection.ascending.rawValue),
        "libraryFilter": .string(LibraryFilterOption.all.rawValue),
    ]

    private let defaults: UserDefaults
    private let cloudStore: UbiquitousKeyValueStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastLocalValues: [String: SyncedPreferenceValue] = [:]
    private var isStarted = false

    init(
        defaults: UserDefaults = .standard,
        cloudStore: UbiquitousKeyValueStoring = NSUbiquitousKeyValueStore.default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )

        cloudStore.synchronize()
        reconcileWithCloud()
    }

    @objc nonisolated private func localDefaultsDidChange() {
        Task { @MainActor [weak self] in
            self?.handleLocalDefaultsChange()
        }
    }

    @objc nonisolated private func cloudStoreDidChange() {
        Task { @MainActor [weak self] in
            self?.reconcileWithCloud()
        }
    }

    private func handleLocalDefaultsChange() {
        let values = localValues()
        guard values != lastLocalValues else { return }
        lastLocalValues = values

        let updatedAt = Date.now
        defaults.set(updatedAt, forKey: Key.localUpdatedAt)
        saveToCloud(values: values, updatedAt: updatedAt)
    }

    private func reconcileWithCloud() {
        let remote = loadCloudEnvelope()
        let localUpdatedAt = defaults.object(forKey: Key.localUpdatedAt) as? Date

        switch SyncedPreferencesResolution.resolve(
            localUpdatedAt: localUpdatedAt,
            remote: remote
        ) {
        case .useRemote(let envelope):
            applyRemote(envelope)
        case .useLocal:
            let values = localValues()
            lastLocalValues = values
            let updatedAt = localUpdatedAt ?? .now
            defaults.set(updatedAt, forKey: Key.localUpdatedAt)
            saveToCloud(values: values, updatedAt: updatedAt)
        case .unchanged:
            lastLocalValues = localValues()
        }
    }

    private func loadCloudEnvelope() -> SyncedPreferencesEnvelope? {
        guard let data = cloudStore.data(forKey: Key.cloudEnvelope) else { return nil }
        return try? decoder.decode(SyncedPreferencesEnvelope.self, from: data)
    }

    private func saveToCloud(
        values: [String: SyncedPreferenceValue],
        updatedAt: Date
    ) {
        let envelope = SyncedPreferencesEnvelope(updatedAt: updatedAt, values: values)
        guard let data = try? encoder.encode(envelope) else { return }
        cloudStore.set(data, forKey: Key.cloudEnvelope)
        cloudStore.synchronize()
    }

    private func applyRemote(_ envelope: SyncedPreferencesEnvelope) {
        for (key, value) in envelope.values where Self.defaultValues[key] != nil {
            switch value {
            case .bool(let bool):
                defaults.set(bool, forKey: key)
            case .string(let string):
                defaults.set(string, forKey: key)
            }
        }
        defaults.set(envelope.updatedAt, forKey: Key.localUpdatedAt)
        lastLocalValues = localValues()
    }

    private func localValues() -> [String: SyncedPreferenceValue] {
        Self.defaultValues.reduce(into: [:]) { values, entry in
            let (key, defaultValue) = entry
            switch defaultValue {
            case .bool(let fallback):
                values[key] = .bool(defaults.object(forKey: key) as? Bool ?? fallback)
            case .string(let fallback):
                values[key] = .string(defaults.string(forKey: key) ?? fallback)
            }
        }
    }
}
