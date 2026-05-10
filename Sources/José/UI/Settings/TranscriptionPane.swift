import SwiftUI

struct TranscriptionPane: View {
    @Bindable var settings: Settings

    @State private var isEditingKey = false
    @State private var draftKey = ""
    @State private var maskedKey = ""
    @State private var testStatus: KeyTestStatus = .idle

    enum KeyTestStatus: Equatable {
        case idle
        case testing
        case valid
        case invalid
        case unreachable

        var label: String? {
            switch self {
            case .idle: nil
            case .testing: "Testing…"
            case .valid: "Key valid ✓"
            case .invalid: "Invalid key"
            case .unreachable: "Couldn't reach OpenAI"
            }
        }

        var color: Color {
            switch self {
            case .idle, .testing: .secondary
            case .valid: Color(red: 0x5D / 255.0, green: 0xD3 / 255.0, blue: 0x9E / 255.0)
            case .invalid: Color(red: 0xEB / 255.0, green: 0x57 / 255.0, blue: 0x57 / 255.0)
            case .unreachable: Color(red: 0xF2 / 255.0, green: 0xC9 / 255.0, blue: 0x4C / 255.0)
            }
        }
    }

    var body: some View {
        PaneScaffold(title: "Transcription", subtitle: "Model, OpenAI key, spoken languages, and the system prompt.") {
            modelCard
            languagesCard
            apiKeyCard
            promptCard
        }
        .onAppear {
            maskedKey = Self.mask(KeychainStore.loadAPIKey())
        }
    }

    private var languagesCard: some View {
        SettingsCard("Spoken languages") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comma-separated. José tells the model to expect these — it will not translate between them. Output stays in whichever language each phrase was actually spoken.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(
                    "e.g. Traditional Chinese, English",
                    text: Binding(
                        get: { settings.spokenLanguages.joined(separator: ", ") },
                        set: { newValue in
                            settings.spokenLanguages = newValue
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var modelCard: some View {
        SettingsCard("Model") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(TranscriptionModel.allCases, id: \.self) { model in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: settings.transcriptionModel == model
                              ? "largecircle.fill.circle"
                              : "circle")
                            .foregroundStyle(settings.transcriptionModel == model
                                             ? Color(red: 0x8B / 255.0, green: 0x7D / 255.0, blue: 1.0)
                                             : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(helperText(for: model))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { settings.transcriptionModel = model }
                }
            }
        }
    }

    private var apiKeyCard: some View {
        SettingsCard("OpenAI API Key") {
            if isEditingKey {
                SecureField("sk-…", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Test") { test() }
                        .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty || testStatus == .testing)
                    Button("Cancel") {
                        isEditingKey = false
                        draftKey = ""
                        testStatus = .idle
                    }
                    Spacer()
                    if let label = testStatus.label {
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundStyle(testStatus.color)
                    }
                }
            } else {
                SettingsRow(
                    "Stored in Keychain",
                    description: maskedKey.isEmpty ? "No key set." : maskedKey
                ) {
                    Button(maskedKey.isEmpty ? "Set Key…" : "Change…") {
                        draftKey = ""
                        testStatus = .idle
                        isEditingKey = true
                    }
                }
            }
        }
    }

    private var promptCard: some View {
        SettingsCard("System Prompt") {
            Text("Sent to OpenAI before every transcription. Customise to bias output toward your domain.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextEditor(text: $settings.systemPrompt)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 160)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            HStack {
                Spacer()
                Button("Reset to default") {
                    settings.systemPrompt = Settings.bundledDefaultPrompt()
                }
                .controlSize(.small)
            }
        }
    }

    private func helperText(for model: TranscriptionModel) -> String {
        switch model {
        case .gpt4oTranscribe:
            "$0.36/hr — best for code-switching"
        case .gpt4oMiniTranscribe:
            "$0.18/hr — half the price; nearly identical on clean audio"
        }
    }

    private func save() {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.saveAPIKey(trimmed)
            maskedKey = Self.mask(trimmed)
            isEditingKey = false
            draftKey = ""
            testStatus = .idle
        } catch {
            Logger.settings.error("save key failed: \(error.localizedDescription)")
        }
    }

    private func test() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        testStatus = .testing
        Task {
            let result = await OpenAIKeyTester.test(key: key)
            await MainActor.run { testStatus = result }
        }
    }

    static func mask(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "" }
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        let prefix = key.prefix(3)
        let suffix = key.suffix(4)
        return "\(prefix)••••••••\(suffix)"
    }
}

/// Hits `/v1/models` to verify a key. Used by both the Transcription pane
/// and the onboarding window.
enum OpenAIKeyTester {
    static func test(key: String) async -> TranscriptionPane.KeyTestStatus {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return .unreachable }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200: return .valid
            case 401, 403: return .invalid
            default: return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}
