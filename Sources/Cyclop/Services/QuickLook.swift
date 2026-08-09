import AppKit
import Quartz

/// Quick Look for shelf cards.
///
/// `QLPreviewPanel` is a shared window that pulls its contents out of whichever
/// object currently controls it, and it only offers control to the responder
/// chain of the *active* application. Cyclop is an accessory app behind a
/// non-activating panel, so it has no place in that chain: asking the panel to
/// open from where the click happened does nothing at all.
///
/// So control is taken explicitly instead. This object hands over the URLs,
/// becomes the panel's data source by hand, and activates the app for as long as
/// the preview is up — which is also what makes the arrow keys and the space bar
/// work inside it, since those are Quick Look's own and need a key window.
@MainActor
final class QuickLook: NSObject {
    static let shared = QuickLook()

    private var urls: [URL] = []
    /// Which item the preview opens on, so previewing the third card of a
    /// selection does not start from the first.
    private var startIndex = 0

    /// Whether the panel was opened by us, so `windowDidClose` only undoes an
    /// activation we actually performed.
    private var isPresenting = false

    private override init() { super.init() }

    /// True when Quick Look is on screen, whoever put it there.
    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    /// Shows `urls`, opening on `url`. A second call while the panel is up
    /// replaces the contents rather than stacking another window, which is what
    /// hitting space on a different card should do.
    func show(_ urls: [URL], starting at: URL? = nil) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        self.urls = existing
        startIndex = at.flatMap { existing.firstIndex(of: $0) } ?? 0

        // Documented as always available, but it is an implicitly-unwrapped
        // Objective-C return and this is a preview, not something worth
        // trapping the whole app over.
        guard let panel = QLPreviewPanel.shared() else { return }
        // Before the panel is asked to appear: it reads the app's active state
        // when it opens, and a panel that came up while the app was inactive
        // stays unfocused — visible, but deaf to every key Quick Look has.
        NSApp.activate(ignoringOtherApps: true)

        if panel.isVisible {
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.currentPreviewItemIndex = startIndex
            return
        }

        isPresenting = true
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = startIndex
    }

    func hide() {
        guard isVisible else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    /// Space toggles, the way it does in Finder.
    func toggle(_ urls: [URL], starting at: URL? = nil) {
        if isVisible {
            hide()
        } else {
            show(urls, starting: at)
        }
    }
}

extension QuickLook: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        // Indices arrive from the panel's own paging, which can outrun a reload.
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}

extension QuickLook: QLPreviewPanelDelegate {
    /// Hands the app's active state back on close.
    ///
    /// Without this the app stays active after a preview: an accessory app with
    /// no main menu leaves the menu bar showing nothing but the Apple logo, and
    /// whatever the person was actually working in is left without focus.
    ///
    /// `deactivate()` and emphatically not `hide(_:)`. Hiding an app orders out
    /// every window it owns, and the window this app owns is the notch — which
    /// nothing here would ever order back in, so one closed preview would take
    /// the panel with it until relaunch.
    func windowDidClose(_ panel: QLPreviewPanel) {
        guard isPresenting else { return }
        isPresenting = false
        urls = []
        NSApp.deactivate()
    }

    /// Esc closes it. The panel handles the rest of its own keys, but only if
    /// the delegate declines them rather than swallowing them.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.keyCode == 53 else { return false }
        hide()
        return true
    }
}
