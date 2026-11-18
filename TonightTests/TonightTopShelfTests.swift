import SwiftData
import XCTest
@testable import Tonight

final class TonightTopShelfTests: XCTestCase {
    func testMovieRoutesRoundTripAndRejectMalformedLinks() {
        let id = UUID()
        XCTAssertEqual(TonightMovieRoute(url: TonightMovieRoute.movie(id).url), .movie(id))
        XCTAssertEqual(TonightMovieRoute(url: TonightMovieRoute.picks.url), .picks)
        for url in ["https://movie/\(id)", "tonight://movie/no-id", "tonight://movie/\(id)/extra",
                    "tonight://movie/\(id)?choose=true", "tonight://movie", "tonight://unknown"] {
            XCTAssertNil(TonightMovieRoute(url: URL(string: url)!))
        }
    }

    func testShelfPreservesPrimaryPicksAndAddsTwoDistinctOwnedMovies() {
        let movies = (0..<8).map { movie("Movie \($0)", id: $0 + 1) }
        let date = Date.now
        let events = zip(movies.prefix(3), [RecommendationKind.bestMatch, .hiddenGem, .deepCut]).map {
            RecommendationEvent(movie: $0.0, recommendedAt: date, kind: $0.1)
        }
        let result = TonightTopShelfSelection.picks(events: events, library: movies, preferences: .init())
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.prefix(3).map(\.id), movies.prefix(3).map(\.id))
        XCTAssertEqual(Set(result.map(\.id)).count, 5)
        XCTAssertTrue(result.allSatisfy { movies.contains($0.movie) })
        XCTAssertTrue(events.allSatisfy { $0.response == .pending })
        XCTAssertTrue(movies.allSatisfy { !$0.isWatched && $0.recommendationCount == 0 })
    }

    func testSparseShelfNeverPadsWithUnresolvedDislikedWatchedOrOffMoodMovies() {
        let first = movie("First", id: 1)
        let unresolved = movie("Unresolved", id: 2); unresolved.resolutionStatus = .unresolved
        let disliked = movie("Disliked", id: 3); disliked.isDisliked = true
        let watched = movie("Watched", id: 4); watched.isWatched = true
        let horror = movie("Horror", id: 5); horror.genres = ["Horror"]
        let event = RecommendationEvent(movie: first, kind: .bestMatch, mood: .funAndEasy)
        let result = TonightTopShelfSelection.picks(events: [event],
            library: [first, unresolved, disliked, watched, horror], preferences: .init(mood: .funAndEasy))
        XCTAssertEqual(result.map(\.id), [first.id])
        XCTAssertTrue(TonightTopShelfSelection.picks(events: [], library: [first], preferences: .init()).isEmpty)
    }

    @MainActor func testOpeningSupplementalMovieDoesNotCreateHistoryOrMarkWatched() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let movie = movie("Alternative", id: 1); context.insert(movie); try context.save()
        let selection = TonightTopShelfMovieSelection(movie: movie, history: [], preferences: .init())
        XCTAssertNotNil(selection.event)
        XCTAssertNil(selection.event?.modelContext)
        XCTAssertFalse(movie.isWatched)
        XCTAssertTrue(try context.fetch(FetchDescriptor<RecommendationEvent>()).isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor func testExplicitChoosePersistsExactMovieAndResponse() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let chosen = movie("Chosen", id: 1), other = movie("Other", id: 2)
        context.insert(chosen); context.insert(other)
        let otherEvent = RecommendationEvent(movie: other, kind: .bestMatch)
        context.insert(otherEvent); try context.save()
        let selection = TonightTopShelfMovieSelection(movie: chosen, history: [otherEvent], preferences: .init())
        selection.respond(.accepted, in: context)
        XCTAssertNil(selection.saveError)
        XCTAssertTrue(chosen.isWatched)
        XCTAssertFalse(other.isWatched)
        XCTAssertEqual(selection.event?.response, .accepted)
        XCTAssertEqual(otherEvent.response, .notTonight)
        XCTAssertNotNil(selection.event?.respondedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RecommendationEvent>()).count, 2)
        selection.respond(.accepted, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RecommendationEvent>()).count, 2)
    }

    @MainActor func testCurrentPickReusesEventAndWatchedStalePickDoesNotOfferChoose() {
        let movie = movie("Current", id: 1)
        let event = RecommendationEvent(movie: movie, kind: .bestMatch)
        let selection = TonightTopShelfMovieSelection(movie: movie, history: [event], preferences: .init())
        XCTAssertTrue(selection.event === event)
        movie.isWatched = true
        XCTAssertNil(TonightTopShelfMovieSelection(movie: movie, history: [event], preferences: .init()).event)
    }

    @MainActor func testRemovedMovieRouteReturnsNoDestinationWithoutChangingLibrary() throws {
        let container = try container()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let movie = movie("Removed", id: 1)
        context.insert(movie); try context.save()
        let id = movie.id
        context.delete(movie); try context.save()
        XCTAssertNil(try TonightTopShelfMovieSelection.open(id: id, in: context, preferences: .init()))
        XCTAssertFalse(context.hasChanges)
    }

    func testSinglePrimaryCanStillFillFiveSlots() {
        let movies = (0..<6).map { movie("Movie \($0)", id: $0 + 1) }
        let event = RecommendationEvent(movie: movies[0], kind: .bestMatch)
        let result = TonightTopShelfSelection.picks(events: [event], library: movies, preferences: .init())
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(Set(result.map(\.id)).count, 5)
    }

    private func movie(_ title: String, id: Int) -> Movie {
        Movie(tmdbID: id, title: title, importedTitle: title, releaseYear: 2000,
              runtimeMinutes: 100, genres: ["Comedy"], tmdbVoteAverage: 7, tmdbVoteCount: 1_000,
              resolutionStatus: .resolved)
    }

    @MainActor private func container() throws -> ModelContainer {
        let schema = Schema([Movie.self, RecommendationEvent.self])
        return try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
}
