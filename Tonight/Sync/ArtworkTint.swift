import CoreGraphics
import Foundation

/// A small, sendable color value; extraction never decodes full-size artwork on the UI actor.
struct ArtworkTint: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let fallback: [Self] = [
        .init(red: 0.32, green: 0.50, blue: 0.70),
        .init(red: 0.70, green: 0.52, blue: 0.42),
        .init(red: 0.50, green: 0.42, blue: 0.65)
    ]

    /// Bound the background to pale or deep shades so semantic text remains readable.
    func surface(dark: Bool, increasedContrast: Bool) -> Self {
        let base = dark ? 0.06 : 0.99
        let amount = increasedContrast ? 0.07 : (dark ? 0.17 : 0.18)
        func blend(_ component: Double) -> Double { base * (1 - amount) + component * amount }
        return Self(red: blend(red), green: blend(green), blue: blend(blue))
    }

    static func extract(from image: CGImage) -> Self? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var buckets: [Int: (weight: Double, red: Double, green: Double, blue: Double)] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[offset + 3] >= 240 else { continue }
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let high = max(red, green, blue), low = min(red, green, blue)
            // Ignore poster borders, white lettering and neutral shadows.
            guard high > 0.15, high < 0.98 || low < 0.85, high - low > 0.10 else { continue }
            let key = Int(pixels[offset] / 32) * 64 + Int(pixels[offset + 1] / 32) * 8 + Int(pixels[offset + 2] / 32)
            let weight = (high - low) * (0.3 + high)
            let previous = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (previous.weight + weight, previous.red + red * weight,
                            previous.green + green * weight, previous.blue + blue * weight)
        }
        guard let winner = buckets.sorted(by: {
            $0.value.weight == $1.value.weight ? $0.key < $1.key : $0.value.weight > $1.value.weight
        }).first?.value else { return nil }
        return Self(red: winner.red / winner.weight, green: winner.green / winner.weight, blue: winner.blue / winner.weight)
    }
}
