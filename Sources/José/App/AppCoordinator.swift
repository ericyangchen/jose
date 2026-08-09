import Foundation
import AppKit

/// Central state machine and dependency hub. Every subsystem is observed
/// here; nothing else owns lifecycle. The flow follows spec §3.4 / §5.5:
///
///     idle → arming → recording → processing → delivering → idle
///
/// Slot A (.pasteAndCopy) takes the full pipeline; slot B (.copyOnly) skips
/// the synthetic ⌘V at the end. Esc cancels from any non-idle state.
@MainActor
final class AppCoordinator: HotkeyManagerDelegate {
    let stateModel = AppStateModel()
    let settings: Settings
    let audioEngine: AudioEngine
    let transcriptionClient: TranscriptionClient
    let outputRouter: OutputRouter
    let usageTracker: UsageTracker
    let permissions: PermissionsCoordinator
    private(set) lazy var hotkeyManager: HotkeyManager = {
        let mgr = HotkeyManager(settings: settings)
        mgr.delegate = self
        return mgr
    }()

    private weak var hud: HUDController?
    private weak var statusItem: StatusItemController?

    private var pendingTranscriptionTask: Task<Void, Never>?
    private var armingTask: Task<Void, Never>?
    private var hardLimitTask: Task<Void, Never>?
    private var softLimitTask: Task<Void, Never>?
    private var escapeMonitor: Any?

    /// Latched recording: the user pressed Control during a hold, so
    /// releasing the hotkey no longer stops the recording. Kept out of
    /// `AppState` deliberately — the enum is Equatable and pattern-matched
    /// at a dozen sites, and the HUD is told explicitly rather than
    /// inferring. See docs/superpowers/specs/2026-08-08-latched-recording-design.md
    private var isLatched: Bool = false

    /// Set on the un-latching press so Control can't re-latch before the
    /// user releases. Without it, stopping with Fn+Ctrl would un-latch on
    /// the Fn down and then latch straight back on the Ctrl down.
    private var suppressLatchUntilRelease: Bool = false

    /// Spec §6.1.3 — short hold-mode taps are dropped so a stray finger graze
    /// doesn't trigger an upload.
    private let armingDelay: Duration = .milliseconds(50)

    /// Recordings shorter than this are silently discarded (spec §3.6).
    private let minimumRecordingDuration: TimeInterval = 0.5

    /// Spec §3.6 — if VAD's lifetime speech ratio is below this, prompt the
    /// user before uploading (the recording is most likely silence).
    private let allSilenceSpeechRatioGate: Double = 0.05

    init(
        settings: Settings,
        audioEngine: AudioEngine,
        transcriptionClient: TranscriptionClient,
        outputRouter: OutputRouter,
        usageTracker: UsageTracker,
        permissions: PermissionsCoordinator
    ) {
        self.settings = settings
        self.audioEngine = audioEngine
        self.transcriptionClient = transcriptionClient
        self.outputRouter = outputRouter
        self.usageTracker = usageTracker
        self.permissions = permissions
    }

    func bindUI(hud: HUDController, statusItem: StatusItemController) {
        self.hud = hud
        self.statusItem = statusItem
    }

    func start() {
        hotkeyManager.start()
        installEscapeMonitor()
    }

    func shutdown() {
        hotkeyManager.stop()
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    func onboardingFinished() {
        Logger.app.info("onboarding finished — coordinator ready to record")
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidGoDown(_ slot: HotkeySlot) {
        Logger.coordinator.debug("hotkey \(slot.rawValue) down")
        if isLatched, stateModel.state.isRecording, stateModel.state.slot == slot {
            // Re-attach the hold. This press starts nothing; the release
            // that follows is what stops the recording.
            Logger.coordinator.debug("hotkey \(slot.rawValue) un-latched")
            setLatched(false)
            suppressLatchUntilRelease = true
            return
        }
        beginRecording(slot: slot)
    }

    func hotkeyDidGoUp(_ slot: HotkeySlot) {
        Logger.coordinator.debug("hotkey \(slot.rawValue) up")
        if isLatched, stateModel.state.isRecording, stateModel.state.slot == slot {
            // Latched — the user let go on purpose. Keep recording.
            return
        }
        finishRecording(slot: slot)
    }

    func hotkeyDidLatch(_ slot: HotkeySlot) {
        guard !suppressLatchUntilRelease, !isLatched else { return }
        guard stateModel.state.slot == slot else { return }
        // `.arming` counts: ModifierHotkey's 50 ms graze filter and this
        // coordinator's 50 ms arming delay run back to back, so a latch
        // can land ~100 ms before the state reaches .recording.
        switch stateModel.state {
        case .arming, .recording:
            Logger.coordinator.debug("hotkey \(slot.rawValue) latched")
            setLatched(true)
        default:
            break
        }
    }

    func hotkeyBindingsWillChange() {
        guard isLatched else { return }
        guard stateModel.state.isRecording, let slot = stateModel.state.slot else {
            setLatched(false)
            suppressLatchUntilRelease = false
            return
        }
        // Finish rather than cancel — the user has already said something
        // worth keeping, and the alternative is a recording that runs until
        // the hard limit with no bound key able to stop it.
        Logger.coordinator.info("hotkey rebind during a latched recording — finishing it")
        finishRecording(slot: slot)
    }

    private func setLatched(_ latched: Bool) {
        guard isLatched != latched else { return }
        isLatched = latched
        hud?.setLatched(latched)
    }

    func hotkeyDidFire(_ slot: HotkeySlot) {
        // Toggle-mode synthetic event: if recording, stop. Otherwise start.
        if case .recording(let activeSlot, _) = stateModel.state, activeSlot == slot {
            finishRecording(slot: slot)
        } else if !stateModel.state.isBusy {
            beginRecording(slot: slot)
            // Toggle mode bypasses the hold-release detection — the next
            // .fire on the same slot will trip finishRecording above.
        }
    }

    // MARK: - Lifecycle steps (filled in by integration phase C2)

    private func beginRecording(slot: HotkeySlot) {
        guard !stateModel.state.isBusy else { return }
        // A fresh recording never inherits a latch.
        setLatched(false)
        suppressLatchUntilRelease = false
        stateModel.transition(to: .arming(slot: slot, since: .now))

        armingTask?.cancel()
        armingTask = Task { [weak self] in
            try? await Task.sleep(for: self?.armingDelay ?? .milliseconds(50))
            guard !Task.isCancelled else { return }
            await self?.actuallyStartRecording(slot: slot)
        }
    }

    private func actuallyStartRecording(slot: HotkeySlot) async {
        guard case .arming = stateModel.state else { return }

        if permissions.microphone != .granted {
            let result = await permissions.requestMicrophone()
            guard result == .granted else {
                Logger.coordinator.warning("microphone permission denied")
                stateModel.transition(to: .error(message: "Microphone access denied"))
                hud?.show(.error(message: "Microphone access denied"))
                permissions.openSystemSettings(for: .microphone)
                await scheduleErrorHide()
                stateModel.transition(to: .idle)
                return
            }
            // After the await, the user may have released the hotkey
            // already; re-check before starting the engine.
            guard case .arming = stateModel.state else { return }
        }

        // Show the HUD *before* awaiting the audio engine — engine startup
        // takes ~50–80 ms (after the VAD pre-warm in AudioEngine.init) but
        // the user wants instant visual feedback. The level stream
        // continuation is registered immediately on makeLevelStream(); it
        // simply doesn't yield values until the engine starts producing
        // buffers. Bars stay at the silence baseline for the brief
        // pre-start window, then come alive.
        hud?.show(.recording(audioLevels: audioEngine.makeLevelStream()))

        do {
            try await audioEngine.start()
            // Engine start can take a few tens of ms; the user might have
            // released (or pressed Esc) during that await. If state is no
            // longer .arming, we have no way to stop the engine via the
            // normal path (no further .up event will arrive), so cancel.
            guard case .arming = stateModel.state else {
                Logger.coordinator.debug("state changed during audio start — cancelling")
                await audioEngine.cancel()
                hud?.hide()
                return
            }
            stateModel.transition(to: .recording(slot: slot, since: .now))
            scheduleSoftLimit(slot: slot)
            scheduleHardLimit(slot: slot)
        } catch {
            Logger.coordinator.error("audio start failed: \(error.localizedDescription)")
            stateModel.transition(to: .error(message: "Mic unavailable"))
            hud?.show(.error(message: "Mic unavailable"))
            await scheduleErrorHide()
            stateModel.transition(to: .idle)
        }
    }

    private func finishRecording(slot: HotkeySlot) {
        // A stray second call must not clobber work that's already moved
        // past recording. Two ways to get one: the hard limit auto-stops a
        // latched recording and the user only then releases the hotkey, or
        // an error is surfaced while the key is still held. Both used to
        // force .idle and hide the HUD out from under an in-flight
        // transcription. Exhaustive on purpose — a new AppState case should
        // fail to compile until someone decides which side it belongs on.
        switch stateModel.state {
        case .idle, .arming, .recording:
            break
        case .processing, .delivering, .error:
            Logger.coordinator.debug("finishRecording ignored — already \(String(describing: self.stateModel.state))")
            return
        }

        // Covers every exit: hotkey release, hard limit, and the bail-out
        // path when the release lands during arming.
        setLatched(false)
        suppressLatchUntilRelease = false

        armingTask?.cancel()
        hardLimitTask?.cancel()
        softLimitTask?.cancel()

        guard case .recording(_, let since) = stateModel.state else {
            // Released before audio actually started — bail.
            stateModel.transition(to: .idle)
            hud?.hide()
            return
        }

        let duration = Date.now.timeIntervalSince(since)
        if duration < minimumRecordingDuration {
            Logger.coordinator.debug("recording too short (\(duration)s) — discarding")
            Task { await self.audioEngine.cancel() }
            stateModel.transition(to: .idle)
            hud?.hide()
            return
        }

        // Don't switch the HUD to .processing yet — runTranscriptionPipeline
        // first stops audio + checks VAD; if no speech was detected we
        // want to morph the recording pill directly into a same-width
        // notice pill, not flash through the tiny spinner pill in
        // between.
        stateModel.transition(to: .processing(slot: slot))

        pendingTranscriptionTask = Task { [weak self] in
            await self?.runTranscriptionPipeline(slot: slot, duration: duration)
        }
    }

    private func runTranscriptionPipeline(slot: HotkeySlot, duration: TimeInterval) async {
        let audioURL = await audioEngine.stop()
        let hadSpeech = audioEngine.hadSpeech

        if !hadSpeech {
            Logger.coordinator.info("VAD ratio under \(Int(self.allSilenceSpeechRatioGate * 100))% — likely silence, discarding")
            try? FileManager.default.removeItem(at: audioURL)
            // Same-width notice pill — morphs in place from the recording
            // pill instead of flashing through a smaller spinner.
            hud?.show(.notice(message: "No speech detected"))
            stateModel.transition(to: .idle)
            try? await Task.sleep(for: .milliseconds(1500))
            hud?.hide()
            return
        }

        // Has speech — switch to the spinner pill while the upload is in flight.
        hud?.show(.processing)

        do {
            let prompt = PromptBuilder.build(from: settings)
            let text = try await transcriptionClient.transcribe(
                audio: audioURL,
                prompt: prompt,
                model: settings.transcriptionModel
            )
            try? FileManager.default.removeItem(at: audioURL)

            usageTracker.record(durationSeconds: duration, model: settings.transcriptionModel)

            stateModel.transition(to: .delivering(slot: slot))
            await outputRouter.deliver(text: text, action: slot.action)
            stateModel.transition(to: .idle)
            hud?.hide()
        } catch is CancellationError {
            // User pressed Esc during processing. cancel() already drove the
            // HUD to .notice("Cancelled") and returned the state machine to
            // idle — bail without overriding it with an error.
            try? FileManager.default.removeItem(at: audioURL)
            return
        } catch let error as TranscriptionError {
            // Keep the m4a around so the user can manually retry the failed
            // upload (per spec §3.6 — m4a stays until next success).
            Logger.coordinator.error("transcription failed (\(error.localizedDescription)) — keeping audio at \(audioURL.path)")
            await surfaceError(error)
        } catch {
            Logger.coordinator.error("transcription failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: audioURL)
            await surfaceError(error)
        }
    }

    private func surfaceError(_ error: Error) async {
        let message: String
        switch error {
        case TranscriptionError.invalidAPIKey:
            message = "Invalid API key — check Settings"
        case TranscriptionError.missingAPIKey:
            message = "No API key set"
        case TranscriptionError.rateLimited(let retryAfter):
            if let after = retryAfter {
                message = "Rate limited — wait \(Int(after))s"
            } else {
                message = "Rate limited"
            }
        case TranscriptionError.network:
            message = "Network error"
        case TranscriptionError.server(let status, _):
            message = "Server error (\(status))"
        default:
            message = "Transcription failed"
        }

        stateModel.transition(to: .error(message: message))
        hud?.show(.error(message: message))
        await scheduleErrorHide()
        stateModel.transition(to: .idle)
    }

    private func scheduleSoftLimit(slot: HotkeySlot) {
        let limit = Duration.seconds(settings.softLimitMinutes * 60)
        softLimitTask = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled, let self else { return }
            // Soft limit: re-emit the recording HUD with a "long recording"
            // notice; we keep the same stream so animation continues.
            await MainActor.run {
                guard case .recording = self.stateModel.state else { return }
                Logger.coordinator.info("soft limit reached")
                self.hud?.show(.notice(message: "Long recording…"))
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, case .recording = self.stateModel.state else { return }
                    self.hud?.show(.recording(audioLevels: self.audioEngine.makeLevelStream()))
                }
            }
        }
    }

    private func scheduleHardLimit(slot: HotkeySlot) {
        let limit = Duration.seconds(settings.hardLimitMinutes * 60)
        hardLimitTask = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                Logger.coordinator.info("hard limit reached — auto-stopping")
                self?.finishRecording(slot: slot)
            }
        }
    }

    private func scheduleErrorHide() async {
        try? await Task.sleep(for: .seconds(2))
        hud?.hide()
    }

    // MARK: - Cancel via Esc

    func cancel() {
        setLatched(false)
        suppressLatchUntilRelease = false

        armingTask?.cancel()
        hardLimitTask?.cancel()
        softLimitTask?.cancel()
        pendingTranscriptionTask?.cancel()
        Task { await self.audioEngine.cancel() }
        stateModel.transition(to: .idle)
        hud?.show(.notice(message: "Cancelled"))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.hud?.hide()
        }
    }

    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            // 53 = kVK_Escape
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                guard self.stateModel.state.isBusy else { return }
                self.cancel()
            }
        }
    }
}
