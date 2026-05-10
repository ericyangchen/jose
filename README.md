# José

> **Hold and Say.** A native macOS dictation app for engineers who code-switch.

`José` is a menu-bar dictation app tuned for software engineers who mix Traditional Chinese and English in the same sentence. Hold a hotkey, talk, release — your transcript is pasted at the cursor. Backed by OpenAI `gpt-4o-transcribe`. Bring your own key.

---

## Install

1. **Download** the latest `José-<version>.zip` from the [Releases page](https://github.com/ericyangchen/jose/releases).
2. **Unzip** and drag `José.app` into `/Applications/`.
3. **Bypass Gatekeeper** — the build is unsigned, so macOS will refuse to open it the first time. Run once:
   ```bash
   xattr -d com.apple.quarantine /Applications/José.app
   ```
   *(Or right-click → **Open** → confirm.)*
4. **Launch José.** Settings opens automatically the first time.

## First launch

You'll go through three quick steps:

1. **Paste your OpenAI API key** ([create one here](https://platform.openai.com/api-keys)). Click **Test** to verify it, then **Save** — the key is stored in your macOS Keychain.
2. **Pick a hotkey** in Settings → Hotkeys. Default is **Fn / 🌐**.
3. **Grant permissions** when macOS prompts on first recording:
   - **Microphone** — to capture your voice.
   - **Accessibility** — to paste at the cursor.

## How to use

| Action | What happens |
|---|---|
| **Hold Fn**, speak, release | Transcribes and pastes at cursor |
| **Slot B** (you bind it) | Transcribes to clipboard only — no auto-paste |
| **Esc** while recording | Cancels (requires Input Monitoring) |

> **Fn key tip**: macOS's default Fn behavior fights hold-to-talk. Open System Settings → Keyboard → "Press 🌐 key to" and set it to *"Do Nothing"* or *"Change Input Source."* If you'd rather use something else, rebind in Settings → Hotkeys (Right Option, ⌘⇧Space, etc.).

## Features

- **Bilingual transcription** — zh-tw + en, mixed in the same sentence
- **Two slots**: paste-and-copy (slot A) / copy-only (slot B), each with hold-to-talk OR toggle mode
- **Native menu-bar app**, no Dock icon, ignorable until you press the hotkey
- **Animated waveform pill** at the bottom of the screen while recording
- **Configurable**: spoken languages, technical vocabulary, system prompt, model choice
- **BYOK** — your key, your bill, no proxy server in the middle

## Privacy

- **BYOK**: API key in your macOS Keychain. Audio goes directly to OpenAI; no third-party server.
- **No telemetry, no analytics, no crash reporter.**
- Per [OpenAI's API terms](https://openai.com/policies/api-data-usage-policies), API audio is *not* used to train models.
- **Transcripts stay in your clipboard** so [Raycast](https://www.raycast.com/) clipboard history catches them. Flip "Restore previous clipboard" in Settings → Output to opt out.

## Settings overview

The Settings window has seven panes:

| Pane | What's there |
|---|---|
| **General** | Launch at login, show in Dock, menu-bar icon visibility |
| **Hotkeys** | Bind slots A & B; hold or toggle mode |
| **Audio** | Pick a non-default microphone |
| **Transcription** | Model (`gpt-4o-transcribe` $0.36/hr vs `gpt-4o-mini-transcribe` $0.18/hr), spoken languages, system prompt, API key |
| **Vocabulary** | Toggle bundled dev categories, add custom terms |
| **Permissions** | Live status of Microphone, Accessibility, Input Monitoring |
| **About** | Version + license |

## Known limitations (v1)

- **Unsigned build.** Until José ships with an Apple Developer ID, every fresh download needs the `xattr` bypass.
- **Esc-to-cancel needs Input Monitoring** — auto-denied by macOS for ad-hoc-signed builds. Recording itself works fine without it. To enable, drag José.app into the Input Monitoring list manually via the `+` button in System Settings (Settings → Permissions has a **"Show José.app in Finder"** helper button).
- **Streaming transcription** lands in v1.1. Current latency is 2–4 s after release.

## Roadmap

- **v1.1** — Streaming transcription via `/v1/realtime` (~500 ms latency); Sparkle auto-update.
- **v2** — `gpt-4o-mini` post-process pass to clean filler words; per-app prompt presets; optional local history.

---

Build instructions, release process, and code style live in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

TBD.
