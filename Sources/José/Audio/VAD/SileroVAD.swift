import Foundation
import Accelerate
import CoreML

/// Silero VAD wrapper. Loads `SileroVAD.mlpackage` (or its compiled
/// `SileroVAD.mlmodelc` form) from the app bundle. Falls back to an
/// RMS-energy threshold if the Core ML model isn't bundled — that lets
/// the build stay green on machines that haven't run the conversion.
///
/// Not thread-safe — callers must serialize `process(_:)` (the audio
/// pipeline already does, via its dedicated DispatchQueue).
final class SileroVAD {
    /// 30 ms at 16 kHz — the chunk size the upstream audio pipeline emits.
    static let chunkSamples = 480

    /// Speech-probability threshold above which a frame counts as speech.
    /// Silero recommends 0.5; we lean permissive for the "no speech detected"
    /// gate where false negatives cost more than false positives.
    private static let speechProbThreshold: Float = 0.5

    /// Sliding-window smoothing over ~100 ms (3 chunks of 30 ms). A frame
    /// is asserted speech only if the majority of the window agreed.
    private static let smoothingWindow = 3

    /// RMS threshold (post 0...1 normalization) above which a chunk is
    /// considered speech in the fallback path. Tuned permissive.
    private static let rmsSpeechThreshold: Float = 0.01

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
                return prob > Self.speechProbThreshold
            }
            // Inference failure on a single chunk shouldn't abort the loop;
            // fall back to RMS for that frame so the stats stay sane.
            return rmsClassify(chunk)
        case .rms:
            return rmsClassify(chunk)
        }
    }

    private func rmsClassify(_ chunk: [Float]) -> Bool {
        let rms = AudioLevelMonitor.rms(chunk)
        let normalized = AudioLevelMonitor.normalize(rms: rms)
        return normalized > Self.rmsSpeechThreshold
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
        // Xcode compiles .mlpackage → .mlmodelc into the app bundle. We name
        // the bundled package SileroVADModel so Xcode's Core ML codegen
        // doesn't produce a SileroVAD.swift that collides with this file.
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "SileroVADModel", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "SileroVADModel", withExtension: "mlpackage")
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            return nil
        }
        do {
            let compiledURL: URL
            if url.pathExtension == "mlmodelc" {
                compiledURL = url
            } else {
                compiledURL = try MLModel.compileModel(at: url)
            }
            let config = MLModelConfiguration()
            // Neural Engine when available, CPU+GPU otherwise. The model is
            // ~tiny so the choice barely matters for throughput; .all lets
            // CoreML pick.
            config.computeUnits = .all
            let model = try MLModel(contentsOf: compiledURL, configuration: config)
            return CoreMLBackend(model: model)
        } catch {
            Logger.vad.error("failed to load SileroVAD model: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Core ML backend

/// Drives the Silero v5 16 kHz inner model.
///
/// The Core ML model expects a 576-sample audio chunk that we assemble
/// as `[64-sample context from the previous call] + [512 new samples]`.
/// Our upstream pipeline produces 480-sample chunks; the backend buffers
/// them up to 512 internally and only fires the model when it has a
/// fresh 512-sample hop. The 64-sample context is maintained across
/// inferences just like Silero's wrapper does.
///
/// The LSTM hidden state `(h, c)` is also threaded across calls.
private final class CoreMLBackend {
    private static let chunkSamples = 512
    private static let contextSamples = 64
    private static let inputSamples = chunkSamples + contextSamples  // 576
    private static let stateSize = 128

    private let model: MLModel
    private let audioArray: MLMultiArray
    private var hArray: MLMultiArray
    private var cArray: MLMultiArray
    private var context: [Float]
    private var pendingHop: [Float]

    init(model: MLModel) {
        self.model = model
        self.audioArray = try! MLMultiArray(shape: [1, NSNumber(value: Self.inputSamples)], dataType: .float32)
        self.hArray = try! MLMultiArray(shape: [1, NSNumber(value: Self.stateSize)], dataType: .float32)
        self.cArray = try! MLMultiArray(shape: [1, NSNumber(value: Self.stateSize)], dataType: .float32)
        self.context = Array(repeating: 0, count: Self.contextSamples)
        self.pendingHop = []
        self.pendingHop.reserveCapacity(Self.chunkSamples * 2)
        zero(hArray)
        zero(cArray)
    }

    func resetState() {
        zero(hArray)
        zero(cArray)
        for i in 0..<Self.contextSamples { context[i] = 0 }
        pendingHop.removeAll(keepingCapacity: true)
    }

    /// `chunk` is 480 samples (30 ms @ 16 kHz) — the upstream AudioEngine
    /// cadence. We accumulate to 512 (Silero's hop) and only then invoke
    /// the model. Returns the latest probability (the previous one if we
    /// haven't filled a hop yet, smoothed at the SileroVAD layer).
    private var lastProb: Float = 0

    func predict(chunk: [Float]) throws -> Float {
        pendingHop.append(contentsOf: chunk)
        while pendingHop.count >= Self.chunkSamples {
            let hop = Array(pendingHop.prefix(Self.chunkSamples))
            pendingHop.removeFirst(Self.chunkSamples)
            try runInference(newHop: hop)
        }
        return lastProb
    }

    private func runInference(newHop: [Float]) throws {
        // Build the 576-sample input: prior context + new hop.
        let audioPtr = audioArray.dataPointer.bindMemory(
            to: Float.self, capacity: Self.inputSamples
        )
        for i in 0..<Self.contextSamples {
            audioPtr[i] = context[i]
        }
        for i in 0..<Self.chunkSamples {
            audioPtr[Self.contextSamples + i] = newHop[i]
        }

        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "audio": MLFeatureValue(multiArray: audioArray),
            "h_in":  MLFeatureValue(multiArray: hArray),
            "c_in":  MLFeatureValue(multiArray: cArray)
        ])
        let outputs = try model.prediction(from: inputs)

        guard let probArray = outputs.featureValue(for: "speech_prob")?.multiArrayValue else {
            throw VADError.missingOutput("speech_prob")
        }
        guard let nextH = outputs.featureValue(for: "h_out")?.multiArrayValue else {
            throw VADError.missingOutput("h_out")
        }
        guard let nextC = outputs.featureValue(for: "c_out")?.multiArrayValue else {
            throw VADError.missingOutput("c_out")
        }

        lastProb = probArray[0].floatValue
        copyMultiArray(nextH, into: hArray)
        copyMultiArray(nextC, into: cArray)

        // Slide the context forward to the last 64 samples of this hop —
        // exactly what Silero's wrapper does: `_context = x1[-context_size:]`.
        for i in 0..<Self.contextSamples {
            context[i] = newHop[Self.chunkSamples - Self.contextSamples + i]
        }
    }

    private func zero(_ array: MLMultiArray) {
        let count = array.count
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        ptr.update(repeating: 0, count: count)
    }

    private func copyMultiArray(_ src: MLMultiArray, into dst: MLMultiArray) {
        let count = min(src.count, dst.count)
        let s = src.dataPointer.bindMemory(to: Float.self, capacity: count)
        let d = dst.dataPointer.bindMemory(to: Float.self, capacity: count)
        d.update(from: s, count: count)
    }
}

private enum VADError: Error {
    case missingOutput(String)
}
