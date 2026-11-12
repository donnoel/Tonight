import CoreGraphics
import XCTest
@testable import Tonight

final class ArtworkTintTests: XCTestCase {
    private func image(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return try XCTUnwrap(context.makeImage())
    }

    func testDifferentArtworkProducesDifferentMatchingAccents() throws {
        let red = try XCTUnwrap(ArtworkTint.extract(from: image(red: 1, green: 0.1, blue: 0.1)))
        let blue = try XCTUnwrap(ArtworkTint.extract(from: image(red: 0.1, green: 0.1, blue: 1)))
        XCTAssertGreaterThan(red.red, red.blue)
        XCTAssertGreaterThan(blue.blue, blue.red)
        XCTAssertNotEqual(red, blue)
    }

    func testNeutralAndTransparentArtworkUsesTheFallback() throws {
        for value in [CGFloat(0), 0.5, 1] {
            XCTAssertNil(ArtworkTint.extract(from: try image(red: value, green: value, blue: value)))
        }
        XCTAssertNil(ArtworkTint.extract(from: try image(red: 1, green: 0, blue: 0, alpha: 0)))
    }

    func testSurfaceColorsStayPaleOrDeepAndIncreaseContrastReducesTint() {
        for tint in [ArtworkTint(red: 1, green: 0, blue: 0), ArtworkTint(red: 0, green: 1, blue: 0),
                     ArtworkTint(red: 0, green: 0, blue: 1)] {
            let light = tint.surface(dark: false, increasedContrast: false)
            let dark = tint.surface(dark: true, increasedContrast: false)
            XCTAssertGreaterThanOrEqual(min(light.red, light.green, light.blue), 0.80)
            XCTAssertLessThanOrEqual(max(dark.red, dark.green, dark.blue), 0.23)
            let highContrast = tint.surface(dark: false, increasedContrast: true)
            XCTAssertGreaterThan(min(highContrast.red, highContrast.green, highContrast.blue),
                                 min(light.red, light.green, light.blue))
        }
    }

    func testExtractionIsDeterministic() throws {
        let artwork = try image(red: 0.2, green: 0.8, blue: 0.6)
        XCTAssertEqual(ArtworkTint.extract(from: artwork), ArtworkTint.extract(from: artwork))
    }
}
