import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var coordinator: AppCoordinator!
    private(set) var statusItemController: StatusItemController!
    private(set) var hudController: HUDController!
    private(set) var settingsWindow: SettingsWindowController!
    private(set) var onboardingWindow: OnboardingWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("José launching")

        // Hide from Dock unless the user opted in.
        let policy: NSApplication.ActivationPolicy = Settings.shared.showInDock
            ? .regular
            : .accessory
        NSApp.setActivationPolicy(policy)

        // Compose the dependency graph. Each subsystem is owned here and
        // injected into AppCoordinator.
        self.coordinator = AppCoordinator(
            settings: Settings.shared,
            audioEngine: AudioEngine(),
            transcriptionClient: TranscriptionClient(),
            outputRouter: OutputRouter(),
            usageTracker: UsageTracker.shared,
            permissions: PermissionsCoordinator.shared
        )

        self.hudController = HUDController()
        self.settingsWindow = SettingsWindowController()
        self.onboardingWindow = OnboardingWindowController()

        self.statusItemController = StatusItemController(
            coordinator: coordinator,
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onQuit: { NSApp.terminate(nil) }
        )

        coordinator.bindUI(hud: hudController, statusItem: statusItemController)

        // Pre-mount the HUD's NSPanel + NSHostingView at launch so the
        // very first hotkey press doesn't pay the SwiftUI-tree mount
        // cost on the hot path.
        hudController.warmUp()

        // Note: we deliberately do *not* call requestInputMonitoring()
        // at launch. macOS auto-denies IOHIDRequestAccess for ad-hoc-
        // signed builds without showing a dialog, leaving the badge
        // stuck on "Denied" with no actionable state for the user.
        // Recording works without IM (modifier-key flagsChanged events
        // pass through without it on macOS 14+); only Esc-to-cancel
        // requires it. The Permissions pane has the explicit Request
        // button + drag-to-list workaround for users who want Esc cancel.

        coordinator.start()

        // First-launch onboarding (BYOK flow). Skips itself + invokes the
        // completion synchronously if a key is already present.
        let isFirstLaunch = (Defaults.bool(for: .onboardingCompleted) ?? false) == false
        onboardingWindow.showIfNeeded { [weak self] in
            self?.coordinator.onboardingFinished()
            self?.requestAllPermissionsAtLaunch()

            // First-time users land in Settings right after the BYOK flow
            // so they can rebind the hotkey, pick a model, etc. before
            // they go hunting for it. Returning users skip — Settings is
            // a click away in the menu-bar dropdown.
            if isFirstLaunch {
                self?.settingsWindow.show()
            }
        }
    }

    /// Request mic + Accessibility + Input Monitoring upfront so the user
    /// hits all the system dialogs in one batch on first launch instead of
    /// being interrupted mid-recording. Each request is idempotent: the
    /// system shows its dialog only when the permission is `.notDetermined`,
    /// and the OS-side check is non-blocking.
    private func requestAllPermissionsAtLaunch() {
        let permissions = PermissionsCoordinator.shared

        Task { @MainActor in
            // 1. Microphone — async API; system shows its consent dialog if
            // status is .notDetermined.
            _ = await permissions.requestMicrophone()

            // 2. Accessibility — synchronous prompt. Only shows once per
            // process; only fires when AXIsProcessTrusted() is currently false.
            permissions.requestAccessibilityPrompt()

            // 3. Input Monitoring — only fires its dialog when status is
            // .unknown / .notDetermined; harmless to call when already granted.
            permissions.requestInputMonitoring()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.app.info("José terminating")
        coordinator?.shutdown()
    }
}
