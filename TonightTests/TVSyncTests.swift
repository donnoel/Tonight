import XCTest
@testable import Tonight

@MainActor
final class TVSyncTests: XCTestCase {
    private func file() -> TVLibraryFile {
        TVLibraryFile(url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "tv.json"))
    }

    private func store(shows: [TVShow], history: [TVWatchSession] = [], file: TVLibraryFile? = nil) throws -> TVLibraryStore {
        let file = file ?? self.file()
        var doc = TVLibraryDocument()
        doc.shows = shows; doc.history = history
        try file.save(doc)
        let store = TVLibraryStore(file: file)
        try store.prepareSync()
        return store
    }

    private func exchange(_ first: TVLibraryStore, _ second: TVLibraryStore, rounds: Int = 3) throws {
        for _ in 0..<rounds {
            let outbound = try XCTUnwrap(first.document.sync).entries.values.map(\.record)
            try second.saveSyncChanges(reconcile: true) { doc in
                for record in outbound { try TVSyncStore.receive(record, in: &doc) }
            }
            let inbound = try XCTUnwrap(second.document.sync).entries.values.map(\.record)
            try first.saveSyncChanges(reconcile: true) { doc in
                for record in inbound { try TVSyncStore.receive(record, in: &doc) }
            }
        }
    }

    func testMigrationBacksUpOriginalAndMergesExistingLibrariesByTMDBIdentity() throws {
        var firstShow = TVSessionEngineTests.show()
        firstShow.isFavorite = true
        var secondShow = firstShow
        secondShow.id = UUID(); secondShow.isFavorite = false
        let firstFile = file()
        let first = try store(shows: [firstShow], file: firstFile)
        let second = try store(shows: [secondShow])
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstFile.preSyncBackupURL.path))
        let backup = try JSONDecoder().decode(TVLibraryDocument.self, from: Data(contentsOf: firstFile.preSyncBackupURL))
        XCTAssertNil(backup.sync)
        XCTAssertEqual(backup.shows[0].id, firstShow.id)
        try exchange(first, second)
        XCTAssertEqual(first.shows.count, 1)
        XCTAssertEqual(second.shows.count, 1)
        XCTAssertEqual(first.shows[0].id, firstShow.id)
        XCTAssertEqual(second.shows[0].id, secondShow.id)
        XCTAssertTrue(second.shows[0].isFavorite)
        XCTAssertEqual(first.document.sync?.entries.mapValues(\.record), second.document.sync?.entries.mapValues(\.record))
    }

    func testIndependentMetadataPositionAndFavoriteEditsMergeWithoutRewinding() throws {
        let first = try store(shows: [TVSessionEngineTests.show()])
        let second = try store(shows: [TVSessionEngineTests.show()])
        var progress = first.shows[0]
        progress.resumeAfter = .init(season: 1, episode: 2); progress.isFavorite = true
        first.updateShow(progress)
        var metadata = second.shows[0]
        metadata.overview = "Richer metadata"
        metadata.episodes.append(TVSessionEngineTests.episode(5, number: 5))
        second.updateShow(metadata)
        try exchange(first, second)
        for store in [first, second] {
            XCTAssertEqual(store.shows[0].resumeAfter, .init(season: 1, episode: 2))
            XCTAssertTrue(store.shows[0].isFavorite)
            XCTAssertEqual(store.shows[0].episodes.count, 5)
        }
    }

    func testInitialOwnershipDoesNotWidenAndLaterExplicitSelectionWins() throws {
        var restricted = TVSessionEngineTests.show()
        restricted.ownedSeasons = [1]
        var complete = restricted
        complete.id = UUID(); complete.ownedSeasons = [1, 2]
        complete.loadedSeasons = [1, 2]
        let first = try store(shows: [restricted])
        let second = try store(shows: [complete])
        try exchange(first, second)
        XCTAssertEqual(first.shows[0].ownedSeasons, [1])
        XCTAssertEqual(second.shows[0].ownedSeasons, [1])
        var edited = second.shows[0]
        edited.ownedSeasons = [1, 2]
        second.updateShow(edited)
        try exchange(first, second)
        XCTAssertEqual(first.shows[0].ownedSeasons, [1, 2])
    }

    func testHistoryUnionRetainsSessionsFromBothDevicesAndUndoPropagates() throws {
        let firstShow = TVSessionEngineTests.show()
        let secondShow = TVSessionEngineTests.show()
        let firstWatch = TVWatchSession(id: UUID(), showID: firstShow.id, showTitle: firstShow.title,
            episodes: [firstShow.episodes[0]], watchedAt: Date(timeIntervalSince1970: 100))
        let secondWatch = TVWatchSession(id: UUID(), showID: secondShow.id, showTitle: secondShow.title,
            episodes: [secondShow.episodes[1]], watchedAt: Date(timeIntervalSince1970: 200))
        let first = try store(shows: [firstShow], history: [firstWatch])
        let second = try store(shows: [secondShow], history: [secondWatch])
        try exchange(first, second)
        XCTAssertEqual(first.document.history.count, 2)
        XCTAssertEqual(second.document.history.count, 2)
        XCTAssertTrue(first.document.history.allSatisfy { $0.showID == first.shows[0].id })
        XCTAssertTrue(second.document.history.allSatisfy { $0.showID == second.shows[0].id })
        first.undoLastWatch()
        try exchange(first, second)
        XCTAssertEqual(first.document.history.map(\.id), [firstWatch.id])
        XCTAssertEqual(second.document.history.map(\.id), [firstWatch.id])
    }

    func testRemoteWatchAdvancesOtherDeviceAndClearsAlreadyWatchedPlan() throws {
        let first = try store(shows: [TVSessionEngineTests.show()])
        let second = try store(shows: [TVSessionEngineTests.show()])
        first.refresh(); second.refresh()
        let plan = try XCTUnwrap(first.document.suggestions.first)
        first.start(plan)
        let otherPlan = try XCTUnwrap(second.document.suggestions.first)
        second.start(otherPlan)
        first.markWatched(plan, now: .now.addingTimeInterval(1))
        try exchange(first, second)
        XCTAssertEqual(second.shows[0].resumeAfter, plan.episodes.last?.position)
        XCTAssertEqual(second.document.history.count, 1)
        XCTAssertNil(second.document.activeSession)
    }

    func testDeletionSurvivesOfflineStaleCopyAndExplicitReimportCanRestore() throws {
        let first = try store(shows: [TVSessionEngineTests.show()])
        let second = try store(shows: [TVSessionEngineTests.show()])
        let original = first.shows[0]
        let stale = try XCTUnwrap(second.document.sync)
        first.removeShow(original.id)
        try exchange(first, second)
        XCTAssertTrue(first.shows.isEmpty)
        XCTAssertTrue(second.shows.isEmpty)
        try first.saveSyncChanges(reconcile: true) { doc in
            for entry in stale.entries.values { try TVSyncStore.receive(entry.record, in: &doc) }
        }
        XCTAssertTrue(first.shows.isEmpty)
        try first.saveSyncChanges { doc in
            let previous = doc
            var restored = original
            restored.id = UUID()
            doc.shows = [restored]
            TVSyncStore.capture(previous: previous, next: &doc)
        }
        try exchange(first, second)
        XCTAssertEqual(second.shows.count, 1)
    }

    func testAcknowledgementCannotClearEditMadeWhileUploadWasInFlight() throws {
        let store = try store(shows: [TVSessionEngineTests.show()])
        let old = try XCTUnwrap(store.document.sync?.entries.values.first?.record)
        var show = store.shows[0]
        show.isFavorite = true
        store.updateShow(show)
        try store.saveSyncChanges { TVSyncStore.acknowledge(old, systemFields: Data(), in: &$0) }
        XCTAssertEqual(store.document.sync?.pendingCount, 1)
        let current = try XCTUnwrap(store.document.sync?.entries.values.first?.record)
        try store.saveSyncChanges { TVSyncStore.acknowledge(current, systemFields: Data(), in: &$0) }
        XCTAssertEqual(store.document.sync?.pendingCount, 0)
    }

    func testOfflineOutboxAndHistorySurviveRelaunchWhileLayoutPreferencesStayLocal() throws {
        let file = file()
        let first = try store(shows: [TVSessionEngineTests.show()], file: file)
        let second = try store(shows: [TVSessionEngineTests.show()])
        first.setPreferences(minutes: 120, mood: .light, unseenOnly: false)
        first.setSessionCount(4)
        var show = first.shows[0]
        show.isPaused = true
        first.updateShow(show)
        let reopened = TVLibraryStore(file: file)
        XCTAssertEqual(reopened.document.sync?.pendingCount, 1)
        XCTAssertTrue(reopened.shows[0].isPaused)
        try exchange(reopened, second)
        XCTAssertTrue(second.shows[0].isPaused)
        XCTAssertEqual(second.document.minutes, 60)
        XCTAssertEqual(second.document.mood, .anything)
        XCTAssertNil(second.document.sessionCount)
    }

    func testUnresolvedMatchRedirectPreservesLocalIdentityAndDoesNotGuessBetweenRemakes() throws {
        var unresolved = TVSessionEngineTests.show()
        unresolved.tmdbID = nil; unresolved.episodes = []; unresolved.loadedSeasons = []
        let first = try store(shows: [unresolved])
        let second = try store(shows: [TVSessionEngineTests.show()])
        try exchange(first, second)
        XCTAssertEqual(first.shows.count, 1)
        XCTAssertEqual(first.shows[0].id, unresolved.id)
        XCTAssertEqual(first.shows[0].tmdbID, 1)
        XCTAssertTrue(first.document.sync?.entries.values.contains { $0.record.show?.redirectTo != nil } == true)
        var remake = TVSessionEngineTests.show()
        remake.tmdbID = 2
        let ambiguous = try store(shows: [unresolved, TVSessionEngineTests.show(), remake])
        XCTAssertEqual(ambiguous.shows.count, 3)
    }

    func testAccountBindingAndIncompatiblePayloadFailWithoutChangingExistingLibrary() throws {
        var state = TVSyncState()
        try state.bind(to: "account-a")
        XCTAssertThrowsError(try state.bind(to: "account-b"))
        XCTAssertEqual(state.accountID, "account-a")
        let store = try store(shows: [TVSessionEngineTests.show()])
        var record = try XCTUnwrap(store.document.sync?.entries.values.first?.record)
        record.version = 2
        XCTAssertThrowsError(try store.saveSyncChanges(reconcile: true) { doc in
            try TVSyncStore.receive(record, in: &doc)
        })
        XCTAssertEqual(store.shows.count, 1)
    }

    func testMergeIsCommutativeAndIdempotentForIndependentFields() throws {
        var first = TVSyncShow(TVSessionEngineTests.show())
        var second = first
        first.value.isFavorite = true
        second.value.isPaused = true
        second.value.ownedSeasons = [1, 2]
        let left = first.merged(with: second)
        let right = second.merged(with: first)
        XCTAssertEqual(left, right)
        XCTAssertEqual(left.merged(with: left), left)
    }
}
