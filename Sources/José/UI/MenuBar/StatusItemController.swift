import Foundation
import AppKit
import Observation

/// Owns the `NSStatusItem`, drives icon repaints from `AppStateModel`, and
/// hosts the dropdown menu. Spec §3.7 / §4.4.
@MainActor
final class StatusItemController {
    private let coordinator: AppCoordinator
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    private let statusItem: NSStatusItem
    private let dropdown: DropdownMenu

    private var levelTask: Task<Void, Never>?
    private var animationTimer: Timer?

    private var latestLevel: Float = 0
    private var spinnerPhase: Double = 0
    private var renderedState: StatusIconState = .idle

    init(
        coordinator: AppCoordinator,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.dropdown = DropdownMenu(
            coordinator: coordinator,
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )

        statusItem.menu = dropdown.menu
        statusItem.button?.image = StatusIcon.image(for: .idle)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "José"

        startObservingState()
    }

    deinit {
        levelTask?.cancel()
        animationTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - State observation

    private func startObservingState() {
        armObservation()
        handleStateChange()
    }

    /// `withObservationTracking` is one-shot — it fires `onChange` exactly
    /// once and then stops. We re-arm it after every state change.
    private func armObservation() {
        withObservationTracking {
            _ = self.coordinator.stateModel.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleStateChange()
            }
        }
    }

    private func handleStateChange() {
        let state = coordinator.stateModel.state
        Logger.menubar.debug("status item state → \(String(describing: state))")
        switch state {
        case .recording:
            startRecordingAnimation()
        case .processing, .delivering:
            startProcessingAnimation()
        case .idle, .arming, .error:
            stopAnimation()
        }
        updateIcon()
        armObservation()
    }

    // MARK: - Animation

    private func startRecordingAnimation() {
        animationTimer?.invalidate()
        latestLevel = 0
        // 30 fps icon repaint.
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateIcon()
            }
        }
        levelTask?.cancel()
        let stream = coordinator.audioEngine.audioLevelStream
        levelTask = Task { [weak self] in
            for await level in stream {
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.latestLevel = level }
            }
        }
    }

    private func startProcessingAnimation() {
        animationTimer?.invalidate()
        spinnerPhase = 0
        levelTask?.cancel()
        // Slower repaint for spinner — 24 fps is plenty.
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.spinnerPhase = (self.spinnerPhase + 1.0 / 24.0).truncatingRemainder(dividingBy: 1.0)
                self.updateIcon()
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        levelTask?.cancel()
        levelTask = nil
        latestLevel = 0
        spinnerPhase = 0
    }

    // MARK: - Render

    private func updateIcon() {
        let next = currentIconState()
        if next != renderedState || isAnimated(next) {
            renderedState = next
            statusItem.button?.image = StatusIcon.image(for: next)
        }
    }

    private func currentIconState() -> StatusIconState {
        switch coordinator.stateModel.state {
        case .idle, .arming:
            return .idle
        case .recording:
            return .recording(level: latestLevel)
        case .processing, .delivering:
            return .processing(phase: spinnerPhase)
        case .error:
            return .error
        }
    }

    private func isAnimated(_ state: StatusIconState) -> Bool {
        switch state {
        case .recording, .processing: true
        case .idle, .error: false
        }
    }
}
