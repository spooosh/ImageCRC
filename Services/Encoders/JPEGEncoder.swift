import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum JPEGEncoder {
    static func encode(image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.encodeFailed(format: .jpeg, underlying: "Destination creation failed")
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality)),
            kCGImageDestinationOptimizeColorForSharing: true,
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed(format: .jpeg, underlying: "Finalize failed")
        }
        return data as Data
    }
}
