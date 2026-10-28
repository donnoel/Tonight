import XCTest
@testable import Tonight

final class TVImportTests: XCTestCase {
    func testPreparedCollectionExcludesSimpsonsAndPreservesThreePartialRanges() throws {
        let entries = try TVImportParser.parse(TVStarterLibrary.titles)
        XCTAssertEqual(entries.count, 39)
        XCTAssertFalse(entries.contains { $0.title.contains("Simpsons") })
        XCTAssertEqual(entries.first { $0.title == "American Horror Story" }?.seasons, [1, 2, 3])
        XCTAssertEqual(entries.first { $0.title == "It's Always Sunny in Philadelphia" }?.seasons, [1, 2, 3, 4])
        XCTAssertEqual(entries.first { $0.title == "Portlandia" }?.seasons, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(entries.first { $0.title == "Battlestar Galactica" }?.year, 2004)
        XCTAssertEqual(entries.first { $0.title == "Cosmos" }?.year, 1980)
        XCTAssertEqual(entries.first { $0.title == "Star Trek" }?.year, 1966)
        XCTAssertEqual(entries.first { $0.title == "Frasier" }?.year, 1993)
    }

    func testParsingCombinesDuplicateRangesWithoutSplittingTitlesWithCommas() throws {
        let entries = try TVImportParser.parse("Show, Actually (2000) (Seasons 1–3)\nShow, Actually (2000) (Season 5)")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "Show, Actually")
        XCTAssertEqual(entries[0].year, 2000)
        XCTAssertEqual(entries[0].seasons, [1, 2, 3, 5])
        for invalid in ["Show (Seasons 3-1)", "Show (Seasons 0-2)", "Show (Seasons 1oops3)", "Show (Seasons 1-)"] {
            XCTAssertThrowsError(try TVImportParser.parse(invalid))
        }
    }

    func testAmbiguousVersionsRequireChoiceAndYearSelectsCorrectVersion() {
        let candidates = [candidate(1, year: "1963-01-01"), candidate(2, year: "1995-01-01")]
        XCTAssertNil(TVShowMatching.confidentMatch(candidates, entry: TVImportEntry(title: "The Outer Limits")))
        XCTAssertEqual(TVShowMatching.confidentMatch(candidates,
            entry: TVImportEntry(title: "The Outer Limits", year: 1963))?.id, 1)
    }

    func testConfirmedYearHandlesExpandedCosmosTitleAndEmptyDuplicate() {
        let cosmos = TVSearchCandidate(id: 1430, name: "Cosmos: A Personal Voyage", firstAirDate: "1980-09-28", overview: "Carl Sagan")
        XCTAssertEqual(TVShowMatching.confidentMatch([cosmos], entry: TVImportEntry(title: "Cosmos", year: 1980))?.id, 1430)
        let original = TVSearchCandidate(id: 6357, name: "The Twilight Zone", firstAirDate: "1959-10-02", overview: "An anthology")
        let placeholder = TVSearchCandidate(id: 294969, name: "The Twilight Zone", firstAirDate: "1959-10-02", overview: "")
        XCTAssertEqual(TVShowMatching.confidentMatch([original, placeholder],
            entry: TVImportEntry(title: "The Twilight Zone", year: 1959))?.id, 6357)
        XCTAssertNil(TVShowMatching.confidentMatch([original, placeholder], entry: TVImportEntry(title: "The Twilight Zone")))
    }

    private func candidate(_ id: Int, year: String) -> TVSearchCandidate {
        TVSearchCandidate(id: id, name: "The Outer Limits", firstAirDate: year)
    }
}

final class TVSessionEngineTests: XCTestCase {
    func testOrderedSessionsRespectOwnershipSequenceAndTimeBudget() throws {
        var doc = TVLibraryDocument()
        var show = Self.show()
        show.ownedSeasons = [1]
        show.episodes += [Self.episode(20, season: 2, number: 1)]
        show.resumeAfter = .init(season: 1, episode: 1)
        doc.shows = [show]
        doc.minutes = 60
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .keepGoing, document: doc, now: .now))
        XCTAssertEqual(plan.episodes.map(\.episodeNumber), [2, 3])
        XCTAssertTrue(plan.episodes.allSatisfy { $0.seasonNumber == 1 })
        XCTAssertLessThanOrEqual(plan.estimatedMinutes, 60)
        doc.minutes = 20
        XCTAssertNil(TVSessionEngine.session(for: show, lane: .keepGoing, document: doc, now: .now))
    }

    func testFamiliarSeasonStoryRevisitsOneSeasonWithoutCrossingIt() throws {
        var doc = TVLibraryDocument()
        var show = Self.show()
        show.viewingStyle = .bySeason
        show.ownedSeasons = [1, 2]
        show.episodes += [Self.episode(21, season: 2, number: 1), Self.episode(22, season: 2, number: 2)]
        doc.minutes = 120
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertEqual(plan.isRediscovery, true)
        XCTAssertLessThanOrEqual(plan.episodes.count, 2)
        XCTAssertEqual(Set(plan.episodes.map(\.seasonNumber)).count, 1)
    }

    func testStandaloneRewatchFavorsEpisodesNotRecentlyWatched() throws {
        var doc = TVLibraryDocument()
        var show = Self.show()
        show.viewingStyle = .anyEpisode
        doc.minutes = 30
        doc.history = [TVWatchSession(id: UUID(), showID: show.id, showTitle: show.title,
            episodes: [show.episodes[0]], watchedAt: .now)]
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertNotEqual(plan.episodes[0].id, show.episodes[0].id)
    }

    func testUnknownRuntimeIsEstimatedAndMoodAndPauseAreHardFilters() throws {
        var doc = TVLibraryDocument()
        var show = Self.show()
        for index in show.episodes.indices { show.episodes[index].runtime = nil }
        doc.shows = [show]
        let plan = try XCTUnwrap(TVSessionEngine.session(for: show, lane: .rediscover, document: doc, now: .now))
        XCTAssertTrue(plan.usesEstimatedRuntime)
        doc.mood = .strange
        XCTAssertTrue(TVSessionEngine.suggestions(document: doc).isEmpty)
        doc.mood = .anything
        doc.shows[0].isPaused = true
        XCTAssertTrue(TVSessionEngine.suggestions(document: doc).isEmpty)
    }

    func testNewToMeExcludesPreviouslySeenShowsAndCompletedEpisodes() {
        var doc = TVLibraryDocument()
        let show = Self.show()
        doc.shows = [show]
        doc.unseenOnly = true
        XCTAssertTrue(TVSessionEngine.suggestions(document: doc).isEmpty)
        doc.shows[0].seenBefore = false
        doc.shows[0].viewingStyle = .anyEpisode
        doc.history = [TVWatchSession(id: UUID(), showID: show.id, showTitle: show.title,
            episodes: show.episodes, watchedAt: .now)]
        XCTAssertTrue(TVSessionEngine.suggestions(document: doc).isEmpty)
    }

    func testSuggestionsAreDistinctAndPersistedGenerationIsRepeatable() {
        var doc = TVLibraryDocument()
        doc.shows = (0..<5).map { index in
            var show = Self.show()
            show.title = "Show \(index)"
            show.tmdbID = index + 1
            return show
        }
        let first = TVSessionEngine.suggestions(document: doc)
        let second = TVSessionEngine.suggestions(document: doc)
        XCTAssertEqual(first.map(\.showID), second.map(\.showID))
        XCTAssertEqual(Set(first.map(\.showID)).count, first.count)
        XCTAssertEqual(first.count, 2, "Compact presentation retains its existing initial two suggestions")
        XCTAssertFalse(first.contains { $0.lane == .keepGoing })
    }

    func testIPadRowsFillWithThreeOrFourDistinctEligibleShowsWithoutInventingContinuations() {
        var document = TVLibraryDocument()
        document.shows = (1...6).map { index in
            var show = Self.show()
            show.title = "Show \(index)"
            show.tmdbID = index
            return show
        }
        for count in [3, 4] {
            document.sessionCount = count
            let plans = TVSessionEngine.suggestions(document: document)
            XCTAssertEqual(plans.count, count)
            XCTAssertEqual(Set(plans.map(\.showID)).count, count)
            XCTAssertFalse(plans.contains { $0.lane == .keepGoing })
            XCTAssertTrue(plans.allSatisfy { $0.estimatedMinutes <= document.minutes })
        }
        document.shows = Array(document.shows.prefix(1))
        XCTAssertEqual(TVSessionEngine.suggestions(document: document).count, 1)
    }

    static func episode(_ id: Int, season: Int = 1, number: Int) -> TVEpisode {
        TVEpisode(id: id, name: "Episode \(number)", seasonNumber: season, episodeNumber: number,
                  runtime: 25, airDate: "2000-01-01", overview: "", stillPath: nil)
    }
    static func show() -> TVShow {
        var show = TVShow(importedTitle: "Show", ownedSeasons: [1], title: "Show", tmdbID: 1)
        show.genres = ["Comedy"]
        show.loadedSeasons = [1]
        show.episodes = (1...4).map { episode($0, number: $0) }
        return show
    }
}

@MainActor
final class TVLibraryStoreTests: XCTestCase {
    private func file() -> TVLibraryFile {
        TVLibraryFile(url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "tv.json"))
    }

    func testImportRoundTripPreservesOwnershipAndReimportDoesNotWidenIt() throws {
        let file = file()
        let store = TVLibraryStore(file: file)
        XCTAssertTrue(store.importTitles(TVStarterLibrary.titles))
        XCTAssertTrue(store.importTitles("American Horror Story"))
        let reopened = TVLibraryStore(file: file)
        XCTAssertEqual(reopened.shows.count, 39)
        XCTAssertEqual(reopened.shows.first { $0.title == "American Horror Story" }?.ownedSeasons, [1, 2, 3])
        XCTAssertTrue(reopened.document.history.isEmpty)
        XCTAssertTrue(reopened.shows.allSatisfy(\.seenBefore))
    }

    func testStartingDoesNotMarkWatchedAndLoggingIsIdempotentAndUndoable() throws {
        let file = file()
        var document = TVLibraryDocument()
        var show = TVSessionEngineTests.show()
        show.seenBefore = false
        document.shows = [show]
        try file.save(document)
        let store = TVLibraryStore(file: file)
        store.refresh()
        let plan = try XCTUnwrap(store.document.suggestions.first)
        store.start(plan)
        XCTAssertTrue(store.document.history.isEmpty)
        XCTAssertNil(store.show(show.id)?.resumeAfter)
        let resumed = TVLibraryStore(file: file)
        XCTAssertEqual(resumed.document.activeSession?.id, plan.id)
        store.markWatched(plan)
        store.markWatched(plan)
        XCTAssertEqual(store.document.history.count, 1)
        XCTAssertEqual(store.show(show.id)?.resumeAfter, plan.episodes.last?.position)
        let persisted = TVLibraryStore(file: file)
        XCTAssertEqual(persisted.document.history.count, 1)
        store.undoLastWatch()
        XCTAssertNil(store.show(show.id)?.resumeAfter)
        XCTAssertTrue(store.document.history.isEmpty)
    }

    func testSpecificReimportRefinesUnknownVersionWithoutCreatingDuplicateOrWideningOwnership() throws {
        let store = TVLibraryStore(file: file())
        _ = store.importTitles("Show (Seasons 1–2)")
        _ = store.importTitles("Show (2004)")
        XCTAssertEqual(store.shows.count, 1)
        XCTAssertEqual(store.shows[0].requestedYear, 2004)
        XCTAssertEqual(store.shows[0].ownedSeasons, [1, 2])
    }

    func testFiveConfirmedVersionsRefineExistingCollectionWithoutDuplicatesOrOwnershipChanges() throws {
        let store = TVLibraryStore(file: file())
        let versions = try TVImportParser.parse(TVStarterLibrary.confirmedVersions)
        var originalList = TVStarterLibrary.titles
        for version in versions {
            originalList = originalList.replacingOccurrences(of: "\(version.title) (\(try XCTUnwrap(version.year)))", with: version.title)
        }
        XCTAssertTrue(store.importTitles(originalList))
        let initialIDs = Set(store.shows.map(\.id))
        XCTAssertTrue(store.importTitles(TVStarterLibrary.confirmedVersions))
        XCTAssertEqual(store.shows.count, 39)
        XCTAssertEqual(Set(store.shows.map(\.id)), initialIDs)
        for version in versions {
            XCTAssertEqual(store.shows.first { $0.importedTitle == version.title }?.requestedYear, version.year)
        }
        XCTAssertEqual(store.shows.first { $0.importedTitle == "American Horror Story" }?.ownedSeasons, [1, 2, 3])
        XCTAssertEqual(store.shows.first { $0.importedTitle == "It's Always Sunny in Philadelphia" }?.ownedSeasons, [1, 2, 3, 4])
        XCTAssertEqual(store.shows.first { $0.importedTitle == "Portlandia" }?.ownedSeasons, [1, 2, 3, 4, 5, 6])
        XCTAssertTrue(store.document.history.isEmpty)
    }

    func testPartialSessionKeepsRemainingEpisodesAndOwnershipEditInvalidatesPlan() throws {
        let file = file()
        var document = TVLibraryDocument()
        document.shows = [TVSessionEngineTests.show()]
        try file.save(document)
        let store = TVLibraryStore(file: file)
        store.refresh()
        let plan = try XCTUnwrap(store.document.suggestions.first)
        store.start(plan)
        store.markWatched(plan, episodeCount: 1)
        XCTAssertEqual(store.document.activeSession?.episodes.count, plan.episodes.count - 1)
        var show = try XCTUnwrap(store.shows.first)
        show.ownedSeasons = [2]
        store.updateShow(show)
        XCTAssertNil(store.document.activeSession)
        XCTAssertTrue(store.document.suggestions.isEmpty)
    }

    func testCorruptAndFutureLibrariesArePreservedAndBlockedFromReplacement() throws {
        let file = file()
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: file.url)
        let store = TVLibraryStore(file: file)
        XCTAssertFalse(store.storageReady)
        XCTAssertFalse(store.importTitles("Show"))
        XCTAssertEqual(try Data(contentsOf: file.url), corrupt)
        var future = TVLibraryDocument()
        future.version = 2
        let data = try JSONEncoder().encode(future)
        try data.write(to: file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf: file.url), data)
    }
}
