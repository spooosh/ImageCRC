import SwiftUI

struct SettingsPanelView: View {
    @Binding var settings: ConversionSettings
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Quality
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Quality", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(settings.quality)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.quality) },
                        set: { settings.quality = Int($0.rounded()) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .tint(Color.accentColor)
                if settings.outputFormat == .png && settings.quality < 100 {
                    Text("PNG < 100 quantizes via pngquant (indexed-color, up to 256 colors).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Output format
            VStack(alignment: .leading, spacing: 6) {
                Label("Output format", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Output folder
            VStack(alignment: .leading, spacing: 6) {
                Label("Output folder", systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    Text(settings.outputDirectory?.path ?? "Not selected")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(settings.outputDirectory == nil ? .secondary : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button("Choose…", action: onChooseFolder)
                        .buttonStyle(.bordered)
                        .pointingHandCursor()
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}
