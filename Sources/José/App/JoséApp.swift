import SwiftUI

@main
struct JoséApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI.Settings (qualified — we have our own Settings type).
        // José is a menu-bar-only app (LSUIElement); the AppDelegate owns
        // every visible window. This scene is never presented.
        SwiftUI.Settings {
            EmptyView()
        }
    }
}
