import Foundation

struct ImageFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let byteSize: Int64
    let inputFormat: InputFormat

    init?(url: URL) {
        guard let format = InputFormat(url: url) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.id = UUID()
        self.url = url
        self.byteSize = Int64(values?.fileSize ?? 0)
        self.inputFormat = format
    }

    var displayName: String { url.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}
