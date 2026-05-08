import SwiftUI

struct ProgressOverlayView: View {
    let progress: Double
    let completed: Int
    let total: Int
    let currentFilename: String?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 22) {
                AnimatedProgressRing(progress: progress)
                    .frame(width: 190, height: 190)
                    .overlay(ringCenter)

                VStack(spacing: 4) {
                    Text("Processing…")
                        .font(.headline)
                    if let currentFilename {
                        Text(currentFilename)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 320)
                    }
                }

                Button(role: .destructive, action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                        .frame(minWidth: 120)
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .pointingHandCursor()
                .accessibilityIdentifier("cancelButton")
            }
            .padding(36)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.35), radius: 26, y: 8)
            .frame(maxWidth: 440)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progressOverlay")
    }

    private var ringCenter: some View {
        VStack(spacing: 2) {
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("\(completed) / \(total)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct AnimatedProgressRing: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { ctx, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(rect.width, rect.height) / 2

                // Pulse
                let pulse = (sin(time * 2.2) + 1) / 2
                let pulseRadius = radius + 4 + pulse * 6
                let pulseRect = CGRect(
                    x: center.x - pulseRadius,
                    y: center.y - pulseRadius,
                    width: pulseRadius * 2,
                    height: pulseRadius * 2
                )
                ctx.stroke(
                    Path(ellipseIn: pulseRect),
                    with: .color(Color.accentColor.opacity(0.12 + pulse * 0.2)),
                    lineWidth: 1.5
                )

                // Track
                ctx.stroke(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(Color.secondary.opacity(0.18)),
                    lineWidth: 12
                )

                // Rotating shimmer sweep
                let spin = time.truncatingRemainder(dividingBy: 2.4) / 2.4 * 2.0 * .pi
                let shimmerStart = Angle.radians(spin)
                let shimmerEnd = Angle.radians(spin + 0.75)
                var shimmerPath = Path()
                shimmerPath.addArc(
                    center: center,
                    radius: radius,
                    startAngle: shimmerStart,
                    endAngle: shimmerEnd,
                    clockwise: false
                )
                ctx.stroke(
                    shimmerPath,
                    with: .color(Color.accentColor.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )

                // Progress arc
                let clamped = max(0, min(1, progress))
                if clamped > 0 {
                    var arc = Path()
                    arc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * clamped),
                        clockwise: false
                    )
                    let gradient = Gradient(colors: [
                        Color.accentColor,
                        Color.accentColor.opacity(0.85),
                        Color(red: 0.93, green: 0.32, blue: 0.65)
                    ])
                    let start = CGPoint(x: 0, y: 0)
                    let end = CGPoint(x: size.width, y: size.height)
                    ctx.stroke(
                        arc,
                        with: .linearGradient(gradient, startPoint: start, endPoint: end),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}
