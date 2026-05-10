import Foundation
import AppKit

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidGoDown(_ slot: HotkeySlot)
    func hotkeyDidGoUp(_ slot: HotkeySlot)
    /// Toggle-mode hotkeys only emit "fired" — the manager translates this
    /// into a synthetic down/up pair based on current recording state.
    func hotkeyDidFire(_ slot: HotkeySlot)
}

@MainActor
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    private let settings: Settings

    private var combos: [HotkeySlot: ComboHotkey] = [:]
    private var modifiers: [HotkeySlot: ModifierHotkey] = [:]
    private var started: Bool = false

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        guard !started else { return }
        started = true

        bind(slot: .A)
        bind(slot: .B)
        observeSettings()
    }

    func stop() {
        guard started else { return }
        started = false

        for combo in combos.values { combo.stop() }
        for modifier in modifiers.values { modifier.stop() }
        combos.removeAll()
        modifiers.removeAll()
    }

    /// Tear down the active bindings and re-build them from the current
    /// settings. Called automatically when the user changes a hotkey or
    /// mode in the Settings UI (see `observeSettings`).
    private func rebind() {
        for combo in combos.values { combo.stop() }
        for modifier in modifiers.values { modifier.stop() }
        combos.removeAll()
        modifiers.removeAll()
        bind(slot: .A)
        bind(slot: .B)
    }

    /// `withObservationTracking` fires its onChange exactly once per
    /// arming. Re-arm after every change so subsequent edits in Settings
    /// also trigger a rebind.
    private func observeSettings() {
        withObservationTracking {
            // Touch every binding-related setting so the tracker covers
            // all of them.
            _ = settings.hotkeyAModifierMask
            _ = settings.hotkeyBModifierMask
            _ = settings.hotkeyAMode
            _ = settings.hotkeyBMode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started else { return }
                Logger.hotkey.info("settings changed — rebinding hotkeys")
                self.rebind()
                self.observeSettings()
            }
        }
    }

    private func bind(slot: HotkeySlot) {
        let mask = self.mask(for: slot)
        let mode = self.mode(for: slot)

        if let mask, mask != 0 {
            let modifierMode: ModifierHotkey.Mode = (mode == .hold) ? .hold : .toggle
            let hotkey = ModifierHotkey(
                slot: slot,
                mask: mask,
                mode: modifierMode,
                onDown: { [weak self] s in self?.delegate?.hotkeyDidGoDown(s) },
                onUp: { [weak self] s in self?.delegate?.hotkeyDidGoUp(s) },
                onFire: { [weak self] s in self?.delegate?.hotkeyDidFire(s) }
            )
            hotkey.start()
            modifiers[slot] = hotkey
        } else {
            let comboMode: ComboHotkey.Mode = (mode == .hold) ? .hold : .toggle
            let hotkey = ComboHotkey(
                slot: slot,
                mode: comboMode,
                onDown: { [weak self] s in self?.delegate?.hotkeyDidGoDown(s) },
                onUp: { [weak self] s in self?.delegate?.hotkeyDidGoUp(s) },
                onFire: { [weak self] s in self?.delegate?.hotkeyDidFire(s) }
            )
            hotkey.start()
            combos[slot] = hotkey
        }
    }

    private func mask(for slot: HotkeySlot) -> UInt? {
        switch slot {
        case .A: settings.hotkeyAModifierMask
        case .B: settings.hotkeyBModifierMask
        }
    }

    private func mode(for slot: HotkeySlot) -> HotkeyMode {
        switch slot {
        case .A: settings.hotkeyAMode
        case .B: settings.hotkeyBMode
        }
    }
}
