# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

**Shipped and iterating.** v0.1.4, ~58 Swift files under `Sources/José/`, all 10 spec stages complete. Work is incremental change against a running app, not scaffolding.

`José.xcodeproj/` is **gitignored and generated**. Run `Scripts/setup.sh` after a fresh clone or any `project.yml` change. Never hand-edit the project file — edit `project.yml`.

## Source of truth

Two documents drive everything. **Always read both before proposing changes** — the spec describes structure, the handoff describes the reasoning that's invisible from structure alone.

- [jose-design-spec.md](jose-design-spec.md) — the **what**: frozen v1 spec covering UX, visual system, architecture, module layout, subsystem details, settings schema, and a 10-stage implementation roadmap with acceptance criteria.
- [jose-context-handoff.md](jose-context-handoff.md) — the **why**: rejected alternatives, author preferences, and decisions that look arbitrary in the spec but were deliberate (e.g. why hotkeys need two implementation paths, why the clipboard isn't restored, why the app can't be sandboxed).

When the spec and handoff disagree, the spec wins for `what` and the handoff wins for `why` — but in practice they're consistent; flag any contradiction to the user instead of guessing.

Both documents describe **v1 as frozen**. Post-v1 work has moved past them in places, so the shipped code also counts as source of truth — check it before trusting a spec detail. Design docs for changes made after v1 live in `docs/superpowers/specs/`.

## Project overview

José ("Ho-Say" / "Hold and Say") is a native macOS menu bar dictation app for engineers who code-switch between Traditional Chinese (Taiwan) and English. Press a hotkey, speak, release → OpenAI `gpt-4o-transcribe` → paste or copy. BYOK, no third-party server, no telemetry.

Stack: Swift 5.10+, SwiftUI primary with AppKit bridges (NSStatusItem, CGEvent, NSVisualEffectView), macOS 14+, Swift Concurrency (no Combine for new code), SPM only.

## Architecture: things you can't infer from the file tree

The module layout in spec §5.3 is straightforward; these are the cross-cutting facts that aren't:

- **`AppCoordinator` is the state machine.** State flows `idle → arming → recording → processing → output → idle` (Core/State.swift). Every subsystem observes this; no module owns its own lifecycle. Sequence diagram in spec §5.5.
- **Hotkey has two independent implementations behind one façade.** `ComboHotkey` wraps the `KeyboardShortcuts` SPM lib (Carbon-backed, down-event only). `ModifierHotkey` is hand-rolled on `NSEvent.flagsChanged` because single modifier keys (Right Option, etc.) need release events and left/right discrimination via device-specific raw bits (`NX_DEVICERSHIFTKEYMASK`). Combo hotkeys do **not** support hold mode — grey it out in the UI. See spec §6.1 and handoff §5.3.
- **Audio is a one-source three-sink fan-out.** `AVAudioEngine.inputNode` → `AVAudioConverter` to 16kHz mono Float32, then split into Silero VAD (30ms / 480-sample chunks), `AudioLevelMonitor` (RMS for HUD/menu bar), and `AVAudioFile` (AAC m4a to temp). Spec §6.2.
- **Silero VAD is already converted and committed** as `Sources/José/Audio/VAD/SileroVADModel.mlpackage`; Xcode compiles it to `.mlmodelc` during a normal build. Do **not** re-run `Scripts/convert_silero.sh` or the Python path unless the model itself changes. The LSTM `h`/`c` hidden state must be threaded through every inference call.
- **VAD does not stop recording in v1.** It's only used for end-of-recording silence detection (`is_speech` ratio < 5% → "No speech detected" prompt). Hold-to-talk release is the only stop signal.
- **The HUD picks its screen via Accessibility, not `NSScreen.main`.** `HUDController.activeScreen()` reads the frontmost app's focused-window position through `AXUIElement` and matches it to a screen, so the pill follows the window you're typing in on multi-monitor setups.
- **Output routing is determined by which hotkey fired, not by focus detection.** Hotkey A = clipboard + simulated ⌘V via CGEvent; Hotkey B = clipboard only. Smart focus detection was deliberately rejected for v1 (handoff §2.3); the `OutputRouter` API takes an `action` parameter so v2 can extend without refactoring.

## Hard constraints — do not violate without asking

These are decisions the author has explicitly committed to. Don't "improve" them without permission.

1. **App cannot be sandboxed.** `CGEvent.post()` requires non-sandbox. Side effect: never on the Mac App Store; requires Accessibility permission.
2. **Clipboard is NOT restored after paste.** This is a feature, not a bug — author uses Raycast clipboard history and wants the transcription to land there. The "Restore previous clipboard" toggle exists in Settings (default OFF) for users who want different behavior. Handoff §3.3, §5.8.
3. **Minimal dependencies.** Only `KeyboardShortcuts` (SPM) and the Silero VAD model file. OpenAI is hit with raw `URLSession` — do not pull in an SDK.
4. **Settings UI is custom, not the standard SwiftUI `Settings` scene.** Sidebar (180pt) + card-stack content. The author paid for this — don't shortcut it with a stock `Form`.
5. **Default vocabulary stays generic / dev-friendly.** Do not personalize defaults to the author; the app is meant to be shared. Spec §6.4.4.
6. **No telemetry, no analytics, no third-party server, no always-on listening, no wake word, no cloud sync, no translation.** Permanently out of scope (handoff §2.5, spec §2.4).
7. **Bundle id is `com.ericyangchen.jose`.** Pre-decided so the eventual signed/notarized build is a drop-in upgrade.
8. **`gpt-4o-transcribe` is the default model**, not `whisper-1`. Same price, materially better on zh-tw/en code-switching.

## Build / test / run

| Command | Purpose |
|---|---|
| `swift build` | Fast compile-check. `Package.swift` exists only for this — it is not the shipping product. |
| `Scripts/setup.sh` | Install xcodegen + generate `José.xcodeproj`. Required after a fresh clone. |
| `xcodebuild -project José.xcodeproj -scheme José -configuration Debug -derivedDataPath .build/dd build` | Build the real `.app`. |
| `Scripts/release.sh` | Archive unsigned `.app`, zip, print SHA-256. |
| `Scripts/publish.sh [tag]` | GitHub release via `gh`. Refuses to clobber an existing tag — bump `MARKETING_VERSION` in `project.yml` first. |

**There is no test target.** Verification is manual — write out an explicit test matrix instead of claiming a change works. Propose adding a target before assuming TDD.

**Pre-existing warnings.** `DropdownMenu.swift:19-20` emits Swift 6 `main actor-isolated static property 'shared'` warnings. Don't attribute them to your change; don't fix them unasked.

**Running a build costs permissions.** The app needs Accessibility + Microphone, and TCC keys off code signature *and* path — a Debug build under `.build/` is a different app to macOS and needs its own grants. Testing against existing grants means replacing `/Applications/José.app` via `Scripts/release.sh`; confirm first, it overwrites the author's installed copy.

## Working with the author

- **MVP mindset is strict.** Don't expand scope. Anything that smells like "while we're here, let's also…" should be confirmed first.
- **Explicit > implicit.** When uncertain, ask rather than infer.
- **The author writes in Traditional Chinese in the design docs and prefers terse, technical replies.** Match that register; skip marketing language.
