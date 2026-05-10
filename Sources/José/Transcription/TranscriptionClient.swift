import Foundation

enum TranscriptionError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval?)
    case network(underlying: Error)
    case server(status: Int, message: String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No OpenAI API key configured"
        case .invalidAPIKey: "Invalid OpenAI API key"
        case .rateLimited: "Rate limited by OpenAI"
        case .network(let err): "Network error: \(err.localizedDescription)"
        case .server(let status, let msg): "Server error (\(status)): \(msg ?? "no message")"
        case .decoding: "Could not decode response"
        }
    }
}

/// OpenAI `/v1/audio/transcriptions` REST client. Worker B3 owns the
/// multipart upload, retry, and error mapping; the type signature below
/// is the contract AppCoordinator depends on.
@MainActor
final class TranscriptionClient {
    init() {}

    func transcribe(
        audio: URL,
        prompt: String,
        model: TranscriptionModel
    ) async throws -> String {
        Logger.transcription.warning(
            "TranscriptionClient.transcribe is a stub — feat/transcription not merged yet"
        )
        throw TranscriptionError.missingAPIKey
    }
}

/// Worker B3 also implements PromptBuilder. Stub kept here so AppCoordinator
/// type-checks.
enum PromptBuilder {
    static func build(from settings: Settings) -> String {
        var lines = [settings.systemPrompt]
        let vocab = enabledVocabulary(for: settings)
        if !vocab.isEmpty {
            lines.append("")
            lines.append("Common technical terms in this user's vocabulary:")
            lines.append(vocab.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private static func enabledVocabulary(for settings: Settings) -> [String] {
        // Worker B3 replaces this with the parsed bundled YAML; the stub
        // returns just the user's custom additions so the prompt still works.
        settings.customVocabulary
    }
}
