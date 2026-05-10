import SwiftUI

/// 30 vertical bars whose heights are driven by recent RMS values. Each bar
/// is painted with a horizontal sample of the Siri gradient (spec §4.2 / §4.6).
///
/// Wrapped in a TimelineView so SwiftUI guarantees a redraw on every frame
/// even if the @Observable invalidation arrives a tick late — without it
/// the bars freeze on shorter HUD pills where height changes between
/// adjacent samples don't pass SwiftUI's diffing threshold.
struct WaveformView: View {
    let levels: [Float]
    let barCount: Int

    private static let siriStops: [Color] = [
        Color(red: 0.949, green: 0.659, blue: 0.769),
        Color(red: 0.710, green: 0.659, blue: 0.910),
        Color(red: 0.561, green: 0.737, blue: 0.910),
        Color(red: 0.584, green: 0.863, blue: 0.875),
    ]

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                drawBars(context: context, size: size)
            }
        }
    }

    private func drawBars(context: GraphicsContext, size: CGSize) {
        guard barCount > 0 else { return }
        let spacing: CGFloat = 2
        let totalSpacing = spacing * CGFloat(barCount - 1)
        let barWidth = max(1.5, (size.width - totalSpacing) / CGFloat(barCount))
        let midY = size.height / 2

        // Floor every bar at ~12% of the pill height so silence still
        // shows a faint baseline (otherwise the waveform reads as "off"
        // between syllables).
        let minHeight = max(2, size.height * 0.12)

        for index in 0..<barCount {
            let level = level(at: index)
            // Scale relative to pill height. log-style normalize is already
            // baked into AudioLevelMonitor, so a linear map is right here.
            let scaled = max(minHeight, CGFloat(level) * size.height)
            let height = min(size.height, scaled)
            let x = CGFloat(index) * (barWidth + spacing)
            let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            let t = barCount == 1 ? 0 : Double(index) / Double(barCount - 1)
            context.fill(path, with: .color(sampleSiri(at: t)))
        }
    }

    private func level(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0.06 }
        // Right-align: newest sample at the rightmost bar, older samples slide left.
        let offset = barCount - levels.count
        let mapped = index - offset
        guard mapped >= 0, mapped < levels.count else { return 0.06 }
        return levels[mapped]
    }

    private func sampleSiri(at t: Double) -> Color {
        let stops = Self.siriStops
        let clamped = max(0, min(1, t))
        let scaled = clamped * Double(stops.count - 1)
        let lower = Int(scaled.rounded(.down))
        let upper = min(stops.count - 1, lower + 1)
        let frac = scaled - Double(lower)
        return stops[lower].interpolated(toward: stops[upper], by: frac)
    }
}

private extension Color {
    func interpolated(toward other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .white
        let r = a.redComponent + (b.redComponent - a.redComponent) * amount
        let g = a.greenComponent + (b.greenComponent - a.greenComponent) * amount
        let bl = a.blueComponent + (b.blueComponent - a.blueComponent) * amount
        return Color(red: r, green: g, blue: bl)
    }
}
