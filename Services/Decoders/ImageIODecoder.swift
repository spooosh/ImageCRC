import Foundation
import ImageIO
import CoreGraphics

enum ImageIODecoder {
    /// Decode any ImageIO-supported format (jpg, png, heic, avif, webp on macOS 14+) to CGImage.
    /// Honours the EXIF orientation tag when present — the returned CGImage's width/height
    /// reflect the visually-correct orientation, not the raw sensor layout.
    static func decode(url: URL) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            throw ConversionError.decodeFailed(url: url, underlying: "CGImageSource create failed")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.decodeFailed(url: url, underlying: "No image in file")
        }
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError.decodeFailed(url: url, underlying: "CGImage create failed")
        }

        // Read EXIF orientation if present. CGImagePropertyOrientation values:
        // 1 = up, 2 = upMirrored, 3 = down, 4 = downMirrored,
        // 5 = leftMirrored, 6 = right (90° CW), 7 = rightMirrored, 8 = left (90° CCW).
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        // Top-level orientation key first, then nested TIFF dict for files that
        // only store it there (some edited JPEGs/HEICs).
        let orientationRaw: UInt32 = {
            if let top = props?[kCGImagePropertyOrientation] as? UInt32 {
                return top
            }
            if let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let nested = tiff[kCGImagePropertyTIFFOrientation] as? UInt32 {
                return nested
            }
            return 1
        }()
        guard let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) else {
            return raw
        }
        if orientation == .up { return raw }
        return Self.applyOrientation(orientation, to: raw)
    }

    /// Bake an EXIF orientation into the pixels by drawing through a
    /// transformed CGContext. Returns a fresh CGImage whose width/height
    /// reflect the visually-correct orientation.
    private static func applyOrientation(
        _ orientation: CGImagePropertyOrientation, to image: CGImage
    ) -> CGImage {
        let srcW = image.width
        let srcH = image.height
        // For 90° rotations (.right / .left / their mirrored variants) the output
        // canvas swaps width and height.
        let swap: Bool = {
            switch orientation {
            case .left, .right, .leftMirrored, .rightMirrored: return true
            default: return false
            }
        }()
        let outW = swap ? srcH : srcW
        let outH = swap ? srcW : srcH

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        // Build the affine transform that maps source pixels into the output
        // canvas. Order matters: translate first to position the origin, then
        // rotate / flip.
        switch orientation {
        case .up:
            break
        case .upMirrored:
            ctx.translateBy(x: CGFloat(outW), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        case .down:
            ctx.translateBy(x: CGFloat(outW), y: CGFloat(outH))
            ctx.rotate(by: .pi)
        case .downMirrored:
            ctx.translateBy(x: 0, y: CGFloat(outH))
            ctx.scaleBy(x: 1, y: -1)
        case .leftMirrored:  // EXIF 5 = transpose: source(x, y) → display(y, x)
            // Output canvas is srcH×srcW (dimensions swapped). Vertical flip + 90° CCW
            // rotation maps source left-edge (red) to display top-left.
            ctx.translateBy(x: CGFloat(outW), y: CGFloat(outH))
            ctx.scaleBy(x: 1, y: -1)
            ctx.rotate(by: .pi / 2)
        case .right:
            // EXIF 6: rotate 90° CW for display.
            // In CG's Y-up space, 90° CW = rotate by -π/2.
            // translate(0, outH) shifts the origin so the rotated image lands in-canvas.
            ctx.translateBy(x: 0, y: CGFloat(outH))
            ctx.rotate(by: -.pi / 2)
        case .rightMirrored:  // EXIF 7 = anti-transpose: source(x, y) → display(H-1-y, W-1-x)
            // Output canvas is srcH×srcW (dimensions swapped). Swap coordinates
            // (scale(1,-1) + rotate(-π/2)) maps source left-edge (red) to display bottom-right.
            ctx.scaleBy(x: 1, y: -1)
            ctx.rotate(by: -.pi / 2)
        case .left:
            // EXIF 8: rotate 90° CCW for display.
            // In CG's Y-up space, 90° CCW = rotate by +π/2.
            ctx.translateBy(x: CGFloat(outW), y: 0)
            ctx.rotate(by: .pi / 2)
        @unknown default:
            return image
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
        return ctx.makeImage() ?? image
    }
}
