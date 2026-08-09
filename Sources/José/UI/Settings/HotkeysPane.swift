import SwiftUI
import KeyboardShortcuts

struct HotkeysPane: View {
    @Bindable var settings: Settings

    var body: some View {
        PaneScaffold(title: "Hotkeys", subtitle: "Bind a key for transcribe-and-paste (slot A) or transcribe-and-copy (slot B).") {
            SettingsCard("Slot A — Transcribe & Paste") {
                SlotEditor(
                    slot: .A,
                    shortcutName: .transcribeAndPaste,
                    modifierMask: Binding(
                        get: { settings.hotkeyAModifierMask },
                        set: { settings.hotkeyAModifierMask = $0 }
                    ),
                    mode: $settings.hotkeyAMode
                )
                Text("Records, copies the transcript, and simulates ⌘V at the cursor.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Slot B — Transcribe & Copy") {
                SlotEditor(
                    slot: .B,
                    shortcutName: .transcribeAndCopy,
                    modifierMask: Binding(
                        get: { settings.hotkeyBModifierMask },
                        set: { settings.hotkeyBModifierMask = $0 }
                    ),
                    mode: $settings.hotkeyBMode
                )
                Text("Records and copies to the clipboard. No paste — pick this when you want to read first.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Tip") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Single-modifier hotkeys (Right Option, Right Command, etc.) work in either Hold or Toggle mode. Combo hotkeys only support Toggle mode — Carbon's hotkey API doesn't expose key-up events.")
                    Text("In Hold mode, press Control at any point while the hotkey is down to latch the recording — a lock appears in the pill and you can let go and keep talking. Press the hotkey again and release it to stop. Not available when Control itself is the hotkey.")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SlotEditor: View {
    let slot: HotkeySlot
    let shortcutName: KeyboardShortcuts.Name
    @Binding var modifierMask: UInt?
    @Binding var mode: HotkeyMode

    @State private var bindingKind: BindingKind

    enum BindingKind: String, CaseIterable, Identifiable {
        case combo
        case modifier
        var id: String { rawValue }
        var label: String {
            switch self {
            case .combo: "Combo (⌘⇧K, ⌃⌥M, …)"
            case .modifier: "Single modifier (Right Option, Fn, …)"
            }
        }
    }

    init(
        slot: HotkeySlot,
        shortcutName: KeyboardShortcuts.Name,
        modifierMask: Binding<UInt?>,
        mode: Binding<HotkeyMode>
    ) {
        self.slot = slot
        self.shortcutName = shortcutName
        self._modifierMask = modifierMask
        self._mode = mode
        self._bindingKind = State(initialValue: modifierMask.wrappedValue == nil ? .combo : .modifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsRow("Binding type") {
                Picker("", selection: $bindingKind) {
                    ForEach(BindingKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 260)
                .onChange(of: bindingKind) { _, newValue in
                    if newValue == .combo {
                        modifierMask = nil
                    } else if modifierMask == nil {
                        modifierMask = ModifierMask.rightOption
                    }
                }
            }

            switch bindingKind {
            case .combo:
                SettingsRow("Shortcut", description: "Click to record. Press Esc or click ✕ to clear.") {
                    KeyboardShortcuts.Recorder(for: shortcutName)
                }
            case .modifier:
                SettingsRow("Modifier key", description: "Hold this key alone to talk.") {
                    Picker("", selection: Binding(
                        get: { modifierMask ?? ModifierMask.rightOption },
                        set: { modifierMask = $0 }
                    )) {
                        ForEach(ModifierChoice.allCases, id: \.mask) { choice in
                            Text(choice.label).tag(choice.mask)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                Button("Clear binding") {
                    modifierMask = nil
                    bindingKind = .combo
                }
                .controlSize(.small)
            }

            SettingsRow("Mode", description: mode == .hold
                        ? "Hold the key while you talk; release to send."
                        : "Press once to start, again to stop.") {
                Picker("", selection: $mode) {
                    Text("Hold").tag(HotkeyMode.hold)
                    Text("Toggle").tag(HotkeyMode.toggle)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
                .disabled(bindingKind == .combo)
                .help(bindingKind == .combo
                      ? "Combo hotkeys only support Toggle mode"
                      : "")
            }
        }
        .onChange(of: bindingKind) { _, newValue in
            // Combo hotkeys cannot run in hold mode (Carbon limitation, spec §6.1.2).
            if newValue == .combo, mode == .hold {
                mode = .toggle
            }
        }
    }
}

private struct ModifierChoice {
    let mask: UInt
    let label: String

    static let allCases: [ModifierChoice] = [
        .init(mask: ModifierMask.rightOption,  label: "Right Option (⌥)"),
        .init(mask: ModifierMask.rightCommand, label: "Right Command (⌘)"),
        .init(mask: ModifierMask.rightShift,   label: "Right Shift (⇧)"),
        .init(mask: ModifierMask.rightControl, label: "Right Control (⌃)"),
        .init(mask: ModifierMask.fn,           label: "Fn (Globe)")
    ]
}
