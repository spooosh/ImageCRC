import Foundation

/// What an encoder can actually produce. Distinct from the user-facing
/// `OutputFormat` because `HEIC` is only reachable via the `.sameAsOrigin`
/// path — it is never shown as a picker option — and because `.sameAsOrigin`
/// itself is a routing choice, not an encoder target.
enum EncoderFormat: String, Hashable, Sendable {
    case jpeg
    case png
    case webp
    case avif
    case heic

    var displayName: String {
        switch self {
        case .jpeg: return "JPG"
        case .png:  return "PNG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .webp: return "webp"
        case .avif: return "avif"
        case .heic: return "heic"
        }
    }
}

/// Per-file execution plan: either we re-encode to a specific encoder target,
/// or we copy the source file verbatim (SVG on the `.sameAsOrigin` path).
enum FileOutputPlan: Equatable, Sendable {
    case encode(EncoderFormat)
    case copy
}

enum OutputPlanner {
    /// Resolve a plan for one file.
    static func plan(for input: InputFormat, selected: OutputFormat) -> FileOutputPlan {
        switch selected {
        case .jpeg: return .encode(.jpeg)
        case .png:  return .encode(.png)
        case .webp: return .encode(.webp)
        case .avif: return .encode(.avif)
        case .sameAsOrigin:
            switch input {
            case .jpeg: return .encode(.jpeg)
            case .png:  return .encode(.png)
            case .webp: return .encode(.webp)
            case .avif: return .encode(.avif)
            case .heic: return .encode(.heic)
            case .svg:  return .copy
            }
        }
    }
}
