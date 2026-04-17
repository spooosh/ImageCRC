import Foundation
import UniformTypeIdentifiers

enum InputFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case svg
    case webp
    case avif
    case heic

    init?(url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": self = .jpeg
        case "png":         self = .png
        case "svg":         self = .svg
        case "webp":        self = .webp
        case "avif":        self = .avif
        case "heic":        self = .heic
        default:            return nil
        }
    }

    static let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "svg", "webp", "avif", "heic"
    ]

    static let allowedUTTypes: [UTType] = {
        var types: [UTType] = [.jpeg, .png, .heic, .svg]
        if let webp = UTType("org.webmproject.webp") { types.append(webp) }
        if let avif = UTType("public.avif") { types.append(avif) }
        return types
    }()
}
