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
    /// gradient glow has a tiny halo of empty pixels to fade into.
    /// Sized to feel like the iPhone Dynamic Island in its compact state —
    /// small enough to disappear from peripheral vision, big enough to
    /// host the dot + waveform + timer.
    private let height: CGFloat = 30
    private static let haloBleed: CGFloat = 3

    init() {}

    /// Eagerly create the HUD panel + its NSHostingView so the *first*
    /// recording doesn't pay the SwiftUI-tree-mounting cost on the hot
    /// path. Called from AppDelegate at launch.
    func warmUp() {
        _ = ensureWindow()
    }

    func show(_ presentation: HUDPresentation) {
        Logger.hud.debug("show: \(String(describing: presentation))")
        let wasFading = hideTask != nil
        hideTask?.cancel()
        hideTask = nil

        let panel = ensureWindow()
        let isFirstShow = !panel.isVisible
        let oldVariant = model.variant
        let newVariant = variant(for: presentation)
        // Smooth morph when we're already visible and the variant changes —
        // typically recording → processing (full pill compresses to spinner
        // puck) or processing → notice (puck expands to message pill).
        let morphing = !isFirstShow && !wasFading && oldVariant != newVariant

        if wasFading {
            panel.animator().alphaValue = 1
            panel.alphaValue = 1
        }

        if morphing {
            morph(panel: panel, to: presentation)
        } else {
            positionWindowForVariant(panel, variant: newVariant)
            applyPresentation(presentation, animated: false)

            if isFirstShow || wasFading {
                animateIn(panel)
            }
        }
    }

    /// Animated transition between two visible variants. The panel frame
    /// shrinks/expands while the SwiftUI content cross-fades inside the
    /// pill — recording bars + timer fade out as the pill compresses to
    /// a 30 × 30 puck, then the spinner fades in. Same applies in reverse
    /// (processing → notice puck expands back to message pill).
    private func morph(panel: HUDWindow, to presentation: HUDPresentation) {
        let newVariant = variant(for: presentation)
        let target = frameForVariant(newVariant, on: panel)

        // Update SwiftUI variant inside withAnimation — content
        // .transition(.opacity) modifiers cross-fade in step with the
        // window's frame animation.
        applyPresentation(presentation, animated: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
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

    private func frameForVariant(_ variant: HUDVariant, on panel: HUDWindow) -> NSRect {
        let screen = activeScreen() ?? NSScreen.main ?? panel.screen ?? NSScreen.screens.first
        let size = currentSize(for: variant)
        guard let screen else {
            return NSRect(origin: panel.frame.origin, size: size)
        }
        let frame = screen.visibleFrame
        let originX = frame.midX - size.width / 2
        let originY = frame.minY + bottomMargin
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private func positionWindowForVariant(_ panel: HUDWindow, variant: HUDVariant) {
        panel.setFrame(frameForVariant(variant, on: panel), display: false)
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

    /// `animated` controls whether the variant change runs inside a
    /// `withAnimation` block — true for in-place morphs between visible
    /// variants (so the SwiftUI .transition(.opacity) on each variant
    /// content cross-fades), false for first-show / hide-then-show paths
    /// where the morph isn't visible anyway.
    private func applyPresentation(_ presentation: HUDPresentation, animated: Bool) {
        cancelStreams()

        // Compute the new variant + side-effect mutations first; only the
        // model.variant assignment goes inside withAnimation so SwiftUI's
        // animation system stays narrowly scoped to the content swap.
        let newVariant: HUDVariant
        switch presentation {
        case .recording(let stream):
            model.resetLevels()
            recordingStart = Date()
            model.elapsed = 0
            model.pulse = true
            newVariant = .recording
            startTimer()
            consumeLevels(stream)

        case .processing:
            recordingStart = nil
            model.pulse = false
            newVariant = .processing

        case .error(let message):
            recordingStart = nil
            model.pulse = false
            newVariant = .error(message)

        case .notice(let message):
            recordingStart = nil
            model.pulse = false
            newVariant = .notice(message)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.30)) {
                model.variant = newVariant
            }
        } else {
            model.variant = newVariant
        }
    }

    private func cancelStreams() {
        levelTask?.cancel()
        levelTask = nil
        timerTask?.cancel()
        timerTask = nil
    }

    private func consumeLevels(_ stream: AsyncStream<Float>) {
        // Audio levels arrive at ~33 Hz (one per 30 ms chunk). Throttle
        // to ~6.6 Hz — peak across each ~150 ms window. With 26 bars in
        // the 130 pt pill, the waveform fills over ~4 s. The 180 ms
        // *linear* animation (see WaveformView) is longer than the push
        // interval, so consecutive samples are always interpolating —
        // the eye never sees a frozen frame between updates. Linear
        // (vs. easeOut) keeps motion continuous; easeOut introduced a
        // small "settle" at every step that read as a jump.
        let groupSize = 5
        levelTask = Task { [weak self] in
            var bucket: [Float] = []
            bucket.reserveCapacity(groupSize)
            for await value in stream {
                if Task.isCancelled { break }
                bucket.append(value)
                if bucket.count >= groupSize {
                    let peak = bucket.max() ?? 0
                    bucket.removeAll(keepingCapacity: true)
                    await MainActor.run {
                        self?.model.pushLevel(peak)
                    }
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
            return NSSize(width: 130 + bleed, height: height + bleed)
        case .processing:
            // Small horizontal pill (~50 × 30) that hosts three
            // sequentially-pulsing dots — more elegant than the
            // circular indeterminate spinner the user wanted gone.
            return NSSize(width: 54 + bleed, height: height + bleed)
        case .error, .notice:
            return NSSize(width: 130 + bleed, height: height + bleed)
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
        // Tighter pop: shorter rise distance + faster duration so the pill
        // appears nearly instantly. 0.13 s feels alive; 0.25 s felt slow.
        let start = NSRect(x: target.origin.x, y: target.origin.y - 8, width: target.width, height: target.height)
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
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
