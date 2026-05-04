import Foundation

/// RAII wrapper for a unique temporary directory under
/// `FileManager.default.temporaryDirectory`. Removes the directory on `deinit`.
/// Construction can fail if the FS rejects the create — the initialiser throws.
final class TempDirectory {
    let url: URL

    init(prefix: String = "imagecrc-test") throws {
        let base = FileManager.default.temporaryDirectory
        let unique = "\(prefix)-\(UUID().uuidString)"
        self.url = base.appendingPathComponent(unique, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
