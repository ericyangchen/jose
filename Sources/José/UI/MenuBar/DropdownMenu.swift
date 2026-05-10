import Foundation
import AppKit

/// `NSMenu` shown when the user clicks the menu-bar status item. Contents
/// are rebuilt right before the menu opens so the live state line and the
/// monthly usage figures always reflect the latest values (spec §3.7).
@MainActor
final class DropdownMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let coordinator: AppCoordinator
    private let usageTracker: UsageTracker
    private let settings: Settings
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(
        coordinator: AppCoordinator,
        usageTracker: UsageTracker = .shared,
        settings: Settings = .shared,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.usageTracker = usageTracker
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuild()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    // MARK: - Build

    private func rebuild() {
        menu.removeAllItems()

        // Live status line (disabled — purely informational).
        let status = NSMenuItem(title: statusTitle(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if settings.showUsageInMenuBar {
            menu.addItem(.separator())

            let header = NSMenuItem(title: "This month", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let minutes = NSMenuItem(title: "  \(formattedMinutes())", action: nil, keyEquivalent: "")
            minutes.isEnabled = false
            menu.addItem(minutes)

            let cost = NSMenuItem(title: "  \(formattedCost())", action: nil, keyEquivalent: "")
            cost.isEnabled = false
            menu.addItem(cost)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(handleOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit José",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)
    }

    private func statusTitle() -> String {
        switch coordinator.stateModel.state {
        case .idle: "● Idle"
        case .arming: "● Arming…"
        case .recording: "● Recording"
        case .processing: "● Processing…"
        case .delivering: "● Delivering…"
        case .error(let message): "● Error: \(message)"
        }
    }

    private func formattedMinutes() -> String {
        let minutes = usageTracker.monthlyMinutes
        return String(format: "%.1f minutes", minutes)
    }

    private func formattedCost() -> String {
        let cost = usageTracker.estimatedMonthlyCost
        return String(format: "~$%.2f (estimated)", cost)
    }

    // MARK: - Actions

    @objc private func handleOpenSettings() {
        onOpenSettings()
    }

    @objc private func handleQuit() {
        onQuit()
    }
}
