import Foundation
import AppKit
import SwiftUI

enum HUDPresentation {
    case recording(audioLevels: AsyncStream<Float>)
    case processing
    case error(message: String)
    case notice(message: String)
}

@MainActor
final class HUDController {
    private let model = HUDViewModel()
    private var window: HUDWindow?
    private var hostingView: NSHostingView<HUDView>?
    private var levelTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var recordingStart: Date?

    private let bottomMargin: CGFloat = 120
    /// Inner pill height. The window is bigger by 2× haloBleed so the
    /// gradient glow has room to extend past the pill edge.
    private let height: CGFloat = 36
    private static let haloBleed: CGFloat = 8

    init() {}

    func show(_ presentation: HUDPresentation) {
        Logger.hud.debug("show: \(String(describing: presentation))")
        let wasFading = hideTask != nil
        hideTask?.cancel()
        hideTask = nil

        let panel = ensureWindow()
        let isFirstShow = !panel.isVisible

        // If we cancelled an animateOut mid-flight, the animator may have
        // already driven alphaValue toward 0 / origin downward. Snap them
        // back to a known-good state synchronously before any new animation
        // so we don't end up visible-but-transparent.
        if wasFading {
            panel.animator().alphaValue = 1
            panel.alphaValue = 1
        }

        // Resize the window FIRST, then update the SwiftUI model. If the
        // model changes before the window is resized, SwiftUI lays out the
        // new variant inside the old window's bounds, asks for more space
        // than it has, and we kick off a constraint-feedback pass.
        positionWindowForVariant(panel, variant: variant(for: presentation))
        applyPresentation(presentation)

        if isFirstShow || wasFading {
            animateIn(panel)
        }
    }

    private func variant(for presentation: HUDPresentation) -> HUDVariant {
        switch presentation {
        case .recording: .recording
        case .processing: .processing
        case .error(let m): .error(m)
        case .notice(let m): .notice(m)
        }
    }

    private func positionWindowForVariant(_ panel: HUDWindow, variant: HUDVariant) {
        let screen = activeScreen() ?? NSScreen.main ?? panel.screen ?? NSScreen.screens.first
        guard let screen else { return }

        let size = currentSize(for: variant)
        let frame = screen.visibleFrame
        let originX = frame.midX - size.width / 2
        let originY = frame.minY + bottomMargin
        panel.setFrame(NSRect(x: originX, y: originY, width: size.width, height: size.height), display: false)
    }

    func hide() {
        Logger.hud.debug("hide")
        cancelStreams()
        guard let panel = window, panel.isVisible else {
            window?.orderOut(nil)
            return
        }
        animateOut(panel)
    }

    // MARK: - Presentation routing

    private func applyPresentation(_ presentation: HUDPresentation) {
        cancelStreams()

        // Plain assignments — no withAnimation. The SwiftUI animation
        // wrapper kicks the hosting view into a constraint-update pass that
        // races with the panel's setFrame, eventually tripping AppKit's
        // "more constraint passes than views" guard and crashing the app.
        // Visual continuity comes from the .transition modifiers on each
        // variant view + the explicit window cross-fade in show().
        switch presentation {
        case .recording(let stream):
            model.resetLevels()
            recordingStart = Date()
            model.elapsed = 0
            model.pulse = true
            model.variant = .recording
            startTimer()
            consumeLevels(stream)

        case .processing:
            recordingStart = nil
            model.pulse = false
            model.variant = .processing

        case .error(let message):
            recordingStart = nil
            model.pulse = false
            model.variant = .error(message)

        case .notice(let message):
            recordingStart = nil
            model.pulse = false
            model.variant = .notice(message)
        }
    }

    private func cancelStreams() {
        levelTask?.cancel()
        levelTask = nil
        timerTask?.cancel()
        timerTask = nil
    }

    private func consumeLevels(_ stream: AsyncStream<Float>) {
        levelTask = Task { [weak self] in
            for await value in stream {
                if Task.isCancelled { break }
                await MainActor.run {
                    self?.model.pushLevel(value)
                }
            }
        }
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    guard let self, let start = self.recordingStart else { return }
                    self.model.elapsed = Date().timeIntervalSince(start)
                }
            }
        }
    }

    // MARK: - Window plumbing

    private func ensureWindow() -> HUDWindow {
        if let existing = window { return existing }

        let initialSize = currentSize(for: model.variant)
        let panel = HUDWindow(contentRect: NSRect(origin: .zero, size: initialSize))

        // Plain NSView wrapper isolates the panel's content layout from
        // the SwiftUI subtree's Auto Layout. NSHostingView directly as
        // contentView trips:
        //
        //   NSGenericException: The window has been marked as needing
        //   another Update Constraints in Window pass...
        //
        // every time the SwiftUI variant changes — its constraint
        // invalidation propagates back up through the window. Putting a
        // plain NSView in between absorbs those passes since it has no
        // constraints of its own.
        let wrapper = NSView(frame: NSRect(origin: .zero, size: initialSize))
        wrapper.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = wrapper.bounds
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        wrapper.addSubview(hosting)

        panel.contentView = wrapper

        self.window = panel
        self.hostingView = hosting
        return panel
    }

    private func currentSize(for variant: HUDVariant) -> NSSize {
        let bleed = Self.haloBleed * 2
        switch variant {
        case .recording:
            return NSSize(width: 200 + bleed, height: height + bleed)
        case .processing:
            // Just a tiny spinner pill — no text. The user said the
            // "Transcribing…" copy was both redundant and made the HUD
            // feel slow / heavy.
            return NSSize(width: height + bleed, height: height + bleed)
        case .error, .notice:
            return NSSize(width: 200 + bleed, height: height + bleed)
        }
    }

    private func positionWindow(_ panel: HUDWindow) {
        let screen = activeScreen() ?? NSScreen.main ?? panel.screen ?? NSScreen.screens.first
        guard let screen else { return }

        let size = currentSize(for: model.variant)
        let frame = screen.visibleFrame
        let originX = frame.midX - size.width / 2
        let originY = frame.minY + bottomMargin
        panel.setFrame(NSRect(x: originX, y: originY, width: size.width, height: size.height), display: true)
    }

    private func activeScreen() -> NSScreen? {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let frontPID {
            let app = AXUIElementCreateApplication(frontPID)
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
               let window = windowRef {
                var posValue: CFTypeRef?
                var sizeValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &posValue)
                AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeValue)

                var origin = CGPoint.zero
                var size = CGSize.zero
                if let posValue {
                    AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
                }
                if let sizeValue {
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                }
                let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                if let match = NSScreen.screens.first(where: { screen in
                    // AX coords are top-left origin; convert to bottom-left to compare with NSScreen.frame.
                    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                    let flipped = CGPoint(x: center.x, y: primaryHeight - center.y)
                    return screen.frame.contains(flipped)
                }) {
                    return match
                }
            }
        }
        return NSScreen.main
    }

    // MARK: - Animations

    private func animateIn(_ panel: HUDWindow) {
        let target = panel.frame
        let start = NSRect(x: target.origin.x, y: target.origin.y - 20, width: target.width, height: target.height)
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func animateOut(_ panel: HUDWindow) {
        let current = panel.frame
        let dropped = NSRect(x: current.origin.x, y: current.origin.y - 10, width: current.width, height: current.height)

        hideTask = Task { [weak self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.4
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0
                    panel.animator().setFrame(dropped, display: true)
                }, completionHandler: {
                    continuation.resume()
                })
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                panel.orderOut(nil)
                panel.alphaValue = 1
                self?.model.resetLevels()
            }
        }
    }
}
