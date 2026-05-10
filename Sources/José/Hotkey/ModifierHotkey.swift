import Foundation
import AppKit

/// Single-modifier hotkey (Right Option, Right Command, Fn, etc.). Worker B1
/// owns the flagsChanged-based implementation that emits both down and up
/// events using the device-specific raw bits.
@MainActor
final class ModifierHotkey {
    private let slot: HotkeySlot
    private let mask: UInt
    private let onDown: (HotkeySlot) -> Void
    private let onUp: (HotkeySlot) -> Void

    init(
        slot: HotkeySlot,
        mask: UInt,
        onDown: @escaping (HotkeySlot) -> Void,
        onUp: @escaping (HotkeySlot) -> Void
    ) {
        self.slot = slot
        self.mask = mask
        self.onDown = onDown
        self.onUp = onUp
    }

    func start() {
        Logger.hotkey.warning("ModifierHotkey is a stub — feat/hotkey not merged yet")
    }

    func stop() {}
}
