import SwiftUI

struct FileRowView: View {
    let file: ImageFile
    let onRemove: () -> Void

    @State private var removeHovered = false

    var body: some View {
        HStack(spacing: 14) {
            AsyncThumbnailView(url: file.url, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(file.inputFormat.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(removeHovered ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { removeHovered = $0 }
            .pointingHandCursor()
            .animation(.easeInOut(duration: 0.12), value: removeHovered)
            .help("Remove")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
