import Foundation

/// Public façade over the AVAudioEngine pipeline. Worker B2 (feat/audio)
/// owns the implementation; this stub keeps the codebase compilable until
/// the worker branch lands.
@MainActor
final class AudioEngine {
    private(set) var audioLevelStream: AsyncStream<Float> = .init { _ in }
    private(set) var hadSpeech: Bool = false

    init() {
        // Worker B2 wires up: AVAudioEngine.inputNode → AVAudioConverter
        // (16k mono Float32) → fan-out to AVAudioFile (m4a temp), Silero VAD,
        // and AudioLevelMonitor (RMS).
    }

    /// Begin capturing to a temp .m4a. Throws if the mic is unavailable
    /// or permission is denied.
    func start() async throws {
        Logger.audio.warning("AudioEngine.start() is a stub — feat/audio not merged yet")
    }

    /// Stop capturing and return the temp .m4a URL.
    func stop() async -> URL {
        Logger.audio.warning("AudioEngine.stop() is a stub — feat/audio not merged yet")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("jose-stub-\(UUID().uuidString).m4a")
    }

    /// Cancel without producing a usable file.
    func cancel() async {
        Logger.audio.warning("AudioEngine.cancel() is a stub — feat/audio not merged yet")
    }
}
