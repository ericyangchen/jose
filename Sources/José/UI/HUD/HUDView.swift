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

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(Capsule())

            content
                .padding(.horizontal, 20)
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
