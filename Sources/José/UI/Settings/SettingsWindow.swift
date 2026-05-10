import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private static let lastPaneKey = "settings.lastSelectedPane"

    override init() {
        super.init()
    }

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Keep window alive so reopening is instant; nothing to clean up.
    }

    private func makeWindow() -> NSWindow {
        let initialPane = SettingsPane(rawValue: UserDefaults.standard.string(forKey: Self.lastPaneKey) ?? "")
            ?? .general
        let root = SettingsRootView(
            settings: Settings.shared,
            initialPane: initialPane,
            onPaneChange: { pane in
                UserDefaults.standard.set(pane.rawValue, forKey: Self.lastPaneKey)
            }
        )
        let host = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentViewController = host
        window.setContentSize(NSSize(width: 920, height: 620))
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}

// MARK: - Root view

private struct SettingsRootView: View {
    @Bindable var settings: Settings
    @State var selection: SettingsPane
    let onPaneChange: (SettingsPane) -> Void

    init(settings: Settings, initialPane: SettingsPane, onPaneChange: @escaping (SettingsPane) -> Void) {
        self.settings = settings
        self._selection = State(initialValue: initialPane)
        self.onPaneChange = onPaneChange
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .background(.ultraThinMaterial)

            // Hairline divider — barely visible, just enough separation
            // between sidebar and content. Replaces the heavy SwiftUI
            // Divider() which read as a hard line.
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(contentBackground)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: selection) { _, newValue in
            onPaneChange(newValue)
        }
    }

    /// Subtle gradient backdrop behind the content cards — the cards'
    /// thinMaterial picks up a faint warm tint from this so the pane
    /// doesn't read as a flat slab of white/black.
    private var contentBackground: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color(red: 0.949, green: 0.659, blue: 0.769).opacity(0.05),
                    Color(red: 0.561, green: 0.737, blue: 0.910).opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:       GeneralPane(settings: settings)
        case .hotkeys:       HotkeysPane(settings: settings)
        case .audio:         AudioPane(settings: settings)
        case .transcription: TranscriptionPane(settings: settings)
        case .vocabulary:    VocabularyPane(settings: settings)
        case .permissions:   PermissionsPane(permissions: PermissionsCoordinator.shared)
        case .about:         AboutPane()
        }
    }
}
