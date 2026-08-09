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
    /// Recent RMS samples, throttled to ~3 Hz by HUDController.consumeLevels.
    /// WaveformView animates each bar's height change between successive
    /// values via SwiftUI's `.animation(.easeOut, value: levels)`, so we
    /// don't need a separate smoothing buffer or tick task.
    var levels: [Float] = []
    var elapsed: TimeInterval = 0
    var pulse: Bool = false
    /// Recording continues with the hotkey released (Control was pressed
    /// during the hold). Swaps the pill's leading dot for a lock glyph.
    /// Deliberately untouched by `HUDController.applyPresentation` so it
    /// survives the soft-limit notice → recording re-show.
    var latched: Bool = false

    static let barCount = 26

    func pushLevel(_ value: Float) {
        let clamped = max(0, min(1, value))
        var next = levels
        next.append(clamped)
        if next.count > Self.barCount {
            next.removeFirst(next.count - Self.barCount)
        }
        // Replace the whole array in one assignment — that fires exactly
        // one @Observable invalidation per push, which SwiftUI animates
        // cleanly. The previous element-by-element mutation produced
        // many invalidations per tick and visibly dropped frames.
        levels = next
    }

    func resetLevels() {
        levels = []
    }
}

struct HUDView: View {
    @Bindable var model: HUDViewModel

    /// The visible pill is smaller than the panel — the surrounding gap
    /// is where the SiriHalo's soft bloom can fade. Kept small (3pt) so
    /// the bloom never reaches the rectangular window edge — that was
    /// what previously made the halo look like a square.
    static let haloBleed: CGFloat = 3

    var body: some View {
        ZStack {
            // The pill itself: frosted background + content. We clip the
            // whole inner ZStack to the capsule shape so during the
            // recording → processing morph the (still-fading) recording
            // content can't overflow past the shrinking pill silhouette.
            ZStack {
                VisualEffectBackground()
                    .opacity(0.86)

                // Padding is per-variant — the recording pill needs side
                // padding for its [dot, waveform, timer] HStack, but the
                // 30×30 processing pill is too narrow for any horizontal
                // padding (it'd squeeze the spinner into negative pixels
                // and clip it to a sliver).
                content
            }
            .clipShape(Capsule())
            .padding(Self.haloBleed)
            .overlay(
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
                .transition(.opacity)
        case .processing:
            processingContent
                .transition(.opacity)
        case .error(let message):
            messageContent(message, color: Color(red: 0.922, green: 0.341, blue: 0.341))
                .transition(.opacity)
        case .notice(let message):
            messageContent(message, color: .secondary)
                .transition(.opacity)
        }
    }

    /// Recording-red, shared by the pulsing dot and the latched lock glyph.
    private static let recordingRed = Color(red: 1.0, green: 0.353, blue: 0.353)

    /// Leading indicator. Pulses while the hotkey is physically held;
    /// becomes a static lock once latched — there's no key being held to
    /// pulse along with, and the glyph is what tells the user the release
    /// gesture is now "press and release again".
    @ViewBuilder
    private var recordingIndicator: some View {
        if model.latched {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Self.recordingRed)
                .transition(.opacity)
        } else {
            Circle()
                .fill(Self.recordingRed)
                .frame(width: 5, height: 5)
                .opacity(model.pulse ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: model.pulse)
                .transition(.opacity)
        }
    }

    private var recordingContent: some View {
        HStack(spacing: 6) {
            recordingIndicator

            WaveformView(levels: model.levels, barCount: HUDViewModel.barCount)
                .frame(height: 16)

            Text(formatTimer(model.elapsed))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
    }

    private var processingContent: some View {
        ProcessingDots()
    }

    private func messageContent(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
    }

    private func formatTimer(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Three sequentially-pulsing dots — the "thinking" indicator shown while
/// transcription is in flight. Each dot fades + scales between a dim and
/// fully-bright state with a 0.16 s stagger, ~0.55 s half-cycle, looping
/// forever. The animation is driven by a single State toggle inside an
/// `.animation(.easeInOut.repeatForever(autoreverses: true))` so SwiftUI
/// handles the easing — no TimelineView or per-frame redraw work.
private struct ProcessingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.primary)
                    .frame(width: 5, height: 5)
                    .opacity(animating ? 1.0 : 0.32)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

/// Bridges `NSVisualEffectView` into SwiftUI for the pill's frosted glass.
///
/// Material choice — `.popover` instead of `.hudWindow`: the HUD material
/// is heavy and opaque to keep its content readable through anything; for
/// our small pill we want the desktop to show through more, so the popover
/// material (lighter, more transparent in both light and dark mode) is a
/// better fit. `isEmphasized = false` skips the saturation boost AppKit
/// applies to "active" UI; `behindWindow` still pulls the desktop blur in
/// from behind the panel. Combined with the .opacity(0.78) modifier on the
/// caller side, the pill reads as a soft translucent capsule.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Siri-style chromatic ring around the pill. A thin angular-gradient stroke
/// hugging the capsule edge with a small soft bloom — the bloom stays
/// inside the pill bleed area so the rectangular window boundary never
/// clips it (clipping was producing visible square corners).
private struct SiriHalo: View {
    private static let stops: [Color] = [
        Color(red: 0.949, green: 0.659, blue: 0.769),
        Color(red: 0.710, green: 0.659, blue: 0.910),
        Color(red: 0.561, green: 0.737, blue: 0.910),
        Color(red: 0.584, green: 0.863, blue: 0.875),
        Color(red: 0.949, green: 0.659, blue: 0.769),  // wrap so rotation seams cleanly
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.5) / 3.5
            let angle = Angle.degrees(phase * 360)
            let gradient = AngularGradient(colors: Self.stops, center: .center, angle: angle)

            ZStack {
                // Soft bloom — thin stroke, small blur, low opacity. Stays
                // tight to the capsule edge so it never reaches the
                // rectangular window boundary.
                Capsule()
                    .strokeBorder(gradient, lineWidth: 2)
                    .blur(radius: 2)
                    .opacity(0.55)

                // Crisp colored ring on the pill edge.
                Capsule()
                    .strokeBorder(gradient, lineWidth: 1)
                    .opacity(0.85)
            }
        }
    }
}
