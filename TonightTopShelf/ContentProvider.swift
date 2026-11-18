import AppIntents
import Foundation
import TVServices

/// Display-only persisted picks. No SwiftData, TMDB credential, or discovery requests.
final class ContentProvider: TVTopShelfContentProvider {
    nonisolated(nonsending) override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let store = try? TonightWidgetSnapshotStore(),
              let snapshot = try? store.load(), !snapshot.picks.isEmpty else { return nil }
        let items = snapshot.picks.prefix(5).map { pick in
            let item = TVTopShelfSectionedItem(identifier: pick.id.uuidString)
            item.title = pick.title
            item.imageShape = .poster
            let imageURL = Self.artworkURL(for: pick) ?? pick.artworkURL
            item.setImageURL(imageURL, for: .screenScale1x)
            item.setImageURL(imageURL, for: .screenScale2x)
            // Opens this exact movie. Selection never records a watch or starts playback.
            item.displayAction = TVTopShelfAction(url: TonightMovieRoute.movie(pick.id).url)
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = Calendar.current.isDateInWeekend(snapshot.generatedAt) ? "Weekend Picks" : "Tonight’s Picks"
        return TVTopShelfSectionedContent(sections: [section])
    }

    private static func artworkURL(for pick: TonightWidgetPick) -> URL? {
        guard let data = pick.artworkData,
              let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TonightWidgetSnapshotStore.appGroupIdentifier) else { return nil }
        let directory = group.appendingPathComponent("Library/Caches/TopShelfArtwork", isDirectory: true)
        let url = directory.appendingPathComponent(pick.id.uuidString + ".jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
