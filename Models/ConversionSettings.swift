import Foundation

struct ConversionSettings: Hashable, Sendable {
    /// Quality 0...100 (100 = best, 0 = smallest). Ignored for lossless formats.
    var quality: Int
    var outputFormat: OutputFormat
    var outputDirectory: URL?
    var resize: ResizeSettings

    static let `default` = ConversionSettings(
        quality: 80,
        outputFormat: .webp,
        outputDirectory: defaultOutputDirectory(),
        resize: ResizeSettings()
    )

    var normalizedQuality: Double {
        Double(min(max(quality, 0), 100)) / 100.0
    }

    var isReady: Bool {
        outputDirectory != nil
    }

    private static func defaultOutputDirectory() -> URL? {
        let fm = FileManager.default
        guard let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return pictures.appendingPathComponent("img-cc", isDirectory: true)
    }
}
