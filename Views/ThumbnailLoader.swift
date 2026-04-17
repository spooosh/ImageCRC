import Foundation
import AppKit
import ImageIO
import CoreGraphics

enum ThumbnailLoader {
    /// Load a small thumbnail for the given URL. Uses ImageIO fast-path when possible,
    /// falls back to NSImage (handles SVG).
    static func load(url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = loadSync(url: url, maxPixelSize: maxPixelSize)
                continuation.resume(returning: img)
            }
        }
    }

    private static func loadSync(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
        ]
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }

        if let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
}
