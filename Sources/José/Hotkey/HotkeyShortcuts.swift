import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Slot A — transcribe and paste at the cursor (spec §3.3).
    static let transcribeAndPaste = Self("transcribeAndPaste")

    /// Slot B — transcribe and copy only (spec §3.3).
    static let transcribeAndCopy = Self("transcribeAndCopy")
}

extension HotkeySlot {
    var keyboardShortcutsName: KeyboardShortcuts.Name {
        switch self {
        case .A: .transcribeAndPaste
        case .B: .transcribeAndCopy
        }
    }
}
