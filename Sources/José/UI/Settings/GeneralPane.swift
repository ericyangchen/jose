import AppKit
import SwiftUI
import ServiceManagement

struct GeneralPane: View {
    @Bindable var settings: Settings

    var body: some View {
        PaneScaffold(title: "General") {
            SettingsCard("Startup") {
                SettingsRow(
                    "Launch José at login",
                    description: "Automatically start when you log in."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { newValue in
                            settings.launchAtLogin = newValue
                            applyLaunchAtLogin(newValue)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider()

                SettingsRow(
                    "Show in Dock",
                    description: "Off keeps José purely in the menu bar."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.showInDock },
                        set: { newValue in
                            settings.showInDock = newValue
                            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsCard("Menu Bar") {
                SettingsRow(
                    "Show usage in dropdown",
                    description: "Displays this month's transcription minutes and estimated cost."
                ) {
                    Toggle("", isOn: $settings.showUsageInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.settings.error("launchAtLogin toggle failed: \(error.localizedDescription)")
        }
    }
}
