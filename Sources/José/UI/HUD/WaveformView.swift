import SwiftUI

/// Vertical bars whose heights track the recent RMS values, painted with
/// the Siri gradient (spec §4.2 / §4.6).
///
/// The previous implementation used `Canvas` inside a 60 Hz `TimelineView`
/// plus a separate smoothing `Task` mutating an interpolated levels
/// array — three competing redraw paths that fought on the main actor and
/// produced visible frame drops at 60 Hz. The new implementation uses an
/// `HStack` of `Capsule` shapes with `.animation(.easeOut, value: levels)`
/// — SwiftUI animates each bar's height change natively and hardware-
/// accelerated, with one redraw per push and no extra task overhead.
struct WaveformView: View {
    let levels: [Float]
    let barCount: Int

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max(1.5, (geo.size.width - totalSpacing) / CGFloat(barCount))
            let height = geo.size.height
            let baseline = max(2, height * 0.12)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color(at: index))
                        .frame(width: barWidth, height: barHeight(at: index, max: height, baseline: baseline))
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .center)
        }
        // Animation outlasts the inter-push interval (~250 ms) so the
        // bars are always interpolating — never frozen mid-frame waiting
        // for the next sample. easeOut feels like a VU meter snap.
        .animation(.easeOut(duration: 0.22), value: levels)
    }

    // MARK: - Per-bar level lookup (right-aligned, newest at the right)

    private func level(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0 }
        let offset = barCount - levels.count
        let mapped = index - offset
        guard mapped >= 0, mapped < levels.count else { return 0 }
        return levels[mapped]
    }

    private func barHeight(at index: Int, max maxHeight: CGFloat, baseline: CGFloat) -> CGFloat {
        let value = level(at: index)
        let scaled = CGFloat(value) * maxHeight
        return min(maxHeight, max(baseline, scaled))
    }

    // MARK: - Per-bar color (precomputed Siri-gradient sample by position)

    private static let siriStops: [(red: Double, green: Double, blue: Double)] = [
        (0.949, 0.659, 0.769),
        (0.710, 0.659, 0.910),
        (0.561, 0.737, 0.910),
        (0.584, 0.863, 0.875),
    ]

    private func color(at index: Int) -> Color {
        let t: Double = barCount <= 1 ? 0 : Double(index) / Double(barCount - 1)
        let stops = Self.siriStops
        let scaled = max(0, min(1, t)) * Double(stops.count - 1)
        let lower = Int(scaled.rounded(.down))
        let upper = min(stops.count - 1, lower + 1)
        let frac = scaled - Double(lower)
        let a = stops[lower]
        let b = stops[upper]
        return Color(
            red: a.red + (b.red - a.red) * frac,
            green: a.green + (b.green - a.green) * frac,
            blue: a.blue + (b.blue - a.blue) * frac
        )
    }
}
