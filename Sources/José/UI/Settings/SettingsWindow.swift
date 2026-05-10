import AppKit
import SwiftUI

/// Wraps the custom Settings window. Worker B7 owns the SwiftUI sidebar +
/// pane stack; this stub provides just the lifecycle so AppDelegate compiles.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    init() {}

    func show() {
        Logger.settings.warning("SettingsWindowController is a stub — feat/settings-ui not merged yet")
        if window == nil {
            let placeholder = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            placeholder.title = "José Settings"
            placeholder.center()
            window = placeholder
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
