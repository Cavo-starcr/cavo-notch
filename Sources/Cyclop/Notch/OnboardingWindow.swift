import AppKit
import Combine
import SwiftUI

/// Hosts the first-run walkthrough, and the hint that sits under the notch while
/// it asks for the gesture.
///
/// This is the app's only real window. Everything else lives in a non-activating
/// panel over the menu bar, so showing this one means activating an accessory app
/// that has no main menu — which is fine for a window someone opened on purpose,
/// and is why it is closed and deactivated as soon as the walkthrough ends rather
/// than left sitting behind other apps.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    /// Bumped when the walkthrough changes enough to be worth showing again.
    /// Stored rather than a bool so a future version can re-introduce itself.
    private static let seenKey = "onboarding.seenVersion"
    private static let currentVersion = 1

    static var wasSeen: Bool {
        UserDefaults.standard.integer(forKey: seenKey) >= currentVersion
    }

    private var window: NSWindow?
    private var hint: NotchHintPanel?
    private var cancellable: AnyCancellable?
    /// Flipped when the panel unfolds, which is how the gesture step passes.
    private let opened = OpenedFlag()

    private weak var controller: NotchController?

    init(controller: NotchController?) {
        self.controller = controller
        super.init()
    }

    // MARK: - Presenting

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let flag = opened
        let view = Onboarding(
            showHint: { [weak self] on in self?.setHint(on) },
            finish: { [weak self] in self?.finish() },
            panelOpened: Binding(get: { flag.value }, set: { flag.value = $0 })
        )

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = localized("CAVO Notch")
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.contentView = NSHostingView(rootView: view)
        w.center()
        // Above ordinary windows: it is being read while the person is asked to
        // move the pointer somewhere else, and it must not get lost behind
        // whatever they were doing when the app launched.
        w.level = .floating
        w.delegate = self
        w.isReleasedWhenClosed = false
        window = w

        // The panel can be opened by the pointer at any moment; the walkthrough
        // only cares while the gesture step is on screen, and the view decides.
        cancellable = controller?.didOpenPanel
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.opened.value = true }

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.seenKey)
        setHint(false)
        window?.close()
    }

    /// Closing by the red button counts as finishing: re-showing a walkthrough
    /// somebody dismissed is the definition of nagging, and the menu bar item
    /// brings it back on request.
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.seenKey)
        setHint(false)
        cancellable = nil
        window = nil
        opened.value = false
        NSApp.deactivate()
    }

    // MARK: - The hint under the notch

    private func setHint(_ on: Bool) {
        guard on else {
            hint?.orderOut(nil)
            hint = nil
            return
        }
        guard let rect = controller?.notchRect else { return }
        let panel = NotchHintPanel(below: rect)
        panel.orderFrontRegardless()
        hint = panel
    }

    /// A tiny observable box, because SwiftUI needs a `Binding` and this object is
    /// not a view model — one flag does not deserve one.
    private final class OpenedFlag {
        var value = false
    }
}

/// "Here" — a small floating label with an arrow, sitting just under the notch
/// while the walkthrough asks for the gesture.
///
/// Borderless, non-activating and click-through: it is pointing at the very
/// region the pointer must reach, so it must not be the thing the pointer hits.
private final class NotchHintPanel: NSPanel {
    init(below notch: CGRect) {
        let size = CGSize(width: 208, height: 62)
        // Just under the notch, centred on it. Below, not beside: the panel is
        // about to unfold downwards over exactly this spot, and by then the hint
        // has done its job and is gone.
        let origin = CGPoint(
            x: notch.midX - size.width / 2,
            y: notch.minY - size.height - 14
        )
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = NSHostingView(rootView: NotchHintView())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct NotchHintView: View {
    @State private var up = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: up ? -4 : 2)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: up)
            Text(localized("Pointer here"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color(red: 0.039, green: 0.400, blue: 1.0))
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { up = true }
    }
}
