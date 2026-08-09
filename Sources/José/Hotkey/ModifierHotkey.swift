import Foundation
import AppKit

@MainActor
final class ModifierHotkey {
    enum Mode {
        case hold
        case toggle
    }

    private let slot: HotkeySlot
    private let mask: UInt
    private let mode: Mode
    private let onDown: (HotkeySlot) -> Void
    private let onUp: (HotkeySlot) -> Void
    private let onFire: (HotkeySlot) -> Void
    private let onLatch: (HotkeySlot) -> Void

    /// Public `NSEvent.ModifierFlags.control` bit. Unlike the hotkey masks
    /// themselves — which need the `NX_DEVICE*` bits to tell left from
    /// right — the latch key doesn't care which Control was pressed, so
    /// the public bit is both simpler and independent of device-bit layout.
    private static let controlFlag: UInt = NSEvent.ModifierFlags.control.rawValue

    /// Device bits for either Control key, used only to detect the
    /// degenerate case where Control *is* the hotkey.
    private static let controlMaskBits: UInt = ModifierMask.leftControl | ModifierMask.rightControl

    /// Latching only makes sense in hold mode (toggle is already
    /// hands-free), and only when the hotkey itself isn't a Control key —
    /// otherwise the latch key would be the hotkey.
    private var latchEnabled: Bool {
        mode == .hold && (mask & Self.controlMaskBits) == 0
    }

    /// Spec §3.4 / §6.1.3 — short taps under 50 ms are silently dropped so a
    /// stray finger graze never starts an upload.
    private let armingDelay: Duration = .milliseconds(50)

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var lastFlags: UInt = 0
    private var isDown: Bool = false
    private var armingTask: Task<Void, Never>?

    init(
        slot: HotkeySlot,
        mask: UInt,
        mode: Mode,
        onDown: @escaping (HotkeySlot) -> Void,
        onUp: @escaping (HotkeySlot) -> Void,
        onFire: @escaping (HotkeySlot) -> Void,
        onLatch: @escaping (HotkeySlot) -> Void
    ) {
        self.slot = slot
        self.mask = mask
        self.mode = mode
        self.onDown = onDown
        self.onUp = onUp
        self.onFire = onFire
        self.onLatch = onLatch
    }

    func start() {
        guard mask != 0 else {
            Logger.hotkey.warning("ModifierHotkey \(self.slot.rawValue) started with empty mask — skipping")
            return
        }

        // Seed lastFlags from the current modifier state. Eating the
        // first event (the previous fix) caused the user's first press
        // after launch to be silently dropped — the press itself *was*
        // the seed event. Use NSEvent.modifierFlags's public bits to
        // figure out whether the watched modifier is currently held,
        // and write the corresponding device-specific mask bit so the
        // first real transition is detected correctly.
        lastFlags = Self.currentRawFlags(forMask: mask)

        // Two monitors: global fires while another app is focused, local fires
        // when José itself has focus (global skips own-app events).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handle(event: event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handle(event: event) }
            return event
        }

        Logger.hotkey.info("ModifierHotkey \(self.slot.rawValue) started (mask=0x\(String(self.mask, radix: 16)), mode=\(String(describing: self.mode)))")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }

        armingTask?.cancel()
        armingTask = nil

        if isDown {
            // Defensive: if we're torn down mid-hold, release so coordinator
            // doesn't get stuck thinking the key is still held.
            isDown = false
            onUp(slot)
        }
    }

    private func handle(event: NSEvent) {
        let flags = UInt(event.modifierFlags.rawValue)
        let prev = lastFlags
        lastFlags = flags

        let bitWasSet = (prev & mask) == mask
        let bitIsSet = (flags & mask) == mask

        if !bitWasSet && bitIsSet {
            handleDown()
        } else if bitWasSet && !bitIsSet {
            handleUp()
        } else if latchEnabled, isDown,
                  (prev & Self.controlFlag) == 0,
                  (flags & Self.controlFlag) != 0 {
            // Control pressed while the hotkey is held — latch the
            // recording so the user can let go and keep talking. The
            // reverse order (Control already held when the hotkey goes
            // down) is handled in handleDown's arming task.
            onLatch(slot)
        }
    }

    /// Best-effort read of the current modifier state at start time.
    /// `NSEvent.modifierFlags` is a public-bit set (no left/right
    /// distinction); this maps it back into the device-specific mask
    /// space so `lastFlags` is seeded with the right bit when the user
    /// is *already* holding the hotkey at hotkey-manager start. For
    /// left/right-distinct modifiers we conservatively assume the
    /// watched side is the one held — worst case: one stray .up event
    /// if it was actually the other side, harmlessly ignored because
    /// `isDown` is false.
    private static func currentRawFlags(forMask mask: UInt) -> UInt {
        let publicFlags = NSEvent.modifierFlags
        switch mask {
        case ModifierMask.fn:
            return publicFlags.contains(.function) ? mask : 0
        case ModifierMask.leftOption, ModifierMask.rightOption:
            return publicFlags.contains(.option) ? mask : 0
        case ModifierMask.leftCommand, ModifierMask.rightCommand:
            return publicFlags.contains(.command) ? mask : 0
        case ModifierMask.leftShift, ModifierMask.rightShift:
            return publicFlags.contains(.shift) ? mask : 0
        case ModifierMask.leftControl, ModifierMask.rightControl:
            return publicFlags.contains(.control) ? mask : 0
        default:
            return 0
        }
    }

    private func handleDown() {
        switch mode {
        case .toggle:
            // Single-modifier toggle: each press flips. We do not emit up.
            onFire(slot)

        case .hold:
            // Delay actual .down emission by armingDelay; if .up arrives first
            // the task is cancelled and nothing fires (it was a tap).
            armingTask?.cancel()
            armingTask = Task { [weak self, slot, armingDelay] in
                try? await Task.sleep(for: armingDelay)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.isDown = true
                self.onDown(slot)
                // Order-insensitive latching: Control already held when
                // the hotkey went down (or pressed during the arming
                // window, before isDown was set) latches too.
                if self.latchEnabled, (self.lastFlags & Self.controlFlag) != 0 {
                    self.onLatch(slot)
                }
            }
        }
    }

    private func handleUp() {
        switch mode {
        case .toggle:
            // Toggle ignores release.
            return

        case .hold:
            if let task = armingTask, !task.isCancelled, !isDown {
                // Released before grace period elapsed — cancel and stay idle.
                task.cancel()
                armingTask = nil
                return
            }
            armingTask = nil
            if isDown {
                isDown = false
                onUp(slot)
            }
        }
    }
}
