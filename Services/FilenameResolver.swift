import Foundation

actor FilenameResolver {
    private var reserved: Set<String> = []
    private let fm = FileManager.default

    func resolve(outputDirectory: URL, baseName: String, ext: String) -> URL {
        var n = 0
        while true {
            let name = n == 0 ? baseName : "\(baseName) (\(n))"
            let candidate = outputDirectory.appendingPathComponent("\(name).\(ext)")
            let key = candidate.path
            if !reserved.contains(key) && !fm.fileExists(atPath: key) {
                reserved.insert(key)
                return candidate
            }
            n += 1
        }
    }

    func reset() {
        reserved.removeAll()
    }
}
