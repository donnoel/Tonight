import XCTest
@testable import Tonight

final class TMDBCredentialStoreTests: XCTestCase {
    func testNormalizedTokenTrimsSurroundingWhitespace() {
        XCTAssertEqual(
            TMDBCredentialStore.normalizedToken("  example-token\n"),
            "example-token"
        )
    }

    func testNormalizedTokenRejectsEmptyInput() {
        XCTAssertNil(TMDBCredentialStore.normalizedToken(" \n\t "))
    }

    func testNormalizedTokenRemovesAccidentalBearerPrefix() {
        XCTAssertEqual(
            TMDBCredentialStore.normalizedToken("Bearer example-token"),
            "example-token"
        )
    }
}
