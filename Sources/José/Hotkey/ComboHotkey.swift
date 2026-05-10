import Foundation
import KeyboardShortcuts

@MainActor
final class ComboHotkey {
    enum Mode {
        case hold
        case toggle
    }

    private let slot: HotkeySlot
    private let mode: Mode
    private let onDown: (HotkeySlot) -> Void
    private let onUp: (HotkeySlot) -> Void
    private let onFire: (HotkeySlot) -> Void

    private var started: Bool = false

    init(
        slot: HotkeySlot,
        mode: Mode,
        onDown: @escaping (HotkeySlot) -> Void,
        onUp: @escaping (HotkeySlot) -> Void,
        onFire: @escaping (HotkeySlot) -> Void
    ) {
        self.slot = slot
        self.mode = mode
        self.onDown = onDown
        self.onUp = onUp
        self.onFire = onFire
    }

    func start() {
        guard !started else { return }
        started = true

        let name = slot.keyboardShortcutsName

        // Clear anything left over from a prior start cycle so re-binding is safe.
        KeyboardShortcuts.removeHandler(for: name)

        switch mode {
        case .toggle:
            KeyboardShortcuts.onKeyDown(for: name) { [slot, onFire] in
                Task { @MainActor in onFire(slot) }
            }

        case .hold:
            // Carbon RegisterEventHotKey has no release semantics for combos
            // with non-modifier triggers (spec §6.1.2 / handoff §5.3). Falling
            // back to fire-mode keeps the hotkey usable even when the user
            // has hold-mode selected for a combo binding.
            Logger.hotkey.warning(
                "ComboHotkey \(self.slot.rawValue) requested hold mode — Carbon hotkeys lack release events for combos, falling back to toggle/fire semantics"
            )
            KeyboardShortcuts.onKeyDown(for: name) { [slot, onFire] in
                Task { @MainActor in onFire(slot) }
            }
        }

        Logger.hotkey.info("ComboHotkey \(self.slot.rawValue) started (mode=\(String(describing: self.mode)))")
    }

    func stop() {
        guard started else { return }
        started = false
        KeyboardShortcuts.removeHandler(for: slot.keyboardShortcutsName)
    }
}
