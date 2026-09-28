import XCTest
@testable import Tonight

@MainActor
final class DealsViewModelTests: XCTestCase {
    func testRefreshFailureKeepsCachedCatalogAndShowsItsAge() async {
        let cached = DealsTestSupport.snapshot()
        let client = MovieDealsClient(
            loadCached: { cached },
            refresh: { _ in throw TestRetrievalError() }
        )
        let model = DealsViewModel(
            client: client,
            now: { DealsTestSupport.now.addingTimeInterval(24 * 60 * 60) }
        )

        await model.load(library: [], forceRefresh: true)

        XCTAssertEqual(model.snapshot, cached)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.notice?.contains("Showing deals last updated") == true)
        XCTAssertTrue(model.notice?.contains("fixture retrieval failed") == true)
    }

    func testRefreshFailureWithoutCacheShowsRetrievalError() async {
        let client = MovieDealsClient(
            loadCached: { nil },
            refresh: { _ in throw TestRetrievalError() }
        )
        let model = DealsViewModel(client: client)

        await model.load(library: [], forceRefresh: true)

        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.errorMessage, "The fixture retrieval failed.")
        XCTAssertNil(model.notice)
    }
}

private struct TestRetrievalError: LocalizedError {
    var errorDescription: String? { "The fixture retrieval failed." }
}

@MainActor
final class MovieDetailArtworkTests: XCTestCase {
    func testDealArtworkFillsMissingTMDBArtworkOnDetail() throws {
        let appleArtworkURL = try XCTUnwrap(
            URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Video/flow/450x675.jpg")
        )
        let view = MovieDetailView(
            movie: Movie(title: "Flow"),
            showsPersonalization: false,
            dealContext: dealContext(artworkURL: appleArtworkURL)
        )

        XCTAssertEqual(view.posterArtworkURL, appleArtworkURL)
        XCTAssertEqual(view.backdropArtworkURL, appleArtworkURL)
    }

    func testTMDBArtworkTakesPriorityOverDealFallback() throws {
        let appleArtworkURL = try XCTUnwrap(
            URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Video/flow/450x675.jpg")
        )
        let movie = Movie(
            title: "Flow",
            posterPath: "/tmdb-poster.jpg",
            backdropPath: "/tmdb-backdrop.jpg",
            resolutionStatus: .resolved
        )
        let view = MovieDetailView(
            movie: movie,
            showsPersonalization: false,
            dealContext: dealContext(artworkURL: appleArtworkURL)
        )

        XCTAssertEqual(
            view.posterArtworkURL,
            TMDBImageURL.make(path: movie.posterPath, size: .posterDetail)
        )
        XCTAssertEqual(
            view.backdropArtworkURL,
            TMDBImageURL.make(path: movie.backdropPath, size: .backdrop)
        )
    }

    private func dealContext(artworkURL: URL?) -> MovieDealContext {
        MovieDealContext(
            appleURL: URL(string: "https://tv.apple.com/us/movie/flow/umc.cmc.flow")!,
            artworkURL: artworkURL,
            price: "$4.99",
            isInLibrary: false,
            lastRefreshed: Date(timeIntervalSince1970: 0),
            recommendationRationale: nil
        )
    }
}
