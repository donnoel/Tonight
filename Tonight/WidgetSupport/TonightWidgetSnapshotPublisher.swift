import Foundation
import OSLog
import SwiftData
#if os(tvOS)
import TVServices
#else
import WidgetKit
#endif

@MainActor
enum TonightWidgetSnapshotPublisher {
    private static var latestSnapshot: TonightWidgetSnapshot?
    private static var publicationTask: Task<Void, Never>?

    #if os(tvOS)
    static var shelfPicks: [TonightWidgetPick] {
        (latestSnapshot ?? (try? TonightWidgetSnapshotStore().load()))?.picks ?? []
    }
    #endif

    static func publish(picks: [RecommendationPick], generatedAt: Date) {
        publish(
            snapshot: TonightWidgetSnapshot(
                generatedAt: generatedAt,
                picks: picks.prefix(3).map {
                    widgetPick(
                        movie: $0.movie,
                        kind: $0.kind,
                        rationale: $0.rationale
                    )
                }
            )
        )
    }

    static func publish(events: [RecommendationEvent], library: [Movie] = []) {
        #if os(tvOS)
        let preferences = TonightTopShelfSelection.preferences
        let hasPendingPicks = RecommendationEngine.activeEvents(from: events, preferences: preferences)
            .contains { $0.response == .pending }
        let previous = latestSnapshot ?? (try? TonightWidgetSnapshotStore().load())
        let picks = TonightTopShelfSelection.picks(events: events, library: library,
            preferences: preferences,
            preferredMovieIDs: hasPendingPicks ? [] : previous?.picks.map(\.id) ?? [])
        publish(snapshot: TonightWidgetSnapshot(
            generatedAt: events.map(\.recommendedAt).max() ?? .now,
            picks: picks.map { widgetPick(movie: $0.movie, kind: $0.kind, rationale: $0.rationale) }))
        #else
        let latestDate = events.map(\.recommendedAt).max()
        let sortedEvents = events
            .filter { event in
                guard event.recommendedAt == latestDate, event.response == .pending,
                      let movie = event.movie,
                      movie.browsingEventID == nil || movie.browsingEventID == event.id else { return false }
                return !movie.isWatched && !movie.isDisliked
            }
            .sorted { $0.kind.sortOrder < $1.kind.sortOrder }
        let generatedAt = sortedEvents.first?.recommendedAt
            ?? events.first?.recommendedAt
            ?? .now

        publish(
            snapshot: TonightWidgetSnapshot(
                generatedAt: generatedAt,
                picks: sortedEvents.prefix(3).compactMap { event in
                    guard let movie = event.movie else { return nil }
                    return widgetPick(
                        movie: movie,
                        kind: event.kind,
                        rationale: RecommendationEngine.rationale(
                            for: movie,
                            kind: event.kind,
                            mood: event.mood
                        )
                    )
                }
            )
        )
        #endif
    }

    static func removeMovie(id: UUID, in context: ModelContext? = nil) {
        removeMovies(ids: [id], in: context)
    }

    static func removeMovies(ids: Set<UUID>, in context: ModelContext? = nil) {
        guard !ids.isEmpty else { return }
        let snapshot: TonightWidgetSnapshot
        if let latestSnapshot {
            snapshot = latestSnapshot
        } else {
            guard let store = try? TonightWidgetSnapshotStore(),
                  let storedSnapshot = try? store.load() else {
                return
            }
            snapshot = storedSnapshot
        }
        let updated = snapshot.removingMovies(ids: ids)
        #if os(tvOS)
        if let context {
            do {
                let events = try context.fetch(FetchDescriptor<RecommendationEvent>())
                let library = try context.fetch(FetchDescriptor<Movie>())
                let picks = TonightTopShelfSelection.picks(events: events, library: library,
                    preferences: TonightTopShelfSelection.preferences,
                    preferredMovieIDs: updated.picks.map(\.id), excluding: ids)
                publish(snapshot: TonightWidgetSnapshot(generatedAt: snapshot.generatedAt,
                    picks: picks.map { widgetPick(movie: $0.movie, kind: $0.kind, rationale: $0.rationale) }))
                return
            } catch {
                Logger(subsystem: "com.donnoel.Tonight", category: "TonightWidget")
                    .error("Top Shelf could not refill after a library change.")
            }
        }
        #endif
        guard updated != snapshot else { return }
        publish(snapshot: updated)
    }

    private static func publish(snapshot: TonightWidgetSnapshot) {
        latestSnapshot = snapshot
        publicationTask?.cancel()
        publicationTask = Task(priority: .utility) {
            await TonightWidgetSnapshotWriter.shared.publish(snapshot)
        }
    }

    private static func widgetPick(
        movie: Movie,
        kind: RecommendationKind,
        rationale: String
    ) -> TonightWidgetPick {
        #if os(tvOS)
        let backdropURL = TMDBImageURL.make(path: movie.backdropPath, size: .backdrop)
        #else
        let backdropURL: URL? = nil
        #endif
        return TonightWidgetPick(
            id: movie.id,
            kindTitle: kind.title,
            title: movie.title,
            metadata: metadata(for: movie),
            rationale: rationale,
            artworkURL: TMDBImageURL.make(path: movie.posterPath, size: .posterCard),
            artworkData: nil,
            backdropURL: backdropURL
        )
    }

    private static func metadata(for movie: Movie) -> String {
        var components: [String] = []
        if let releaseYear = movie.releaseYear {
            components.append(String(releaseYear))
        }
        if let runtimeMinutes = movie.runtimeMinutes {
            let hours = runtimeMinutes / 60
            let minutes = runtimeMinutes % 60
            components.append(hours == 0 ? "\(minutes)m" : "\(hours)h \(minutes)m")
        }
        if let genre = movie.genres.first {
            components.append(genre)
        }
        return components.joined(separator: " · ")
    }
}

private actor TonightWidgetSnapshotWriter {
    static let shared = TonightWidgetSnapshotWriter()

    private let logger = Logger(
        subsystem: "com.donnoel.Tonight",
        category: "TonightWidget"
    )
    private let performanceSignposter = OSSignposter(
        subsystem: "com.donnoel.Tonight",
        category: "WidgetPerformance"
    )

    func publish(_ requestedSnapshot: TonightWidgetSnapshot) async {
        let publishInterval = performanceSignposter.beginInterval("Widget Publication")
        defer {
            performanceSignposter.endInterval("Widget Publication", publishInterval)
        }

        guard !Task.isCancelled else { return }
        guard let store = try? TonightWidgetSnapshotStore() else {
            logger.error("The Tonight widget App Group is unavailable.")
            return
        }

        let existingSnapshot = try? store.load()
        var snapshot = reuseArtwork(in: requestedSnapshot, from: existingSnapshot)

        // Empty snapshots have no meaningful generation date.
        if snapshot.picks.isEmpty, let existingSnapshot, existingSnapshot.picks.isEmpty {
            snapshot = existingSnapshot
        }

        snapshot = await enrichArtwork(in: snapshot)
        guard !Task.isCancelled else { return }

        if snapshot != existingSnapshot {
            do {
                try store.save(snapshot)
                #if os(tvOS)
                TVTopShelfContentProvider.topShelfContentDidChange()
                #else
                WidgetCenter.shared.reloadTimelines(ofKind: TonightWidgetSnapshotStore.widgetKind)
                #endif
            } catch {
                logger.error("Widget snapshot update failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        #if os(tvOS)
        await TopShelfMotionWriter.shared.prepare(snapshot)
        #endif
    }

    private func reuseArtwork(
        in snapshot: TonightWidgetSnapshot,
        from existingSnapshot: TonightWidgetSnapshot?
    ) -> TonightWidgetSnapshot {
        let artworkByID = Dictionary(uniqueKeysWithValues: (existingSnapshot?.picks ?? []).map { ($0.id, $0) })
        var snapshot = snapshot
        for index in snapshot.picks.indices {
            let pick = snapshot.picks[index]
            guard let existing = artworkByID[pick.id] else { continue }
            if existing.artworkURL == pick.artworkURL {
                snapshot.picks[index].artworkData = existing.artworkData
            }
            #if os(tvOS)
            if existing.backdropURL == pick.backdropURL {
                snapshot.picks[index].backdropData = existing.backdropData
            }
            #endif
        }
        return snapshot
    }

    private func enrichArtwork(in snapshot: TonightWidgetSnapshot) async -> TonightWidgetSnapshot {
        var snapshot = snapshot
        for index in snapshot.picks.indices {
            guard !Task.isCancelled else { return snapshot }
            if snapshot.picks[index].artworkData == nil, let url = snapshot.picks[index].artworkURL {
                snapshot.picks[index].artworkData = await artwork(for: url)
            }
            #if os(tvOS)
            if snapshot.picks[index].backdropData == nil, let url = snapshot.picks[index].backdropURL {
                snapshot.picks[index].backdropData = await artwork(for: url)
            }
            #endif
        }
        return snapshot
    }

    private func artwork(for url: URL) async -> Data? {
        guard !Task.isCancelled else { return nil }
        do {
            let data = try await LibraryArtworkCache.shared.data(for: url)
            try Task.checkCancellation()
            return data.count <= 2_000_000 ? data : nil
        } catch is CancellationError {
            return nil
        } catch {
            logger.error("Widget artwork download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
