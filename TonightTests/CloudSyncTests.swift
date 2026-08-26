import SwiftData
import XCTest
@testable import Tonight

final class CloudSyncTests: XCTestCase {
    func testCloudConfigurationKeepsDefaultStoreLocation() {
        let localConfiguration = ModelConfiguration(
            schema: TonightModelContainer.schema,
            cloudKitDatabase: .none
        )

        XCTAssertEqual(
            TonightModelContainer.cloudConfiguration().url,
            localConfiguration.url
        )
        XCTAssertEqual(
            TonightModelContainer.cloudKitContainerIdentifier,
            "iCloud.com.donnoel.Tonight"
        )
    }

    @MainActor
    func testReconciliationMergesWatchedAndResolvedCopiesWithoutLosingHistory() throws {
        let container = try ModelContainer(
            for: TonightModelContainer.schema,
            configurations: [TonightModelContainer.inMemoryConfiguration()]
        )
        let context = container.mainContext
        let sharedEventID = UUID()
        let unresolved = Movie(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Mr. Deeds",
            importedYear: 2002
        )
        let resolved = Movie(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            tmdbID: 2022,
            title: "International Release Name",
            importedYear: 2002,
            releaseYear: 2002,
            overviewText: "A resolved overview.",
            posterPath: "/poster.jpg",
            resolutionStatus: .resolved
        )
        let bridge = Movie(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            tmdbID: 2022,
            title: "Mr. Deeds",
            importedYear: 2002,
            releaseYear: 2002,
            resolutionStatus: .resolved
        )
        resolved.isWatched = true
        resolved.dateWatched = Date(timeIntervalSince1970: 100)
        let firstEvent = RecommendationEvent(
            id: sharedEventID,
            movie: unresolved,
            recommendedAt: Date(timeIntervalSince1970: 50),
            kind: .bestMatch,
            response: .pending
        )
        let duplicateEvent = RecommendationEvent(
            id: sharedEventID,
            movie: resolved,
            recommendedAt: Date(timeIntervalSince1970: 50),
            kind: .bestMatch,
            response: .accepted
        )

        context.insert(unresolved)
        context.insert(resolved)
        context.insert(bridge)
        context.insert(firstEvent)
        context.insert(duplicateEvent)
        try context.save()

        XCTAssertTrue(try LibrarySyncReconciler.reconcile(in: context))

        let movies = try context.fetch(FetchDescriptor<Movie>())
        let events = try context.fetch(FetchDescriptor<RecommendationEvent>())
        let movie = try XCTUnwrap(movies.first)
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(movies.count, 1)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(movie.tmdbID, 2022)
        XCTAssertEqual(movie.resolutionStatus, .resolved)
        XCTAssertEqual(movie.posterPath, "/poster.jpg")
        XCTAssertTrue(movie.isWatched)
        XCTAssertEqual(event.response, .accepted)
        XCTAssertTrue(event.movie === movie)
        XCTAssertFalse(try LibrarySyncReconciler.reconcile(in: context))
    }

    func testPreferenceResolutionUsesNewestEnvelope() {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let remote = SyncedPreferencesEnvelope(
            updatedAt: newDate,
            values: ["tonightUnwatchedOnly": .bool(true)]
        )

        XCTAssertEqual(
            SyncedPreferencesResolution.resolve(localUpdatedAt: oldDate, remote: remote),
            .useRemote(remote)
        )
        XCTAssertEqual(
            SyncedPreferencesResolution.resolve(localUpdatedAt: newDate, remote: remote),
            .unchanged
        )
        XCTAssertEqual(
            SyncedPreferencesResolution.resolve(localUpdatedAt: nil, remote: nil),
            .useLocal
        )
    }
}
