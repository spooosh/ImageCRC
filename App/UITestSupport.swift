import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Launch-argument-driven hooks that let XCUITest seed the app's state without
/// driving NSOpenPanel. Dormant unless `IMAGECRC_UI_TEST=1` is set in the
/// process environment — adds zero overhead to normal launches.
enum UITestSupport {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["IMAGECRC_UI_TEST"] == "1"
    }

    /// Apply launch-argument-driven preloads to the given view model. Call once
    /// after the VM is constructed. No-op when `isActive` is false.
    @MainActor
    static func applyLaunchArguments(to viewModel: ConversionViewModel) {
        guard isActive else { return }
        let args = ProcessInfo.processInfo.arguments

        if let dir = value(for: "--ui-test-output-dir", in: args) {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            viewModel.settings.outputDirectory = url
        }

        if let countStr = value(for: "--ui-test-preload-files", in: args),
           let count = Int(countStr), count > 0,
           let outputDir = viewModel.settings.outputDirectory {
            let side = (value(for: "--ui-test-preload-size", in: args)).flatMap(Int.init) ?? 256
            let stagingDir = outputDir
                .deletingLastPathComponent()
                .appendingPathComponent("ui-test-inputs", isDirectory: true)
            try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            var seeded: [URL] = []
            for i in 0..<count {
                let url = stagingDir.appendingPathComponent("preload-\(i).png")
                if writeSyntheticPNG(width: side, height: side, to: url) {
                    seeded.append(url)
                }
            }
            viewModel.addURLs(seeded)
        }
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @discardableResult
    private static func writeSyntheticPNG(width: Int, height: Int, to url: URL) -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bmp = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bmp
        ) else { return false }
        ctx.setFillColor(red: 0.6, green: 0.4, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let img = ctx.makeImage() else { return false }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }
}
