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
        onFire: @escaping (HotkeySlot) -> Void
    ) {
        self.slot = slot
        self.mask = mask
        self.mode = mode
        self.onDown = onDown
        self.onUp = onUp
        self.onFire = onFire
    }

    func start() {
        guard mask != 0 else {
            Logger.hotkey.warning("ModifierHotkey \(self.slot.rawValue) started with empty mask — skipping")
            return
        }

        lastFlags = UInt(NSEvent.modifierFlags.rawValue)

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
