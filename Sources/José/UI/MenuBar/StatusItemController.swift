import Foundation
import AppKit
import Observation

/// Owns the `NSStatusItem`, drives icon repaints from `AppStateModel`, and
/// hosts the dropdown menu. Spec §3.7 / §4.4.
///
/// Visibility model: rather than toggling `statusItem.isVisible`, we
/// add/remove the underlying `NSStatusItem` itself. macOS treats a
/// user-driven hide of `.removalAllowed` items as sticky — flipping
/// `isVisible = true` after the fact often doesn't bring the icon back
/// reliably. Removing and re-creating gives a clean, predictable transition.
@MainActor
final class StatusItemController {
    private let coordinator: AppCoordinator
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    private var statusItem: NSStatusItem?
    private let dropdown: DropdownMenu

    private var levelTask: Task<Void, Never>?
    private var animationTimer: Timer?
    private var visibilityObservation: NSKeyValueObservation?

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
        self.dropdown = DropdownMenu(
            coordinator: coordinator,
            onOpenSettings: onOpenSettings,
            onQuit: onQuit
        )

        if Settings.shared.showMenuBarIcon {
            installStatusItem()
        }

        armSettingsTracking()
        startObservingState()
    }

    deinit {
        levelTask?.cancel()
        animationTimer?.invalidate()
        visibilityObservation?.invalidate()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Install / uninstall

    private func installStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = dropdown.menu
        item.button?.image = StatusIcon.image(for: .idle)
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "José"
        item.behavior = [.removalAllowed]

        // KVO: if the user ⌘-drags the icon out of the menu bar, AppKit
        // sets isVisible = false on the live item. Treat that as a true
        // uninstall on our side too — actually remove the NSStatusItem
        // and write the setting through, so re-toggling it on later
        // creates a fresh, clean item.
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard let self, change.newValue == false else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                Logger.menubar.info("user removed status item via ⌘-drag — uninstalling")
                self.uninstallStatusItem()
                if Settings.shared.showMenuBarIcon {
                    Settings.shared.showMenuBarIcon = false
                }
            }
        }

        statusItem = item
        renderedState = .idle
        // Render the right initial frame for the current state.
        handleStateChange()
    }

    private func uninstallStatusItem() {
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    // MARK: - Settings ↔ menu-bar sync

    /// `withObservationTracking` is one-shot — re-arm after each fire.
    /// When the user flips Settings.showMenuBarIcon, install or uninstall
    /// the NSStatusItem accordingly. This is the toggle path; the KVO
    /// observation in `installStatusItem` handles the user-drag path.
    private func armSettingsTracking() {
        withObservationTracking {
            _ = Settings.shared.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let desired = Settings.shared.showMenuBarIcon
                if desired && self.statusItem == nil {
                    self.installStatusItem()
                } else if !desired && self.statusItem != nil {
                    self.uninstallStatusItem()
                }
                self.armSettingsTracking()
            }
        }
    }

    // MARK: - State observation

    private func startObservingState() {
        armObservation()
        handleStateChange()
    }

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
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateIcon()
            }
        }
        levelTask?.cancel()
        let stream = coordinator.audioEngine.makeLevelStream()
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
        guard let statusItem else { return }  // icon hidden — skip render
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
