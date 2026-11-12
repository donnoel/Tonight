import SwiftData
import XCTest
@testable import Tonight

final class MovieViewingHistoryTests: XCTestCase {
    func testOnlyExplicitViewingResponsesAppearWithoutDeletingExposureHistory() {
        let events = RecommendationResponse.allCases.map {
            RecommendationEvent(kind: .bestMatch, response: $0)
        }
        let history = MovieViewingHistory.entries(events: events, watchedMovies: [])
        XCTAssertEqual(Set(history.map(\.response)), [.accepted, .watched])
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(events.count, RecommendationResponse.allCases.count)
    }

    func testResponseDateDeterminesOrderAndSurvivesLaterMovieWatchChanges() {
        let movie = Movie(title: "A movie")
        let oldOffer = RecommendationEvent(movie: movie,
            recommendedAt: Date(timeIntervalSince1970: 10), kind: .bestMatch)
        oldOffer.recordResponse(.accepted, at: Date(timeIntervalSince1970: 300))
        let newerOffer = RecommendationEvent(recommendedAt: Date(timeIntervalSince1970: 200),
                                            kind: .deepCut, response: .watched)
        movie.lastWatchedDate = Date(timeIntervalSince1970: 500)
        let history = MovieViewingHistory.entries(events: [newerOffer, oldOffer], watchedMovies: [])
        XCTAssertEqual(history.map(\.date), [Date(timeIntervalSince1970: 300), Date(timeIntervalSince1970: 200)])
        XCTAssertTrue(movie.isWatched)
        XCTAssertEqual(oldOffer.response, .accepted)
    }

    func testLibraryWatchAppearsAndMatchingRecommendationIsNotDuplicated() {
        let movie = Movie(title: "Library movie")
        let event = RecommendationEvent(movie: movie, kind: .bestMatch)
        event.recordResponse(.watched, at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(MovieViewingHistory.entries(events: [], watchedMovies: [movie]).count, 1)
        XCTAssertEqual(MovieViewingHistory.entries(events: [event], watchedMovies: [movie]).count, 1)
        movie.lastWatchedDate = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(MovieViewingHistory.entries(events: [event], watchedMovies: [movie]).count, 2)
        movie.isWatched = false
        XCTAssertTrue(MovieViewingHistory.entries(events: [], watchedMovies: [movie]).isEmpty)
    }

    func testLegacyResponseUsesOriginalDateWithoutDuplicatingMutableWatchState() {
        let movie = Movie(title: "Legacy")
        movie.isWatched = true
        movie.lastWatchedDate = Date(timeIntervalSince1970: 200)
        let event = RecommendationEvent(movie: movie, recommendedAt: Date(timeIntervalSince1970: 100),
                                        kind: .deepCut, response: .accepted)
        let history = MovieViewingHistory.entries(events: [event], watchedMovies: [movie])
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.date, event.recommendedAt)
        XCTAssertNil(event.respondedAt)
    }

    @MainActor
    func testResponseTimestampPersistsAfterStoreReopens() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let date = Date(timeIntervalSince1970: 500)
        do {
            let container = try ModelContainer(for: Movie.self, RecommendationEvent.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let event = RecommendationEvent(movie: Movie(title: "Persisted"), kind: .bestMatch)
            container.mainContext.insert(event)
            event.recordResponse(.accepted, at: date)
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: Movie.self, RecommendationEvent.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let event = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<RecommendationEvent>()).first)
        XCTAssertEqual(event.respondedAt, date)
        XCTAssertEqual(event.response, .accepted)
        XCTAssertTrue(try XCTUnwrap(event.movie).isWatched)
        XCTAssertEqual(MovieViewingHistory.entries(events: [event], watchedMovies: []).first?.date, date)
    }
}
