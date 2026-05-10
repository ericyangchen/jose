import Foundation
import AppKit
import AVFoundation

enum SystemPermission {
    case microphone
    case accessibility
    case inputMonitoring
}

/// Permission requests + System Settings deep-links. Phase C3 fleshes out
/// the polling + first-run UX; this stub keeps everything compiling.
@MainActor
final class PermissionsCoordinator {
    init() {}

    var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var accessibilityAuthorized: Bool {
        // AXIsProcessTrusted() returns true if Accessibility is granted.
        // We DO NOT prompt here (passing nil options) — that's done lazily
        // when the user first triggers Hotkey A.
        return AXIsProcessTrusted()
    }

    func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func requestAccessibilityPrompt() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt" as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary?)
    }

    func openSystemSettings(for permission: SystemPermission) {
        let urlString: String
        switch permission {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
