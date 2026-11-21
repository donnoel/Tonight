#if os(tvOS) || os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TopShelfFeatureArtwork {
    private static let canvas = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    static func render(backdropData: Data?, posterData: Data?) -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high

        if let backdrop = decode(backdropData, limit: Int(canvas.width)), backdrop.width > backdrop.height {
            let scale = max(canvas.width / CGFloat(backdrop.width), canvas.height / CGFloat(backdrop.height))
            context.draw(backdrop, in: centeredFrame(for: backdrop, in: canvas, scale: scale))
        } else {
            let midnight = CGColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1)
            let indigo = CGColor(red: 0.15, green: 0.15, blue: 0.31, alpha: 1)
            let amber = CGColor(red: 0.44, green: 0.24, blue: 0.16, alpha: 1)
            gradient([midnight, indigo, amber], from: .zero, to: CGPoint(x: canvas.maxX, y: canvas.maxY),
                     in: context, colorSpace: colorSpace)

            if let poster = decode(posterData, limit: Int(canvas.height)) {
                let area = CGRect(x: 982, y: 105, width: 826, height: 925)
                let scale = min(area.width / CGFloat(poster.width), area.height / CGFloat(poster.height))
                context.draw(poster, in: centeredFrame(for: poster, in: area, scale: scale))
            }
        }

        // The native title occupies the leading edge; the Dock can cover the bottom.
        let clear = CGColor(red: 0.02, green: 0.025, blue: 0.05, alpha: 0)
        let leadingShade = CGColor(red: 0.02, green: 0.025, blue: 0.05, alpha: 0.72)
        let dockShade = CGColor(red: 0.02, green: 0.025, blue: 0.05, alpha: 0.55)
        gradient([leadingShade, clear], from: .zero, to: CGPoint(x: 1060, y: 0),
                 in: context, colorSpace: colorSpace)
        gradient([dockShade, clear], from: .zero, to: CGPoint(x: 0, y: 375),
                 in: context, colorSpace: colorSpace)

        let output = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func decode(_ data: Data?, limit: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ]
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func centeredFrame(for image: CGImage, in area: CGRect, scale: CGFloat) -> CGRect {
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    private static func gradient(_ colors: [CGColor], from start: CGPoint, to end: CGPoint,
                                 in context: CGContext, colorSpace: CGColorSpace) {
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
#endif
