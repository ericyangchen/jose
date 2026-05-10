import SwiftUI
import AppKit

struct AboutPane: View {
    var body: some View {
        PaneScaffold(title: "About", subtitle: "Version, license, and project links.") {
            SettingsCard {
                HStack(alignment: .top, spacing: 20) {
                    appIcon
                    VStack(alignment: .leading, spacing: 6) {
                        Text("José")
                            .font(.system(size: 22, weight: .semibold))
                        Text("Hold and Say")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("Version \(version) (build \(build))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    Spacer()
                }
            }

            SettingsCard("Links") {
                VStack(alignment: .leading, spacing: 6) {
                    Link("GitHub repository",
                         destination: URL(string: "https://github.com/eric/jose")!)
                    Link("OpenAI API terms of use",
                         destination: URL(string: "https://openai.com/policies/api-data-usage-policies")!)
                }
                .font(.system(size: 13))
            }

            SettingsCard("Privacy") {
                Text("José sends audio directly from your Mac to OpenAI using your own API key. No third-party server is involved. Per OpenAI's API terms, requests sent through the API are not used to train OpenAI's models by default — distinct from ChatGPT's terms.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Text("© 2026 Eric Chen")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0xF2 / 255, green: 0xA8 / 255, blue: 0xC4 / 255),
                        Color(red: 0xB5 / 255, green: 0xA8 / 255, blue: 0xE8 / 255),
                        Color(red: 0x8F / 255, green: 0xBC / 255, blue: 0xE8 / 255),
                        Color(red: 0x95 / 255, green: 0xDC / 255, blue: 0xDF / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 72, height: 72)
        .shadow(radius: 4, y: 2)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
