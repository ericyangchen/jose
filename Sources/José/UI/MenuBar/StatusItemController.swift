import Foundation
import AppKit

/// Controls the NSStatusItem and its dropdown menu. Worker B6 owns the
/// SwiftUI Canvas-driven icon, animation states, and dropdown contents.
@MainActor
final class StatusItemController {
    private let coordinator: AppCoordinator
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(
        coordinator: AppCoordinator,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        Logger.menubar.warning("StatusItemController is a stub — feat/menubar-icon not merged yet")
    }
}
