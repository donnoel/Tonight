import SwiftData
import XCTest
@testable import Tonight

final class LocalLibraryDuplicateRepairTests: XCTestCase {
    @MainActor
    func testRepairConsolidatesOneResolvedDuplicateAndPreservesHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let unresolved = Movie(
            title: "Alien 3",
            importedTitle: "Alien 3",
            resolutionStatus: .unresolved
        )
        unresolved.isWatched = true
        unresolved.dateWatched = Date(timeIntervalSince1970: 200)
        unresolved.watchedStateModifiedAt = Date(timeIntervalSince1970: 300)
        unresolved.userRating = 4.5
        let resolved = Movie(
            tmdbID: 8077,
            title: "Alien³",
            importedTitle: "Alien 3",
            releaseYear: 1992,
            overviewText: "Resolved metadata",
            posterPath: "/poster.jpg",
            resolutionStatus: .resolved
        )
        let event = RecommendationEvent(
            movie: unresolved,
            kind: .bestMatch,
            response: .watched
        )
        context.insert(unresolved)
        context.insert(resolved)
        context.insert(event)
        try context.save()

        let summary = try LocalLibraryDuplicateRepair.repair(in: context)
        let movies = try context.fetch(FetchDescriptor<Movie>())
        let savedEvent = try XCTUnwrap(
            context.fetch(FetchDescriptor<RecommendationEvent>()).first
        )
        let savedMovie = try XCTUnwrap(movies.first)

        XCTAssertEqual(summary.consolidatedMovies, 1)
        XCTAssertEqual(movies.count, 1)
        XCTAssertEqual(savedMovie.tmdbID, 8077)
        XCTAssertEqual(savedMovie.resolutionStatus, .resolved)
        XCTAssertEqual(savedMovie.posterPath, "/poster.jpg")
        XCTAssertTrue(savedMovie.isWatched)
        XCTAssertEqual(savedMovie.watchedStateModifiedAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(savedMovie.userRating, 4.5)
        XCTAssertTrue(savedEvent.movie === savedMovie)
        XCTAssertEqual(
            try LocalLibraryDuplicateRepair.repair(in: context).consolidatedMovies,
            0
        )
    }

    @MainActor
    func testRepairLeavesAmbiguousRemakesForManualChoice() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(
            Movie(
                title: "The Thing",
                importedTitle: "The Thing",
                resolutionStatus: .unresolved
            )
        )
        context.insert(
            Movie(
                tmdbID: 1091,
                title: "The Thing",
                importedTitle: "The Thing",
                releaseYear: 1982,
                resolutionStatus: .resolved
            )
        )
        context.insert(
            Movie(
                tmdbID: 60935,
                title: "The Thing",
                importedTitle: "The Thing",
                releaseYear: 2011,
                resolutionStatus: .resolved
            )
        )
        try context.save()

        let summary = try LocalLibraryDuplicateRepair.repair(in: context)

        XCTAssertEqual(summary.consolidatedMovies, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Movie>()), 3)
    }

    @MainActor
    func testConsolidationPreservesNewerExplicitUnwatchedState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let watchedDuplicate = Movie(
            title: "Alien 3",
            importedTitle: "Alien 3",
            resolutionStatus: .unresolved
        )
        watchedDuplicate.isWatched = true
        watchedDuplicate.dateWatched = Date(timeIntervalSince1970: 100)
        watchedDuplicate.lastWatchedDate = Date(timeIntervalSince1970: 100)
        watchedDuplicate.watchedStateModifiedAt = Date(timeIntervalSince1970: 100)
        let resolved = Movie(
            tmdbID: 8077,
            title: "Alien³",
            importedTitle: "Alien 3",
            releaseYear: 1992,
            resolutionStatus: .resolved
        )
        resolved.isWatched = false
        resolved.watchedStateModifiedAt = Date(timeIntervalSince1970: 200)
        context.insert(watchedDuplicate)
        context.insert(resolved)
        try context.save()

        try LocalLibraryDuplicateRepair.consolidate(
            watchedDuplicate,
            into: resolved,
            in: context
        )

        XCTAssertFalse(resolved.isWatched)
        XCTAssertNil(resolved.dateWatched)
        XCTAssertNil(resolved.lastWatchedDate)
        XCTAssertEqual(resolved.watchedStateModifiedAt, Date(timeIntervalSince1970: 200))
    }

    @MainActor
    func testRepairUsesImportedYearToDisambiguateRemakes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(
            Movie(
                title: "The Thing",
                importedTitle: "The Thing",
                importedYear: 1982,
                resolutionStatus: .unresolved
            )
        )
        context.insert(
            Movie(
                tmdbID: 1091,
                title: "The Thing",
                importedTitle: "The Thing",
                importedYear: 1982,
                releaseYear: 1982,
                resolutionStatus: .resolved
            )
        )
        context.insert(
            Movie(
                tmdbID: 60935,
                title: "The Thing",
                importedTitle: "The Thing",
                importedYear: 2011,
                releaseYear: 2011,
                resolutionStatus: .resolved
            )
        )
        try context.save()

        let summary = try LocalLibraryDuplicateRepair.repair(in: context)
        let movies = try context.fetch(FetchDescriptor<Movie>())

        XCTAssertEqual(summary.consolidatedMovies, 1)
        XCTAssertEqual(movies.count, 2)
        XCTAssertFalse(movies.contains { $0.resolutionStatus != .resolved })
    }

    @MainActor
    func testRepairDoesNotMergeConflictingKnownYears() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(
            Movie(
                title: "The Thing",
                importedTitle: "The Thing",
                importedYear: 1982,
                resolutionStatus: .unresolved
            )
        )
        context.insert(
            Movie(
                tmdbID: 60935,
                title: "The Thing",
                importedTitle: "The Thing",
                releaseYear: 2011,
                resolutionStatus: .resolved
            )
        )
        try context.save()

        let summary = try LocalLibraryDuplicateRepair.repair(in: context)

        XCTAssertEqual(summary.consolidatedMovies, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Movie>()), 2)
    }

    @MainActor
    func testConfirmedCollisionConsolidatesDifferentImportedTitles() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let unresolved = Movie(
            title: "Lock",
            importedTitle: "Lock",
            resolutionStatus: .unresolved
        )
        let resolved = Movie(
            tmdbID: 100,
            title: "Lock, Stock and Two Smoking Barrels",
            importedTitle: "Stock and Two Smoking Barrels",
            releaseYear: 1998,
            resolutionStatus: .resolved
        )
        context.insert(unresolved)
        context.insert(resolved)
        try context.save()

        try LocalLibraryDuplicateRepair.consolidate(
            unresolved,
            into: resolved,
            in: context
        )

        let movies = try context.fetch(FetchDescriptor<Movie>())
        XCTAssertEqual(movies.count, 1)
        XCTAssertEqual(movies.first?.tmdbID, 100)
        XCTAssertEqual(movies.first?.resolutionStatus, .resolved)
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
