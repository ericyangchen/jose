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
    @discardableResult
    func requestInputMonitoring() -> PermissionStatus {
        let result = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
        Logger.permissions.info("input monitoring requested → \(result ? "granted" : "denied/pending")")
        return inputMonitoring
    }

    // MARK: - Deeplinks

    func openSystemSettings(for permission: SystemPermission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
