import Foundation
import OSLog
import WidgetKit

@MainActor
enum TonightWidgetSnapshotPublisher {
    private static var latestSnapshot: TonightWidgetSnapshot?
    private static var publicationTask: Task<Void, Never>?

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

    static func publish(events: [RecommendationEvent]) {
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
    }

    static func removeMovie(id: UUID) {
        removeMovies(ids: [id])
    }

    static func removeMovies(ids: Set<UUID>) {
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
        TonightWidgetPick(
            id: movie.id,
            kindTitle: kind.title,
            title: movie.title,
            metadata: metadata(for: movie),
            rationale: rationale,
            artworkURL: TMDBImageURL.make(path: movie.posterPath, size: .posterCard),
            artworkData: nil
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
        guard !Task.isCancelled, snapshot != existingSnapshot else { return }

        do {
            try store.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: TonightWidgetSnapshotStore.widgetKind)
        } catch {
            logger.error(
                "Widget snapshot update failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func reuseArtwork(
        in snapshot: TonightWidgetSnapshot,
        from existingSnapshot: TonightWidgetSnapshot?
    ) -> TonightWidgetSnapshot {
        let artworkByID = Dictionary(
            uniqueKeysWithValues: (existingSnapshot?.picks ?? []).compactMap { pick in
                pick.artworkData.map { (pick.id, (pick.artworkURL, $0)) }
            }
        )
        var snapshot = snapshot
        for index in snapshot.picks.indices {
            let pick = snapshot.picks[index]
            if let existingArtwork = artworkByID[pick.id],
               existingArtwork.0 == pick.artworkURL {
                snapshot.picks[index].artworkData = existingArtwork.1
            }
        }
        return snapshot
    }

    private func enrichArtwork(in snapshot: TonightWidgetSnapshot) async -> TonightWidgetSnapshot {
        var snapshot = snapshot
        for index in snapshot.picks.indices where snapshot.picks[index].artworkData == nil {
            guard !Task.isCancelled,
                  let url = snapshot.picks[index].artworkURL else {
                continue
            }

            do {
                let data = try await LibraryArtworkCache.shared.data(for: url)
                guard !Task.isCancelled else { return snapshot }
                if data.count <= 2_000_000 {
                    snapshot.picks[index].artworkData = data
                }
            } catch is CancellationError {
                return snapshot
            } catch {
                logger.error(
                    "Widget artwork download failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return snapshot
    }
}
