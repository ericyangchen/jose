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
    }

    func stop() {
        guard started else { return }
        started = false

        for combo in combos.values { combo.stop() }
        for modifier in modifiers.values { modifier.stop() }
        combos.removeAll()
        modifiers.removeAll()
    }

    /// Re-binding strategy: call stop() + start() after Settings changes.
    /// We deliberately do not observe Settings here — the Settings UI is the
    /// only mutator and it can drive the cycle explicitly when the user
    /// commits a change, keeping ownership of lifecycle in one place.
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
