import Foundation
import OSLog
import TVServices
import UIKit

/// Prepares previews in the app so the extension can serve existing files immediately.
actor TopShelfMotionWriter {
    static let shared = TopShelfMotionWriter()

    private var task: Task<Void, Never>?
    private var requestedFile: URL?
    private var announcedFile: URL?
    private let logger = Logger(subsystem: "com.donnoel.Tonight", category: "TopShelfMotion")

    func prepare(_ snapshot: TonightWidgetSnapshot) {
        guard #available(tvOS 26, *), let directory = TopShelfMotionCache.directory else { return }
        let pick = snapshot.picks.first
        let destination = pick.flatMap { TopShelfMotionCache.destination(for: $0, in: directory) }
        guard task == nil || destination != requestedFile else { return }
        requestedFile = destination
        let previous = task
        previous?.cancel()
        task = Task(priority: .utility) {
            await previous?.value
            defer { if !Task.isCancelled { task = nil } }
            guard !Task.isCancelled, let artwork = pick?.backdropData, let destination,
                  await MainActor.run(body: { !UIAccessibility.isReduceMotionEnabled }) else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: destination.path()) {
                    try await write(artwork, to: destination)
                }
                try Task.checkCancellation()
                if destination != announcedFile {
                    announcedFile = destination
                    TVTopShelfContentProvider.topShelfContentDidChange()
                }
                try trimCache(in: directory, keeping: destination)
            } catch is CancellationError {
                return
            } catch {
                let failure = error as NSError
                logger.error("Top Shelf preview unavailable (\(failure.domain, privacy: .public) \(failure.code, privacy: .public)).")
            }
        }
    }

    @available(tvOS 26, *)
    private func write(_ artwork: Data, to url: URL) async throws {
        let temporary = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await TopShelfMotionPreview.write(backdrop: artwork, to: temporary)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    private func trimCache(in directory: URL, keeping current: URL) throws {
        let candidates = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        let previous = candidates.filter { $0.pathExtension == "mp4" && $0 != current }
            .map { url in (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (url, _) in previous.dropFirst(9) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
