import XCTest
@testable import Tonight

final class TonightWidgetSnapshotStoreTests: XCTestCase {
    func testSnapshotRoundTripsThroughSharedStoreFormat() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = TonightWidgetSnapshotStore(directoryURL: directoryURL)
        let snapshot = TonightWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 2_000_000_000),
            picks: [
                TonightWidgetPick(
                    id: UUID(),
                    kindTitle: "Best Fit",
                    title: "Test Movie",
                    metadata: "2001 · 1h 42m · Drama",
                    rationale: "A focused test pick.",
                    artworkURL: URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg"),
                    artworkData: Data([0x01, 0x02, 0x03])
                )
            ]
        )

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }

    func testRemovingMoviePreservesRemainingPicksAndGenerationDate() {
        let firstID = UUID()
        let secondID = UUID()
        let generatedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = TonightWidgetSnapshot(
            generatedAt: generatedAt,
            picks: [
                pick(id: firstID, title: "First"),
                pick(id: secondID, title: "Second")
            ]
        )

        let updated = snapshot.removingMovie(id: firstID)

        XCTAssertEqual(updated.generatedAt, generatedAt)
        XCTAssertEqual(updated.picks.map(\.id), [secondID])
    }

    private func pick(id: UUID, title: String) -> TonightWidgetPick {
        TonightWidgetPick(
            id: id,
            kindTitle: "Best Fit",
            title: title,
            metadata: "2001",
            rationale: "Test rationale",
            artworkURL: nil,
            artworkData: nil
        )
    }
}
