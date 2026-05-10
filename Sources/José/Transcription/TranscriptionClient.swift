import Foundation

enum TranscriptionError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval?)
    case network(underlying: Error)
    case server(status: Int, message: String?)
    case decoding
    case audioReadFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No OpenAI API key configured"
        case .invalidAPIKey: "Invalid OpenAI API key"
        case .rateLimited(let retry):
            if let retry { "Rate limited by OpenAI (retry in \(Int(retry))s)" }
            else         { "Rate limited by OpenAI" }
        case .network(let err): "Network error: \(err.localizedDescription)"
        case .server(let status, let msg): "Server error (\(status)): \(msg ?? "no message")"
        case .decoding: "Could not decode response"
        case .audioReadFailed(let err): "Could not read audio file: \(err.localizedDescription)"
        }
    }
}

/// OpenAI `/v1/audio/transcriptions` REST client.
///
/// One automatic retry on transient failure (5xx OR a network timeout) with
/// 1s backoff. 401 and 429 are surfaced immediately — they are not transient.
/// Spec: §6.4 / handoff §5.6.
@MainActor
final class TranscriptionClient {

    // MARK: - Configuration

    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private static let multipartFileName = "audio.m4a"
    private static let multipartContentType = "audio/mp4"
    private static let retryBackoff: UInt64 = 1_000_000_000 // 1s in ns

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // OpenAI transcription requests can take 5–30s for a 2-minute audio
        // clip; the default 60s request timeout is fine, but the resource
        // timeout (default 7 days) is overkill.
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func transcribe(
        audio: URL,
        prompt: String,
        model: TranscriptionModel
    ) async throws -> String {
        // 1. Check key BEFORE doing any work — fail fast on misconfiguration.
        guard let apiKey = KeychainStore.loadAPIKey() else {
            Logger.transcription.error("transcribe: no API key in keychain")
            throw TranscriptionError.missingAPIKey
        }

        // 2. Read the audio file once. Building multipart bodies in memory is
        // fine here — the m4a is bounded by the 10-min hard cap (~5 MB).
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audio)
        } catch {
            Logger.transcription.error(
                "transcribe: failed to read audio file at \(audio.path): \(error.localizedDescription)"
            )
            throw TranscriptionError.audioReadFailed(underlying: error)
        }

        let boundary = "jose-\(UUID().uuidString)"
        let body = Self.makeMultipartBody(
            boundary: boundary,
            audio: audioData,
            model: model.rawValue,
            prompt: prompt
        )

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        Logger.transcription.info(
            "transcribe: POST /v1/audio/transcriptions model=\(model.rawValue) bytes=\(audioData.count)"
        )

        // 3. Run with one retry on transient failure.
        return try await sendWithRetry(request)
    }

    // MARK: - Retry loop

    private func sendWithRetry(_ request: URLRequest) async throws -> String {
        do {
            return try await send(request)
        } catch let error as TranscriptionError {
            guard Self.shouldRetry(error) else { throw error }
            Logger.transcription.warning(
                "transcribe: transient failure, retrying once after 1s — \(error.localizedDescription)"
            )
            try? await Task.sleep(nanoseconds: Self.retryBackoff)
            return try await send(request)
        }
    }

    private static func shouldRetry(_ error: TranscriptionError) -> Bool {
        switch error {
        case .server(let status, _) where (500...599).contains(status):
            return true
        case .network(let underlying):
            // Only retry on timeouts. DNS / certificate / "not connected"
            // errors are unlikely to flip on a 1s retry.
            if let urlError = underlying as? URLError {
                return urlError.code == .timedOut
            }
            return false
        default:
            return false
        }
    }

    // MARK: - Single request

    private func send(_ request: URLRequest) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw TranscriptionError.network(underlying: urlError)
        } catch {
            throw TranscriptionError.network(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.decoding
        }

        switch http.statusCode {
        case 200...299:
            do {
                let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                Logger.transcription.info(
                    "transcribe: ok (\(decoded.text.count) chars)"
                )
                return decoded.text
            } catch {
                Logger.transcription.error(
                    "transcribe: 2xx but JSON decode failed — \(error.localizedDescription)"
                )
                throw TranscriptionError.decoding
            }

        case 401:
            Logger.transcription.error("transcribe: 401 invalid API key")
            throw TranscriptionError.invalidAPIKey

        case 429:
            let retryAfter = Self.parseRetryAfter(http)
            let retryDesc = retryAfter.map { "\($0)" } ?? "nil"
            Logger.transcription.warning(
                "transcribe: 429 rate limited (retry-after=\(retryDesc))"
            )
            throw TranscriptionError.rateLimited(retryAfter: retryAfter)

        case 500...599:
            let message = Self.parseErrorMessage(from: data)
            Logger.transcription.error(
                "transcribe: \(http.statusCode) server error — \(message ?? "no message")"
            )
            throw TranscriptionError.server(status: http.statusCode, message: message)

        default:
            // 4xx other than 401/429 (e.g., 400 bad request, 413 too large).
            let message = Self.parseErrorMessage(from: data)
            Logger.transcription.error(
                "transcribe: \(http.statusCode) — \(message ?? "no message")"
            )
            throw TranscriptionError.server(status: http.statusCode, message: message)
        }
    }

    // MARK: - Helpers

    private static func parseRetryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        // OpenAI returns an integer number of seconds. RFC 7231 also allows an
        // HTTP-date here, but we don't bother parsing that.
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        return Double(trimmed)
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
            return envelope.error.message
        }
        // Fall back to raw body — useful for log lines, capped to keep logs sane.
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return String(text.prefix(500))
        }
        return nil
    }

    /// Builds an RFC 7578 multipart/form-data body with the four fields the
    /// transcription endpoint expects: file, model, prompt, response_format,
    /// temperature.
    static func makeMultipartBody(
        boundary: String,
        audio: Data,
        model: String,
        prompt: String
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\(crlf)")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            body.append("\(value)\(crlf)")
        }

        // Binary file part first — order doesn't matter to the API but keeps
        // the body easy to eyeball when debugging.
        body.append("--\(boundary)\(crlf)")
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(multipartFileName)\"\(crlf)"
        )
        body.append("Content-Type: \(multipartContentType)\(crlf)\(crlf)")
        body.append(audio)
        body.append(crlf)

        appendField(name: "model", value: model)
        appendField(name: "prompt", value: prompt)
        appendField(name: "response_format", value: "json")
        appendField(name: "temperature", value: "0")

        body.append("--\(boundary)--\(crlf)")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}
