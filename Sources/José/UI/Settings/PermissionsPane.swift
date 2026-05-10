import SwiftUI

/// Live status of the three macOS permissions José needs, with one-click
/// access to each System Settings page.
struct PermissionsPane: View {
    @Bindable var permissions: PermissionsCoordinator

    /// Refresh tick — `withObservationTracking` wakes us when the user
    /// toggles a permission in System Settings while the pane is visible.
    @State private var refreshTimer: Timer?

    var body: some View {
        PaneScaffold(title: "Permissions") {
            SettingsCard {
                Text("José needs three system permissions to function. Toggle each in System Settings → Privacy & Security; status here updates automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard {
                VStack(spacing: 16) {
                    let allPerms = SystemPermission.allCases
                    ForEach(Array(allPerms.enumerated()), id: \.element.id) { index, perm in
                        PermissionRow(
                            permission: perm,
                            status: permissions.status(for: perm),
                            onOpen: { permissions.openSystemSettings(for: perm) },
                            onRetry: { handleRetry(for: perm) }
                        )
                        if index < allPerms.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            SettingsCard("Notes") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• Status reads live from the OS — no need to restart José after granting.")
                    Text("• If José is an unsigned debug build, every Xcode rebuild creates a new ad-hoc signature. Accessibility trust is bound to the binary's signature, so you may need to toggle the Accessibility checkbox OFF and back ON after a rebuild.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("• Input Monitoring requires an app restart after granting before global hotkeys start working.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            permissions.refresh()
            // SwiftUI can fire onAppear more than once for the same view
            // instance (e.g. when the pane is re-selected without the
            // previous view being deallocated). Invalidate any prior
            // timer first so we never leak repeating callbacks.
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak permissions] _ in
                Task { @MainActor in permissions?.refresh() }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func handleRetry(for permission: SystemPermission) {
        switch permission {
        case .microphone:
            Task { _ = await permissions.requestMicrophone() }
        case .accessibility:
            permissions.requestAccessibilityPrompt()
            // If the prompt is suppressed (already shown this session and
            // user dismissed without granting), just open Settings.
            if permissions.accessibility != .granted {
                permissions.openSystemSettings(for: .accessibility)
            }
        case .inputMonitoring:
            permissions.requestInputMonitoring()
            if permissions.inputMonitoring != .granted {
                permissions.openSystemSettings(for: .inputMonitoring)
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: SystemPermission
    let status: PermissionStatus
    let onOpen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 24)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(permission.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    statusBadge
                }
                Text(permission.rationale)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Button("Open Settings", action: onOpen)
                    .controlSize(.small)
                if status != .granted {
                    Button("Request", action: onRetry)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var icon: String {
        switch permission {
        case .microphone: "mic.fill"
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        }
    }

    private var iconColor: Color {
        status == .granted ? .accentColor : .secondary
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch status {
            case .granted:
                return ("Granted", Color(red: 0x5D / 255.0, green: 0xD3 / 255.0, blue: 0x9E / 255.0))
            case .denied:
                return ("Denied", Color(red: 0xEB / 255.0, green: 0x57 / 255.0, blue: 0x57 / 255.0))
            case .notDetermined:
                return ("Not asked", Color(red: 0xF2 / 255.0, green: 0xC9 / 255.0, blue: 0x4C / 255.0))
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.18))
            )
            .foregroundStyle(color)
    }
}
