import SwiftUI
import AppKit

struct CompletionSheetView: View {
    let summary: ConversionSummary
    let onDismiss: () -> Void

    @State private var didAutoOpen = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: summary.successes.count)

            Text(title)
                .font(.title2.weight(.semibold))

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let ratio = summary.savingsRatio, ratio > 0 {
                Text(savingsText(ratio: ratio))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.10),
                                in: Capsule())
            }

            if !summary.failures.isEmpty {
                DisclosureGroup("\(summary.failures.count) failed") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(summary.failures) { result in
                                errorRow(for: result)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxHeight: 140)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 10) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        summary.successes.compactMap {
                            if case .success(let url, _, _) = $0.outcome { return url }
                            return nil
                        }
                    )
                }
                .buttonStyle(.bordered)
                .disabled(summary.successes.isEmpty)

                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 460)
        .onAppear {
            guard !didAutoOpen else { return }
            didAutoOpen = true
            if !summary.successes.isEmpty {
                NSWorkspace.shared.open(summary.outputDirectory)
            }
        }
    }

    private var icon: String {
        if summary.successes.isEmpty {
            return "exclamationmark.triangle.fill"
        } else if !summary.failures.isEmpty || summary.wasCancelled {
            return "checkmark.circle.badge.questionmark"
        } else {
            return "checkmark.seal.fill"
        }
    }

    private var tint: Color {
        if summary.successes.isEmpty { return .orange }
        if !summary.failures.isEmpty || summary.wasCancelled { return .yellow }
        return .green
    }

    private var title: String {
        summary.wasCancelled ? "Cancelled" : "All done"
    }

    private var subtitle: String {
        let s = summary.successes.count
        let t = summary.total
        var text = "\(s) of \(t) images converted"
        if summary.wasCancelled {
            text += " (cancelled)"
        } else if !summary.failures.isEmpty {
            text += " — \(summary.failures.count) failed"
        }
        return text
    }

    private func savingsText(ratio: Double) -> String {
        let percent = Int((ratio * 100).rounded())
        let saved = summary.totalOriginalBytes - summary.totalOutputBytes
        let savedStr = ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)
        return "Saved \(savedStr) (\(percent)% smaller)"
    }

    @ViewBuilder
    private func errorRow(for result: ConversionResult) -> some View {
        if case .failure(let err) = result.outcome {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.source.lastPathComponent)
                        .font(.caption.weight(.semibold))
                    Text(err.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
