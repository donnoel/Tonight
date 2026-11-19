import XCTest
@testable import Tonight

final class AppleTVMovieHandoffTests: XCTestCase {
    @MainActor
    func testSavesChoiceBeforeOpeningVerifiedListing() async throws {
        let url = URL(string: "https://tv.apple.com/us/movie/movie/umc.cmc.test")!
        var actions: [String] = []
        let outcome = try await AppleTVMovieHandoff.open(query: .init(title: "Movie", year: 2000),
            resolve: { _ in actions.append("resolve"); return url },
            choose: { actions.append("save"); return true },
            launch: { destination in
                XCTAssertEqual(destination, url)
                actions.append("open"); return true
            })
        XCTAssertEqual(outcome, .opened)
        XCTAssertEqual(actions, ["resolve", "save", "open"])
    }

    @MainActor
    func testMissingListingDoesNotMarkWatchedOrOpenAnotherMovie() async throws {
        let outcome = try await AppleTVMovieHandoff.open(query: .init(title: "Movie", year: 2000),
            resolve: { _ in nil },
            choose: { XCTFail("No choice should be recorded without a listing"); return true },
            launch: { _ in XCTFail("No listing should open"); return true })
        XCTAssertEqual(outcome, .unavailable)
    }

    @MainActor
    func testSaveFailurePreventsExternalHandoff() async throws {
        let outcome = try await AppleTVMovieHandoff.open(query: .init(title: "Movie", year: 2000),
            resolve: { _ in URL(string: "https://tv.apple.com/us/movie/movie/umc.cmc.test") },
            choose: { false },
            launch: { _ in XCTFail("Keep Tonight open when the choice cannot save"); return true })
        XCTAssertEqual(outcome, .saveFailed)
    }

    @MainActor
    func testLaunchFailureReportsSavedChoiceWithoutClaimingPlayback() async throws {
        var saved = false
        let outcome = try await AppleTVMovieHandoff.open(query: .init(title: "Movie", year: 2000),
            resolve: { _ in URL(string: "https://tv.apple.com/us/movie/movie/umc.cmc.test") },
            choose: { saved = true; return true }, launch: { _ in false })
        XCTAssertTrue(saved)
        XCTAssertEqual(outcome, .openFailed)
    }

    @MainActor
    func testCancelledLookupDoesNotChooseOrLaunch() async {
        do {
            _ = try await AppleTVMovieHandoff.open(query: .init(title: "Movie", year: 2000),
                resolve: { _ in throw CancellationError() },
                choose: { XCTFail("Cancelled lookup must not mark watched"); return true },
                launch: { _ in XCTFail("Cancelled lookup must not open Apple TV"); return true })
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
