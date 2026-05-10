import Foundation
import AppKit

@MainActor
final class ClipboardManager {
    init() {}

    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Snapshots the clipboard, writes `text`, then (after `restoreAfter`)
    /// restores the snapshot iff our text is still the most recent entry.
    /// No-op restore unless `Settings.shared.restorePreviousClipboard` is true.
    func writeAndOptionallyRestore(_ text: String, restoreAfter: Duration) async {
        let pb = NSPasteboard.general
        let snapshotString = pb.string(forType: .string)
        let snapshotChangeCount = pb.changeCount

        pb.clearContents()
        pb.setString(text, forType: .string)
        let writeChangeCount = pb.changeCount

        guard Settings.shared.restorePreviousClipboard else { return }

        try? await Task.sleep(for: restoreAfter)

        guard pb.changeCount == writeChangeCount else {
            Logger.output.debug("clipboard mutated since write — leaving as-is")
            return
        }

        pb.clearContents()
        if let snapshotString {
            pb.setString(snapshotString, forType: .string)
        }
        Logger.output.debug("restored clipboard snapshot (was changeCount=\(snapshotChangeCount))")
    }
}
