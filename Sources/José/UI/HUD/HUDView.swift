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
    /// Newly-arrived RMS samples (one per ~140 ms after throttling).
    /// `pushLevel` appends here; the smoothing tick interpolates the
    /// displayedLevels view-state toward these targets.
    var levels: [Float] = []
    /// What the WaveformView actually draws — interpolates each frame
    /// toward `levels` so bar height transitions are smooth instead of
    /// stepwise.
    var displayedLevels: [Float] = []
    var elapsed: TimeInterval = 0
    var pulse: Bool = false

    static let barCount = 24

    func pushLevel(_ value: Float) {
        let clamped = max(0, min(1, value))
        levels.append(clamped)
        if levels.count > Self.barCount {
            levels.removeFirst(levels.count - Self.barCount)
        }
        // Make sure displayedLevels has the same length so the smoothing
        // tick has a target slot for every bar. New slots start near zero
        // so the bar grows in from the baseline rather than popping in.
        while displayedLevels.count < levels.count {
            displayedLevels.append(0)
        }
        if displayedLevels.count > Self.barCount {
            displayedLevels.removeFirst(displayedLevels.count - Self.barCount)
        }
    }

    /// Called at ~60 Hz from HUDController during recording. Eases each
    /// displayed value toward its target. Lerp factor 0.22 was tuned by
    /// eye — bars track the voice but don't feel jittery.
    func tickSmoothing() {
        guard displayedLevels.count == levels.count else { return }
        let lerp: Float = 0.22
        for i in 0..<displayedLevels.count {
            displayedLevels[i] += (levels[i] - displayedLevels[i]) * lerp
        }
    }

    func resetLevels() {
        levels.removeAll(keepingCapacity: true)
        displayedLevels.removeAll(keepingCapacity: true)
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
            // The pill itself: frosted background + content.
            ZStack {
                VisualEffectBackground()
                    .clipShape(Capsule())

                // Padding is per-variant — the recording pill needs side
                // padding for its [dot, waveform, timer] HStack, but the
                // 36×36 processing pill is too narrow for any horizontal
                // padding (it'd squeeze the spinner into negative pixels
                // and clip it to a sliver).
                content
            }
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

            WaveformView(levels: model.displayedLevels, barCount: HUDViewModel.barCount)
                .frame(height: 24)

            Text(formatTimer(model.elapsed))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
    }

    private var processingContent: some View {
        // No outer padding — the processing pill is square (~36×36) and
        // any horizontal padding squashes the indeterminate ProgressView
        // into a clipped sliver. Centered in the parent ZStack.
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
            .padding(.horizontal, 16)
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
