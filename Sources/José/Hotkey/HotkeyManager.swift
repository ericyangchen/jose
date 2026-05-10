import Foundation
import AppKit

/// Owns combo-hotkey + modifier-hotkey paths and forwards down/up events to
/// the AppCoordinator. The two implementations live in separate files
/// (ComboHotkey.swift, ModifierHotkey.swift) — this file is the public façade
/// the rest of the app talks to.
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

    init(settings: Settings) {
        self.settings = settings
    }

    /// Worker B1 implements the actual registration logic in
    /// ComboHotkey.swift + ModifierHotkey.swift and surfaces it via these
    /// two methods.
    func start() {
        // Implementation provided by feat/hotkey worker.
    }

    func stop() {
        // Implementation provided by feat/hotkey worker.
    }
}
