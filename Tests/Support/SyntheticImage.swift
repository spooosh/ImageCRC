// Tests/Support/SyntheticImage.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

    /// Linear horizontal red→blue gradient. Non-trivial color content for codec tests.
    /// Crashes on context creation failure (test-only contract).
    static func gradient(
        width: Int,
        height: Int,
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
            fatalError("SyntheticImage.gradient: failed to create CGContext (\(width)x\(height))")
        }
        guard let cgGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                     CGColor(red: 0, green: 0, blue: 1, alpha: 1)] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            fatalError("SyntheticImage.gradient: failed to create CGGradient")
        }
        ctx.drawLinearGradient(
            cgGradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: width, y: 0),
            options: []
        )
        guard let image = ctx.makeImage() else {
            fatalError("SyntheticImage.gradient: makeImage() returned nil")
        }
        return image
    }

    /// Encode a CGImage to JPEG with a specific EXIF orientation tag.
    /// Used by EXIF orientation probe-then-fix tests.
    /// `exifOrientation` follows the TIFF/EXIF spec: 1=normal, 6=90° CW, 8=270° CW, etc.
    static func jpegData(from image: CGImage, exifOrientation: Int) -> Data {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            fatalError("SyntheticImage.jpegData: destination creation failed")
        }
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: exifOrientation
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            fatalError("SyntheticImage.jpegData: finalize failed")
        }
        return mutableData as Data
    }
}
