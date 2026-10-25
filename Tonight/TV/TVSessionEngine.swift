import Foundation

enum TVSessionEngine {
    static func suggestions(document: TVLibraryDocument, now: Date = .now) -> [TVViewingSession] {
        let eligible = document.shows.filter {
            !$0.isPaused && $0.tmdbID != nil && $0.metadataComplete &&
            document.mood.accepts($0) && (!document.unseenOnly || !$0.seenBefore) &&
            !availableEpisodes(for: $0, document: document).isEmpty
        }
        let recent = document.history.sorted { $0.watchedAt > $1.watchedAt }.first
        let recentShow = eligible.first { $0.id == recent?.showID }
            ?? document.shows.first { $0.id == recent?.showID }
        let previouslySuggested = Set(document.suggestedShowIDs)
        var remaining = eligible
        var picks: [TVViewingSession] = []

        for lane in [TVSessionLane.keepGoing, .changePace, .rediscover] {
            let candidates = remaining.filter { show in
                lane != .keepGoing || (show.resumeAfter != nil && show.viewingStyle != .anyEpisode)
            }
            let ranked = candidates.sorted { left, right in
                let lhs = score(left, lane: lane, document: document, recentShow: recentShow,
                                previouslySuggested: previouslySuggested, now: now)
                let rhs = score(right, lane: lane, document: document, recentShow: recentShow,
                                previouslySuggested: previouslySuggested, now: now)
                return lhs == rhs ? left.id.uuidString < right.id.uuidString : lhs > rhs
            }
            for show in ranked {
                guard let session = session(for: show, lane: lane, document: document, now: now) else { continue }
                picks.append(session)
                remaining.removeAll { $0.id == show.id }
                break
            }
        }
        // Fill the requested iPad row using additional distinct shows. A continuation
        // is never invented when the user has not established a viewing position.
        if let count = document.sessionCount {
            while picks.count < count {
                let lane: TVSessionLane = picks.count.isMultiple(of: 2) ? .rediscover : .changePace
                let ranked = remaining.sorted {
                    let left = score($0, lane: lane, document: document, recentShow: recentShow,
                                     previouslySuggested: previouslySuggested, now: now)
                    let right = score($1, lane: lane, document: document, recentShow: recentShow,
                                      previouslySuggested: previouslySuggested, now: now)
                    return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
                }
                var added = false
                for show in ranked {
                    guard let plan = session(for: show, lane: lane, document: document, now: now) else { continue }
                    picks.append(plan)
                    remaining.removeAll { $0.id == show.id }
                    added = true
                    break
                }
                if !added { break }
            }
        }
        return picks
    }

    static func availableEpisodes(for show: TVShow, document: TVLibraryDocument) -> [TVEpisode] {
        var episodes = show.eligibleEpisodes
        if !show.seenBefore {
            let watched = Set(document.history.filter { $0.showID == show.id }.flatMap { $0.episodes.map(\.id) })
            episodes = episodes.filter { !watched.contains($0.id) }
        }
        if show.viewingStyle != .anyEpisode, let resume = show.resumeAfter {
            return episodes.filter { $0.position > resume }
        }
        return episodes
    }

    static func session(for show: TVShow, lane: TVSessionLane, document: TVLibraryDocument,
                        now: Date) -> TVViewingSession? {
        var available = availableEpisodes(for: show, document: document)
        guard !available.isEmpty else { return nil }
        if show.viewingStyle == .anyEpisode {
            let watches = document.history.filter { $0.showID == show.id }
            let lastWatch = Dictionary(grouping: watches.flatMap { watch in
                watch.episodes.map { ($0.id, watch.watchedAt) }
            }, by: { $0.0 }).mapValues { $0.map(\.1).max() ?? .distantPast }
            available.sort {
                let left = lastWatch[$0.id] ?? .distantPast
                let right = lastWatch[$1.id] ?? .distantPast
                if left != right { return left < right }
                return rotation($0.id, generation: document.generation) > rotation($1.id, generation: document.generation)
            }
        } else if show.viewingStyle == .bySeason && show.resumeAfter == nil {
            let starts = available.filter { $0.episodeNumber == 1 }
            let first = starts.max {
                rotation($0.id, generation: document.generation) < rotation($1.id, generation: document.generation)
            }
            guard let first else { return nil }
            available = available.filter { $0.seasonNumber == first.seasonNumber }
        }

        var selected: [TVEpisode] = []
        var total = 0
        var estimated = false
        for episode in available {
            if selected.count == 6 { break }
            // Unknown runtimes use a visible estimate, never a fabricated exact runtime.
            let duration = duration(of: episode, show: show)
            if total + duration.minutes > document.minutes {
                if show.viewingStyle == .anyEpisode { continue }
                break
            }
            if show.viewingStyle == .bySeason, let first = selected.first,
               episode.seasonNumber != first.seasonNumber { break }
            selected.append(episode)
            total += duration.minutes
            estimated = estimated || duration.estimated
        }
        guard !selected.isEmpty else { return nil }
        let reason: String
        switch lane {
        case .keepGoing:
            reason = "Pick up after \(show.resumeAfter?.label ?? "your last episode"), with the story kept in order."
        case .changePace:
            if let recent = document.history.sorted(by: { $0.watchedAt > $1.watchedAt }).first,
               let previous = document.shows.first(where: { $0.id == recent.showID }),
               Set(previous.genres).isDisjoint(with: Set(show.genres)) {
                reason = "A different mix of genres after \(previous.title), chosen from your own collection."
            } else {
                reason = "A different corner of your collection, with room for \(selected.count == 1 ? "one episode" : "\(selected.count) episodes") tonight."
            }
        case .rediscover:
            let hasHistory = document.history.contains { $0.showID == show.id }
            if !show.seenBefore {
                reason = "An episode you haven’t logged as watched, from a show you marked as new to you."
            } else if show.viewingStyle == .inOrder && show.resumeAfter == nil {
                reason = "Begin a fresh rewatch at the start of your owned collection."
            } else {
                reason = hasHistory ? "Return to a familiar show, favoring episodes you haven’t revisited lately."
                    : "Rediscover a familiar show you haven’t logged a session with yet."
            }
        }
        return TVViewingSession(showID: show.id, lane: lane, episodes: selected,
                                estimatedMinutes: total, usesEstimatedRuntime: estimated,
                                rationale: reason, createdAt: now)
    }

    static func duration(of episode: TVEpisode, show: TVShow) -> (minutes: Int, estimated: Bool) {
        let known = episode.runtime.flatMap { $0 > 0 ? $0 : nil }
        let fallback = show.episodeRuntime.flatMap { $0 > 0 ? $0 : nil }
        return (known ?? fallback ?? (show.genres.contains("Comedy") ? 30 : 60), known == nil)
    }

    private static func score(_ show: TVShow, lane: TVSessionLane, document: TVLibraryDocument,
                              recentShow: TVShow?, previouslySuggested: Set<UUID>, now: Date) -> Double {
        let history = document.history.filter { $0.showID == show.id }
        let last = history.map(\.watchedAt).max()
        let days = last.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? 365
        let stableID = show.tmdbID ?? show.title.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fff_ffff }
        var result = Double(rotation(stableID, generation: document.generation) % 1000) / 1000
        result += show.isFavorite ? 2 : 0
        // A full library rotation before reusing suggestions, while allowing a continued story.
        if lane != .keepGoing && !previouslySuggested.contains(show.id) { result += 1000 }
        switch lane {
        case .keepGoing:
            result += last.map { max(0, 100 - now.timeIntervalSince($0) / 86_400) } ?? 0
        case .changePace:
            if let recentShow {
                result += Double(Set(show.genres).subtracting(recentShow.genres).count) * 5
                if recentShow.id == show.id { result -= 50 }
            }
        case .rediscover:
            result += min(days, 365) / 10
        }
        return result
    }

    private static func rotation(_ id: Int, generation: UInt64) -> UInt64 {
        var value = UInt64(bitPattern: Int64(id)) &+ generation &* 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}
