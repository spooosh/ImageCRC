import Foundation
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case jpeg
    case png
    case webp
    case avif
    case sameAsOrigin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg:         return "JPG"
        case .png:          return "PNG"
        case .webp:         return "WebP"
        case .avif:         return "AVIF"
        case .sameAsOrigin: return "Origin"
        }
    }

    /// Meaningful only for direct-encode picker choices. `.sameAsOrigin` resolves
    /// the effective extension per-file via `OutputPlanner`, so the empty string
    /// here is intentional and never read on that path.
    var fileExtension: String {
        switch self {
        case .jpeg:         return "jpg"
        case .png:          return "png"
        case .webp:         return "webp"
        case .avif:         return "avif"
        case .sameAsOrigin: return ""
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg:         return .jpeg
        case .png:          return .png
        case .webp:         return UTType("org.webmproject.webp") ?? UTType.image
        case .avif:         return UTType("public.avif") ?? UTType.image
        case .sameAsOrigin: return .image
        }
    }

    var isLossless: Bool {
        self == .png
    }
}
