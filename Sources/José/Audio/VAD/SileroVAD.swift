import Foundation
import Accelerate
import CoreML

/// Silero VAD wrapper with an RMS-pseudo-VAD fallback.
///
/// The Core ML conversion of Silero v5 currently fails on coremltools 8.x
/// (see `convert_silero.py`); for v1 we ship the fallback. The Core ML
/// codepath is sketched here so it can be activated once the model lands —
/// either way the public surface is the same.
///
/// Not thread-safe — callers must serialize `process(_:)` (the audio
/// pipeline already does, via its dedicated DispatchQueue).
final class SileroVAD {
    /// 30 ms at 16 kHz.
    static let chunkSamples = 480

    /// RMS threshold (post 0...1 normalization) above which a chunk is
    /// considered speech. Tuned to be permissive — false negatives are
    /// worse than false positives for the "no speech detected" warning.
    private static let speechRMSThreshold: Float = 0.01

    /// Sliding-window smoothing over ~100 ms (3 chunks of 30 ms). Speech
    /// is asserted only if the majority of the window is above threshold.
    private static let smoothingWindow = 3

    private var pending: [Float] = []
    private var windowVotes: [Bool] = []
    private var totalChunks: Int = 0
    private var speechChunks: Int = 0

    private let backend: Backend

    init() {
        if let coreml = Self.tryLoadCoreML() {
            self.backend = .coreml(coreml)
            Logger.vad.info("SileroVAD: using CoreML backend")
        } else {
            self.backend = .rms
            Logger.vad.warning("SileroVAD: model unavailable, using RMS fallback")
        }
        pending.reserveCapacity(Self.chunkSamples * 2)
        windowVotes.reserveCapacity(Self.smoothingWindow)
    }

    // MARK: - Public

    /// Total ratio of chunks classified as speech across the recording's
    /// lifetime. AudioEngine.hadSpeech checks this against ≥ 5%.
    var speechRatio: Float {
        guard totalChunks > 0 else { return 0 }
        return Float(speechChunks) / Float(totalChunks)
    }

    /// Feed Float32 samples (16 kHz mono). Each completed 480-sample chunk
    /// is classified and folded into `speechRatio`.
    func process(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        while pending.count >= Self.chunkSamples {
            let chunk = Array(pending.prefix(Self.chunkSamples))
            pending.removeFirst(Self.chunkSamples)
            let raw = classify(chunk)
            let smoothed = smooth(raw)
            totalChunks += 1
            if smoothed { speechChunks += 1 }
        }
    }

    func reset() {
        pending.removeAll(keepingCapacity: true)
        windowVotes.removeAll(keepingCapacity: true)
        totalChunks = 0
        speechChunks = 0
        if case .coreml(let m) = backend {
            m.resetState()
        }
    }

    // MARK: - Private

    private func classify(_ chunk: [Float]) -> Bool {
        switch backend {
        case .coreml(let model):
            if let prob = try? model.predict(chunk: chunk) {
                return prob > 0.5
            }
            return rmsClassify(chunk)
        case .rms:
            return rmsClassify(chunk)
        }
    }

    private func rmsClassify(_ chunk: [Float]) -> Bool {
        let rms = AudioLevelMonitor.rms(chunk)
        let normalized = AudioLevelMonitor.normalize(rms: rms)
        return normalized > Self.speechRMSThreshold
    }

    private func smooth(_ flag: Bool) -> Bool {
        windowVotes.append(flag)
        if windowVotes.count > Self.smoothingWindow {
            windowVotes.removeFirst(windowVotes.count - Self.smoothingWindow)
        }
        let positive = windowVotes.filter { $0 }.count
        return positive * 2 > windowVotes.count
    }

    // MARK: - Backend

    private enum Backend {
        case coreml(CoreMLBackend)
        case rms
    }

    private static func tryLoadCoreML() -> CoreMLBackend? {
        guard let url = Bundle.main.url(forResource: "SileroVAD", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "SileroVAD", withExtension: "mlmodel") else {
            return nil
        }
        do {
            let compiled: URL
            if url.pathExtension == "mlmodelc" {
                compiled = url
            } else {
                compiled = try MLModel.compileModel(at: url)
            }
            let config = MLModelConfiguration()
            let model = try MLModel(contentsOf: compiled, configuration: config)
            return CoreMLBackend(model: model)
        } catch {
            Logger.vad.error("failed to load SileroVAD model: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Thin Core ML wrapper. Silero v5 expects a 512-sample chunk + a 2×1×128
/// LSTM state; we pad/truncate the 480-sample input to 512.
///
/// This codepath is currently unreachable in v1 (no .mlmodelc bundled) but
/// the implementation is ready for when conversion is fixed.
private final class CoreMLBackend {
    private let model: MLModel
    private static let inputSamples = 512
    private static let stateShape: [NSNumber] = [2, 1, 128]
    private var state: MLMultiArray

    init(model: MLModel) {
        self.model = model
        self.state = try! MLMultiArray(shape: Self.stateShape, dataType: .float32)
        zero(state)
    }

    func resetState() {
        zero(state)
    }

    func predict(chunk: [Float]) throws -> Float {
        var padded = chunk
        if padded.count < Self.inputSamples {
            padded.append(contentsOf: repeatElement(0, count: Self.inputSamples - padded.count))
        } else if padded.count > Self.inputSamples {
            padded = Array(padded.prefix(Self.inputSamples))
        }

        let audio = try MLMultiArray(shape: [1, NSNumber(value: Self.inputSamples)], dataType: .float32)
        for i in 0..<Self.inputSamples {
            audio[i] = NSNumber(value: padded[i])
        }
        let sr = try MLMultiArray(shape: [1], dataType: .int32)
        sr[0] = NSNumber(value: Int32(16000))

        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "audio_chunk": MLFeatureValue(multiArray: audio),
            "state": MLFeatureValue(multiArray: state),
            "sr": MLFeatureValue(multiArray: sr)
        ])
        let outputs = try model.prediction(from: inputs)

        if let next = outputs.featureValue(for: "next_state")?.multiArrayValue {
            state = next
        }
        guard let prob = outputs.featureValue(for: "speech_prob")?.multiArrayValue else {
            return 0
        }
        return prob[0].floatValue
    }

    private func zero(_ array: MLMultiArray) {
        let count = array.count
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(array.dataPointer))
        ptr.update(repeating: 0, count: count)
    }
}
