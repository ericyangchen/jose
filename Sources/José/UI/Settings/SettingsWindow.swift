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
        window.title = "José Settings"
        window.titlebarAppearsTransparent = true
        window.contentViewController = host
        window.setContentSize(NSSize(width: 860, height: 580))
        window.minSize = NSSize(width: 720, height: 480)
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
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .onChange(of: selection) { _, newValue in
            onPaneChange(newValue)
        }
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
