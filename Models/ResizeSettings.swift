import Foundation

struct ResizeSettings: Hashable, Sendable {
    enum Mode: String, Hashable, Sendable, CaseIterable, Identifiable {
        case fit
        case fill

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .fit:  return "Fit"
            case .fill: return "Fill"
            }
        }
    }

    var mode: Mode = .fit
    var width: Int? = nil
    var height: Int? = nil
    var enlarge: Bool = false

    var isActive: Bool { width != nil || height != nil }
}
