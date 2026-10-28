import XCTest
@testable import Tonight

@MainActor
final class TVRediscoveryTests: XCTestCase {
    private func file() -> TVLibraryFile {
        TVLibraryFile(url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "tv.json"))
    }

    private func familiarShow() -> TVShow {
        var show = TVSessionEngineTests.show()
        show.genres = ["Drama", "Mystery"]
        show.ownedSeasons = [1, 2]
        show.loadedSeasons = [1, 2]
        show.episodes = (1...12).map { index in
            TVSessionEngineTests.episode(index, season: index > 6 ? 2 : 1, number: (index - 1) % 6 + 1)
        }
        return show
    }

    func testFamiliarDramaCanVisitMiddleOfOwnedSeasonDespiteSavedPosition() throws {
        var show = familiarShow()
        show.ownedSeasons = [2]
        show.resumeAfter = .init(season: 2, episode: 6)
        var doc = TVLibraryDocument()
        doc.shows = [show]
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertEqual(plan.isRediscovery, true)
        XCTAssertEqual(plan.episodes.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(plan.episodes.first).episodeNumber, 1)
        XCTAssertTrue(plan.episodes.allSatisfy { $0.seasonNumber == 2 })
        XCTAssertEqual(plan.episodes[1].episodeNumber, plan.episodes[0].episodeNumber + 1)
        XCTAssertLessThanOrEqual(plan.estimatedMinutes, doc.minutes)
    }

    func testNewToMeStaysInOrderEvenForStandaloneStyleAndExcludesLoggedEpisodes() throws {
        var show = familiarShow()
        show.seenBefore = false
        show.viewingStyle = .anyEpisode
        var doc = TVLibraryDocument()
        doc.shows = [show]
        doc.history = [TVWatchSession(id: UUID(), showID: show.id, showTitle: show.title,
            episodes: [show.episodes[0]], watchedAt: .now)]
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertEqual(plan.episodes.map(\.episodeNumber), [2, 3])
        XCTAssertEqual(plan.isRediscovery, false)
    }

    func testNewToMeDoesNotSkipAnOverBudgetPilotToReachShorterEpisodes() {
        var show = familiarShow()
        show.seenBefore = false
        show.episodes[0].runtime = 90
        var doc = TVLibraryDocument()
        doc.shows = [show]
        XCTAssertTrue(TVSessionEngine.eligibleShows(document: doc).isEmpty)
        XCTAssertTrue(TVSessionEngine.suggestions(document: doc).isEmpty)
    }

    func testRefreshRotatesEverySlotAcrossCycleBoundaryAndPersistsEpisodeOffers() throws {
        var doc = TVLibraryDocument()
        doc.sessionCount = 3
        doc.shows = (1...8).map { index in
            var show = familiarShow()
            show.title = "Show \(index)"; show.tmdbID = index
            if index == 1 { show.resumeAfter = .init(season: 1, episode: 1) }
            return show
        }
        let file = file()
        try file.save(doc)
        let store = TVLibraryStore(file: file)
        var previous = Set<UUID>()
        var firstCycle = Set<UUID>()
        for index in 0..<8 {
            let sessions = store.document.suggestions
            let current = Set(sessions.map(\.showID))
            XCTAssertEqual(current.count, 3)
            XCTAssertTrue(current.isDisjoint(with: previous), "No slot stays pinned across refreshes")
            XCTAssertFalse(sessions.contains { $0.lane == .keepGoing })
            if index < 3 { firstCycle.formUnion(current) }
            previous = current
            store.refresh()
        }
        XCTAssertEqual(firstCycle.count, 8)
        let reopened = TVLibraryStore(file: file)
        XCTAssertEqual(reopened.document.episodeOffers, store.document.episodeOffers)
        XCTAssertEqual(reopened.document.suggestions, store.document.suggestions)
        XCTAssertTrue(reopened.document.history.isEmpty)
    }

    func testSmallCollectionRotatesEpisodeRunsWithoutRepeatingThePreviousVisit() throws {
        var doc = TVLibraryDocument()
        doc.shows = [familiarShow()]
        let file = file()
        try file.save(doc)
        let store = TVLibraryStore(file: file)
        for _ in 0..<8 {
            let previous = Set(try XCTUnwrap(store.document.suggestions.first).episodes.map(\.id))
            store.refresh()
            let next = try XCTUnwrap(store.document.suggestions.first)
            XCTAssertTrue(previous.isDisjoint(with: next.episodes.map(\.id)))
            XCTAssertEqual(next.episodes.count, 2)
        }
    }

    func testEpisodeDescriptionsInformSelectionAndExplanationWithoutInventingThemes() throws {
        var show = familiarShow()
        show.episodes[1].overview = "A detective investigates a mystery."
        show.episodes[2].overview = "A mysterious murder reveals a clue."
        var doc = TVLibraryDocument()
        doc.shows = [show]
        var recentEpisode = show.episodes[0]
        recentEpisode.overview = "A detective investigates a murder."
        doc.history = [TVWatchSession(id: UUID(), showID: UUID(), showTitle: "Previous show",
            episodes: [recentEpisode], watchedAt: .now)]
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertEqual(plan.episodes.map(\.id), [2, 3])
        XCTAssertTrue(plan.rationale.contains("descriptions echo the mystery"))
        doc.history = []
        doc.mood = .anything
        let withoutEvidence = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertFalse(withoutEvidence.rationale.contains("recent viewing"))
    }

    func testRecentlyWatchedEpisodesAreAvoidedAndUnknownRuntimeStaysEstimated() throws {
        var show = familiarShow()
        for index in show.episodes.indices { show.episodes[index].runtime = nil }
        show.episodeRuntime = 25
        var doc = TVLibraryDocument()
        doc.shows = [show]
        let watched = Array(show.episodes[1...2])
        doc.history = [TVWatchSession(id: UUID(), showID: show.id, showTitle: show.title,
            episodes: watched, watchedAt: .now)]
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertTrue(Set(watched.map(\.id)).isDisjoint(with: plan.episodes.map(\.id)))
        XCTAssertTrue(plan.usesEstimatedRuntime)
    }

    func testMissingUnownedAndUnairedEpisodesCannotFormAnInventedRun() throws {
        var show = familiarShow()
        show.ownedSeasons = [1]
        show.episodes = [show.episodes[0], show.episodes[2], show.episodes[6]]
        var future = TVSessionEngineTests.episode(99, number: 4)
        future.airDate = "2999-01-01"
        show.episodes.append(future)
        var doc = TVLibraryDocument()
        doc.shows = [show]
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertEqual(plan.episodes.count, 1)
        XCTAssertEqual(plan.episodes[0].seasonNumber, 1)
        XCTAssertNotEqual(plan.episodes[0].id, 99)
    }

    func testRediscoveryLogsAndSyncsHistoryWithoutMovingContinuationAndUndoIsSafe() throws {
        var show = familiarShow()
        show.resumeAfter = .init(season: 1, episode: 1)
        var doc = TVLibraryDocument()
        doc.shows = [show]
        let file = file()
        try file.save(doc)
        let store = TVLibraryStore(file: file)
        try store.prepareSync()
        let plan = try XCTUnwrap(store.document.suggestions.first)
        store.start(plan)
        XCTAssertTrue(store.document.history.isEmpty)
        store.markWatched(plan, episodeCount: 1)
        XCTAssertEqual(store.shows[0].resumeAfter, show.resumeAfter)
        XCTAssertEqual(store.document.activeSession?.isRediscovery, true)
        XCTAssertEqual(store.document.history.count, 1)
        XCTAssertEqual(store.document.sync?.entries.values.filter { $0.record.watch != nil }.count, 1)
        store.undoLastWatch()
        XCTAssertTrue(store.document.history.isEmpty)
        XCTAssertEqual(store.shows[0].resumeAfter, show.resumeAfter)
        let continuation = try XCTUnwrap(TVSessionEngine.continuations(document: store.document).first)
        XCTAssertEqual(continuation.episodes.first?.position, .init(season: 1, episode: 2))
        XCTAssertEqual(continuation.isRediscovery, false)
        store.markWatched(continuation)
        XCTAssertEqual(store.shows[0].resumeAfter, continuation.episodes.last?.position)
    }

    func testUpgradePreservesLegacyPlanHistoryAndPersonalStateAndReplacesOldSuggestions() throws {
        var show = familiarShow()
        show.resumeAfter = .init(season: 1, episode: 1)
        var doc = TVLibraryDocument()
        doc.shows = [show]
        var legacy = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .keepGoing, document: doc, now: .now))
        legacy.isRediscovery = nil
        doc.activeSession = legacy; doc.suggestions = [legacy]
        let file = file()
        try file.save(doc)
        let store = TVLibraryStore(file: file)
        XCTAssertEqual(store.document.activeSession, legacy)
        XCTAssertEqual(store.shows[0], show)
        XCTAssertTrue(store.document.history.isEmpty)
        XCTAssertEqual(store.document.sessionEngineVersion, TVSessionEngine.version)
        XCTAssertTrue(store.document.suggestions.allSatisfy { $0.isRediscovery == true })
        let roundTrip = try file.load()
        XCTAssertEqual(roundTrip.activeSession?.isRediscovery, nil)
        XCTAssertNotNil(roundTrip.episodeOffers)
    }
}
