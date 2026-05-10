import Foundation
import AppKit
import AVFoundation
import IOKit.hid
import Observation

enum SystemPermission: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var rationale: String {
        switch self {
        case .microphone:
            "Required to capture your voice for transcription."
        case .accessibility:
            "Required to paste the transcript at your cursor (synthesizes ⌘V into the focused app)."
        case .inputMonitoring:
            "Required to listen for the global hotkey while José is in the background."
        }
    }

    var systemSettingsURL: URL? {
        let urlString: String
        switch self {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
        return URL(string: urlString)
    }
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

/// Tracks live status of the three permissions José needs and surfaces
/// request / open-Settings helpers. The status is `@Observable`, so the
/// Permissions UI re-renders whenever `refresh()` is called (we poll while
/// the pane is visible to catch the user toggling in System Settings).
@Observable
@MainActor
final class PermissionsCoordinator {
    static let shared = PermissionsCoordinator()

    private(set) var microphone: PermissionStatus = .notDetermined
    private(set) var accessibility: PermissionStatus = .notDetermined
    private(set) var inputMonitoring: PermissionStatus = .notDetermined

    private init() {
        refresh()
    }

    func status(for permission: SystemPermission) -> PermissionStatus {
        switch permission {
        case .microphone: microphone
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }

    /// Re-reads the live state from the OS. Cheap; safe to call frequently.
    func refresh() {
        microphone = currentMicrophoneStatus()
        accessibility = currentAccessibilityStatus()
        inputMonitoring = currentInputMonitoringStatus()
    }

    // MARK: - Live reads

    private func currentMicrophoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .notDetermined
        }
    }

    private func currentAccessibilityStatus() -> PermissionStatus {
        // No way for the OS to tell us "the user hasn't decided yet" for
        // Accessibility — the trust list is binary. We treat anything
        // other than `trusted` as denied (the user has to take action).
        AXIsProcessTrusted() ? .granted : .denied
    }

    private func currentInputMonitoringStatus() -> PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        case kIOHIDAccessTypeUnknown: .notDetermined
        default: .notDetermined
        }
    }

    // MARK: - Requests

    /// Triggers macOS' microphone consent dialog if status is .notDetermined.
    /// Re-reads status afterward so observers see the result.
    @discardableResult
    func requestMicrophone() async -> PermissionStatus {
        if currentMicrophoneStatus() != .notDetermined {
            refresh()
            return microphone
        }
        let granted = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        refresh()
        Logger.permissions.info("microphone requested → \(granted ? "granted" : "denied")")
        return granted ? .granted : .denied
    }

    /// Fires the system Accessibility prompt (only does anything visible
    /// the first time per process — and only when not already trusted).
    /// No-op if already granted.
    func requestAccessibilityPrompt() {
        guard !AXIsProcessTrusted() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: NSDictionary = [key: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        refresh()
    }

    /// Triggers the Input Monitoring system prompt. Only shows once per
    /// process. After granting, the app must be restarted for the OS to
    /// honor it for global event listeners.
    ///
    /// We call this *before* installing any global event listeners so the
    /// OS gets a chance to register José in the Input Monitoring privacy
    /// list at a known time. Some macOS versions only add the app to the
    /// list after the first IOHIDRequestAccess call (not on the
    /// `addGlobalMonitorForEvents` call alone), so calling this proactively
    /// matters even when the hotkey monitor would technically work without
    /// the permission.
    @discardableResult
    func requestInputMonitoring() -> PermissionStatus {
        let beforeStatus = currentInputMonitoringStatus()
        let result = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
        Logger.permissions.info(
            "input monitoring requested → result=\(result), before=\(String(describing: beforeStatus)), after=\(String(describing: self.inputMonitoring))"
        )
        return inputMonitoring
    }

    // MARK: - Deeplinks

    func openSystemSettings(for permission: SystemPermission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pops a Finder window with José.app pre-selected so the user can
    /// drag it into the System Settings → Privacy → Input Monitoring (or
    /// Accessibility) list using the `+` button. This is the workaround
    /// for unsigned debug builds: macOS auto-denies IOHIDRequestAccess
    /// without showing a dialog, so the app never appears in the list
    /// automatically — manually adding it via the + button is the only
    /// path to grant.
    func revealAppInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// Wipes all TCC trust entries for José (Microphone + Accessibility +
    /// Input Monitoring). Useful for unsigned debug builds where each
    /// rebuild's new ad-hoc signature gets a stale "denied" cached entry
    /// the user can't see or undo through System Settings. Runs `tccutil`
    /// as the current user — no sudo needed.
    @discardableResult
    func resetTCCTrust() -> Bool {
        let services = ["ListenEvent", "Accessibility", "Microphone"]
        var allOK = true
        for service in services {
            let proc = Process()
            proc.launchPath = "/usr/bin/tccutil"
            proc.arguments = ["reset", service, KeychainStore.service]
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 { allOK = false }
            } catch {
                Logger.permissions.error("tccutil reset \(service) failed: \(error.localizedDescription)")
                allOK = false
            }
        }
        refresh()
        Logger.permissions.info("TCC reset \(allOK ? "succeeded" : "had failures") — restart the app to re-prompt")
        return allOK
    }
}
