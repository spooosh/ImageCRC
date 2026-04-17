import Foundation
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case jpeg
    case png
    case webp
    case avif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: return "JPG"
        case .png:  return "PNG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .webp: return "webp"
        case .avif: return "avif"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png:  return .png
        case .webp: return UTType("org.webmproject.webp") ?? UTType.image
        case .avif: return UTType("public.avif") ?? UTType.image
        }
    }

    var isLossless: Bool {
        self == .png
    }
}
