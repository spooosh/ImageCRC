import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum PNGEncoder {
    /// PNG is lossless; quality is ignored.
    static func encode(image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.encodeFailed(format: .png, underlying: "Destination creation failed")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed(format: .png, underlying: "Finalize failed")
        }
        return data as Data
    }
}
