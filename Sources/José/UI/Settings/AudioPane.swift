import SwiftUI
import AVFoundation

struct AudioPane: View {
    @Bindable var settings: Settings
    @State private var devices: [AudioDeviceOption] = []

    var body: some View {
        PaneScaffold(title: "Audio", subtitle: "Choose which microphone José listens on.") {
            SettingsCard("Input Device") {
                SettingsRow(
                    "Microphone",
                    description: "Choose the input source José uses while recording."
                ) {
                    Picker("", selection: Binding(
                        get: { settings.inputDeviceUID ?? "" },
                        set: { settings.inputDeviceUID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("(System default)").tag("")
                        ForEach(devices) { device in
                            Text(device.name).tag(device.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 260)
                }

                Button("Refresh") {
                    refreshDevices()
                }
                .controlSize(.small)
            }
        }
        .onAppear { refreshDevices() }
    }

    private func refreshDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        devices = session.devices.map {
            AudioDeviceOption(uniqueID: $0.uniqueID, name: $0.localizedName)
        }
    }
}

private struct AudioDeviceOption: Identifiable, Hashable {
    let uniqueID: String
    let name: String
    var id: String { uniqueID }
}
