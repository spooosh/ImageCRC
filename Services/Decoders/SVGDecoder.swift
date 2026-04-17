import Foundation
import AppKit
import CoreGraphics

enum SVGDecoder {
    /// Default rasterization size when an SVG has no explicit dimensions.
    static let defaultSize = CGSize(width: 1024, height: 1024)

    /// Decode an SVG file to CGImage by rasterizing via NSImage (macOS 14+ SVG support).
    static func decode(url: URL) throws -> CGImage {
        guard let nsImage = NSImage(contentsOf: url) else {
            throw ConversionError.decodeFailed(url: url, underlying: "NSImage could not load SVG")
        }

        var rasterSize = nsImage.size
        if rasterSize.width < 1 || rasterSize.height < 1 {
            rasterSize = defaultSize
        }

        let rect = NSRect(origin: .zero, size: rasterSize)
        var proposedRect = rect
        guard let cgImage = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return try redraw(nsImage: nsImage, size: rasterSize, sourceURL: url)
        }

        // If the returned CGImage looks like a vector snapshot with tiny size, redraw at proper size.
        if cgImage.width < 2 || cgImage.height < 2 {
            return try redraw(nsImage: nsImage, size: rasterSize, sourceURL: url)
        }
        return cgImage
    }

    private static func redraw(nsImage: NSImage, size: CGSize, sourceURL: URL) throws -> CGImage {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ConversionError.decodeFailed(url: sourceURL, underlying: "Could not create rasterization context")
        }

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsImage.draw(
            in: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            throw ConversionError.decodeFailed(url: sourceURL, underlying: "Could not rasterize SVG")
        }
        return cgImage
    }
}
