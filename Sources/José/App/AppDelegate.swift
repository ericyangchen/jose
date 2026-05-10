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
            self?.requestAllPermissionsAtLaunch(isFirstLaunch: isFirstLaunch)

            // Opening the .app should open Settings — even for returning
            // users. José is menu-bar-only with no Dock icon, so without
            // this every relaunch produced no visible UI and the user
            // had no idea anything happened.
            self?.settingsWindow.show()
        }
    }

    /// Called when the user re-opens the .app while José is already
    /// running (double-clicking the bundle in Finder, opening from
    /// Spotlight, etc.). For a menu-bar-only LSUIElement app there are
    /// no windows to bring forward by default, so the relaunch would
    /// otherwise be a no-op. Show Settings instead — that's the user's
    /// way of "opening" the app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }

    /// Request mic + Accessibility upfront so the user hits all the system
    /// dialogs in one batch on first launch instead of being interrupted
    /// mid-recording. Each request is idempotent: the system only shows its
    /// dialog when the permission is `.notDetermined`.
    ///
    /// `isFirstLaunch` is the trigger for the System Settings auto-open
    /// when AX isn't granted — `AXIsProcessTrustedWithOptions(prompt: true)`
    /// shows a dialog but doesn't always *register* the app in the AX
    /// list (especially for ad-hoc-signed bundles). Opening the AX page
    /// directly lets the user toggle the entry on (or click `+` to add
    /// the bundle manually if it doesn't show up).
    private func requestAllPermissionsAtLaunch(isFirstLaunch: Bool) {
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

            // Give the AX prompt a beat to register the app in TCC. Then
            // on first launch only, if the user still hasn't granted, open
            // System Settings → Privacy → Accessibility so the entry is
            // immediately findable. Returning users skip this — they don't
            // want Settings popping every launch.
            if isFirstLaunch {
                try? await Task.sleep(for: .seconds(1))
                if permissions.accessibility != .granted {
                    permissions.openSystemSettings(for: .accessibility)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.app.info("José terminating")
        coordinator?.shutdown()
    }
}
