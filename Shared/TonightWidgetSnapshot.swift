import Foundation

nonisolated struct TonightWidgetPick: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kindTitle: String
    let title: String
    let metadata: String
    let rationale: String
    let artworkURL: URL?
    var artworkData: Data?
}

nonisolated struct TonightWidgetSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    var picks: [TonightWidgetPick]

    static func empty(at date: Date = .now) -> TonightWidgetSnapshot {
        TonightWidgetSnapshot(generatedAt: date, picks: [])
    }

    func removingMovie(id: UUID) -> TonightWidgetSnapshot {
        removingMovies(ids: [id])
    }

    func removingMovies(ids: Set<UUID>) -> TonightWidgetSnapshot {
        TonightWidgetSnapshot(
            generatedAt: generatedAt,
            picks: picks.filter { !ids.contains($0.id) }
        )
    }
}

nonisolated enum TonightWidgetSnapshotStoreError: Error {
    case appGroupUnavailable
}

nonisolated struct TonightWidgetSnapshotStore: Sendable {
    static let appGroupIdentifier = "group.com.donnoel.Tonight"
    static let widgetKind = "TonightPicksWidget"

    private let directoryURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            throw TonightWidgetSnapshotStoreError.appGroupUnavailable
        }

        self.init(directoryURL: groupURL.appendingPathComponent("Tonight", isDirectory: true))
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func load() throws -> TonightWidgetSnapshot? {
        let fileURL = snapshotFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try PropertyListDecoder().decode(
            TonightWidgetSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ snapshot: TonightWidgetSnapshot) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(snapshot).write(to: snapshotFileURL, options: .atomic)
    }

    private var snapshotFileURL: URL {
        directoryURL.appendingPathComponent("tonight-widget-snapshot.plist")
    }
}
