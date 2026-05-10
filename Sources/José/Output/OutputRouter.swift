import Foundation
import AppKit

@MainActor
final class OutputRouter {
    private let clipboard = ClipboardManager()

    init() {}

    func deliver(text: String, action: RecordingAction) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.output.info("empty transcription — nothing to deliver")
            return
        }

        if Settings.shared.restorePreviousClipboard {
            await clipboard.writeAndOptionallyRestore(trimmed, restoreAfter: .milliseconds(500))
        } else {
            clipboard.write(trimmed)
        }

        if action == .pasteAndCopy {
            if !PasteSimulator.isAuthorized {
                // Re-issue the prompt so the user has a one-click path to
                // System Settings → Privacy & Security → Accessibility,
                // even if they dismissed the launch-time dialog.
                PasteSimulator.requestAuthorizationPrompt()
            }
            try? await Task.sleep(for: .milliseconds(30))
            PasteSimulator.send()
        }

        Logger.output.info("delivered \(trimmed.count) chars (\(action.rawValue))")
    }
}
