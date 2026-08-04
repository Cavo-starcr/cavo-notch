import AppKit

/// Watches the pointer globally so the panel reacts even though the app never
/// becomes active. Mouse-move monitors need no accessibility permission.
@MainActor
final class HoverMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pending: DispatchWorkItem?
    /// State the pending work item is going to apply, if any.
    private var pendingTarget: Bool?
    private var isInside = false

    /// Rect that must be entered to open, in screen coordinates.
    var openRect: CGRect = .zero
    /// Rect that must be left to close, in screen coordinates.
    var closeRect: CGRect = .zero
    /// Delay before opening / closing, seconds.
    var openDelay: TimeInterval = 0.12
    var closeDelay: TimeInterval = 0.28

    var onChange: ((Bool) -> Void)?

    func start() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.evaluate() }
            return event
        }
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
        cancelPending()
    }

    /// Re-evaluates against the current pointer location; call after the panel
    /// is opened programmatically so leaving it still closes the panel.
    func evaluate() {
        let point = NSEvent.mouseLocation
        let rect = isInside ? closeRect : openRect
        let nowInside = rect.contains(point)

        guard nowInside != isInside else {
            // Pointer came back before the transition fired — drop it.
            cancelPending()
            return
        }
        // A transition to this state is already scheduled. Rescheduling it on
        // every event would mean the delay never elapses while the hand keeps
        // the pointer trembling, and the panel would only react once the mouse
        // stopped dead — e.g. during a click.
        guard pendingTarget != nowInside else { return }

        pending?.cancel()
        pendingTarget = nowInside
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.pendingTarget = nil
            // Confirm the pointer is still there once the delay has elapsed.
            let stillInside = (self.isInside ? self.closeRect : self.openRect).contains(NSEvent.mouseLocation)
            guard stillInside == nowInside else { return }
            self.isInside = nowInside
            self.onChange?(nowInside)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (nowInside ? openDelay : closeDelay), execute: work)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
        pendingTarget = nil
    }

    /// Force the internal state, e.g. when the panel is toggled from the menu.
    func setInside(_ value: Bool) {
        cancelPending()
        isInside = value
    }
}
