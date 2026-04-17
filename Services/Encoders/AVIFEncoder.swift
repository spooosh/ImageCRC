import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum AVIFEncoder {
    /// AVIF encoding via ImageIO. Requires macOS 14+ for the write path.
    static func encode(image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        let avifType = UTType("public.avif") ?? UTType.image
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            avifType.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.encodeFailed(format: .avif, underlying: "Destination creation failed (AVIF write requires macOS 14+)")
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality))
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed(format: .avif, underlying: "Finalize failed")
        }
        return data as Data
    }
}
