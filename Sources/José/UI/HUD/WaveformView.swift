import SwiftUI

/// 30 vertical bars whose heights are driven by recent RMS values. Each bar
/// is painted with a horizontal sample of the Siri gradient (spec §4.2 / §4.6).
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
        Canvas { context, size in
            guard barCount > 0 else { return }
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max(1.5, (size.width - totalSpacing) / CGFloat(barCount))
            let midY = size.height / 2

            for index in 0..<barCount {
                let level = level(at: index)
                let height = max(2, min(size.height, CGFloat(level) * 40))
                let x = CGFloat(index) * (barWidth + spacing)
                let rect = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let t = barCount == 1 ? 0 : Double(index) / Double(barCount - 1)
                context.fill(path, with: .color(sampleSiri(at: t)))
            }
        }
    }

    private func level(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0.05 }
        // Right-align: newest sample at the rightmost bar.
        let offset = barCount - levels.count
        let mapped = index - offset
        guard mapped >= 0, mapped < levels.count else { return 0.05 }
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
