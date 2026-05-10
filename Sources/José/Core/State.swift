import Foundation
import Observation

enum HotkeySlot: String, Codable, Hashable, Sendable {
    case A
    case B

    var action: RecordingAction {
        switch self {
        case .A: .pasteAndCopy
        case .B: .copyOnly
        }
    }
}

enum RecordingAction: String, Codable, Hashable, Sendable {
    case pasteAndCopy
    case copyOnly
}

enum AppState: Equatable, Sendable {
    case idle
    case arming(slot: HotkeySlot, since: Date)
    case recording(slot: HotkeySlot, since: Date)
    case processing(slot: HotkeySlot)
    case delivering(slot: HotkeySlot)
    case error(message: String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .idle, .error: false
        case .arming, .recording, .processing, .delivering: true
        }
    }

    var slot: HotkeySlot? {
        switch self {
        case .idle, .error: nil
        case .arming(let slot, _),
             .recording(let slot, _),
             .processing(let slot),
             .delivering(let slot):
            slot
        }
    }
}

@Observable
@MainActor
final class AppStateModel {
    private(set) var state: AppState = .idle

    func transition(to next: AppState) {
        Logger.coordinator.debug("state: \(String(describing: self.state)) → \(String(describing: next))")
        state = next
    }
}
