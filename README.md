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
- **Hold-to-talk OR toggle.** Per-hotkey choice. **Fn (globe key)** is the default for slot A in hold mode.
- **Native menu-bar app, no Dock icon.** Floating Dynamic-Island-style pill shows recording state, animated waveform, elapsed timer, then a 3-dot processing indicator.
- **BYOK.** Your OpenAI key stays in the macOS Keychain. Audio goes directly to OpenAI; no third-party server.
- **No telemetry, no always-on listening.** Hotkey-triggered, zero in the background.

---

## Install (for users)

### 1. Download

Grab `José-<version>.zip` from the [Releases page](https://github.com/ericyangchen/jose/releases) and unzip it. Drag `José.app` into `/Applications/`.

### 2. Bypass Gatekeeper (one-time)

The build is unsigned — Apple Developer Program costs $99/yr and José doesn't pay it. macOS will refuse to open it the first time. Run this once:

```bash
xattr -d com.apple.quarantine /Applications/José.app
```

Or right-click the app in Finder → **Open** → confirm the warning dialog.

### 3. First launch — BYOK + permissions

When you launch José for the first time:

1. **Welcome window** asks for your OpenAI API key. Paste it (you can [create one here](https://platform.openai.com/api-keys)) and click **Test** — José validates against `/v1/models`. Click **Save**; the key goes into your macOS Keychain.
2. **Settings opens automatically** so you can rebind the hotkey, pick a model, configure spoken languages, etc. Close it whenever you're ready.
3. macOS will prompt for **Microphone** and **Accessibility** permissions on first hotkey press. Grant both — Microphone to capture your voice, Accessibility so José can synthesize ⌘V into the focused app.

### 4. Use it

Hold the hotkey (default **Fn**), speak (mix Chinese and English freely), release. Within ~3 seconds your transcript is pasted at the cursor.

> **Heads up about the Fn key**: System Settings → Keyboard → "Press 🌐 key to" needs to be set to **"Do Nothing"** or **"Change Input Source"**. If it's set to "Show Emoji & Symbols" or "Start Dictation," that'll fight José's hold-to-talk. You can also rebind to a different key in Settings → Hotkeys.

---

## Settings overview

Click the menu-bar icon → **Settings…** to open the configuration window.

| Pane | What's there |
|---|---|
| **General** | Launch at login, show in Dock, show usage estimate in dropdown |
| **Hotkeys** | Bind slot A and B; pick hold or toggle mode |
| **Audio** | Choose a non-default microphone |
| **Transcription** | Pick `gpt-4o-transcribe` ($0.36/hr) or `gpt-4o-mini-transcribe` ($0.18/hr); set spoken languages; edit system prompt; replace API key |
| **Vocabulary** | Toggle dev categories or add custom terms |
| **Permissions** | Live status of Microphone, Accessibility, and (optional) Input Monitoring |
| **About** | Version + license |

---

## Privacy

- **Bring Your Own Key.** Your OpenAI API key sits in your macOS Keychain. It's used only to call OpenAI directly; no third-party server.
- **No telemetry, no analytics, no crash reporter.** No code in this app phones home.
- **Audio uploaded to OpenAI for transcription.** The temp `.m4a` file is deleted as soon as the response arrives. OpenAI's API terms (distinct from ChatGPT's) state that API data is not used for training by default.
- **Transcripts stay in your clipboard** so tools like [Raycast](https://www.raycast.com/) clipboard history can pick them up. Toggle "Restore previous clipboard" in Settings → Output if you'd rather not.

---

## Building from source (for contributors)

```bash
git clone https://github.com/ericyangchen/jose.git
cd jose
./Scripts/setup.sh        # installs xcodegen via brew, generates José.xcodeproj
open José.xcodeproj       # ⌘R to run; Product → Archive to ship
```

To produce a release zip ready to upload to GitHub:

```bash
./Scripts/release.sh
# → .build/release/José-<version>.zip + SHA-256
```

To regenerate the Silero VAD Core ML model (only needed if you're updating to a newer Silero release — the conversion script requires Python 3.12; coremltools 8.x's native libs don't ship for 3.13 yet):

```bash
./Scripts/convert_silero.sh
```

---

## Known limitations (v1)

- **Unsigned build.** Until José gets a Developer ID, every fresh download needs the Gatekeeper bypass shown above.
- **Right Option may conflict with some keyboard layouts** (US-International typing accented characters, Pinyin, etc.). Fn is the default for that reason; rebind in Settings → Hotkeys if you need.
- **Esc-to-cancel during recording requires Input Monitoring permission**, which macOS auto-denies for ad-hoc-signed builds. Recording itself works fine without it; only the cancel shortcut is disabled.
- **Streaming transcription is v1.1.** Current transcription is the batch endpoint — typically 2–4 s after release. The Realtime API path (~500 ms latency) is the next major upgrade.

---

## Roadmap

- **v1.1** — Streaming transcription via `/v1/realtime`; partial-text HUD; Sparkle auto-update
- **v2** — `gpt-4o-mini` post-process pass to clean filler words; per-app prompt presets; optional local history

---

## Contributing

PRs welcome. Code style:
- Swift 5.10+, SwiftUI primary with AppKit bridges
- macOS 14+ deployment target
- `async/await`, no Combine for new code
- One test pass before pushing: `xcodegen generate && xcodebuild -scheme José -configuration Debug build`

## License

TBD.
