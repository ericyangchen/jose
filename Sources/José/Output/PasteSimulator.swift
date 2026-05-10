import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

@MainActor
enum PasteSimulator {
    private static let cmdKey: CGKeyCode = 0x37
    private static let vKey: CGKeyCode = 0x09

    /// Posts a synthetic ⌘V to `cghidEventTap`. Requires Accessibility.
    static func send() {
        guard AXIsProcessTrusted() else {
            Logger.output.warning("AXIsProcessTrusted=false — ⌘V will be a no-op; clipboard-only fallback")
            return
        }

        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            Logger.output.error("failed to create CGEventSource")
            return
        }

        guard
            let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false),
            let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false)
        else {
            Logger.output.error("failed to create CGEvent for ⌘V sequence")
            return
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = .maskCommand

        let tap = CGEventTapLocation.cghidEventTap
        cmdDown.post(tap: tap)
        vDown.post(tap: tap)
        vUp.post(tap: tap)
        cmdUp.post(tap: tap)
    }
}
