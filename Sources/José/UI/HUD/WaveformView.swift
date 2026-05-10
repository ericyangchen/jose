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
            let spacing: CGFloat = 1
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max(1, (geo.size.width - totalSpacing) / CGFloat(barCount))
            let height = geo.size.height

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color(at: index))
                        .frame(width: barWidth, height: barHeight(at: index, max: height))
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

    private func barHeight(at index: Int, max maxHeight: CGFloat) -> CGFloat {
        let value = level(at: index)
        // No baseline floor — silence renders as zero-height (invisible)
        // bars instead of a fake idle waveform. The user wants the
        // visualization to be honest: no voice → no bars.
        let scaled = CGFloat(value) * maxHeight
        return min(maxHeight, max(0, scaled))
    }

    // MARK: - Per-bar color (precomputed Siri-gradient sample by position)

    /// Deeper, more saturated Siri palette for the waveform bars.
    /// The HUD halo's pastel stops (~78 % lightness) read fine as a glow,
    /// but on the translucent popover-material pill those same pastels
    /// got washed out — the bars were hard to see. These stops sit at
    /// roughly 55–65 % lightness so they punch against both light and
    /// dark mode pill backgrounds while still looking Siri-chromatic.
    private static let siriStops: [(red: Double, green: Double, blue: Double)] = [
        (0.92, 0.40, 0.62),  // deep rose
        (0.55, 0.40, 0.94),  // vivid purple
        (0.28, 0.58, 0.96),  // deeper blue
        (0.30, 0.78, 0.84),  // deeper cyan
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
