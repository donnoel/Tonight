#if os(tvOS) || os(macOS)
import CryptoKit
import Foundation

enum TopShelfMotionCache {
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TonightWidgetSnapshotStore.appGroupIdentifier)?
            .appendingPathComponent("Library/Caches/TopShelfMotion", isDirectory: true)
    }

    static func destination(for pick: TonightWidgetPick, in directory: URL) -> URL? {
        guard let artwork = pick.backdropData else { return nil }
        let fingerprint = SHA256.hash(data: artwork).prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(pick.id.uuidString)-\(fingerprint)-v2.mp4")
    }
}
#endif
