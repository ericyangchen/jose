import SwiftUI

/// Live status of the three macOS permissions José needs, with one-click
/// access to each System Settings page.
struct PermissionsPane: View {
    @Bindable var permissions: PermissionsCoordinator

    /// Refresh tick — `withObservationTracking` wakes us when the user
    /// toggles a permission in System Settings while the pane is visible.
    @State private var refreshTimer: Timer?

    var body: some View {
        PaneScaffold(title: "Permissions", subtitle: "What José is allowed to do on this Mac.") {
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

            SettingsCard("Trouble granting Input Monitoring?") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Unsigned debug builds get auto-denied for Input Monitoring without showing a dialog (each rebuild gets a new ad-hoc signature, which macOS treats as untrusted). The two workarounds:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .center, spacing: 8) {
                        Text("1.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Drag José.app into the list manually:")
                            .font(.system(size: 11))
                        Spacer()
                        Button("Show José.app in Finder") {
                            permissions.revealAppInFinder()
                        }
                        .controlSize(.small)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text("2.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Reset cached TCC trust and relaunch:")
                            .font(.system(size: 11))
                        Spacer()
                        Button("Reset Trust") {
                            permissions.resetTCCTrust()
                        }
                        .controlSize(.small)
                    }

                    Text("After granting Input Monitoring, fully quit and relaunch José — the OS only honors the new permission for monitors installed *after* the grant.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    @State private var showsImAddInstructions = false

    private func handleRetry(for permission: SystemPermission) {
        switch permission {
        case .microphone:
            Task { _ = await permissions.requestMicrophone() }
        case .accessibility:
            permissions.requestAccessibilityPrompt()
            if permissions.accessibility != .granted {
                permissions.openSystemSettings(for: .accessibility)
            }
        case .inputMonitoring:
            // The OS-side IOHIDRequestAccess silently auto-denies for
            // ad-hoc-signed builds, so the standard Request flow doesn't
            // produce a list entry the user can toggle. Skip straight to
            // the manual-add workaround: pop Finder + Settings and show
            // a clear instruction sheet.
            permissions.requestInputMonitoring()
            if permissions.inputMonitoring != .granted {
                permissions.openSystemSettings(for: .inputMonitoring)
                permissions.revealAppInFinder()
                showsImAddInstructions = true
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
                    if permission.isOptional {
                        Text("Optional")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.4)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(.secondary)
                    }
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
