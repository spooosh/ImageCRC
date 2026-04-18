import SwiftUI

struct FileListView: View {
    let files: [ImageFile]
    let onRemove: (ImageFile) -> Void
    let onClear: () -> Void

    @State private var clearHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(files.count) image\(files.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Button("Clear all", role: .destructive, action: onClear)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(clearHovered ? Color.red : Color.secondary)
                    .onHover { clearHovered = $0 }
                    .pointingHandCursor()
                    .animation(.easeInOut(duration: 0.12), value: clearHovered)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(files) { file in
                        FileRowView(file: file) { onRemove(file) }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
