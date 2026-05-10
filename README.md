# José

> **Hold and Say.** A native macOS dictation app for engineers who code-switch.
>
> _名稱由來：José 的西班牙語發音 "Ho-Say" 即為 "Hold and Say"。_

`José` is a menu-bar dictation app tuned for software engineers who mix Traditional Chinese and English in the same sentence. Hold a hotkey, talk, release — your transcript is pasted at the cursor. Backed by OpenAI `gpt-4o-transcribe`. Bring your own key.

## Status

🚧 **Under construction.** v1 (MVP) is being built.

See [project.yml](project.yml) once generated, and the implementation log in `git log`.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+
- An OpenAI API key with access to `gpt-4o-transcribe`

## Building

```bash
./Scripts/setup.sh        # one-time: brew install xcodegen + generate project
open José.xcodeproj
# Product → Archive in Xcode, then export
```

Or:

```bash
./Scripts/release.sh      # archives + zips + prints SHA-256
```

## Installing the unsigned build

Until José ships with a Developer ID signature, macOS Gatekeeper will refuse the first launch. To bypass:

```bash
xattr -d com.apple.quarantine /Applications/José.app
```

Or right-click the app → Open → confirm.

## Privacy

- **Bring Your Own Key.** Your OpenAI key is stored in the macOS Keychain and used only to call OpenAI directly. No third-party server.
- **No telemetry.** No analytics, no crash reporter, no background recording.
- **Audio is uploaded to OpenAI for transcription.** The temp `.m4a` file is deleted as soon as the response comes back. OpenAI's API terms (distinct from ChatGPT's) state that API data is not used for training by default.
- **Transcripts stay in your clipboard** so tools like Raycast clipboard history can pick them up. Toggle "Restore previous clipboard" in Settings if you'd rather not keep them.

## License

TBD.
