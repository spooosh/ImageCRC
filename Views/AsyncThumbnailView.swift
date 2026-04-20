import SwiftUI

struct AsyncThumbnailView: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: size * 0.35))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .task(id: url) {
            let pixelSize = size * 3
            image = await ThumbnailLoader.load(url: url, maxPixelSize: pixelSize)
        }
    }
}
