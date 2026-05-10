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
    private var escapeMonitor: Any?

    /// Recording grace period (spec §6.1.3) — short hold-mode taps are
    /// dropped so a stray finger graze doesn't trigger an upload.
    private let armingDelay: Duration = .milliseconds(50)

    /// Recordings shorter than this are silently discarded (spec §3.6).
    private let minimumRecordingDuration: Duration = .milliseconds(500)

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
        beginRecording(slot: slot)
    }

    func hotkeyDidGoUp(_ slot: HotkeySlot) {
        Logger.coordinator.debug("hotkey \(slot.rawValue) up")
        finishRecording(slot: slot)
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
        do {
            try await audioEngine.start()
            stateModel.transition(to: .recording(slot: slot, since: .now))
            hud?.show(.recording(audioLevels: audioEngine.audioLevelStream))
            scheduleHardLimit(slot: slot)
        } catch {
            Logger.coordinator.error("audio start failed: \(error.localizedDescription)")
            stateModel.transition(to: .error(message: "Mic unavailable"))
            hud?.show(.error(message: "Mic unavailable"))
            await scheduleErrorHide()
        }
    }

    private func finishRecording(slot: HotkeySlot) {
        armingTask?.cancel()
        hardLimitTask?.cancel()

        guard case .recording(_, let since) = stateModel.state else {
            // Released before audio actually started — just go back to idle.
            stateModel.transition(to: .idle)
            hud?.hide()
            return
        }

        let duration = Date.now.timeIntervalSince(since)
        if duration < (Double(minimumRecordingDuration.components.seconds)
                       + Double(minimumRecordingDuration.components.attoseconds) / 1e18) {
            Logger.coordinator.debug("recording too short (\(duration)s) — discarding")
            Task { _ = await audioEngine.cancel() }
            stateModel.transition(to: .idle)
            hud?.hide()
            return
        }

        stateModel.transition(to: .processing(slot: slot))
        hud?.show(.processing)

        pendingTranscriptionTask = Task { [weak self] in
            await self?.runTranscriptionPipeline(slot: slot, duration: duration)
        }
    }

    private func runTranscriptionPipeline(slot: HotkeySlot, duration: TimeInterval) async {
        do {
            let audioURL = await audioEngine.stop()
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
        } catch {
            Logger.coordinator.error("transcription failed: \(error.localizedDescription)")
            stateModel.transition(to: .error(message: error.localizedDescription))
            hud?.show(.error(message: error.localizedDescription))
            await scheduleErrorHide()
            stateModel.transition(to: .idle)
        }
    }

    private func scheduleHardLimit(slot: HotkeySlot) {
        let limit = Duration.seconds(settings.hardLimitMinutes * 60)
        hardLimitTask = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            await MainActor.run {
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
        armingTask?.cancel()
        hardLimitTask?.cancel()
        pendingTranscriptionTask?.cancel()
        Task { _ = await audioEngine.cancel() }
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
