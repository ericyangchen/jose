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

        // Request Input Monitoring *before* the hotkey manager installs
        // any global event listeners — that's the OS's signal to register
        // José in the System Settings → Privacy → Input Monitoring list.
        // Calling it after `addGlobalMonitorForEvents` doesn't always
        // trigger the registration on macOS 14+, which is why the row
        // sometimes never appears in System Settings.
        _ = PermissionsCoordinator.shared.requestInputMonitoring()

        coordinator.start()

        // First-launch onboarding (BYOK flow). Skips itself + invokes the
        // completion synchronously if a key is already present.
        onboardingWindow.showIfNeeded { [weak self] in
            self?.coordinator.onboardingFinished()
            self?.requestAllPermissionsAtLaunch()
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
