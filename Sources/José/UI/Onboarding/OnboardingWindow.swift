import AppKit
import SwiftUI

/// First-launch BYOK flow. Worker B7 owns the real flow; this stub just
/// fires the completion handler so AppCoordinator compiles + runs.
@MainActor
final class OnboardingWindowController {
    init() {}

    /// Show only if no API key is in Keychain. Calls `completion` once
    /// the user finishes (or skips if no onboarding is needed).
    func showIfNeeded(completion: @escaping () -> Void) {
        if KeychainStore.loadAPIKey() != nil {
            completion()
            return
        }
        Logger.app.warning("OnboardingWindowController is a stub — feat/settings-ui will replace this")
        completion()
    }
}
