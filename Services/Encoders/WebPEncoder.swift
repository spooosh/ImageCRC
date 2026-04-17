import Foundation
import CoreGraphics
import libwebp

enum WebPEncoder {
    /// Encode a CGImage to WebP using libwebp.
    /// - Parameters:
    ///   - image: source image
    ///   - quality: 0.0...1.0 — mapped to libwebp's 0...100 scale.
    static func encode(image: CGImage, quality: Double) throws -> Data {
        let buffer = try RGBABuffer.make(from: image)
        let qualityFactor = Float(max(0.0, min(1.0, quality)) * 100.0)

        var outputPtr: UnsafeMutablePointer<UInt8>? = nil
        let written: Int = buffer.bytes.withUnsafeBufferPointer { bufPtr in
            guard let base = bufPtr.baseAddress else { return 0 }
            return WebPEncodeRGBA(
                base,
                Int32(buffer.width),
                Int32(buffer.height),
                Int32(buffer.bytesPerRow),
                qualityFactor,
                &outputPtr
            )
        }

        defer {
            if let p = outputPtr { WebPFree(p) }
        }

        guard written > 0, let out = outputPtr else {
            throw ConversionError.encodeFailed(format: .webp, underlying: "WebPEncodeRGBA returned 0 bytes")
        }

        return Data(bytes: out, count: written)
    }
}
