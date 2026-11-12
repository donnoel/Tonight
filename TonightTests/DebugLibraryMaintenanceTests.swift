#if DEBUG
import SwiftData
import XCTest
@testable import Tonight

@MainActor
final class DebugLibraryMaintenanceTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Movie.self, RecommendationEvent.self, LibrarySyncEntry.self,
            LibrarySyncState.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    func testExactIDRemovalQueuesTombstoneAndPreservesSameNameMovieAndOtherHistory() throws {
        let container = try container()
        let context = container.mainContext
        let remove = Movie(tmdbID: 10, title: "Same title")
        let keep = Movie(tmdbID: 11, title: "Same title")
        context.insert(remove); context.insert(keep)
        let event = RecommendationEvent(movie: keep, kind: .bestMatch, response: .accepted)
        context.insert(event)
        let state = try LibrarySyncStore.state(in: context)
        try LibrarySyncStore.capture([remove, keep], deleted: [], initial: true, state: state, in: context)
        state.seeded = true
        try context.save()
        let removedID = remove.id
        try DebugLibraryMaintenance.removeMovies(ids: [removedID], in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Movie>()).map(\.id), [keep.id])
        let tombstone = try XCTUnwrap(context.fetch(FetchDescriptor<LibrarySyncEntry>()).first { $0.recordName == "tmdb-10" })
        XCTAssertTrue(try tombstone.document().deleted)
        XCTAssertTrue(tombstone.pendingUpload)
        XCTAssertNil(tombstone.localMovieID)
        XCTAssertTrue(event.movie === keep)
        XCTAssertEqual(event.response, .accepted)
        try DebugLibraryMaintenance.removeMovies(ids: [removedID], in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Movie>()), 1)
    }

    func testPartiallyMissingRequestDoesNotRemoveAnyMovie() throws {
        let container = try container()
        let context = container.mainContext
        let keep = Movie(title: "Keep")
        context.insert(keep)
        try context.save()
        XCTAssertThrowsError(try DebugLibraryMaintenance.removeMovies(ids: [keep.id, UUID()], in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Movie>()), 1)
    }
}
#endif
