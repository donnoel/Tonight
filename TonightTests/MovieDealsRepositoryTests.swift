import Foundation
import XCTest
@testable import Tonight

final class MovieDealsRepositoryTests: XCTestCase {
    func testReusesLocalMetadataAndOnlyHandsUnknownTitlesToTMDB() async throws {
        let localDeal = DealsTestSupport.appleDeal(
            title: "Local Match",
            identifier: "umc.cmc.local"
        )
        let unknownDeal = DealsTestSupport.appleDeal(
            title: "Unknown Match",
            identifier: "umc.cmc.unknown",
            position: 1
        )
        let provider = StubAppleMovieDealsProvider(deals: [localDeal, unknownDeal])
        let recorder = EnrichmentRecorder()
        let enricher = DealTMDBEnricher { deal, token in
            await recorder.record(title: deal.title, token: token)
            return .unresolved("No confident fixture match.")
        }
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cache = MovieDealsCache(
            fileURL: directoryURL.appending(path: "deals.json")
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let localMovie = Movie(
            tmdbID: 77,
            title: "Local Match",
            releaseYear: 1999,
            overviewText: "Already cached in Tonight",
            genres: ["Drama"],
            resolutionStatus: .resolved
        )
        let localSnapshot = try XCTUnwrap(LibraryMovieSnapshot(movie: localMovie))
        let repository = MovieDealsRepository(
            provider: provider,
            cache: cache,
            enricher: enricher,
            readCredential: { "fixture-token" },
            now: { DealsTestSupport.now }
        )

        let snapshot = try await repository.refresh(library: [localSnapshot])
        let calls = await recorder.calls
        let cachedSnapshot = await cache.load()

        XCTAssertEqual(calls, [EnrichmentCall(title: "Unknown Match", token: "fixture-token")])
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].metadata?.tmdbID, 77)
        XCTAssertEqual(snapshot.items[0].matchStatus, .matched)
        XCTAssertEqual(snapshot.items[1].matchStatus, .unresolved)
        XCTAssertEqual(snapshot.enrichmentState, .partial)
        XCTAssertEqual(cachedSnapshot, snapshot)
    }

    func testMissingCredentialPreservesEveryAppleDeal() async throws {
        let deals = [
            DealsTestSupport.appleDeal(title: "One", identifier: "umc.cmc.one"),
            DealsTestSupport.appleDeal(
                title: "Two",
                identifier: "umc.cmc.two",
                position: 1
            )
        ]
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let cache = MovieDealsCache(
            fileURL: directoryURL.appending(path: "deals.json")
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = MovieDealsRepository(
            provider: StubAppleMovieDealsProvider(deals: deals),
            cache: cache,
            enricher: DealTMDBEnricher { _, _ in
                XCTFail("TMDB enrichment should not run without a token")
                return .unresolved("Unexpected")
            },
            readCredential: { nil },
            now: { DealsTestSupport.now }
        )

        let snapshot = try await repository.refresh(library: [])

        XCTAssertEqual(snapshot.items.map(\.appleDeal.title), ["One", "Two"])
        XCTAssertTrue(snapshot.items.allSatisfy { $0.matchStatus == .unavailable })
        XCTAssertEqual(snapshot.enrichmentState, .unavailable)
    }
}

private struct StubAppleMovieDealsProvider: AppleMovieDealsProviding {
    let deals: [AppleMovieDeal]

    func fetchDeals() async throws -> [AppleMovieDeal] {
        deals
    }
}

private struct EnrichmentCall: Equatable, Sendable {
    let title: String
    let token: String
}

private actor EnrichmentRecorder {
    private(set) var calls: [EnrichmentCall] = []

    func record(title: String, token: String) {
        calls.append(EnrichmentCall(title: title, token: token))
    }
}
