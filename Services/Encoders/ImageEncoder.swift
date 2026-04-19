import Foundation
import CoreGraphics

enum ImageEncoder {
    static func encode(image: CGImage, to format: EncoderFormat, quality: Double) async throws -> Data {
        switch format {
        case .jpeg: return try JPEGEncoder.encode(image: image, quality: quality)
        case .png:  return try await encodePNG(image: image, quality: quality)
        case .avif: return try AVIFEncoder.encode(image: image, quality: quality)
        case .webp: return try WebPEncoder.encode(image: image, quality: quality)
        case .heic: return try HEICEncoder.encode(image: image, quality: quality)
        }
    }

    /// PNG path: always produces a valid ImageIO PNG first, then — if the slider
    /// is below 100 — runs it through pngquant for indexed-color compression.
    private static func encodePNG(image: CGImage, quality: Double) async throws -> Data {
        let lossless = try PNGEncoder.encode(image: image)
        let q = Int((quality * 100).rounded())
        if q >= 100 {
            return lossless
        }
        return try await PNGQuantizer.quantize(pngData: lossless, quality: q)
    }
}
