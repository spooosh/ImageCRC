import Foundation
import CoreGraphics

enum ImageDecoder {
    static func decode(file: ImageFile) throws -> CGImage {
        switch file.inputFormat {
        case .svg:
            return try SVGDecoder.decode(url: file.url)
        case .jpeg, .png, .heic, .avif, .webp:
            return try ImageIODecoder.decode(url: file.url)
        }
    }
}
