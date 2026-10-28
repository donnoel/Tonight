import Foundation

enum TVSessionEngine {
    static let version = 2

    static func eligibleShows(document: TVLibraryDocument, now: Date = .now) -> [TVShow] {
        document.shows.filter { show in
            guard !show.isPaused, show.tmdbID != nil, show.metadataComplete,
                  document.mood.accepts(show), !document.unseenOnly || !show.seenBefore else { return false }
            let episodes = availableEpisodes(for: show, document: document, now: now)
            if !show.seenBefore {
                return episodes.first.map { duration(of: $0, show: show).minutes <= document.minutes } == true
            }
            return episodes.contains { duration(of: $0, show: show).minutes <= document.minutes }
        }
    }

    static func suggestions(document: TVLibraryDocument, now: Date = .now) -> [TVViewingSession] {
        var remaining = eligibleShows(document: document, now: now)
        let recentShow = document.shows.first { $0.id == latestWatch(document)?.showID }
        let previouslySuggested = Set(document.suggestedShowIDs)
        var picks: [TVViewingSession] = []
        // Continue Watching has its own control; every suggestion slot participates in rotation.
        for index in 0..<max(0, document.sessionCount ?? 2) {
            let lane: TVSessionLane = index.isMultiple(of: 2) ? .rediscover : .changePace
            let ranked = remaining.sorted { left, right in
                let lhs = score(left, lane: lane, document: document, recentShow: recentShow,
                                previouslySuggested: previouslySuggested, now: now)
                let rhs = score(right, lane: lane, document: document, recentShow: recentShow,
                                previouslySuggested: previouslySuggested, now: now)
                return lhs == rhs ? left.id.uuidString < right.id.uuidString : lhs > rhs
            }
            guard let plan = ranked.lazy.compactMap({ session(for: $0, lane: lane, document: document, now: now) }).first else { break }
            picks.append(plan)
            remaining.removeAll { $0.id == plan.showID }
        }
        return picks
    }

    static func continuations(document: TVLibraryDocument, now: Date = .now) -> [TVViewingSession] {
        document.shows.filter {
            !$0.isPaused && $0.tmdbID != nil && $0.metadataComplete && $0.resumeAfter != nil &&
            $0.viewingStyle != .anyEpisode
        }.sorted { left, right in
            let lhs = document.history.filter { $0.showID == left.id }.map(\.watchedAt).max() ?? .distantPast
            let rhs = document.history.filter { $0.showID == right.id }.map(\.watchedAt).max() ?? .distantPast
            return lhs == rhs ? left.title.localizedStandardCompare(right.title) == .orderedAscending : lhs > rhs
        }.compactMap { session(for: $0, lane: .keepGoing, document: document, now: now) }
    }

    static func availableEpisodes(for show: TVShow, document: TVLibraryDocument,
                                  now: Date = .now, continuing: Bool = false) -> [TVEpisode] {
        var episodes = show.eligibleEpisodes.filter {
            MovieDateParser.date(from: $0.airDate).map { $0 <= now } == true
        }
        if !show.seenBefore {
            let watched = Set(document.history.filter { $0.showID == show.id }.flatMap { $0.episodes.map(\.id) })
            episodes.removeAll { watched.contains($0.id) }
        }
        if (continuing || !show.seenBefore), let resume = show.resumeAfter {
            episodes.removeAll { $0.position <= resume }
        }
        return episodes
    }

    static func session(for show: TVShow, lane: TVSessionLane, document: TVLibraryDocument,
                        now: Date) -> TVViewingSession? {
        let rediscovery = show.seenBefore && lane != .keepGoing
        let available = availableEpisodes(for: show, document: document, now: now, continuing: lane == .keepGoing)
        guard !available.isEmpty else { return nil }
        let scores = rediscovery ? Dictionary(available.map {
            ($0.id, episodeScore($0, show: show, document: document, now: now))
        }, uniquingKeysWith: max) : [:]
        let selected: [TVEpisode]
        if !rediscovery {
            selected = run(startingAt: 0, in: available, show: show, minutes: document.minutes, limit: 6,
                           sameSeason: show.viewingStyle == .bySeason)
        } else if show.viewingStyle == .anyEpisode {
            let ranked = available.sorted {
                let left = scores[$0.id] ?? 0
                let right = scores[$1.id] ?? 0
                return left == right ? $0.id < $1.id : left > right
            }
            var mix: [TVEpisode] = []
            var remaining = document.minutes
            for episode in ranked where mix.count < 3 {
                let minutes = duration(of: episode, show: show).minutes
                if minutes <= remaining { mix.append(episode); remaining -= minutes }
            }
            selected = mix
        } else {
            // Small consecutive visits can begin anywhere, but never jump over a missing episode.
            let runs = available.indices.map {
                run(startingAt: $0, in: available, show: show, minutes: document.minutes, limit: 2, sameSeason: true)
            }.filter { !$0.isEmpty }
            selected = runs.max { left, right in
                let lhs = runScore(left, scores: scores)
                let rhs = runScore(right, scores: scores)
                return lhs == rhs ? (left.first?.id ?? 0) < (right.first?.id ?? 0) : lhs < rhs
            } ?? []
        }
        guard !selected.isEmpty else { return nil }
        let durations = selected.map { duration(of: $0, show: show) }
        return TVViewingSession(showID: show.id, lane: lane, episodes: selected,
            estimatedMinutes: durations.reduce(0) { $0 + $1.minutes },
            usesEstimatedRuntime: durations.contains { $0.estimated },
            rationale: rationale(selected, show: show, lane: lane, document: document, rediscovery: rediscovery),
            createdAt: now, isRediscovery: rediscovery)
    }

    static func offerKey(showID: UUID, episodeID: Int) -> String { "\(showID.uuidString):\(episodeID)" }

    private static func run(startingAt index: Int, in available: [TVEpisode], show: TVShow,
                            minutes: Int, limit: Int, sameSeason: Bool) -> [TVEpisode] {
        var result: [TVEpisode] = []
        var total = 0
        for episode in available.dropFirst(index) {
            guard result.count < limit else { break }
            if let previous = result.last {
                if episode.seasonNumber == previous.seasonNumber {
                    guard episode.episodeNumber == previous.episodeNumber + 1 else { break }
                } else {
                    guard !sameSeason, episode.seasonNumber == previous.seasonNumber + 1,
                          episode.episodeNumber == 1 else { break }
                }
            }
            let duration = duration(of: episode, show: show).minutes
            guard total + duration <= minutes else { break }
            result.append(episode); total += duration
        }
        return result
    }

    private static func runScore(_ episodes: [TVEpisode], scores: [Int: Double]) -> Double {
        episodes.map { scores[$0.id] ?? 0 }.reduce(0, +)
            + (episodes.count == 2 ? 3 : 0)
    }

    private static func episodeScore(_ episode: TVEpisode, show: TVShow,
                                     document: TVLibraryDocument, now: Date) -> Double {
        let key = offerKey(showID: show.id, episodeID: episode.id)
        let offer = document.episodeOffers?[key]
        var result = offer.map { Double(min(document.generation &- min($0, document.generation), 100)) } ?? 1_000
        if document.suggestions.contains(where: { $0.showID == show.id && $0.episodes.contains(where: { $0.id == episode.id }) }) {
            result -= 2_000
        }
        let lastWatch = document.history.filter { $0.showID == show.id && $0.episodes.contains { $0.id == episode.id } }
            .map(\.watchedAt).max()
        if let lastWatch {
            let days = max(0, now.timeIntervalSince(lastWatch) / 86_400)
            result -= max(0, 30 - days) * 50
        }
        let themes = episodeThemes(episode)
        result += Double(themes.intersection(recentThemes(document)).count) * 12
        result += Double(themes.intersection(moodThemes(document.mood)).count) * 12
        // Prefer a visit beyond the pilot when otherwise equally suitable, without excluding pilots.
        if episode.episodeNumber > 1 { result += 2 }
        return result + Double(rotation(episode.id, generation: document.generation) % 1_000) / 1_000
    }

    private static func rationale(_ episodes: [TVEpisode], show: TVShow, lane: TVSessionLane,
                                   document: TVLibraryDocument, rediscovery: Bool) -> String {
        if lane == .keepGoing {
            return "Continue after \(show.resumeAfter?.label ?? "your starting point"), with the story kept in order."
        }
        if !rediscovery { return "A show marked new to you, starting at your next unwatched episode and staying in order." }
        let introduction: String
        if show.viewingStyle == .anyEpisode { introduction = "A standalone mix from your owned seasons." }
        else if let first = episodes.first, let last = episodes.last {
            introduction = episodes.count == 1
                ? "Drop into season \(first.seasonNumber), episode \(first.episodeNumber)."
                : "A short visit to season \(first.seasonNumber), episodes \(first.episodeNumber)–\(last.episodeNumber), kept in order."
        } else { introduction = "A fresh visit to your collection." }
        let themes = episodes.reduce(into: Set<String>()) { $0.formUnion(episodeThemes($1)) }
        if let theme = themes.intersection(recentThemes(document)).sorted().first {
            return introduction + " Episode descriptions echo the \(theme) in your recent viewing."
        }
        if let theme = themes.intersection(moodThemes(document.mood)).sorted().first {
            return introduction + " Episode descriptions suggest \(theme), matching your mood."
        }
        if lane == .changePace, let recent = latestWatch(document),
           let previous = document.shows.first(where: { $0.id == recent.showID }),
           Set(previous.genres).isDisjoint(with: Set(show.genres)) {
            return introduction + " A different mix of genres after \(previous.title)."
        }
        return introduction + " Favoring episodes not offered or logged lately."
    }

    // These descriptions are evidence for lightweight themes, never invented episode arcs or ratings.
    private static let themeWords: [String: Set<String>] = [
        "mystery": ["mystery", "mysterious", "investigate", "investigation", "clue", "murder", "detective"],
        "secrets": ["secret", "secrets", "identity", "truth", "reveal", "hidden"],
        "family ties": ["family", "father", "mother", "brother", "sister", "parents"],
        "friendship": ["friend", "friends", "friendship", "reunion"],
        "rivalry": ["rival", "rivalry", "competition", "enemy", "enemies"],
        "pressure": ["deadline", "crisis", "pressure", "escape", "threat", "trapped"],
        "strange turns": ["alien", "aliens", "strange", "dream", "dreams", "supernatural", "unexplained", "experiment"]
    ]

    private static func episodeThemes(_ episode: TVEpisode) -> Set<String> {
        let words = Set(episode.overview.lowercased().split { !$0.isLetter }.map(String.init))
        return Set(themeWords.filter { !$0.value.isDisjoint(with: words) }.keys)
    }

    private static func recentThemes(_ document: TVLibraryDocument) -> Set<String> {
        (latestWatch(document)?.episodes ?? []).reduce(into: Set<String>()) { $0.formUnion(episodeThemes($1)) }
    }

    private static func moodThemes(_ mood: TVSessionMood) -> Set<String> {
        switch mood {
        case .anything: []
        case .light: ["friendship", "family ties"]
        case .gripping: ["mystery", "secrets", "pressure", "rivalry"]
        case .strange: ["strange turns", "mystery"]
        }
    }

    private static func latestWatch(_ document: TVLibraryDocument) -> TVWatchSession? {
        document.history.max { $0.watchedAt < $1.watchedAt }
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
        // Exposure rotates independently of watch history, including across a completed browsing cycle.
        if !previouslySuggested.contains(show.id) { result += 1_000 }
        if !document.suggestions.contains(where: { $0.showID == show.id }) { result += 10_000 }
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
