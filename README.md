# José

> **Hold and Say.** A native macOS dictation app for engineers who code-switch.
>
> _名稱由來：José 的西班牙語發音 "Ho-Say" 即為 "Hold and Say"。_

`José` is a menu-bar dictation app tuned for software engineers who frequently mix Traditional Chinese and English in the same sentence. Hold a hotkey, talk, release — your transcript is pasted at the cursor. Backed by OpenAI `gpt-4o-transcribe`. Bring your own key.

---

## Highlights

- **Built for code-switching** — default prompt + tech vocabulary list is tuned so `把這個 component refactor 成 functional 的` comes out right.
- **Two hotkeys, two behaviors.**
  - **A** — *Transcribe & Paste:* writes the transcript to the clipboard, then synthesizes ⌘V at the cursor.
  - **B** — *Transcribe & Copy:* writes to the clipboard only.
- **Hold-to-talk OR toggle.** Per-hotkey choice. Right Option is the default for A in hold mode.
- **Native menu-bar app, no Dock icon.** Floating pill HUD shows recording state + waveform.
- **BYOK.** Your OpenAI key stays in the macOS Keychain. Your audio goes directly to OpenAI; no third-party server in the middle.
- **No telemetry. No always-on listening.** Hotkey-triggered, zero in the background.

## Requirements

- macOS 14 (Sonoma) or later — Apple Silicon recommended
- [Xcode 15+](https://apps.apple.com/us/app/xcode/id497799835) (the build is unsigned, so you'll archive locally)
- An OpenAI API key with access to `gpt-4o-transcribe` ([create one](https://platform.openai.com/api-keys))

## Building

One-time setup (installs `xcodegen` if needed and generates the project):

```bash
./Scripts/setup.sh
open José.xcodeproj
# In Xcode: Product → Archive → Distribute App → Copy App
```

Or, fully scripted (unsigned archive + zip + SHA-256):

```bash
./Scripts/release.sh
# → .build/release/José-0.1.0.zip
```

Drop `José.app` into `/Applications/`.

### First launch — Gatekeeper bypass

The build is unsigned, so macOS will refuse to open it the first time. To bypass:

```bash
xattr -d com.apple.quarantine /Applications/José.app
```

…or right-click the app → **Open** → confirm the warning.

### Permissions José will ask for

| Permission | Why | When |
|---|---|---|
| **Microphone** | Capture your voice | First time you press a hotkey |
| **Accessibility** | Synthesize ⌘V into the focused app | First time hotkey A fires |
| **Input Monitoring** | Listen for global hotkeys | First launch |

If you missed a prompt, José deep-links you to the right page in System Settings → Privacy & Security.

## Setup

1. Launch José. The menu-bar icon appears (three small bars).
2. The onboarding window asks for your OpenAI API key. Paste it, click **Test** (José hits `/v1/models` to verify), then **Save**.
3. Open Settings (menu bar → **Settings…**) to bind hotkeys, choose a model, or edit the vocabulary.

## Usage

### Default bindings

| Action | Hotkey | Mode |
|---|---|---|
| Transcribe & Paste (slot A) | Right Option | Hold-to-talk |
| Transcribe & Copy (slot B) | *unset — bind one in Settings* | Hold-to-talk |

### The recording loop

```
Press hotkey → HUD pill appears with waveform → speak →
release hotkey → HUD shows "Transcribing…" → text is pasted (or copied)
```

Press **Esc** during recording or processing to cancel without uploading.

### Limits

- Soft limit: 2 minutes (HUD shows "Long recording…")
- Hard limit: 10 minutes (auto-stop + upload)
- Recordings under 0.5 s are silently discarded
- Recordings with no detected speech (< 5 % of frames) are discarded with a "No speech detected" notice

### Cost estimation

The menu-bar dropdown shows a rolling monthly minutes / cost estimate. José tracks audio seconds per model locally and multiplies by the public OpenAI rates — accurate to within a few percent. This is *not* synced with your real OpenAI billing dashboard; the **estimated** label in the dropdown is intentional.

## Privacy

- **Bring Your Own Key.** Your OpenAI key is stored in the macOS Keychain. Used only to call OpenAI directly.
- **No telemetry, no analytics, no crash reporter.** No code in this app phones home.
- **Audio uploaded to OpenAI for transcription.** The temp `.m4a` file is deleted as soon as the response is in. OpenAI's API terms (distinct from ChatGPT's) state that API data is not used for training by default — see the OpenAI Data Usage policy if you want the source.
- **Transcripts stay in your clipboard** so tools like [Raycast](https://www.raycast.com/) clipboard history can pick them up. The default is *not* to restore the previous clipboard contents — toggle "Restore previous clipboard" in Settings → Output if you'd rather.

## Known limitations (v1)

- **Silero VAD ships as an RMS fallback.** The Core ML conversion pipeline (coremltools 8.x) is currently incompatible with Silero's torchscript export. RMS-based silence detection is good enough for the "no speech detected" warning the spec requires; real Silero is queued for v1.1. The conversion script is in [Scripts/convert_silero.sh](Scripts/convert_silero.sh) for whoever wants to iterate.
- **No clipboard restore by default** — see Privacy above. This is a feature, not a bug.
- **Right Option may conflict with some keyboard layouts** (e.g., US-International when typing accented characters). Rebind to a different modifier in Settings → Hotkeys.
- **Unsigned build.** Until the project gets a Developer ID, every fresh download needs the Gatekeeper bypass shown above.

## Roadmap

- **v1.1** — Streaming transcription via `/v1/realtime` so partial text shows up as you speak; real Silero VAD; auto-update via Sparkle.
- **v2** — A third hotkey that runs the transcript through `gpt-4o-mini` for filler-removal and tone polish before pasting; per-app prompt presets; optional local history.

See the design spec for the full picture.

## Development

```
Sources/José/
├── App/            # AppDelegate, SwiftUI @main, AppCoordinator state machine
├── Core/           # AppState enum, Settings, Logger, ModifierMask constants
├── Storage/        # KeychainStore, UserDefaults wrapper
├── Hotkey/         # ComboHotkey (KeyboardShortcuts) + ModifierHotkey (flagsChanged)
├── Audio/          # AVAudioEngine pipeline → m4a + RMS + Silero VAD
├── Transcription/  # /v1/audio/transcriptions multipart client + PromptBuilder
├── Output/         # NSPasteboard + CGEvent ⌘V
├── Permissions/    # Mic + Accessibility + Input Monitoring
├── Usage/          # Local minutes/cost tracking
├── UI/MenuBar/     # NSStatusItem + Canvas-rendered icon (4 states)
├── UI/HUD/         # Floating pill panel + Siri-gradient waveform
├── UI/Settings/    # Custom NSWindow with sidebar + 6 panes
└── UI/Onboarding/  # First-launch BYOK flow
```

The whole project follows a strictly observable pattern: `AppCoordinator` is the only state owner. Subsystems either *publish* (audio levels, hotkey events) or *consume* (HUD, menu-bar icon) `AppStateModel`. There's no global mutable state and no Combine — everything's `async/await` + `@Observable`.

The hotkey subsystem has two implementations behind one façade because macOS has no single API that handles both Carbon-style combos *and* single-modifier hold/release. See `Sources/José/Hotkey/` and design spec §6.1 for the gory bits.

## License

TBD.
