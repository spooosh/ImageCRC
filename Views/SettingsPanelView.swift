import SwiftUI

struct SettingsPanelView: View {
    enum Field: Hashable { case quality, width, height }

    @Binding var settings: ConversionSettings
    let onChooseFolder: () -> Void
    var focus: FocusState<Field?>.Binding

    /// Keep all TextFields disabled on the first render so AppKit's NSWindow
    /// cannot auto-select any of them as initial first responder — that auto
    /// selection is what spawns the AutoFill popover service on launch.
    /// Flipped back to false one runloop cycle later, by which time initial
    /// firstResponder has already been resolved to a non-TextField view.
    @State private var textFieldsLocked = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            qualitySection.settingsSectionStyle()
            resizeSection.settingsSectionStyle()
            outputSection.settingsSectionStyle()
        }
        .onAppear {
            DispatchQueue.main.async { textFieldsLocked = false }
        }
    }

    // MARK: - Sections

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Label("Quality", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                TextField("", text: Self.qualityBinding($settings.quality))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .font(.subheadline.monospacedDigit())
                    .focused(focus, equals: .quality)
                    .disabled(textFieldsLocked)
                Text("%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(settings.quality) },
                    set: { settings.quality = Int($0.rounded()) }
                ),
                in: 0...100
            )
            .tint(Color.accentColor)
            if settings.outputFormat == .png && settings.quality < 100 {
                Text("PNG < 100 quantizes via pngquant (indexed-color, up to 256 colors).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var resizeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Resize", systemImage: "aspectratio")
                .font(.headline)
            FullWidthSegmented(
                selection: $settings.resize.mode,
                options: ResizeSettings.Mode.allCases,
                title: { $0.displayName }
            )

            HStack(spacing: 8) {
                TextField("auto", text: Self.numericBinding($settings.resize.width))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .focused(focus, equals: .width)
                    .disabled(textFieldsLocked)
                Text("×").foregroundStyle(.secondary)
                TextField("auto", text: Self.numericBinding($settings.resize.height))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .focused(focus, equals: .height)
                    .disabled(textFieldsLocked)
                Text("px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Output settings", systemImage: "tray.and.arrow.down")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Format")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                FullWidthSegmented(
                    selection: $settings.outputFormat,
                    options: OutputFormat.allCases,
                    title: { $0.displayName }
                )
                if settings.outputFormat == .sameAsOrigin {
                    Text("SVG files are copied as-is — resize and quality don't apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
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
    }

    // MARK: - Helpers

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

    private static func qualityBinding(_ source: Binding<Int>) -> Binding<String> {
        Binding(
            get: { String(source.wrappedValue) },
            set: { newValue in
                let digits = newValue.filter { $0.isASCII && $0.isNumber }
                if digits.isEmpty { return }
                if let n = Int(digits) {
                    source.wrappedValue = min(max(n, 0), 100)
                }
            }
        )
    }
}

private struct FullWidthSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}

private struct SettingsSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color.secondary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

private extension View {
    func settingsSectionStyle() -> some View {
        modifier(SettingsSectionStyle())
    }
}
