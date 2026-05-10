import Foundation
import Accelerate

/// Computes RMS energy over 30 ms / 480-sample chunks at 16 kHz mono.
/// Output is normalized to a 0...1 range suitable for a meter view.
///
/// Not thread-safe by itself — callers must serialize `process(_:)` calls
/// (the AudioEngine pipeline already runs them on a single tap-driven queue).
final class AudioLevelMonitor {
    private let chunkSamples: Int
    private var pending: [Float] = []
    private let onLevel: (Float) -> Void

    init(chunkSamples: Int = 480, onLevel: @escaping (Float) -> Void) {
        self.chunkSamples = chunkSamples
        self.onLevel = onLevel
        pending.reserveCapacity(chunkSamples * 2)
    }

    /// Append new Float32 samples (16 kHz mono). Emits one normalized RMS
    /// value per fully-collected chunk.
    func process(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        while pending.count >= chunkSamples {
            let chunk = Array(pending.prefix(chunkSamples))
            pending.removeFirst(chunkSamples)
            onLevel(Self.normalize(rms: Self.rms(chunk)))
        }
    }

    /// Flush any remaining partial chunk on stop. Single emission, padded
    /// with zeros to keep the timing roughly stable.
    func flush() {
        guard !pending.isEmpty else { return }
        var chunk = pending
        pending.removeAll(keepingCapacity: true)
        if chunk.count < chunkSamples {
            chunk.append(contentsOf: repeatElement(0, count: chunkSamples - chunk.count))
        }
        onLevel(Self.normalize(rms: Self.rms(chunk)))
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var mean: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            vDSP_measqv(ptr.baseAddress!, 1, &mean, vDSP_Length(samples.count))
        }
        return sqrtf(mean)
    }

    /// Map raw RMS (~0.02–0.3 for normal speech) to a perceptual 0...1
    /// range with a log curve. The window is tuned to expand the
    /// dynamic range of normal speech: very quiet rooms map near 0,
    /// loud syllables hit ~0.9, and the difference between an "uhh"
    /// and a stressed word is visibly different bar heights instead of
    /// both bars saturating at the cap.
    static func normalize(rms: Float) -> Float {
        guard rms > 1e-6 else { return 0 }
        let db = 20 * log10f(rms)            // ~ -120 ... 0
        // -55 dB (very quiet room) → 0, -10 dB (loud speech) → 1.
        let normalized = (db + 55) / 45
        return max(0, min(1, normalized))
    }
}
