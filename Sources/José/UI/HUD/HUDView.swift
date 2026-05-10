import SwiftUI
import AppKit

/// Variant currently shown in the pill. Drives layout, copy, and animations.
enum HUDVariant: Equatable {
    case recording
    case processing
    case error(String)
    case notice(String)
}

/// Observable view-model owned by the HUDController. Mutated from the main
/// actor as audio levels arrive and the recording timer ticks.
@MainActor
@Observable
final class HUDViewModel {
    var variant: HUDVariant = .processing
    var levels: [Float] = []
    var elapsed: TimeInterval = 0
    var pulse: Bool = false

    static let barCount = 30

    func pushLevel(_ value: Float) {
        let clamped = max(0, min(1, value))
        levels.append(clamped)
        if levels.count > Self.barCount {
            levels.removeFirst(levels.count - Self.barCount)
        }
    }

    func resetLevels() {
        levels.removeAll(keepingCapacity: true)
    }
}

struct HUDView: View {
    @Bindable var model: HUDViewModel

    /// The visible pill is smaller than the panel — the surrounding gap
    /// is where the SiriHalo's blurred glow can bleed without being
    /// clipped by the window edge.
    static let haloBleed: CGFloat = 8

    var body: some View {
        ZStack {
            // The pill itself: frosted background + content.
            ZStack {
                VisualEffectBackground()
                    .clipShape(Capsule())

                content
                    .padding(.horizontal, 16)
            }
            .padding(Self.haloBleed)
            .overlay(
                // Halo sits ON the pill's edge (inside the bleed area).
                Group {
                    if showsHalo {
                        SiriHalo()
                            .padding(Self.haloBleed)
                            .allowsHitTesting(false)
                    }
                }
            )
        }
    }

    private var showsHalo: Bool {
        switch model.variant {
        case .recording, .processing: true
        case .error, .notice: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.variant {
        case .recording:
            recordingContent
        case .processing:
            processingContent
        case .error(let message):
            messageContent(message, color: Color(red: 0.922, green: 0.341, blue: 0.341))
        case .notice(let message):
            messageContent(message, color: .secondary)
        }
    }

    private var recordingContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 1.0, green: 0.353, blue: 0.353))
                .frame(width: 7, height: 7)
                .opacity(model.pulse ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: model.pulse)

            WaveformView(levels: model.levels, barCount: HUDViewModel.barCount)
                .frame(height: 18)

            Text(formatTimer(model.elapsed))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var processingContent: some View {
        ProgressView()
            .controlSize(.small)
            .progressViewStyle(.circular)
    }

    private func messageContent(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func formatTimer(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Bridges `NSVisualEffectView` (`.hudWindow`, `.behindWindow`, `.active`) into
/// SwiftUI. Provides the pill's frosted background.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Siri-style chromatic halo around the pill. Two layered capsule strokes
/// painted with an angular gradient that rotates continuously, plus a
/// blurred outer glow for the "floating" feel — same vibe as the Siri
/// orb on iPhone or the Apple Intelligence frame.
private struct SiriHalo: View {
    private static let stops: [Color] = [
        Color(red: 0.949, green: 0.659, blue: 0.769),
        Color(red: 0.710, green: 0.659, blue: 0.910),
        Color(red: 0.561, green: 0.737, blue: 0.910),
        Color(red: 0.584, green: 0.863, blue: 0.875),
        Color(red: 0.949, green: 0.659, blue: 0.769),  // wrap back so the rotation is seamless
    ]

    var body: some View {
        TimelineView(.animation) { context in
            // 360° every ~3.5s. Slow enough to feel ambient, fast enough
            // that you can see the colors moving.
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.5) / 3.5
            let angle = Angle.degrees(phase * 360)

            ZStack {
                // Outer glow — bigger, blurred, lower opacity. Sits behind
                // the pill silhouette and bleeds out.
                Capsule()
                    .strokeBorder(
                        AngularGradient(colors: Self.stops, center: .center, angle: angle),
                        lineWidth: 4
                    )
                    .blur(radius: 8)
                    .opacity(0.85)
                    .padding(-2)

                // Crisp ring on the pill edge.
                Capsule()
                    .strokeBorder(
                        AngularGradient(colors: Self.stops, center: .center, angle: angle),
                        lineWidth: 1.2
                    )
                    .opacity(0.95)
            }
        }
    }
}
