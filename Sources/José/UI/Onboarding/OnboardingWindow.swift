import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var completion: (() -> Void)?

    override init() {
        super.init()
    }

    /// Shows the onboarding window if no API key is in Keychain. Calls
    /// `completion` either immediately (key already present) or once the
    /// user verifies and saves a valid key.
    func showIfNeeded(completion: @escaping () -> Void) {
        if KeychainStore.loadAPIKey() != nil {
            completion()
            return
        }
        self.completion = completion
        presentWindow()
    }

    private func presentWindow() {
        let root = OnboardingRootView(
            onFinish: { [weak self] in
                self?.finish()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        let host = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to José"
        window.titlebarAppearsTransparent = true
        window.contentViewController = host
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        self.window = window
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func finish() {
        Defaults.set(true, for: .onboardingCompleted)
        window?.close()
        window = nil
        completion?()
        completion = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Block closing the window unless onboarding completed (i.e. a key
        // was stored). The user can still quit the app outright via the
        // explicit Quit button or ⌘Q.
        return KeychainStore.loadAPIKey() != nil
    }
}

// MARK: - Root view

private struct OnboardingRootView: View {
    let onFinish: () -> Void
    let onQuit: () -> Void

    @State private var key: String = ""
    @State private var status: TranscriptionPane.KeyTestStatus = .idle
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("José")
                    .font(.system(size: 26, weight: .semibold))
                Text("Hold and Say.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Text("José needs your OpenAI API key to transcribe. Your key stays on this Mac in the macOS Keychain — nothing is sent through any third-party server.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                HStack(spacing: 4) {
                    Text("Get a key")
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.system(size: 13, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Paste your key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                SecureField("sk-…", text: $key)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button("Test") { test() }
                    .disabled(trimmed.isEmpty || isWorking)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(status != .valid || isWorking)
                Spacer()
                if let label = status.label {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(status.color)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Quit José") { onQuit() }
                    .controlSize(.small)
                Spacer()
                Text("You can change this later in Settings → Transcription.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 520, height: 420, alignment: .topLeading)
        .background(.regularMaterial)
        .onChange(of: key) { _, _ in
            // Any edit invalidates the previous test result.
            if status != .idle { status = .idle }
        }
    }

    private var trimmed: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func test() {
        let candidate = trimmed
        guard !candidate.isEmpty else { return }
        isWorking = true
        status = .testing
        Task {
            let result = await OpenAIKeyTester.test(key: candidate)
            await MainActor.run {
                status = result
                isWorking = false
            }
        }
    }

    private func save() {
        let candidate = trimmed
        guard status == .valid, !candidate.isEmpty else { return }
        do {
            try KeychainStore.saveAPIKey(candidate)
            onFinish()
        } catch {
            Logger.app.error("onboarding save key failed: \(error.localizedDescription)")
            status = .unreachable
        }
    }
}
