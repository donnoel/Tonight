import CloudKit
import XCTest
import SwiftData
@testable import Tonight

@MainActor
final class LibrarySyncTests: XCTestCase {
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Movie.self, RecommendationEvent.self, LibrarySyncEntry.self, LibrarySyncState.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func seed(_ movies: [Movie], in context: ModelContext) throws {
        for movie in movies { context.insert(movie) }
        let state = try LibrarySyncStore.state(in: context)
        try LibrarySyncStore.capture(movies, deleted: [], initial: true, state: state, in: context)
        state.seeded = true
        try LibrarySyncStore.reconcile(in: context)
        try context.save()
    }

    private func movie(_ id: Int? = 238, title: String = "The Godfather", watched: Bool = false) -> Movie {
        let movie = Movie(tmdbID: id, title: title, importedYear: 1972, releaseYear: 1972,
                          overviewText: "A family story", posterPath: "/poster.jpg", backdropPath: "/backdrop.jpg",
                          runtimeMinutes: 175, genres: ["Drama"], director: "Director", primaryCast: ["Actor"],
                          resolutionStatus: id == nil ? .unresolved : .resolved)
        movie.isWatched = watched
        return movie
    }

    private func entries(_ context: ModelContext) throws -> [LibrarySyncEntry] {
        try context.fetch(FetchDescriptor<LibrarySyncEntry>())
    }

    /// Model the CloudKit conflict/fetch boundary without networking or credentials.
    private func exchange(from source: ModelContext, to destination: ModelContext) throws {
        let byName = Dictionary(uniqueKeysWithValues: try entries(destination).map { ($0.recordName, $0) })
        for sourceEntry in try entries(source) {
            let incoming = try sourceEntry.document()
            if let existing = byName[sourceEntry.recordName] {
                try existing.setDocument(try existing.document().merged(with: incoming))
            } else {
                destination.insert(try LibrarySyncEntry(name: sourceEntry.recordName, document: incoming))
            }
        }
        try LibrarySyncStore.reconcile(in: destination)
        try destination.save()
    }

    func testExistingLibrariesMergeWithoutDuplicatingAndKeepRichDetails() throws {
        let left = try container(); let right = try container()
        let rich = movie(watched: true)
        let sparse = movie(); sparse.overviewText = ""; sparse.director = nil; sparse.primaryCast = []
        try seed([rich], in: left.mainContext)
        try seed([sparse, movie(999, title: "Another Film")], in: right.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        for context in [left.mainContext, right.mainContext] {
            let movies = try context.fetch(FetchDescriptor<Movie>())
            XCTAssertEqual(movies.count, 2)
            let merged = try XCTUnwrap(movies.first { $0.tmdbID == 238 })
            XCTAssertTrue(merged.isWatched)
            XCTAssertEqual(merged.director, "Director")
            XCTAssertEqual(merged.posterPath, "/poster.jpg")
            XCTAssertEqual(merged.primaryCast, ["Actor"])
        }
        XCTAssertEqual(sparse.id, try right.mainContext.fetch(FetchDescriptor<Movie>()).first { $0.tmdbID == 238 }?.id)
    }

    func testOfflineWatchAndMetadataChangesMergeIndependently() throws {
        let left = try container(); let right = try container()
        let a = movie(); let b = movie()
        try seed([a], in: left.mainContext); try seed([b], in: right.mainContext)
        a.isWatched = true; a.watchedStateModifiedAt = .now; a.dateWatched = .now
        try LibrarySyncStore.save(left.mainContext)
        b.overviewText = "Corrected description"
        try LibrarySyncStore.save(right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        XCTAssertTrue(a.isWatched); XCTAssertTrue(b.isWatched)
        XCTAssertEqual(a.overviewText, "Corrected description")
        XCTAssertEqual(b.overviewText, "Corrected description")
        b.isWatched = false; b.watchedStateModifiedAt = .now; b.dateWatched = nil
        try LibrarySyncStore.save(right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        XCTAssertFalse(a.isWatched)
    }

    func testDeletionSurvivesStaleDeviceAndExplicitReimportRestores() throws {
        let left = try container(); let right = try container()
        let a = movie(); let b = movie()
        try seed([a], in: left.mainContext); try seed([b], in: right.mainContext)
        left.mainContext.delete(a); try LibrarySyncStore.save(left.mainContext)
        b.isWatched = true; b.watchedStateModifiedAt = .now
        try LibrarySyncStore.save(right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        XCTAssertEqual(try left.mainContext.fetchCount(FetchDescriptor<Movie>()), 0)
        XCTAssertEqual(try right.mainContext.fetchCount(FetchDescriptor<Movie>()), 0)
        let reimport = movie()
        right.mainContext.insert(reimport); try LibrarySyncStore.save(right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        XCTAssertEqual(try left.mainContext.fetchCount(FetchDescriptor<Movie>()), 1)
    }

    func testUnresolvedResolutionKeepsIdentityAndHistoryAndDoesNotReappear() throws {
        let left = try container(); let right = try container()
        let a = movie(nil); let b = movie(nil)
        try seed([a], in: left.mainContext); try seed([b], in: right.mainContext)
        let event = RecommendationEvent(movie: b, kind: .bestMatch)
        right.mainContext.insert(event); try right.mainContext.save()
        a.tmdbID = 238; a.resolutionStatus = .resolved
        try LibrarySyncStore.save(left.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        for context in [left.mainContext, right.mainContext] {
            let movies = try context.fetch(FetchDescriptor<Movie>())
            XCTAssertEqual(movies.count, 1); XCTAssertEqual(movies.first?.tmdbID, 238)
        }
        XCTAssertEqual(event.movie?.tmdbID, 238)
        XCTAssertEqual(event.movie?.id, b.id)
    }

    func testAmbiguousTitleDoesNotMergeDifferentTMDBIdentities() throws {
        let store = try container()
        try seed([movie(1), movie(2), movie(nil)], in: store.mainContext)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<Movie>()), 3)
    }

    func testMissingYearMergesOnlyWhenThereIsOneResolvedCandidate() throws {
        let store = try container()
        let unknown = movie(nil); unknown.importedYear = nil; unknown.releaseYear = nil
        try seed([movie(), unknown], in: store.mainContext)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<Movie>()), 1)
        let ambiguousStore = try container()
        let remake = movie(999); remake.importedYear = 2000; remake.releaseYear = 2000
        let ambiguous = movie(nil); ambiguous.importedYear = nil; ambiguous.releaseYear = nil
        try seed([movie(), remake, ambiguous], in: ambiguousStore.mainContext)
        XCTAssertEqual(try ambiguousStore.mainContext.fetchCount(FetchDescriptor<Movie>()), 3)
    }

    func testUnknownCopyCannotResurrectDeletedResolvedTitle() throws {
        let left = try container(); let right = try container()
        let a = movie(); let b = movie(nil)
        try seed([a], in: left.mainContext); try seed([b], in: right.mainContext)
        left.mainContext.delete(a); try LibrarySyncStore.save(left.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        XCTAssertEqual(try right.mainContext.fetchCount(FetchDescriptor<Movie>()), 0)
    }

    func testSavedOutboxAndMovieSurviveRelaunchTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.store")
        do {
            let store = try container(url: url)
            let a = movie(); try seed([a], in: store.mainContext)
            a.isWatched = true; a.watchedStateModifiedAt = .now
            try LibrarySyncStore.save(store.mainContext)
        }
        let restored = try container(url: url)
        XCTAssertTrue(try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<Movie>()).first).isWatched)
        let entry = try XCTUnwrap(entries(restored.mainContext).first)
        XCTAssertTrue(entry.pendingUpload); XCTAssertTrue(try entry.document().movie.watched.isWatched)
    }

    func testAdditiveMigrationPreservesOriginalLibraryAndHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.store")
        let id: UUID
        do {
            let old = try ModelContainer(for: Movie.self, RecommendationEvent.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let a = movie(watched: true); id = a.id
            old.mainContext.insert(a)
            old.mainContext.insert(RecommendationEvent(movie: a, kind: .bestMatch))
            try old.mainContext.save()
        }
        let updated = try container(url: url)
        let a = try XCTUnwrap(updated.mainContext.fetch(FetchDescriptor<Movie>()).first)
        XCTAssertEqual(a.id, id); XCTAssertTrue(a.isWatched)
        XCTAssertEqual(try updated.mainContext.fetch(FetchDescriptor<RecommendationEvent>()).first?.movie?.id, id)
    }

    func testMergeIsCommutativeAndIdempotent() {
        let a = movie(); let b = movie(watched: true); b.posterPath = nil
        let left = LibrarySyncDocument(movie: SyncedLibraryMovie(movie: a), revision: .initial, initial: true)
        let right = LibrarySyncDocument(movie: SyncedLibraryMovie(movie: b), revision: .initial, initial: true)
        XCTAssertEqual(left.merged(with: right), right.merged(with: left))
        let merged = left.merged(with: right)
        XCTAssertEqual(merged.merged(with: left), merged)
        XCTAssertTrue(merged.movie.watched.isWatched)
        XCTAssertEqual(merged.movie.details.posterPath, "/poster.jpg")
    }

    func testOfflineWatchEditFollowsAResolvedAlias() throws {
        let left = try container(); let right = try container()
        let a = movie(nil); let b = movie(nil)
        try seed([a], in: left.mainContext); try seed([b], in: right.mainContext)
        a.tmdbID = 238; a.resolutionStatus = .resolved
        try LibrarySyncStore.save(left.mainContext)
        b.isWatched = true; b.watchedStateModifiedAt = .now
        try LibrarySyncStore.save(right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        XCTAssertTrue(a.isWatched)
        XCTAssertTrue(try XCTUnwrap(right.mainContext.fetch(FetchDescriptor<Movie>()).first).isWatched)
    }

    func testResolutionChainsPreserveRemoteIdentity() throws {
        let left = try container(); let right = try container()
        let a = movie(nil); let b = movie(nil)
        try seed([a], in: left.mainContext); try seed([b], in: right.mainContext)
        a.tmdbID = 238; a.resolutionStatus = .resolved; try LibrarySyncStore.save(left.mainContext)
        a.tmdbID = 999; try LibrarySyncStore.save(left.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        let movies = try right.mainContext.fetch(FetchDescriptor<Movie>())
        XCTAssertEqual(movies.count, 1); XCTAssertEqual(movies.first?.id, b.id)
        XCTAssertEqual(movies.first?.tmdbID, 999)
    }

    func testRepeatedReconciliationDoesNotRequeueAcknowledgedRecords() throws {
        let store = try container()
        try seed([movie()], in: store.mainContext)
        let entry = try XCTUnwrap(entries(store.mainContext).first)
        entry.pendingUpload = false; try store.mainContext.save()
        for _ in 0..<5 {
            try LibrarySyncStore.reconcile(in: store.mainContext)
            try store.mainContext.save()
            XCTAssertFalse(entry.pendingUpload)
        }
    }

    func testAcknowledgedQueuePrefixCannotStarveLaterUploads() {
        let stale: [CKSyncEngine.PendingRecordZoneChange] = (0..<100).map {
            .saveRecord(CKRecord.ID(recordName: "old-\($0)"))
        }
        let pending = CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: "pending"))
        let active = LibrarySyncUploadQueue.activeSaves(stale + [pending], recordNames: ["pending"])
        XCTAssertEqual(Array(active.prefix(100)), [pending])
    }

    func testRecommendationOnlyEditsDoNotQueueMovieUpload() throws {
        let store = try container(); let a = movie()
        try seed([a], in: store.mainContext)
        let entry = try XCTUnwrap(entries(store.mainContext).first)
        entry.pendingUpload = false; try store.mainContext.save()
        a.recommendationCount += 1; a.lastRecommendedDate = .now
        try LibrarySyncStore.save(store.mainContext)
        XCTAssertFalse(entry.pendingUpload)
    }

    private func recordPicks(in context: ModelContext, at date: Date) throws -> [Int] {
        let movies = try context.fetch(FetchDescriptor<Movie>())
        let history = try context.fetch(FetchDescriptor<RecommendationEvent>())
        let batch = RecommendationEngine.nextBatch(from: movies, history: history, now: date, seed: 7)
        for pick in batch.picks {
            let event = RecommendationEvent(movie: pick.movie, recommendedAt: date, kind: pick.kind,
                rotationID: batch.rotationID, browsingGeneration: batch.browsingGeneration)
            context.insert(event)
            pick.movie.browsingProgress = LibraryBrowsingProgress(generation: batch.browsingGeneration,
                shownAt: date, eventID: event.id)
        }
        try LibrarySyncStore.save(context)
        return batch.picks.compactMap(\.movie.tmdbID)
    }

    func testEngineConfigurationMigrationPreservesLibraryAndPendingProgress() throws {
        let store = try container()
        try seed([movie()], in: store.mainContext)
        _ = try recordPicks(in: store.mainContext, at: .now)
        let state = try LibrarySyncStore.state(in: store.mainContext)
        state.engineState = Data("legacy subscription".utf8)
        state.accountID = "original-account"
        let documents = try entries(store.mainContext).map { try $0.document() }
        state.prepareEngineConfiguration()
        XCTAssertNil(state.engineState)
        XCTAssertEqual(state.accountID, "original-account")
        XCTAssertTrue(state.seeded)
        XCTAssertEqual(try entries(store.mainContext).map { try $0.document() }, documents)
        XCTAssertTrue(try XCTUnwrap(entries(store.mainContext).first).pendingUpload)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<Movie>()), 1)
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<RecommendationEvent>()), 1)
        state.engineState = Data("current subscription".utf8)
        state.prepareEngineConfiguration()
        XCTAssertEqual(state.engineState, Data("current subscription".utf8))
    }

    private func remaining(in context: ModelContext) throws -> Set<Int> {
        Set(RecommendationEngine.recommendationPool(
            from: try context.fetch(FetchDescriptor<Movie>()),
            history: try context.fetch(FetchDescriptor<RecommendationEvent>()),
            preferences: RecommendationPreferences()).movies.compactMap(\.tmdbID))
    }

    func testBrowsingProgressUnionsLegacyDevicesWithoutSyncingTheirHistory() throws {
        let left = try container(); let right = try container()
        let a = (1...10).map { (id: Int) in movie(id, title: "Movie \(id)") }
        let b = (1...10).map { (id: Int) in movie(id, title: "Movie \(id)") }
        try seed(a, in: left.mainContext); try seed(b, in: right.mainContext)
        for item in a.prefix(3) {
            left.mainContext.insert(RecommendationEvent(movie: item, kind: .bestMatch))
        }
        for item in b[2..<7] {
            right.mainContext.insert(RecommendationEvent(movie: item, kind: .bestMatch))
        }
        try LibrarySyncStore.save(left.mainContext); try LibrarySyncStore.save(right.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        XCTAssertEqual(try remaining(in: left.mainContext), Set(8...10))
        XCTAssertEqual(try remaining(in: right.mainContext), Set(8...10))
        XCTAssertEqual(try left.mainContext.fetchCount(FetchDescriptor<RecommendationEvent>()), 3)
        XCTAssertEqual(try right.mainContext.fetchCount(FetchDescriptor<RecommendationEvent>()), 5)
        XCTAssertEqual(try left.mainContext.fetchCount(FetchDescriptor<Movie>()), 10)
        for item in try entries(left.mainContext) { item.pendingUpload = false }
        try left.mainContext.save()
        try LibrarySyncStore.save(left.mainContext)
        XCTAssertFalse(try entries(left.mainContext).contains { $0.pendingUpload })
    }

    func testAlternatingDevicesShowsAllTenBeforeRepeatingAndContinuesAutomatically() throws {
        let left = try container(); let right = try container()
        try seed((1...10).map { (id: Int) in movie(id, title: "Movie \(id)") }, in: left.mainContext)
        try seed((1...10).map { (id: Int) in movie(id, title: "Movie \(id)") }, in: right.mainContext)
        var picked: [Int] = []
        for index in 0..<8 {
            let source = index.isMultiple(of: 2) ? left.mainContext : right.mainContext
            let destination = index.isMultiple(of: 2) ? right.mainContext : left.mainContext
            let titles = try recordPicks(in: source, at: Date(timeIntervalSince1970: 2_000_000_000 + Double(index)))
            XCTAssertEqual(titles.count, index % 4 == 3 ? 1 : 3)
            picked += titles
            try exchange(from: source, to: destination)
            try exchange(from: destination, to: source)
            XCTAssertEqual(try remaining(in: source), try remaining(in: destination))
        }
        XCTAssertEqual(picked.count, 20)
        XCTAssertEqual(Set(picked.prefix(10)), Set(1...10))
        XCTAssertEqual(Set(picked.suffix(10)), Set(1...10))
    }

    func testOfflineBrowsingAndMovieEditsMergeWithoutRewindingProgress() throws {
        let left = try container(); let right = try container()
        let a = movie(); let b = movie()
        try seed([a], in: left.mainContext); try seed([b], in: right.mainContext)
        let newer = LibraryBrowsingProgress(generation: 2, shownAt: Date(timeIntervalSince1970: 100), eventID: UUID())
        a.browsingProgress = newer
        b.browsingProgress = LibraryBrowsingProgress(generation: 1, shownAt: Date(timeIntervalSince1970: 999), eventID: UUID())
        b.isWatched = true; b.watchedStateModifiedAt = .now; b.overviewText = "Updated elsewhere"
        try LibrarySyncStore.save(left.mainContext); try LibrarySyncStore.save(right.mainContext)
        try exchange(from: right.mainContext, to: left.mainContext)
        try exchange(from: left.mainContext, to: right.mainContext)
        XCTAssertEqual(a.browsingProgress, newer); XCTAssertEqual(b.browsingProgress, newer)
        XCTAssertTrue(a.isWatched); XCTAssertEqual(a.overviewText, "Updated elsewhere")
        let aProgress = LibraryBrowsingProgress(generation: 3, shownAt: .now, eventID: UUID())
        let bProgress = LibraryBrowsingProgress(generation: 3, shownAt: aProgress.shownAt, eventID: UUID())
        XCTAssertEqual(LibraryBrowsingProgress.merged(aProgress, bProgress),
                       LibraryBrowsingProgress.merged(bProgress, aProgress))
        XCTAssertEqual(LibraryBrowsingProgress.merged(newer, newer), newer)
    }

    func testBrowsingOutboxSurvivesRelaunchAndOlderPayloadsCannotEraseProgress() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("browsing.store")
        var expected: LibraryBrowsingProgress?
        do {
            let local = try container(url: url); let item = movie()
            try seed([item], in: local.mainContext)
            for entry in try entries(local.mainContext) { entry.pendingUpload = false }
            _ = try recordPicks(in: local.mainContext, at: .now)
            expected = item.browsingProgress
        }
        let reopened = try container(url: url)
        let entry = try XCTUnwrap(entries(reopened.mainContext).first)
        XCTAssertTrue(entry.pendingUpload)
        XCTAssertEqual(try entry.document().movie.browsing, expected)
        let document = try entry.document()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LibrarySyncCoding.encode(document)) as? [String: Any])
        var movieJSON = try XCTUnwrap(json["movie"] as? [String: Any])
        movieJSON.removeValue(forKey: "browsing"); json["movie"] = movieJSON
        let old = try JSONDecoder().decode(LibrarySyncDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.movie.browsing)
        XCTAssertEqual(document.merged(with: old).movie.browsing, expected)
        XCTAssertEqual(old.merged(with: document).movie.browsing, expected)
    }
}
