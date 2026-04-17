import Foundation
import CoreGraphics

enum ImageEncoder {
    static func encode(image: CGImage, to format: OutputFormat, quality: Double) throws -> Data {
        switch format {
        case .jpeg: return try JPEGEncoder.encode(image: image, quality: quality)
        case .png:  return try PNGEncoder.encode(image: image)
        case .avif: return try AVIFEncoder.encode(image: image, quality: quality)
        case .webp: return try WebPEncoder.encode(image: image, quality: quality)
        }
    }
}
