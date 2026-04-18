import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let hasFiles: Bool
    let onAdd: ([URL]) -> Void
    let onBrowse: () -> Void

    @State private var isTargeted = false
    @State private var isHovering = false

    private var isActive: Bool { isTargeted || isHovering }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isTargeted
                              ? Color.accentColor.opacity(0.12)
                              : Color.secondary.opacity(0.05))
                )
                .animation(.easeInOut(duration: 0.15), value: isActive)

            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                Text(hasFiles
                     ? "Drop more images here or click to browse"
                     : "Drop images here or click to browse")
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("JPG · JPEG · PNG · SVG · WebP · AVIF · HEIC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(height: 180)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onBrowse() }
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .dropDestination(for: URL.self) { urls, _ in
            onAdd(urls)
            return true
        } isTargeted: { value in
            isTargeted = value
        }
    }
}
