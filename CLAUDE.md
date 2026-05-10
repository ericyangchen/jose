# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

**Spec-only, pre-implementation.** The repo currently contains two design documents and no code, build system, or git history. Any first implementation work must scaffold the Xcode project from scratch following the spec.

## Source of truth

Two documents drive everything. **Always read both before proposing changes** — the spec describes structure, the handoff describes the reasoning that's invisible from structure alone.

- [jose-design-spec.md](jose-design-spec.md) — the **what**: frozen v1 spec covering UX, visual system, architecture, module layout, subsystem details, settings schema, and a 10-stage implementation roadmap with acceptance criteria.
- [jose-context-handoff.md](jose-context-handoff.md) — the **why**: rejected alternatives, author preferences, and decisions that look arbitrary in the spec but were deliberate (e.g. why hotkeys need two implementation paths, why the clipboard isn't restored, why the app can't be sandboxed).

When the spec and handoff disagree, the spec wins for `what` and the handoff wins for `why` — but in practice they're consistent; flag any contradiction to the user instead of guessing.

## Project overview

José ("Ho-Say" / "Hold and Say") is a native macOS menu bar dictation app for engineers who code-switch between Traditional Chinese (Taiwan) and English. Press a hotkey, speak, release → OpenAI `gpt-4o-transcribe` → paste or copy. BYOK, no third-party server, no telemetry.

Stack: Swift 5.10+, SwiftUI primary with AppKit bridges (NSStatusItem, CGEvent, NSVisualEffectView), macOS 14+, Swift Concurrency (no Combine for new code), SPM only.

## Architecture: things you can't infer from the file tree

The module layout in spec §5.3 is straightforward; these are the cross-cutting facts that aren't:

- **`AppCoordinator` is the state machine.** State flows `idle → arming → recording → processing → output → idle` (Core/State.swift). Every subsystem observes this; no module owns its own lifecycle. Sequence diagram in spec §5.5.
- **Hotkey has two independent implementations behind one façade.** `ComboHotkey` wraps the `KeyboardShortcuts` SPM lib (Carbon-backed, down-event only). `ModifierHotkey` is hand-rolled on `NSEvent.flagsChanged` because single modifier keys (Right Option, etc.) need release events and left/right discrimination via device-specific raw bits (`NX_DEVICERSHIFTKEYMASK`). Combo hotkeys do **not** support hold mode — grey it out in the UI. See spec §6.1 and handoff §5.3.
- **Audio is a one-source three-sink fan-out.** `AVAudioEngine.inputNode` → `AVAudioConverter` to 16kHz mono Float32, then split into Silero VAD (30ms / 480-sample chunks), `AudioLevelMonitor` (RMS for HUD/menu bar), and `AVAudioFile` (AAC m4a to temp). Spec §6.2.
- **Silero VAD ships as a bundled `.mlmodelc`, not an SPM package.** Convert ONNX → CoreML once with `coremltools` on Apple Silicon (spec §6.3.1); the LSTM `h`/`c` hidden state must be threaded through every inference call.
- **VAD does not stop recording in v1.** It's only used for end-of-recording silence detection (`is_speech` ratio < 5% → "No speech detected" prompt). Hold-to-talk release is the only stop signal.
- **Output routing is determined by which hotkey fired, not by focus detection.** Hotkey A = clipboard + simulated ⌘V via CGEvent; Hotkey B = clipboard only. Smart focus detection was deliberately rejected for v1 (handoff §2.3); the `OutputRouter` API takes an `action` parameter so v2 can extend without refactoring.

## Hard constraints — do not violate without asking

These are decisions the author has explicitly committed to. Don't "improve" them without permission.

1. **App cannot be sandboxed.** `CGEvent.post()` requires non-sandbox. Side effect: never on the Mac App Store; requires Accessibility permission.
2. **Clipboard is NOT restored after paste.** This is a feature, not a bug — author uses Raycast clipboard history and wants the transcription to land there. The "Restore previous clipboard" toggle exists in Settings (default OFF) for users who want different behavior. Handoff §3.3, §5.8.
3. **Minimal dependencies.** Only `KeyboardShortcuts` (SPM) and the Silero VAD model file. OpenAI is hit with raw `URLSession` — do not pull in an SDK.
4. **Settings UI is custom, not the standard SwiftUI `Settings` scene.** Sidebar (180pt) + card-stack content. The author paid for this — don't shortcut it with a stock `Form`.
5. **Default vocabulary stays generic / dev-friendly.** Do not personalize defaults to the author; the app is meant to be shared. Spec §6.4.4.
6. **No telemetry, no analytics, no third-party server, no always-on listening, no wake word, no cloud sync, no translation.** Permanently out of scope (handoff §2.5, spec §2.4).
7. **Bundle id is `com.eric.jose`.** Pre-decided so the eventual signed/notarized build is a drop-in upgrade.
8. **`gpt-4o-transcribe` is the default model**, not `whisper-1`. Same price, materially better on zh-tw/en code-switching.

## Recommended implementation order

Spec §10 lists 10 stages with explicit acceptance criteria — follow them in order. Two stages historically eat the most time:

- **Stage 3 (Audio + VAD)** — ONNX → CoreML conversion needs a one-time Python run on Apple Silicon.
- **Stage 6 (HUD)** — `NSPanel` + SwiftUI `Canvas` has multi-screen edge cases.

Fastest path to a working demo: Stage 0 → 1 → 2 → 3 → 4, then `print()` the transcription to verify the core loop end-to-end before circling back for Output, HUD, and icons.

## Build / test / run

No build system exists yet. Once the Xcode project is scaffolded (Stage 0), commands will be standard `xcodebuild` / Xcode GUI builds — there's no custom tooling planned beyond an eventual `scripts/release.sh` for archiving and zipping. Update this section once those land.

## Working with the author

- **MVP mindset is strict.** Don't expand scope. Anything that smells like "while we're here, let's also…" should be confirmed first.
- **Explicit > implicit.** When uncertain, ask rather than infer.
- **The author writes in Traditional Chinese in the design docs and prefers terse, technical replies.** Match that register; skip marketing language.
