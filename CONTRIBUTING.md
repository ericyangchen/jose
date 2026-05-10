# Contributing to José

Thanks for poking around. José is small (~3K LOC of Swift) and the architecture is documented in [CLAUDE.md](CLAUDE.md). PRs welcome.

---

## Prerequisites

- **macOS 14 (Sonoma) or later** — Apple Silicon recommended
- **[Xcode 15+](https://apps.apple.com/us/app/xcode/id497799835)** — full Xcode, not just Command Line Tools
- **[Homebrew](https://brew.sh/)** — for `xcodegen`
- **Python 3.12** — only if you want to regenerate the Silero VAD Core ML model

## Build

```bash
git clone https://github.com/ericyangchen/jose.git
cd jose
./Scripts/setup.sh        # installs xcodegen via brew, generates José.xcodeproj
open José.xcodeproj       # ⌘R to run
```

The `Scripts/setup.sh` step is one-time. After that, opening `José.xcodeproj` and pressing ⌘R is the dev loop.

If you change [project.yml](project.yml) (adding a target, changing build settings, etc.), regenerate the project:

```bash
xcodegen generate
```

## Project structure

```
Sources/José/
├── App/             # AppDelegate, SwiftUI @main, AppCoordinator state machine
├── Core/            # AppState, Settings, Logger, ModifierMask constants
├── Storage/         # KeychainStore, UserDefaults wrapper
├── Hotkey/          # ComboHotkey (KeyboardShortcuts) + ModifierHotkey (flagsChanged)
├── Audio/           # AVAudioEngine pipeline → m4a + RMS + Silero VAD
├── Transcription/   # /v1/audio/transcriptions multipart client + PromptBuilder
├── Output/          # NSPasteboard + CGEvent ⌘V
├── Permissions/     # Mic + Accessibility + Input Monitoring
├── Usage/           # Local minutes/cost tracking
├── UI/MenuBar/      # NSStatusItem + Canvas-rendered icon
├── UI/HUD/          # Floating pill panel + Siri-gradient waveform
├── UI/Settings/     # Custom NSWindow with sidebar + 7 panes
└── UI/Onboarding/   # First-launch BYOK flow
```

`AppCoordinator` is the state machine — every subsystem either *publishes* (audio levels, hotkey events) or *consumes* (HUD, menu bar) `AppStateModel`. No global mutable state, no Combine; everything's `async/await` + `@Observable`.

## Code style

- Swift 5.10+, SwiftUI primary with AppKit bridges (`NSStatusItem`, `CGEvent`, `NSVisualEffectView`)
- macOS 14+ deployment target
- Prefer `let` over `var`
- `async/await`, no Combine for new code
- `@MainActor` on UI-bound types; audio internals can use background queues
- Minimal comments — explain *why*, not *what*. Identifier names should already explain *what*.

## Verifying changes

Before pushing:

```bash
xcodegen generate
xcodebuild -project José.xcodeproj -scheme José -configuration Debug build
```

If you're touching the audio pipeline, also test recording end-to-end:

1. Run from Xcode (⌘R)
2. Hold Fn, say something, release
3. Confirm transcript pastes at cursor
4. Check the log for any errors:
   ```bash
   log show --predicate 'subsystem == "com.ericyangchen.jose"' --last 5m --info --debug
   ```

## Releasing

There's a one-shot publish script that builds an unsigned `.app`, ad-hoc-signs it, zips it, and creates a GitHub release with the zip attached:

```bash
./Scripts/publish.sh
```

Bump `MARKETING_VERSION` in [project.yml](project.yml) before each release — the script refuses to clobber an existing tag.

Manual breakdown:

- `./Scripts/release.sh` — archive + ad-hoc-resign (`--identifier com.ericyangchen.jose --options runtime` so macOS TCC keys grants stably) + zip + SHA-256
- `gh release create v<x.y.z> .build/release/José-<x.y.z>.zip ...`

The signing identifier matters. `xcodebuild ... CODE_SIGNING_ALLOWED=NO` alone produces a "linker-signed" binary with an unbound Info.plist; macOS TCC keys grants by `(bundle id, signature)`, so without a stable signature, every launch reads as a new app and Microphone/Accessibility grants don't persist. The `release.sh` re-sign step is what makes grants sticky.

## Regenerating the Silero VAD model

Only needed if you're updating to a newer Silero release. The conversion script downloads the upstream torchscript, swaps the STFT + LSTM submodules out for ones coremltools 8.x can compile, and writes a Core ML model into `Sources/José/Audio/VAD/SileroVADModel.mlpackage`.

```bash
./Scripts/convert_silero.sh
```

Requires Python 3.12 specifically — coremltools 8.x's native libraries (`libcoremlpython`, `libmilstoragepython`) don't ship for Python 3.13 yet. If you don't have it: `brew install python@3.12`.

## Architecture notes that aren't in the file tree

These are decisions that look arbitrary in the code but were deliberate:

- **Hotkey has two implementations behind one façade.** `ComboHotkey` wraps the `KeyboardShortcuts` SPM lib (Carbon-backed, down-event only). `ModifierHotkey` is hand-rolled on `NSEvent.flagsChanged` because single modifier keys (Right Option, Fn, etc.) need release events and left/right discrimination via device-specific raw bits (`NX_DEVICERSHIFTKEYMASK` etc.). Combo hotkeys do **not** support hold mode.
- **Audio is a one-source three-sink fan-out.** `AVAudioEngine.inputNode` → `AVAudioConverter` to 16 kHz mono Float32, then split into Silero VAD, `AudioLevelMonitor` (RMS for HUD/menu bar), and `AVAudioFile` (AAC m4a to temp).
- **VAD does not stop recording.** It's only used for end-of-recording silence detection (`is_speech` ratio < 5 % → discard with "No speech detected" notice). Hold-to-talk release is the only stop signal.
- **Output routing is determined by which hotkey fired, not by focus detection.** Smart focus detection was deliberately rejected for v1; the `OutputRouter` API takes an `action` parameter so v2 can extend without refactoring.
- **App is not sandboxed.** `CGEvent.post()` requires non-sandbox. Side effects: never on the Mac App Store; requires Accessibility permission.
- **Clipboard is NOT restored after paste** by default — author uses Raycast clipboard history. The "Restore previous clipboard" toggle exists in Settings → Output (default OFF) for users who want different behavior.
- **`gpt-4o-transcribe` is the default model**, not `whisper-1`. Same price, materially better on zh-tw/en code-switching.

## Out of scope

These are explicitly **not** going to happen:
- Cloud sync / cross-device
- Subscription / backend proxy
- Wake word / always-on listening
- Translation
- iOS app (keyboard extension limits make it impractical)
