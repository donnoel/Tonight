import Foundation
import OSLog
import WidgetKit

@MainActor
enum TonightWidgetSnapshotPublisher {
    private static let logger = Logger(
        subsystem: "com.donnoel.Tonight",
        category: "TonightWidget"
    )
    private static var artworkTask: Task<Void, Never>?

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
        guard !ids.isEmpty,
              let store = try? TonightWidgetSnapshotStore(),
              let snapshot = try? store.load() else {
            return
        }
        let updated = snapshot.removingMovies(ids: ids)
        guard updated != snapshot else { return }
        artworkTask?.cancel()
        artworkTask = nil
        persist(updated, using: store)
    }

    private static func publish(snapshot: TonightWidgetSnapshot) {
        guard let store = try? TonightWidgetSnapshotStore() else {
            logger.error("The Tonight widget App Group is unavailable.")
            return
        }

        let existingSnapshot = try? store.load()
        var artworkByID: [UUID: (URL?, Data)] = [:]
        for pick in existingSnapshot?.picks ?? [] {
            if let artworkData = pick.artworkData {
                artworkByID[pick.id] = (pick.artworkURL, artworkData)
            }
        }
        var snapshot = snapshot
        for index in snapshot.picks.indices {
            let pick = snapshot.picks[index]
            if let existingArtwork = artworkByID[pick.id],
               existingArtwork.0 == pick.artworkURL {
                snapshot.picks[index].artworkData = existingArtwork.1
            }
        }

        // Empty snapshots have no meaningful generation date.
        if snapshot.picks.isEmpty, let existingSnapshot, existingSnapshot.picks.isEmpty {
            snapshot = existingSnapshot
        }
        if snapshot != existingSnapshot {
            persist(snapshot, using: store)
        } else if artworkTask != nil {
            return
        }

        artworkTask?.cancel()
        artworkTask = nil
        guard snapshot.picks.contains(where: { $0.artworkData == nil && $0.artworkURL != nil }) else {
            return
        }

        artworkTask = Task { @MainActor in
            defer {
                if !Task.isCancelled { artworkTask = nil }
            }
            var enrichedSnapshot = snapshot

            for index in enrichedSnapshot.picks.indices where
                enrichedSnapshot.picks[index].artworkData == nil {
                guard !Task.isCancelled,
                      let url = enrichedSnapshot.picks[index].artworkURL else {
                    continue
                }

                do {
                    guard let data = try await TonightWidgetArtworkLoader.load(from: url),
                          !Task.isCancelled else {
                        continue
                    }
                    enrichedSnapshot.picks[index].artworkData = data
                } catch is CancellationError {
                    return
                } catch {
                    logger.error(
                        "Widget artwork download failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            guard !Task.isCancelled,
                  let latestSnapshot = try? store.load(),
                  latestSnapshot.generatedAt == enrichedSnapshot.generatedAt else {
                return
            }
            if enrichedSnapshot != latestSnapshot {
                persist(enrichedSnapshot, using: store)
            }
        }
    }

    private static func persist(
        _ snapshot: TonightWidgetSnapshot,
        using store: TonightWidgetSnapshotStore
    ) {
        do {
            try store.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: TonightWidgetSnapshotStore.widgetKind)
        } catch {
            logger.error(
                "Widget snapshot update failed: \(error.localizedDescription, privacy: .public)"
            )
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

nonisolated enum TonightWidgetArtworkLoader {
    static func load(from url: URL) async throws -> Data? {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard data.count <= 2_000_000,
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.mimeType?.hasPrefix("image/") == true else {
            return nil
        }
        return data
    }
}
