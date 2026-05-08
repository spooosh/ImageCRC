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
            // Generate off main so the runloop stays responsive long enough
            // for macOS accessibility to finish loading. Large gradient images
            // synthesised on main blocked startup past XCUITest's setup
            // window. Hop back to MainActor for the VM update.
            Task.detached(priority: .userInitiated) {
                var seeded: [URL] = []
                for i in 0..<count {
                    let url = stagingDir.appendingPathComponent("preload-\(i).png")
                    if writeSyntheticPNG(width: side, height: side, to: url) {
                        seeded.append(url)
                    }
                }
                let captured = seeded
                await MainActor.run {
                    viewModel.addURLs(captured)
                }
            }
        }
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func writeSyntheticPNG(width: Int, height: Int, to url: URL) -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bmp = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bmp
        ) else { return false }
        // Solid colours compress to ~0 DCT energy and the cancel-flow batch
        // would finish in <300ms on Apple Silicon — too fast for the progress
        // overlay to land in the AX tree. A diagonal red→blue gradient drawn
        // via CGContext.drawLinearGradient (optimised path) gives realistic
        // PNG decode + JPEG encode wall-clock time without spending CPU on a
        // per-pixel Swift loop.
        let colors: [CGColor] = [
            CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            CGColor(red: 0, green: 0, blue: 1, alpha: 1),
        ]
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: cs,
                                     colors: colors as CFArray,
                                     locations: locations) {
            ctx.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
                options: []
            )
        }
        guard let img = ctx.makeImage() else { return false }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }
}
