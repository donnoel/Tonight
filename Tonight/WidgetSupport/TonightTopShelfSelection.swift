import Foundation
import Observation
import SwiftData

/// App-side selection only. The extension receives display values and stable movie IDs.
enum TonightTopShelfSelection {
    static var preferences: RecommendationPreferences {
        let defaults = UserDefaults.standard
        return RecommendationPreferences(
            mood: defaults.string(forKey: "tonightMood").flatMap(RecommendationMood.init(rawValue:)) ?? .anything,
            underTwoHours: defaults.bool(forKey: "tonightUnderTwoHours"),
            unwatchedOnly: defaults.bool(forKey: "tonightUnwatchedOnly"),
            somethingOlder: defaults.bool(forKey: "tonightSomethingOlder"),
            moreAdventurous: defaults.bool(forKey: "tonightMoreAdventurous"))
    }

    static func picks(events: [RecommendationEvent], library: [Movie],
                      preferences: RecommendationPreferences, now: Date = .now,
                      preferredMovieIDs: [UUID] = [], excluding excludedIDs: Set<UUID> = []) -> [RecommendationPick] {
        let eligibleLibrary = library.filter {
            !excludedIDs.contains($0.id) && !$0.isWatched
                && RecommendationEngine.isEligible($0, preferences: preferences)
        }
        let eligibleIDs = Set(eligibleLibrary.map(\.id))
        let latestDate = events.map(\.recommendedAt).max()
        let active = events.filter { event in
            guard event.recommendedAt == latestDate, event.response == .pending,
                  let movie = event.movie,
                  movie.browsingEventID == nil || movie.browsingEventID == event.id else { return false }
            return eligibleIDs.contains(movie.id)
        }.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
        var seen: Set<UUID> = []
        let primaryPicks = active.compactMap { event -> RecommendationPick? in
            guard let movie = event.movie else { return nil }
            return RecommendationPick(kind: event.kind, movie: movie,
                rationale: RecommendationEngine.rationale(for: movie, kind: event.kind, mood: event.mood))
        }
        let preservedPicks = preferredMovieIDs.compactMap { id -> RecommendationPick? in
            guard let movie = eligibleLibrary.first(where: { $0.id == id }) else { return nil }
            return primaryPicks.first(where: { $0.id == id })
                ?? RecommendationPick(kind: .wildcard, movie: movie,
                    rationale: RecommendationEngine.rationale(for: movie, kind: .wildcard, mood: preferences.mood))
        }
        var picks = (preservedPicks + primaryPicks).filter { seen.insert($0.id).inserted }
        while picks.count < 5 {
            let alternatives = RecommendationEngine.recommendations(
                from: eligibleLibrary.filter { !seen.contains($0.id) },
                history: events, preferences: preferences, now: now)
            guard !alternatives.isEmpty else { break }
            let additions = alternatives.prefix(5 - picks.count)
            picks.append(contentsOf: additions)
            seen.formUnion(additions.map(\.id))
        }
        return Array(picks.prefix(5))
    }
}

/// Opening a shelf item is read-only. Only an explicit response persists history/taste.
@MainActor @Observable
final class TonightTopShelfMovieSelection: Identifiable {
    let movie: Movie
    let event: RecommendationEvent?
    let activeEvents: [RecommendationEvent]
    var saveError: String?
    nonisolated let id: UUID

    init(movie: Movie, history: [RecommendationEvent], preferences: RecommendationPreferences) {
        self.movie = movie
        id = movie.id
        activeEvents = RecommendationEngine.activeEvents(from: history, preferences: preferences)
        if movie.isWatched || movie.isDisliked || movie.resolutionStatus != .resolved {
            event = nil
        } else {
            event = activeEvents.first { $0.movie?.id == movie.id && $0.response == .pending }
                ?? RecommendationEvent(movie: movie, kind: .wildcard, mood: preferences.mood)
        }
    }

    static func open(id: UUID, in context: ModelContext,
                     preferences: RecommendationPreferences) throws -> TonightTopShelfMovieSelection? {
        let descriptor = FetchDescriptor<Movie>(predicate: #Predicate { $0.id == id })
        guard let movie = try context.fetch(descriptor).first else { return nil }
        let history = try context.fetch(FetchDescriptor<RecommendationEvent>())
        return TonightTopShelfMovieSelection(movie: movie, history: history, preferences: preferences)
    }

    func respond(_ response: RecommendationResponse, in context: ModelContext) {
        guard let event, event.response == .pending else { return }
        if event.modelContext == nil { context.insert(event) }
        event.recordResponse(response, at: .now)
        if response == .accepted {
            for other in activeEvents where other.id != event.id && other.response == .pending {
                other.response = .notTonight
            }
        }
        do {
            try LibrarySyncStore.save(context)
            if response.removesMovieFromActivePicks {
                TonightWidgetSnapshotPublisher.removeMovie(id: movie.id, in: context)
            }
        } catch {
            context.rollback()
            saveError = "Your choice couldn’t be saved. Please try again."
        }
    }
}
