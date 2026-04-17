import Foundation
import ImageIO
import CoreGraphics

enum ImageIODecoder {
    /// Decode any ImageIO-supported format (jpg, png, heic, avif, webp on macOS 14+) to CGImage.
    static func decode(url: URL) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            throw ConversionError.decodeFailed(url: url, underlying: "CGImageSource create failed")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.decodeFailed(url: url, underlying: "No image in file")
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError.decodeFailed(url: url, underlying: "CGImage create failed")
        }
        return cgImage
    }
}
