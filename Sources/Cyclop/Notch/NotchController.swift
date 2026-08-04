import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchController {
    private var panel: NotchPanel?
    private var rootView: NotchRootView?
    private var viewModel: NotchViewModel?
    private let hover = HoverMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var closeActiveRectWork: DispatchWorkItem?

    func install() {
        build()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func teardown() {
        hover.stop()
        viewModel?.stop()
        panel?.orderOut(nil)
    }

    func toggle() {
        guard let viewModel else { return }
        setOpen(!viewModel.isOpen)
        hover.setInside(viewModel.isOpen)
    }

    // MARK: - Construction

    private func rebuild() {
        hover.stop()
        viewModel?.stop()
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
        build()
    }

    private func build() {
        let geometry = NotchGeometry.current()
        let vm = NotchViewModel(geometry: geometry)
        viewModel = vm

        let panel = NotchPanel(contentRect: geometry.windowFrame)
        let root = NotchRootView(frame: CGRect(origin: .zero, size: geometry.windowSize))
        root.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: NotchContentView(vm: vm))
        hosting.frame = root.bounds
        hosting.autoresizingMask = [.width, .height]
        if #available(macOS 14.0, *) {
            hosting.sizingOptions = []
        }
        root.addSubview(hosting)

        root.onDragEntered = { [weak self] in
            guard let self, let vm = self.viewModel else { return }
            vm.tab = .shelf
            vm.isDropTargeted = true
            self.setOpen(true)
        }
        root.onDragExited = { [weak self] in
            guard let self, let vm = self.viewModel else { return }
            vm.isDropTargeted = false
            self.hover.evaluate()
            // The pointer usually is not over the panel after a drag leaves.
            self.scheduleCollapseIfPointerAway()
        }
        root.onDrop = { [weak self] urls in
            guard let self, let vm = self.viewModel else { return false }
            vm.isDropTargeted = false
            let accepted = vm.accept(urls: urls)
            self.hover.setInside(true)
            self.setOpen(true)
            self.scheduleCollapseIfPointerAway()
            return accepted
        }

        panel.contentView = root
        panel.setFrame(geometry.windowFrame, display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.rootView = root

        applyActiveRect(open: false)

        hover.openRect = geometry.hoverRect
        hover.closeRect = geometry.expandedHoverRect
        hover.onChange = { [weak self] inside in
            self?.setOpen(inside)
        }
        hover.start()

        vm.start()
    }

    // MARK: - Open / close

    private func setOpen(_ open: Bool) {
        guard let vm = viewModel, vm.isOpen != open else { return }
        closeActiveRectWork?.cancel()

        if open {
            // Grow the interactive area first so the pointer never falls
            // through a region the animation has not covered yet.
            applyActiveRect(open: true)
            withAnimation(Theme.openAnimation) { vm.isOpen = true }
        } else {
            withAnimation(Theme.openAnimation) { vm.isOpen = false }
            let work = DispatchWorkItem { [weak self] in self?.applyActiveRect(open: false) }
            closeActiveRectWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: work)
        }
    }

    private func scheduleCollapseIfPointerAway() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let geometry = self.viewModel?.geometry else { return }
            if !geometry.expandedHoverRect.contains(NSEvent.mouseLocation) {
                self.hover.setInside(false)
                self.setOpen(false)
            }
        }
    }

    private func applyActiveRect(open: Bool) {
        guard let vm = viewModel, let rootView else { return }
        let size = open ? vm.geometry.expandedSize : vm.geometry.notchSize
        var rect = vm.geometry.contentRect(for: size)
        if open {
            // Slack so the concave shoulders stay grabbable. Never while
            // collapsed: that would swallow clicks on menu bar items next to
            // the notch.
            rect = rect.insetBy(dx: -Theme.openTopRadius, dy: 0)
        }
        rootView.activeRect = rect
    }
}
