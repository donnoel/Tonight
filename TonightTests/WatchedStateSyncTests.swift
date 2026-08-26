import Foundation
import SwiftData
import XCTest
@testable import Tonight

final class WatchedStateSyncTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    func testNewerRemoteWatchStateUpdatesMatchingLocalMovie() {
        let movie = makeMovie(tmdbID: 603, title: "The Matrix", year: 1999)
        let remote = syncedState(
            tmdbID: 603,
            title: "The Matrix",
            year: 1999,
            isWatched: true,
            modifiedAt: later
        )

        let resolution = WatchedStateSyncResolver.resolve(
            remoteSnapshot: WatchedStateSyncSnapshot(records: [remote]),
            localStates: [LocalWatchedState(movie: movie)]
        )

        XCTAssertEqual(resolution.localUpdates.count, 1)
        XCTAssertEqual(resolution.localUpdates.first?.movieID, movie.id)
        XCTAssertEqual(resolution.localUpdates.first?.state, remote)
    }

    func testNewerLocalUnwatchWinsAndIsPublished() {
        let movie = makeMovie(tmdbID: 603, title: "The Matrix", year: 1999)
        movie.isWatched = false
        movie.watchedStateModifiedAt = later
        let olderRemote = syncedState(
            tmdbID: 603,
            title: "The Matrix",
            year: 1999,
            isWatched: true,
            modifiedAt: earlier
        )

        let resolution = WatchedStateSyncResolver.resolve(
            remoteSnapshot: WatchedStateSyncSnapshot(records: [olderRemote]),
            localStates: [LocalWatchedState(movie: movie)]
        )

        XCTAssertTrue(resolution.localUpdates.isEmpty)
        XCTAssertEqual(resolution.snapshot.records.count, 1)
        XCTAssertEqual(resolution.snapshot.records.first?.isWatched, false)
        XCTAssertEqual(resolution.snapshot.records.first?.modifiedAt, later)
    }

    func testFallbackMatchesResolvedRecordToUnresolvedLocalTitleAndYear() {
        let movie = makeMovie(tmdbID: nil, title: "Dune", year: 2021)
        let remote = syncedState(
            tmdbID: 438_631,
            title: "Dune",
            year: 2021,
            isWatched: true,
            modifiedAt: later
        )

        let resolution = WatchedStateSyncResolver.resolve(
            remoteSnapshot: WatchedStateSyncSnapshot(records: [remote]),
            localStates: [LocalWatchedState(movie: movie)]
        )

        XCTAssertEqual(resolution.localUpdates.map(\.movieID), [movie.id])
    }

    func testConflictingTMDBIDsDoNotMatchEvenWhenTitleAndYearMatch() {
        let movie = makeMovie(tmdbID: 1091, title: "The Thing", year: 1982)
        let remote = syncedState(
            tmdbID: 60_935,
            title: "The Thing",
            year: 1982,
            isWatched: true,
            modifiedAt: later
        )

        let resolution = WatchedStateSyncResolver.resolve(
            remoteSnapshot: WatchedStateSyncSnapshot(records: [remote]),
            localStates: [LocalWatchedState(movie: movie)]
        )

        XCTAssertTrue(resolution.localUpdates.isEmpty)
        XCTAssertEqual(resolution.snapshot.records, [remote])
    }

    func testUnresolvedMovieDoesNotChooseBetweenConflictingRemoteTMDBIDs() {
        let movie = makeMovie(tmdbID: nil, title: "The Thing", year: 1982)
        let first = syncedState(
            tmdbID: 1091,
            title: "The Thing",
            year: 1982,
            isWatched: true,
            modifiedAt: earlier
        )
        let second = syncedState(
            tmdbID: 60_935,
            title: "The Thing",
            year: 1982,
            isWatched: false,
            modifiedAt: later
        )

        let resolution = WatchedStateSyncResolver.resolve(
            remoteSnapshot: WatchedStateSyncSnapshot(records: [first, second]),
            localStates: [LocalWatchedState(movie: movie)]
        )

        XCTAssertTrue(resolution.localUpdates.isEmpty)
        XCTAssertEqual(
            Set(resolution.snapshot.records.compactMap(\.identity.tmdbID)),
            [1091, 60_935]
        )
    }

    func testUnrelatedRemoteRecordsArePreserved() {
        let movie = makeMovie(tmdbID: 603, title: "The Matrix", year: 1999)
        movie.isWatched = true
        movie.dateWatched = later
        movie.lastWatchedDate = later
        movie.watchedStateModifiedAt = later
        let unrelated = syncedState(
            tmdbID: 13,
            title: "Forrest Gump",
            year: 1994,
            isWatched: true,
            modifiedAt: earlier
        )

        let resolution = WatchedStateSyncResolver.resolve(
            remoteSnapshot: WatchedStateSyncSnapshot(records: [unrelated]),
            localStates: [LocalWatchedState(movie: movie)]
        )

        XCTAssertEqual(resolution.snapshot.records.count, 2)
        XCTAssertTrue(resolution.snapshot.records.contains(unrelated))
    }

    func testLegacyWatchedMovieWithoutSyncTimestampBootstrapsToSnapshot() {
        let movie = makeMovie(tmdbID: 603, title: "The Matrix", year: 1999)
        movie.isWatched = true
        movie.dateWatched = earlier
        movie.lastWatchedDate = later

        let resolution = WatchedStateSyncResolver.resolve(
            remoteSnapshot: WatchedStateSyncSnapshot(),
            localStates: [LocalWatchedState(movie: movie)]
        )

        XCTAssertEqual(resolution.snapshot.records.first?.isWatched, true)
        XCTAssertEqual(resolution.snapshot.records.first?.modifiedAt, later)
    }

    @MainActor
    func testCoordinatorAppliesRemoteStateAndPersistsItLocally() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let movie = makeMovie(tmdbID: 603, title: "The Matrix", year: 1999)
        context.insert(movie)
        try context.save()

        let remote = syncedState(
            tmdbID: 603,
            title: "The Matrix",
            year: 1999,
            isWatched: true,
            modifiedAt: later
        )
        let snapshot = WatchedStateSyncSnapshot(records: [remote])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let store = TestWatchedStateKeyValueStore()
        store.set(
            try encoder.encode(snapshot),
            forKey: "tonight.watchedState.v1"
        )

        WatchedStateSyncCoordinator(keyValueStore: store).reconcile(in: context)

        XCTAssertTrue(movie.isWatched)
        XCTAssertEqual(movie.dateWatched, later)
        XCTAssertEqual(movie.lastWatchedDate, later)
        XCTAssertEqual(movie.watchedStateModifiedAt, later)
        XCTAssertFalse(context.hasChanges)
    }

    private func makeMovie(tmdbID: Int?, title: String, year: Int?) -> Movie {
        Movie(
            tmdbID: tmdbID,
            title: title,
            importedTitle: title,
            importedYear: year,
            releaseYear: year,
            resolutionStatus: tmdbID == nil ? .unresolved : .resolved
        )
    }

    private func syncedState(
        tmdbID: Int?,
        title: String,
        year: Int?,
        isWatched: Bool,
        modifiedAt: Date
    ) -> SyncedWatchedState {
        SyncedWatchedState(
            identity: WatchedStateIdentity(
                tmdbID: tmdbID,
                title: title,
                releaseYear: year
            ),
            isWatched: isWatched,
            dateWatched: isWatched ? modifiedAt : nil,
            lastWatchedDate: isWatched ? modifiedAt : nil,
            modifiedAt: modifiedAt
        )
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Movie.self,
            RecommendationEvent.self,
            configurations: configuration
        )
    }
}

private final class TestWatchedStateKeyValueStore: WatchedStateKeyValueStore {
    private var values: [String: Any] = [:]

    func data(forKey defaultName: String) -> Data? {
        values[defaultName] as? Data
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    func synchronize() -> Bool {
        true
    }
}
