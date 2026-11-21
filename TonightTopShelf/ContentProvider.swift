import AppIntents
import Foundation
import TVServices
import UIKit

/// Display-only persisted picks. No SwiftData, TMDB credential, or discovery requests.
final class ContentProvider: TVTopShelfContentProvider {
    nonisolated(nonsending) override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let reduceMotion = await MainActor.run { UIAccessibility.isReduceMotionEnabled }
        guard let store = try? TonightWidgetSnapshotStore(),
              let snapshot = try? store.load(), let pick = snapshot.picks.first else { return nil }
        let motionDirectory = reduceMotion ? nil : TopShelfMotionCache.directory
        let item = TVTopShelfCarouselItem(identifier: pick.id.uuidString)
        item.title = pick.title
        item.contextTitle = Calendar.current.isDateInWeekend(snapshot.generatedAt) ? "Weekend Pick" : "Tonight’s Pick"
        let imageURL = autoreleasepool { Self.artworkURL(for: pick) } ?? pick.backdropURL ?? pick.artworkURL
        item.setImageURL(imageURL, for: .screenScale1x)
        item.setImageURL(imageURL, for: .screenScale2x)
        if let motionDirectory,
           let preview = TopShelfMotionCache.destination(for: pick, in: motionDirectory),
           FileManager.default.fileExists(atPath: preview.path()) {
            item.previewVideoURL = preview
        }
        // Opens this exact movie. Selection never records a watch or starts playback.
        item.displayAction = TVTopShelfAction(url: TonightMovieRoute.movie(pick.id).url)
        return TVTopShelfCarouselContent(style: .actions, items: [item])
    }

    private static func artworkURL(for pick: TonightWidgetPick) -> URL? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TonightWidgetSnapshotStore.appGroupIdentifier),
              let data = TopShelfFeatureArtwork.render(backdropData: pick.backdropData, posterData: pick.artworkData) else { return nil }
        let directory = group.appendingPathComponent("Library/Caches/TopShelfArtwork", isDirectory: true)
        let url = directory.appendingPathComponent(pick.id.uuidString + "-feature.jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
