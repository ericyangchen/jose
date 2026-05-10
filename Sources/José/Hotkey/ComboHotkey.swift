import Foundation
import KeyboardShortcuts

/// Carbon-backed combo-hotkey path (e.g. ⌘⇧Space). Worker B1 owns the
/// real implementation; this stub keeps the codebase compiling.
@MainActor
final class ComboHotkey {
    private let slot: HotkeySlot
    private let onFire: (HotkeySlot) -> Void

    init(slot: HotkeySlot, onFire: @escaping (HotkeySlot) -> Void) {
        self.slot = slot
        self.onFire = onFire
    }

    func start() {
        Logger.hotkey.warning("ComboHotkey is a stub — feat/hotkey not merged yet")
    }

    func stop() {}
}
