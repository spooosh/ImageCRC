import Foundation
import CoreGraphics

enum ImageResizer {
    /// Resize `image` according to `settings`. Returns the input unchanged when
    /// the settings are inactive, when no geometric change is needed, or when
    /// the backing `CGContext` cannot be created.
    static func resize(_ image: CGImage, settings: ResizeSettings) -> CGImage {
        guard settings.isActive else { return image }
        let sourceW = image.width
        let sourceH = image.height
        guard sourceW > 0, sourceH > 0 else { return image }

        let scale = rawScale(sourceW: sourceW, sourceH: sourceH, settings: settings)
        let clamped = settings.enlarge ? scale : min(scale, 1.0)
        guard clamped > 0 else { return image }

        let intermediateW = max(1, Int((Double(sourceW) * clamped).rounded()))
        let intermediateH = max(1, Int((Double(sourceH) * clamped).rounded()))

        let (outputW, outputH, drawX, drawY) = outputGeometry(
            intermediateW: intermediateW,
            intermediateH: intermediateH,
            settings: settings
        )

        if outputW == sourceW && outputH == sourceH && drawX == 0 && drawY == 0
            && intermediateW == sourceW && intermediateH == sourceH {
            return image
        }

        let colorSpace: CGColorSpace = {
            if let cs = image.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpaceCreateDeviceRGB()
        }()

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: outputW,
            height: outputH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: drawX, y: drawY, width: intermediateW, height: intermediateH)
        )
        return context.makeImage() ?? image
    }

    private static func rawScale(sourceW: Int, sourceH: Int, settings: ResizeSettings) -> Double {
        switch (settings.width, settings.height) {
        case let (.some(w), .some(h)):
            let sx = Double(w) / Double(sourceW)
            let sy = Double(h) / Double(sourceH)
            switch settings.mode {
            case .fit:  return min(sx, sy)
            case .fill: return max(sx, sy)
            }
        case let (.some(w), .none):
            return Double(w) / Double(sourceW)
        case let (.none, .some(h)):
            return Double(h) / Double(sourceH)
        case (.none, .none):
            return 1.0
        }
    }

    /// Returns the target output size and the draw-rect offset for the scaled image.
    /// Offset is non-zero only for centered crop in fill mode.
    private static func outputGeometry(
        intermediateW: Int,
        intermediateH: Int,
        settings: ResizeSettings
    ) -> (w: Int, h: Int, x: Int, y: Int) {
        if settings.mode == .fill,
           let targetW = settings.width,
           let targetH = settings.height {
            let outputW = min(intermediateW, targetW)
            let outputH = min(intermediateH, targetH)
            let drawX = (outputW - intermediateW) / 2
            let drawY = (outputH - intermediateH) / 2
            return (outputW, outputH, drawX, drawY)
        }
        return (intermediateW, intermediateH, 0, 0)
    }
}
