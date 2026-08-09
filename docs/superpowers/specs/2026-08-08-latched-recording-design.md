# Latched recording (hold → Control → hands-free)

Status: approved, ready for implementation plan
Date: 2026-08-08

## Problem

Slot A defaults to Fn in hold mode. When the user knows in advance they will
speak for a while, holding the key for the whole utterance is uncomfortable.
They want a way to start recording and then let go.

## Rejected alternatives

**A second Fn+Control hotkey binding in toggle mode.** This was the original
ask. It requires three changes we avoid entirely with the latch: exclusive
modifier matching in `ModifierHotkey` (today's `(flags & mask) == mask` is
"contains", so `Fn` always fires before `Fn+Ctrl` can be recognised), a single
shared `flagsChanged` monitor in `HotkeyManager` for deterministic arbitration
between overlapping bindings, and decoupling `RecordingAction` from
`HotkeySlot` — the toggle must paste, but slot A already owns paste and slot B
is copy-only.

**Double-tap the hotkey to latch.** Cheap on the hot path, because recordings
under `minimumRecordingDuration` (0.5 s) are already discarded, so the
wait-for-second-tap window only ever delays presses that were going to be
thrown away. Rejected because macOS's own Dictation shortcut is a double-press
of Globe or Control; if the user has it enabled, double-tapping Fn fires
Apple's dictation on top of José.

**Auto-latch after N seconds of holding.** Too implicit — it silently breaks
normal hold-to-talk for anyone who genuinely holds through a long utterance.

**Menu-bar click to latch.** Reaching for the mouse defeats the purpose of a
hotkey.

## Design

Latching is not a second binding. It is a modifier on the recording that slot
A is already running, so the output action never changes hands and no settings
schema changes.

### Gesture

```
Fn down ............ recording (hold, unchanged)
Ctrl down .......... LATCHED
Fn up .............. ignored — keep recording
  ... talk freely ...
Fn down ............ un-latch (no new recording — already busy)
Fn up .............. stop + transcribe + paste
```

Control held *before* Fn goes down latches immediately, so `Ctrl+Fn` pressed
as a chord works in either order.

### Latch suppression

On the un-latching `Fn` press, latching is suppressed for the remainder of
that hold. Without this, stopping with `Fn+Ctrl` re-latches: `Fn` down
un-latches, then `Ctrl` down sees a live recording and latches again. With
suppression, both `Fn` alone and `Fn+Ctrl` stop the recording.

### State

`AppCoordinator` owns two flags:

- `isLatched: Bool`
- `suppressLatchUntilRelease: Bool`

Not added to `AppState`. The enum is `Equatable` and pattern-matched at
several sites; a separate flag keeps the change contained, and the HUD is told
explicitly rather than inferring from state.

Both flags reset in `beginRecording`, `finishRecording`, and `cancel()`.

### Delegate behaviour

| Event | Condition | Behaviour |
|---|---|---|
| `hotkeyDidGoDown` | `isLatched` and state is `.recording` for this slot | un-latch, set `suppressLatchUntilRelease`, return |
| | otherwise | `beginRecording` (unchanged) |
| `hotkeyDidLatch` | state is `.arming` or `.recording` for this slot, and not suppressed | `isLatched = true` |
| `hotkeyDidGoUp` | `isLatched` **and** state is `.recording` | ignore — keep recording |
| | otherwise | clear both flags, `finishRecording` (unchanged) |

The `.recording` requirement on `hotkeyDidGoUp` matters: a latch can land while
the coordinator is still `.arming` (`ModifierHotkey`'s 50 ms graze filter and
`AppCoordinator`'s 50 ms arming delay are sequential). If the user releases
during that window, the event must fall through to the normal bail-to-idle
path instead of stranding a recording that never started.

### Control-edge detection

Lives in `ModifierHotkey`, which already owns a `flagsChanged` monitor and
`lastFlags`. No new monitor.

- In `handle(event:)`: a control up→down transition while `isDown` emits
  `onLatch(slot)`.
- In `handleDown()`'s arming task: after `onDown(slot)`, if control is already
  held per `lastFlags`, also emit `onLatch(slot)`. This is the
  order-insensitive half.

Detection uses the public `NSEvent.ModifierFlags.control` bit (`1 << 18`),
not the `NX_DEVICE*` device-specific bits. It covers both sides of the
keyboard and does not depend on device-bit layout. This differs from the rest
of `ModifierHotkey`, which needs device bits precisely because it must tell
left from right; the latch key does not.

Two eligibility guards:

1. Hold mode only. Toggle mode already runs hands-free.
2. The slot's own mask must not contain a Control key. A user who binds Right
   Control to slot A gets no latching, because the latch key would be the
   hotkey itself.

### HUD

`HUDViewModel` gains `latched: Bool`. When set, the recording pill's leading
5 pt pulsing red dot is replaced by SF Symbol `lock.fill` at ~9 pt in the same
red, with no pulse.

`HUDController.setLatched(_:)` mutates the model directly and must **not** go
through `show()`. Re-showing `.recording` runs `applyPresentation`, which calls
`resetLevels()` and zeroes `elapsed` — the waveform and timer would visibly
restart at the moment of latching.

### Settings

No schema change, no migration, no new persisted keys. One line of copy added
to the Tip card in `HotkeysPane` explaining the gesture.

## Two robustness fixes latching forces

Both are states that were unreachable-in-practice before, and become ordinary
once a recording can outlive the key that started it.

### `finishRecording` must ignore already-handed-off states

The bail-out path forced `.idle` and hid the HUD whenever state wasn't
`.recording`. A second call therefore clobbered an in-flight transcription:
the hard limit auto-stops a latched recording, the user (not holding anything,
so with no cue that it stopped) presses the hotkey to stop it, and the pill
vanishes mid-upload. The paste still landed; the HUD lied.

This predates latching — hold the hotkey for the full hard limit and release,
same result — but latching is the feature that produces long recordings nobody
is holding a key through, so it goes from a curiosity to a normal Tuesday.

`finishRecording` now switches exhaustively on `AppState` and returns early on
`.processing`, `.delivering`, and `.error`. `.error` is included for the same
class of reason: surfacing an error while the key is still down, then
releasing, used to dismiss the error toast before its 2 s timer.

Exhaustive rather than `default:` so a future `AppState` case fails to compile
until someone decides which side of the line it belongs on.

### Rebinding during a latched recording

`HotkeyManager.rebind()` tears down and rebuilds bindings whenever the user
edits a hotkey in Settings. `ModifierHotkey.stop()` emits a synthetic `onUp`
if the key was physically held — but a latched recording has already been
released, so no synthetic release arrives, and the recording is left running
with no bound key able to stop it. Only Esc (which discards the audio) and the
hard limit remain.

`rebind()` now calls `hotkeyBindingsWillChange()` on the delegate *before*
stopping the old bindings. The coordinator finishes a latched recording rather
than cancelling it — the user has already said something worth keeping.

The two fixes compose: when the key *was* held, the coordinator finishes the
recording and the teardown's synthetic `onUp` then hits the new early-return
guard instead of clobbering the transcription it just started.

Deliberately wired to `rebind()` only, not `stop()`. `stop()` also runs on app
shutdown, where kicking off a transcription that can't complete is worse than
dropping it.

## Files

| File | Change |
|---|---|
| `Sources/José/Hotkey/ModifierHotkey.swift` | control edge → `onLatch` callback, eligibility guards |
| `Sources/José/Hotkey/HotkeyManager.swift` | `hotkeyDidLatch` + `hotkeyBindingsWillChange` on the delegate, wire `onLatch`, notify before `rebind` |
| `Sources/José/App/AppCoordinator.swift` | two flags, four delegate branches, `setLatched`, resets, exhaustive `finishRecording` guard |
| `Sources/José/UI/HUD/HUDController.swift` | `setLatched(_:)` bypassing `show()` |
| `Sources/José/UI/HUD/HUDView.swift` | `latched` on `HUDViewModel`, dot → lock glyph |
| `Sources/José/UI/Settings/HotkeysPane.swift` | one line in the Tip card |

## Known limitations

**Stop requires a press longer than 50 ms.** `ModifierHotkey`'s hold mode
drops presses shorter than `armingDelay` as grazes, so a sub-50 ms tap while
latched does nothing — the recording stays latched and the user presses again.
Non-destructive, and a deliberate press-and-release is 60–120 ms. Accepted
rather than restructuring a working component.

**Right Control bound to slot A disables latching.** See eligibility guard 2.

**Esc cancels rather than finishes.** A latched recording ended with Esc
discards its audio, same as any other recording. Finishing requires the Fn
press-and-release. The existing hard limit (default 10 min) remains the
backstop for a latched recording the user forgets about.

**No cue that the hard limit fired.** When a latched recording auto-stops, the
HUD moves to processing and then away, but the user isn't holding anything and
may not be looking. Their next hotkey press is now a no-op against the
transcription (correctly, after the fix above) rather than the stop they
intended. Acceptable for v1; a distinct notice would be the fix.

## Verification

No test target exists in the repo. This design does not add one; the
`AppCoordinator` branch logic is pure state manipulation and would unit-test
cleanly if a target is added later.

Manual matrix:

1. Latch after start — Fn down, speak, Ctrl, release Fn, keep speaking, Fn
   press-release → transcript pastes.
2. Ctrl pre-held — hold Ctrl, press Fn, release both → recording continues.
3. Release during arming — Fn down, Ctrl, release Fn within ~100 ms → returns
   to idle, no stranded recording.
4. Stop with Fn alone while latched.
5. Stop with Fn+Ctrl while latched — must stop, not re-latch.
6. Esc while latched → cancels, flags cleared, next Fn hold behaves normally.
7. Hard limit while latched → auto-stops and transcribes.
8. Right Control bound to slot A → no latching, hold mode unaffected.
9. Slot A in toggle mode → Ctrl during recording does nothing.
10. HUD shows the lock glyph only while latched; waveform and timer do not
    reset at the moment of latching.
11. Hard limit fires while latched, *then* press the hotkey → the pill must
    stay through the upload and the paste must land. This is the clobber fix.
12. Error surfaced while the key is still held (e.g. deny the microphone),
    then release → the error toast must survive its full 2 s.
13. Change the slot A binding in Settings during a latched recording → the
    recording finishes and transcribes rather than running to the hard limit.
