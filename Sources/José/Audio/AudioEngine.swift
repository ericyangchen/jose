import Foundation
@preconcurrency import AVFoundation

enum AudioEngineError: LocalizedError {
    case microphoneUnavailable
    case formatUnsupported
    case recorderInitFailed(Error)
    case engineStartFailed(Error)
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return NSLocalizedString(
                "Microphone is unavailable. Check System Settings → Privacy & Security → Microphone.",
                comment: "")
        case .formatUnsupported:
            return NSLocalizedString(
                "The selected input device's audio format isn't supported.",
                comment: "")
        case .recorderInitFailed(let err):
            return String(format: NSLocalizedString(
                "Couldn't open the recording file: %@", comment: ""),
                          err.localizedDescription)
        case .engineStartFailed(let err):
            return String(format: NSLocalizedString(
                "Audio engine failed to start: %@", comment: ""),
                          err.localizedDescription)
        case .alreadyRunning:
            return NSLocalizedString("Audio engine is already running.", comment: "")
        }
    }
}

/// Façade over the AVAudioEngine pipeline (spec §6.2).
///
/// Pipeline:
///   inputNode (system rate)
///     → AVAudioConverter (16 kHz mono Float32)
///         ├── AVAudioFile (AAC m4a temp)
///         ├── SileroVAD (30 ms / 480-sample chunks)
///         └── AudioLevelMonitor (RMS → audioLevelStream)
///
/// Threading: the public surface is `@MainActor`. AVAudioEngine's tap
/// callback runs on a render thread, so all per-buffer work is funneled
/// through a private serial `DispatchQueue` and the underlying mutable
/// state is `nonisolated(unsafe)`. This keeps the per-buffer hot path off
/// the main actor while preserving a serial happens-before relationship
/// across start/stop/cancel.
@MainActor
final class AudioEngine {
    // MARK: - Public surface

    /// Vends a fresh single-consumer stream of normalized RMS levels
    /// (0...1, ~33 Hz). Each call returns a new AsyncStream; the engine
    /// fans out every level value to every active subscriber so the HUD,
    /// menu-bar icon, and any future consumer can each iterate their own
    /// stream without splitting samples between them.
    func makeLevelStream() -> AsyncStream<Float> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let id = UUID()
            audioQueue.async { [weak self] in
                self?.state.levelSubscribers[id] = continuation
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.audioQueue.async { [weak self] in
                    self?.state.levelSubscribers.removeValue(forKey: id)
                }
            }
        }
    }

    var hadSpeech: Bool {
        audioQueue.sync {
            guard let vad = state.vad else { return false }
            return vad.speechRatio >= 0.05
        }
    }

    // MARK: - Private state (touched only on `audioQueue`)

    private nonisolated(unsafe) var state = State()
    private nonisolated let audioQueue = DispatchQueue(label: "com.eric.jose.audio", qos: .userInteractive)

    private struct State {
        var engine: AVAudioEngine?
        var converter: AVAudioConverter?
        var converterInputFormat: AVAudioFormat?
        var converterOutputFormat: AVAudioFormat?
        var recorder: AudioRecorder?
        var vad: SileroVAD?
        var levels: AudioLevelMonitor?
        var isRunning = false
        /// Active subscribers to the level stream — keyed by the
        /// per-stream UUID so unsubscribe (onTermination) can find its row.
        var levelSubscribers: [UUID: AsyncStream<Float>.Continuation] = [:]
    }

    // MARK: - Init

    init() {
        // Pre-warm the SileroVAD instance on the audio queue so the
        // ~400 ms Core ML model load doesn't sit in front of every
        // recording. By the time the user presses a hotkey for the
        // first time, this background task is almost certainly done.
        // We keep the same instance alive across recordings and just
        // reset its LSTM state between sessions.
        audioQueue.async { [self] in
            if state.vad == nil {
                state.vad = SileroVAD()
            }
        }
    }

    private nonisolated func broadcastLevel(_ level: Float) {
        // Always called on audioQueue (from the audio tap callback).
        for continuation in state.levelSubscribers.values {
            continuation.yield(level)
        }
    }

    // MARK: - Public API

    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            audioQueue.async { [self] in
                do {
                    try self.startOnQueue()
                    cont.resume()
                } catch {
                    self.tearDownOnQueue(deleteFile: true)
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func stop() async -> URL {
        await withCheckedContinuation { (cont: CheckedContinuation<URL, Never>) in
            audioQueue.async { [self] in
                let url = self.stopOnQueue()
                cont.resume(returning: url)
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            audioQueue.async { [self] in
                self.tearDownOnQueue(deleteFile: true)
                cont.resume()
            }
        }
    }

    // MARK: - Queue-bound implementation

    private nonisolated func startOnQueue() throws {
        dispatchPrecondition(condition: .onQueue(audioQueue))
        guard !state.isRunning else { throw AudioEngineError.alreadyRunning }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioEngineError.microphoneUnavailable
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioEngineError.formatUnsupported
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioEngineError.formatUnsupported
        }

        let recorder: AudioRecorder
        do {
            recorder = try AudioRecorder(pcmFormat: outputFormat)
        } catch {
            throw AudioEngineError.recorderInitFailed(error)
        }

        // Reuse the pre-warmed VAD; reset its state so leftover speech
        // counters from the previous recording don't leak into this one.
        // If init's pre-warm task hasn't finished yet (rare), create one
        // here as a fallback — paying the model load cost only this once.
        if state.vad == nil {
            state.vad = SileroVAD()
        }
        let vad = state.vad!
        vad.reset()
        let levels = AudioLevelMonitor { [weak self] level in
            self?.broadcastLevel(level)
        }

        // Tap on the input node in its native format; conversion happens
        // inside the tap callback so we can keep one render-thread hop.
        let tapBufferSize: AVAudioFrameCount = 1024
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            self.audioQueue.async {
                self.handleInputBuffer(buffer)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            recorder.discard()
            throw AudioEngineError.engineStartFailed(error)
        }

        state.engine = engine
        state.converter = converter
        state.converterInputFormat = inputFormat
        state.converterOutputFormat = outputFormat
        state.recorder = recorder
        // state.vad is already set (reused from pre-warm or fallback above).
        state.levels = levels
        state.isRunning = true

        Logger.audio.info("audio engine started — input \(Int(inputFormat.sampleRate)) Hz \(inputFormat.channelCount) ch → 16 kHz mono")
    }

    private nonisolated func stopOnQueue() -> URL {
        dispatchPrecondition(condition: .onQueue(audioQueue))
        guard let recorder = state.recorder else {
            // Engine already torn down or never started — return a
            // placeholder URL so the caller doesn't crash. Coordinator
            // paths that hit this should already have errored out.
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("jose-empty-\(UUID().uuidString).m4a")
        }
        state.levels?.flush()
        let url = recorder.url
        let speechRatio = state.vad?.speechRatio ?? 0
        Logger.audio.info("audio engine stopping — speech ratio \(String(format: "%.2f", speechRatio * 100))%")
        tearDownOnQueue(deleteFile: false)
        return url
    }

    private nonisolated func tearDownOnQueue(deleteFile: Bool) {
        dispatchPrecondition(condition: .onQueue(audioQueue))
        if let engine = state.engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        if deleteFile {
            state.recorder?.discard()
        } else {
            state.recorder?.close()
        }
        state.engine = nil
        state.converter = nil
        state.converterInputFormat = nil
        state.converterOutputFormat = nil
        state.recorder = nil
        // Keep `vad` alive briefly so `hadSpeech` stays meaningful between
        // stop() and the coordinator reading it. It's reset on next start.
        state.levels = nil
        state.isRunning = false
    }

    // MARK: - Hot path (audioQueue)

    private nonisolated func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        dispatchPrecondition(condition: .onQueue(audioQueue))
        guard state.isRunning,
              let converter = state.converter,
              let outFormat = state.converterOutputFormat,
              let recorder = state.recorder,
              let vad = state.vad,
              let levels = state.levels else { return }

        // Output capacity scales with the sample-rate ratio (rounded up).
        let inSR = buffer.format.sampleRate
        let outSR = outFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * outSR / inSR)) + 32

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            return
        }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let error {
            Logger.audio.error("audio converter error: \(error.localizedDescription)")
            return
        }
        guard status != .error, outBuffer.frameLength > 0 else { return }

        // Fan-out: file, VAD, level monitor.
        recorder.append(outBuffer)

        if let channelData = outBuffer.floatChannelData?.pointee {
            let buf = UnsafeBufferPointer(start: channelData, count: Int(outBuffer.frameLength))
            vad.process(buf)
            levels.process(buf)
        }
    }
}
