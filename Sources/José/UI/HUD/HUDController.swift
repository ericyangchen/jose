import Foundation
import AppKit

enum HUDPresentation {
    case recording(audioLevels: AsyncStream<Float>)
    case processing
    case error(message: String)
    case notice(message: String)
}

/// Owner of the floating pill HUD window. Worker B5 owns the borderless
/// NSPanel + SwiftUI view tree; this stub keeps callers compiling.
@MainActor
final class HUDController {
    init() {}

    func show(_ presentation: HUDPresentation) {
        Logger.hud.debug("show: \(String(describing: presentation))")
        // feat/hud worker provides the real implementation.
    }

    func hide() {
        Logger.hud.debug("hide")
    }
}
