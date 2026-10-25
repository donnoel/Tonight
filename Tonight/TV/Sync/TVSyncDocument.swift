import CryptoKit
import Foundation

enum TVSyncIdentity {
    static func key(_ show: TVShow) -> String {
        if let id = show.tmdbID { return "tv-show-\(id)" }
        let identity = MovieTitleNormalizer.normalize(show.importedTitle) + "|" + (show.requestedYear.map(String.init) ?? "unknown")
        return "tv-title-" + digest(identity)
    }

    static func localID(_ key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct TVSyncShow: Codable, Equatable, Sendable {
    var value: TVShow
    var revisions: [String: LibraryRevision] = [:]
    var deleted = false
    var redirectTo: String?

    init(_ show: TVShow, history: [TVWatchSession] = []) {
        value = show
        value.id = TVSyncIdentity.localID(TVSyncIdentity.key(show))
        value.episodes.sort { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
        value.seasons.sort { $0.number < $1.number }
        value.loadedSeasons = Set(value.loadedSeasons).sorted()
        value.ownedSeasons = value.ownedSeasons.map { Set($0).sorted() }
        for field in ["metadata", "ownership", "style", "familiarity", "favorite", "pause", "position", "membership"] {
            revisions[field] = .initial
        }
        if show.resumeAfter != nil {
            let date = history.filter { $0.showID == show.id }.map(\.watchedAt).max() ?? .distantPast
            revisions["position"] = LibraryRevision(date: date, device: "")
        }
    }

    func revision(_ field: String) -> LibraryRevision { revisions[field] ?? .initial }

    mutating func update(_ show: TVShow, previous: TVShow?, revision: LibraryRevision) {
        if previous.map(Self.metadata) != Self.metadata(show) {
            let personal = value
            value = show
            value.id = TVSyncIdentity.localID(TVSyncIdentity.key(show))
            value.ownedSeasons = personal.ownedSeasons
            value.viewingStyle = personal.viewingStyle
            value.seenBefore = personal.seenBefore
            value.isFavorite = personal.isFavorite
            value.isPaused = personal.isPaused
            value.resumeAfter = personal.resumeAfter
            revisions["metadata"] = revision
        }
        if previous?.ownedSeasons != show.ownedSeasons { value.ownedSeasons = show.ownedSeasons; revisions["ownership"] = revision }
        if previous?.viewingStyle != show.viewingStyle { value.viewingStyle = show.viewingStyle; revisions["style"] = revision }
        if previous?.seenBefore != show.seenBefore { value.seenBefore = show.seenBefore; revisions["familiarity"] = revision }
        if previous?.isFavorite != show.isFavorite { value.isFavorite = show.isFavorite; revisions["favorite"] = revision }
        if previous?.isPaused != show.isPaused { value.isPaused = show.isPaused; revisions["pause"] = revision }
        if previous?.resumeAfter != show.resumeAfter { value.resumeAfter = show.resumeAfter; revisions["position"] = revision }
        if deleted || redirectTo != nil || previous == nil {
            deleted = false; redirectTo = nil; revisions["membership"] = revision
        }
    }

    func merged(with other: Self) -> Self {
        var result = self
        let metadataWinner: Self
        if (value.tmdbID == nil) != (other.value.tmdbID == nil) {
            metadataWinner = value.tmdbID == nil ? other : self
        } else if revision("metadata") != other.revision("metadata") {
            metadataWinner = revision("metadata") > other.revision("metadata") ? self : other
        } else if Self.completeness(value) != Self.completeness(other.value) {
            metadataWinner = Self.completeness(value) > Self.completeness(other.value) ? self : other
        } else {
            metadataWinner = LibrarySyncDocument.stableKey(Self.metadata(value)) >= LibrarySyncDocument.stableKey(Self.metadata(other.value)) ? self : other
        }
        result.value = metadataWinner.value
        result.revisions["metadata"] = max(revision("metadata"), other.revision("metadata"))
        // Episode enrichment is additive. Ownership is merged separately and remains authoritative.
        result.value.episodes = Self.union(value.episodes, other.value.episodes, id: \.id)
            .sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
        result.value.seasons = Self.union(value.seasons, other.value.seasons, id: \.number).sorted { $0.number < $1.number }
        result.value.loadedSeasons = Set(value.loadedSeasons + other.value.loadedSeasons).sorted()

        func winner(_ field: String) -> Self {
            if revision(field) != other.revision(field) { return revision(field) > other.revision(field) ? self : other }
            return LibrarySyncDocument.stableKey(value) >= LibrarySyncDocument.stableKey(other.value) ? self : other
        }
        if revision("ownership") == .initial && other.revision("ownership") == .initial {
            switch (value.ownedSeasons, other.value.ownedSeasons) {
            case (.some(let left), .some(let right)): result.value.ownedSeasons = Set(left).intersection(right).sorted()
            case (.some(let seasons), .none), (.none, .some(let seasons)): result.value.ownedSeasons = Set(seasons).sorted()
            case (.none, .none): result.value.ownedSeasons = nil
            }
        } else { result.value.ownedSeasons = winner("ownership").value.ownedSeasons }
        result.value.viewingStyle = revision("style") == other.revision("style")
            ? (value.viewingStyle.rawValue >= other.value.viewingStyle.rawValue ? value.viewingStyle : other.value.viewingStyle)
            : winner("style").value.viewingStyle
        result.value.seenBefore = revision("familiarity") == other.revision("familiarity")
            ? value.seenBefore && other.value.seenBefore : winner("familiarity").value.seenBefore
        result.value.isFavorite = revision("favorite") == other.revision("favorite")
            ? value.isFavorite || other.value.isFavorite : winner("favorite").value.isFavorite
        result.value.isPaused = revision("pause") == other.revision("pause")
            ? value.isPaused || other.value.isPaused : winner("pause").value.isPaused
        if revision("position") == other.revision("position") {
            result.value.resumeAfter = [value.resumeAfter, other.value.resumeAfter].compactMap { $0 }.max()
        } else { result.value.resumeAfter = winner("position").value.resumeAfter }
        let membership = winner("membership")
        result.deleted = membership.deleted
        result.redirectTo = membership.redirectTo
        if revision("membership") == other.revision("membership") {
            result.deleted = deleted || other.deleted
            result.redirectTo = [redirectTo, other.redirectTo].compactMap { $0 }.max()
        }
        for field in ["ownership", "style", "familiarity", "favorite", "pause", "position", "membership"] {
            result.revisions[field] = max(revision(field), other.revision(field))
        }
        return result
    }

    static func metadata(_ show: TVShow) -> TVShow {
        var result = show
        result.id = TVSyncIdentity.localID(TVSyncIdentity.key(show))
        result.ownedSeasons = nil; result.viewingStyle = .inOrder; result.seenBefore = true
        result.isFavorite = false; result.isPaused = false; result.resumeAfter = nil
        result.episodes.sort { $0.id < $1.id }
        result.seasons.sort { $0.number < $1.number }
        result.loadedSeasons = Set(result.loadedSeasons).sorted()
        return result
    }

    private static func completeness(_ show: TVShow) -> Int {
        (show.tmdbID == nil ? 0 : 100) + show.episodes.count + show.genres.count +
            (show.posterPath == nil ? 0 : 1) + (show.overview.isEmpty ? 0 : 1)
    }

    private static func union<T: Encodable, ID: Hashable>(_ left: [T], _ right: [T], id: KeyPath<T, ID>) -> [T] {
        var byID: [ID: T] = [:]
        for item in left + right {
            let key = item[keyPath: id]
            if let current = byID[key], LibrarySyncDocument.stableKey(current) >= LibrarySyncDocument.stableKey(item) { continue }
            byID[key] = item
        }
        return Array(byID.values)
    }
}

struct TVSyncWatch: Codable, Equatable, Sendable {
    var value: TVWatchSession
    var showKey: String
    var revision: LibraryRevision
    var deleted = false

    func merged(with other: Self) -> Self {
        if revision != other.revision { return revision > other.revision ? self : other }
        if deleted != other.deleted { return deleted ? self : other }
        return LibrarySyncDocument.stableKey(self) >= LibrarySyncDocument.stableKey(other) ? self : other
    }
}

struct TVSyncRecord: Codable, Equatable, Sendable {
    var version = 1
    var recordName: String
    var show: TVSyncShow?
    var watch: TVSyncWatch?

    func validated() throws -> Self {
        guard version == 1, (show == nil) != (watch == nil),
              (show != nil && (recordName.hasPrefix("tv-show-") || recordName.hasPrefix("tv-title-"))) ||
                (watch != nil && recordName == "tv-watch-\(watch!.value.id.uuidString)") else {
            throw TVSyncError.newerFormat
        }
        return self
    }

    func merged(with other: Self) throws -> Self {
        _ = try validated(); _ = try other.validated()
        guard recordName == other.recordName else { throw TVSyncError.newerFormat }
        var result = self
        if let show, let remote = other.show { result.show = show.merged(with: remote) }
        else if let watch, let remote = other.watch { result.watch = watch.merged(with: remote) }
        else { throw TVSyncError.newerFormat }
        return result
    }
}

struct TVSyncEntry: Codable, Equatable, Sendable {
    var record: TVSyncRecord
    var systemFields: Data?
    var pendingUpload = true
}

struct TVSyncState: Codable, Sendable {
    var deviceID = UUID().uuidString
    var accountID: String?
    var engineState: Data?
    var zoneEstablished = false
    var lastSync: Date?
    var clock = Date.distantPast
    var entries: [String: TVSyncEntry] = [:]
    var localShowKeys: [String: String] = [:]
    var status = "Preparing TV sync…"
    var recoveryRequired = false

    var pendingCount: Int { entries.values.count { $0.pendingUpload } }

    mutating func bind(to account: String) throws {
        guard accountID == nil || accountID == account else { throw TVSyncError.accountChanged }
        accountID = account
    }
}

enum TVSyncError: LocalizedError {
    case newerFormat, accountChanged, cloudReset, localStorage, oversizedRecord
    var errorDescription: String? {
        switch self {
        case .newerFormat: "TV sync is paused because iCloud has an unsupported TV record. Update Tonight before retrying."
        case .accountChanged: "TV sync is paused because the iCloud account changed. Sign back into the original account. Your local TV collection is safe."
        case .cloudReset: "TV sync is paused because its iCloud records unexpectedly disappeared. Your local TV collection and pending edits are safe."
        case .localStorage: "TV sync is paused because a local change couldn’t be saved. Your existing TV files have been preserved."
        case .oversizedRecord: "A TV show’s metadata is too large to sync. Its details remain saved on this device."
        }
    }
}
