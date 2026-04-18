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

            // Resize
            VStack(alignment: .leading, spacing: 6) {
                Label("Resize", systemImage: "aspectratio")
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $settings.resize.mode) {
                    ForEach(ResizeSettings.Mode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    TextField("auto", text: Self.numericBinding($settings.resize.width))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("×").foregroundStyle(.secondary)
                    TextField("auto", text: Self.numericBinding($settings.resize.height))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Toggle(isOn: $settings.resize.enlarge) {
                    Text("Allow enlargement").font(.subheadline)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if !settings.resize.isActive {
                    Text("Leave both fields empty to skip resizing.")
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

    private static func numericBinding(_ source: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue.map(String.init) ?? "" },
            set: { newValue in
                let digits = newValue.filter { $0.isASCII && $0.isNumber }
                if digits.isEmpty {
                    source.wrappedValue = nil
                } else if let n = Int(digits), n >= 1 {
                    source.wrappedValue = n
                }
            }
        )
    }
}
