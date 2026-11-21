import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

@available(tvOS 26, macOS 26, *)
enum TopShelfMotionPreview {
    private static let width = 1280
    private static let height = 720
    private static let fps: Int32 = 18
    private static let frameCount = 12 * Int(fps)

    enum RenderError: Error { case invalidArtwork, missingPixelPool, frame, encoding }

    static func write(backdrop: Data, to url: URL) async throws {
        guard let source = CGImageSourceCreateWithData(backdrop as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int, pixelWidth > pixelHeight,
              let still = TopShelfFeatureArtwork.render(backdropData: backdrop, posterData: nil),
              let framedSource = CGImageSourceCreateWithData(still as CFData, nil),
              let frame = CGImageSourceCreateImageAtIndex(framedSource, 0, nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw RenderError.invalidArtwork }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_400_000,
                AVVideoExpectedSourceFrameRateKey: Int(fps),
                AVVideoMaxKeyFrameIntervalKey: 2 * Int(fps)
            ]
        ])
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: .init(
            pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
            size: .init(width: Self.width, height: height)
        ))
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        guard let pool = receiver.pixelBufferPool else { throw RenderError.missingPixelPool }

        for index in 0..<frameCount {
            try Task.checkCancellation()
            var pixels = try pool.makeMutablePixelBuffer()
            // Ease from the still to a 4% push-in and back to the still.
            let phase = Double(index) / Double(frameCount)
            let scale = 1 + 0.04 * (1 - cos(phase * 2 * .pi)) / 2
            try pixels.accessUnsafeMutableRawPlaneBytes { planes in
                guard let plane = planes.first,
                      let context = CGContext(data: plane.bytes.baseAddress, width: Self.width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: plane.properties.bytesPerRow,
                                              space: colorSpace,
                                              bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                                  | CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw RenderError.frame }
                let width = Double(Self.width) * scale
                let height = Double(Self.height) * scale
                context.interpolationQuality = .medium
                context.draw(frame, in: CGRect(x: (Double(Self.width) - width) / 2,
                                               y: (Double(Self.height) - height) / 2, width: width, height: height))
            }
            try await receiver.append(CVReadOnlyPixelBuffer(pixels), with: CMTime(value: Int64(index), timescale: fps))
        }
        receiver.finish()
        writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? RenderError.encoding }
    }
}
