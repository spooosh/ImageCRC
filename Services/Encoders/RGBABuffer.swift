import Foundation
import CoreGraphics

struct RGBABuffer {
    let bytes: [UInt8]
    let width: Int
    let height: Int
    let bytesPerRow: Int

    /// Rasterize a CGImage into a packed 8-bit RGBA buffer (premultiplied, big endian byte order).
    static func make(from image: CGImage) throws -> RGBABuffer {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        try buffer.withUnsafeMutableBufferPointer { ptr -> Void in
            guard let base = ptr.baseAddress,
                  let ctx = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                throw ConversionError.encodeFailed(format: .webp, underlying: "Bitmap context creation failed")
            }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return RGBABuffer(bytes: buffer, width: width, height: height, bytesPerRow: bytesPerRow)
    }
}
