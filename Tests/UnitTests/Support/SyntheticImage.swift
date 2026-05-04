// Tests/UnitTests/Support/SyntheticImage.swift
import CoreGraphics
import Foundation

enum SyntheticImage {
    /// Solid-colour RGBA premultiplied CGImage of the given dimensions.
    /// Crashes deliberately on failure — these are test-only constructors and
    /// silent fallbacks would mask wiring bugs.
    static func solid(
        width: Int,
        height: Int,
        red: CGFloat = 1,
        green: CGFloat = 0,
        blue: CGFloat = 0,
        alpha: CGFloat = 1,
        colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    ) -> CGImage {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("SyntheticImage: failed to create CGContext (\(width)x\(height))")
        }
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            fatalError("SyntheticImage: CGContext.makeImage() returned nil")
        }
        return image
    }
}
