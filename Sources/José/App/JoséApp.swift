import SwiftUI

@main
struct JoséApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // José is a menu-bar-only app (LSUIElement). All UI is owned by
        // AppDelegate via NSStatusItem, NSPanel (HUD), and NSWindow (Settings).
        // The Scene below exists only to satisfy SwiftUI's @main requirement;
        // we never present its window.
        Settings {
            EmptyView()
        }
    }
}
