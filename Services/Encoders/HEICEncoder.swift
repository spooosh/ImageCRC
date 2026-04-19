import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum HEICEncoder {
    /// HEIC encoding via ImageIO. Supported since macOS 10.13; our deployment
    /// target is 14 so no availability gating is required.
    static func encode(image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        let heicType = UTType("public.heic") ?? UTType.image
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            heicType.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.encodeFailed(format: .heic, underlying: "Destination creation failed")
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality))
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed(format: .heic, underlying: "Finalize failed")
        }
        return data as Data
    }
}
