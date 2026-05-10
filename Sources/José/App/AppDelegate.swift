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
        // injected into AppCoordinator. Workers fill in implementations
        // for the placeholder types referenced below.
        self.coordinator = AppCoordinator(
            settings: Settings.shared,
            audioEngine: AudioEngine(),
            transcriptionClient: TranscriptionClient(),
            outputRouter: OutputRouter(),
            usageTracker: UsageTracker.shared,
            permissions: PermissionsCoordinator()
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
        coordinator.start()

        // First-launch onboarding (BYOK flow). Skips itself if a key is
        // already present.
        onboardingWindow.showIfNeeded { [weak self] in
            self?.coordinator.onboardingFinished()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.app.info("José terminating")
        coordinator?.shutdown()
    }
}
