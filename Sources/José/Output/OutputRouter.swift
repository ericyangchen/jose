import Foundation
import AppKit

/// Routes a transcription to the clipboard and (for slot A) simulates ⌘V.
/// Worker B4 owns ClipboardManager and PasteSimulator implementations.
@MainActor
final class OutputRouter {
    init() {}

    func deliver(text: String, action: RecordingAction) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.output.info("empty transcription — nothing to deliver")
            return
        }

        // Worker B4 replaces this with the real ClipboardManager which honors
        // Settings.shared.restorePreviousClipboard.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)

        switch action {
        case .copyOnly:
            Logger.output.info("copied to clipboard (\(trimmed.count) chars)")
        case .pasteAndCopy:
            // Worker B4 replaces this with PasteSimulator.send().
            Logger.output.warning(
                "PasteSimulator stub — feat/output not merged yet; clipboard set but ⌘V not sent"
            )
        }
    }
}
