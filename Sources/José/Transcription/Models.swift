import Foundation

/// Successful response from `POST /v1/audio/transcriptions` when
/// `response_format=json`.
///
/// Reference: https://platform.openai.com/docs/api-reference/audio/createTranscription
struct TranscriptionResponse: Decodable {
    let text: String
}

/// Error envelope returned by the OpenAI REST API on non-2xx responses.
///
/// Example body:
/// ```
/// { "error": { "message": "Invalid Authentication", "type": "invalid_request_error", "code": "invalid_api_key" } }
/// ```
struct OpenAIErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let message: String
        let type: String?
        let code: String?
    }

    let error: ErrorBody
}
