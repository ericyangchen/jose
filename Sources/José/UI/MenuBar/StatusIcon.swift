import Foundation
import AppKit
import SwiftUI

/// Visual states for the status-bar icon. Spec §4.4.
enum StatusIconState: Equatable {
    case idle
    case recording(level: Float)
    case processing(phase: Double)  // 0.0 ... 1.0, drives spinner rotation
    case error
}

/// SwiftUI Canvas-rendered image for the menu-bar `NSStatusItem`.
/// Three vertical bars (middle tallest), 22×22pt with 2pt vertical padding.
@MainActor
enum StatusIcon {
    static let size = CGSize(width: 22, height: 22)

    /// Renders the given state to an `NSImage` ready to assign to
    /// `NSStatusItem.button.image`. Idle/recording/processing are template
    /// images (system tints them); error keeps its red overlay.
    static func image(for state: StatusIconState) -> NSImage {
        let renderer = ImageRenderer(
            content: StatusIconView(state: state)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let image = renderer.nsImage ?? NSImage(size: size)
        image.size = size
        switch state {
        case .error: image.isTemplate = false
        default: image.isTemplate = true
        }
        return image
    }
}

private struct StatusIconView: View {
    let state: StatusIconState

    var body: some View {
        Canvas { context, canvasSize in
            switch state {
            case .idle:
                drawBars(context: context, size: canvasSize, levels: [0.45, 0.7, 0.45])
            case .recording(let level):
                drawBars(context: context, size: canvasSize, levels: recordingLevels(for: level))
            case .processing(let phase):
                drawSpinner(context: context, size: canvasSize, phase: phase)
            case .error:
                drawBars(context: context, size: canvasSize, levels: [0.45, 0.7, 0.45])
                drawErrorOverlay(context: context, size: canvasSize)
            }
        }
    }

    private func recordingLevels(for level: Float) -> [Double] {
        let l = max(0.0, min(1.0, Double(level)))
        // Slight stagger so the trio doesn't pulse identically.
        let outerA = 0.35 + l * 0.55
        let middle = 0.55 + l * 0.45
        let outerB = 0.30 + l * 0.60
        return [outerA, middle, outerB]
    }

    private func drawBars(context: GraphicsContext, size: CGSize, levels: [Double]) {
        let barCount = 3
        let barWidth: CGFloat = 3
        let spacing: CGFloat = 2
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let originX = (size.width - totalWidth) / 2
        let padding: CGFloat = 2
        let usable = size.height - padding * 2
        let centerY = size.height / 2

        for i in 0..<barCount {
            let h = max(2, CGFloat(levels[i]) * usable)
            let x = originX + CGFloat(i) * (barWidth + spacing)
            let y = centerY - h / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            context.fill(path, with: .color(.primary))
        }
    }

    private func drawSpinner(context: GraphicsContext, size: CGSize, phase: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = 6
        let dotRadius: CGFloat = 1.6
        let dotCount = 3
        for i in 0..<dotCount {
            let angle = (Double(i) / Double(dotCount)) * .pi * 2 + phase * .pi * 2
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            let opacity = 0.35 + 0.65 * (Double(i) / Double(dotCount - 1))
            let rect = CGRect(
                x: x - dotRadius, y: y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(opacity)))
        }
    }

    private func drawErrorOverlay(context: GraphicsContext, size: CGSize) {
        // Triangle badge in the bottom-right corner. Drawn directly so we
        // don't depend on bundled SF Symbols rendering inside Canvas.
        let badgeSize: CGFloat = 11
        let inset: CGFloat = 0
        let rect = CGRect(
            x: size.width - badgeSize - inset,
            y: size.height - badgeSize - inset,
            width: badgeSize,
            height: badgeSize
        )
        let red = Color(nsColor: NSColor(srgbRed: 0xEB/255, green: 0x57/255, blue: 0x57/255, alpha: 1))

        var triangle = Path()
        triangle.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        triangle.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.maxY - 1))
        triangle.addLine(to: CGPoint(x: rect.minX + 0.5, y: rect.maxY - 1))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(red))

        // Exclamation stroke
        let stroke = Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY + 4))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 4))
        }
        context.stroke(stroke, with: .color(.white), lineWidth: 1.2)

        let dotSize: CGFloat = 1.2
        let dotRect = CGRect(
            x: rect.midX - dotSize / 2,
            y: rect.maxY - 3,
            width: dotSize, height: dotSize
        )
        context.fill(Path(ellipseIn: dotRect), with: .color(.white))
    }
}
