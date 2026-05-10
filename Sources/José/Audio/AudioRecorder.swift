import Foundation
import AVFoundation

/// Writes incoming Float32 PCM (16 kHz mono) to a temp `.m4a` file via
/// `AVAudioFile`, which transparently re-encodes to AAC.
///
/// Not thread-safe — callers must serialize `append(_:)` / `close()` (the
/// audio pipeline does so on its dedicated DispatchQueue).
final class AudioRecorder {
    let url: URL
    private let pcmFormat: AVAudioFormat
    private var file: AVAudioFile?

    /// Designated init. Throws if the underlying file can't be opened
    /// (e.g. disk full, sandboxed temp path missing). The output file is
    /// AAC-in-MP4 sampled at 16 kHz mono.
    init(pcmFormat: AVAudioFormat) throws {
        self.pcmFormat = pcmFormat
        self.url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jose-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        self.file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: pcmFormat.commonFormat,
            interleaved: pcmFormat.isInterleaved
        )
    }

    /// Append a buffer in the PCM Float32 16 kHz mono format. Silently
    /// returns if the file has been closed.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let file else { return }
        do {
            try file.write(from: buffer)
        } catch {
            Logger.audio.error("AudioRecorder write failed: \(error.localizedDescription)")
        }
    }

    /// Close the file. Subsequent `append` calls are no-ops.
    func close() {
        file = nil
    }

    /// Close the file and remove it from disk. Safe to call multiple times.
    func discard() {
        close()
        try? FileManager.default.removeItem(at: url)
    }
}
