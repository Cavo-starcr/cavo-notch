import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var controller: NotchController?
    private var statusItem: NSStatusItem?
    private var clearVaultItem: NSMenuItem?
    private var privacyItem: NSMenuItem?
    private var privacyAllItem: NSMenuItem?
    private var privacySectionItems: [PrivacyMode.Section: NSMenuItem] = [:]
    private var loginItem: NSMenuItem?
    private var saveShotsItem: NSMenuItem?
    private var notifyItem: NSMenuItem?
    private var onboarding: OnboardingWindow?
    private var appearanceWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()
        controller?.install()
        installStatusItem()
        observeTimer()
        // Set before anything can be delivered, otherwise a banner that arrives
        // while the app happens to be frontmost is dropped without a trace.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

        // First run only. An app that hides in the notch looks like a launch that
        // failed, so the one thing worth interrupting for is where to point.
        onboarding = OnboardingWindow(controller: controller)
        if !OnboardingWindow.wasSeen {
            // After the status item exists: the last step points at it, and an
            // arrow at an icon that is not there yet explains nothing.
            DispatchQueue.main.async { [weak self] in self?.onboarding?.show() }
        }
    }

    /// Shows the banner even when Cyclop is the active app.
    ///
    /// The default is to suppress it — reasonable for an app you are looking at,
    /// wrong for this one: being active here means a preview or a menu is open,
    /// not that anyone is watching the countdown.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.teardown()
    }

    // MARK: - Menu bar item

    private func installStatusItem() {
        // Variable, not square: the timer writes a countdown next to the icon,
        // and a fixed square would clip it.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "eye.fill",
            accessibilityDescription: "CAVO Notch"
        )
        item.button?.image?.isTemplate = true
        // Set once, not on every tick: monospaced digits are what stop the item
        // twitching wider and narrower as the countdown runs, and the font does
        // not change afterwards — only the title does.
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)

        let menu = NSMenu()
        // Enabling is decided here, not guessed from the responder chain: the
        // clear item below is disabled exactly when the folder is empty.
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(withTitle: "CAVO Notch \(Bundle.main.shortVersion)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: localized("Open Panel"),
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let login = NSMenuItem(
            title: localized("Launch at Login"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)
        loginItem = login

        // Sits next to the panel switch rather than among the folder items: it
        // changes what the panel shows, and it is the one people look for in a
        // hurry, with the camera already running.
        //
        // A submenu rather than a plain switch, because the tabs hold different
        // things and not everyone wants all of them covered. "All" comes first
        // and is what most people will ever touch; the sections below it are
        // for the case where that is too much.
        let privacy = NSMenuItem(title: localized("Hide Contents"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let all = NSMenuItem(title: localized("All"), action: #selector(togglePrivacyAll), keyEquivalent: "")
        all.target = self
        submenu.addItem(all)
        privacyAllItem = all
        submenu.addItem(.separator())

        for section in PrivacyMode.Section.allCases {
            let item = NSMenuItem(
                title: section.title,
                action: #selector(togglePrivacySection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = section.rawValue
            submenu.addItem(item)
            privacySectionItems[section] = item
        }

        privacy.submenu = submenu
        menu.addItem(privacy)
        privacyItem = privacy

        let saveShots = NSMenuItem(
            title: localized("Save Clipboard Screenshots"),
            action: #selector(toggleSaveClipboardImages),
            keyEquivalent: ""
        )
        saveShots.target = self
        saveShots.state = NotchViewModel.saveClipboardImagesEnabled ? .on : .off
        menu.addItem(saveShots)
        saveShotsItem = saveShots

        let notify = NSMenuItem(
            title: localized("Timer Notifications"),
            action: #selector(toggleTimerNotifications),
            keyEquivalent: ""
        )
        notify.target = self
        notify.state = TimerNotifier.isEnabled ? .on : .off
        menu.addItem(notify)
        notifyItem = notify

        let style = NSMenuItem(
            title: localized("Appearance…"),
            action: #selector(showAppearance),
            keyEquivalent: ""
        )
        style.target = self
        menu.addItem(style)

        let howTo = NSMenuItem(
            title: localized("How It Works"),
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        howTo.target = self
        menu.addItem(howTo)

        let openFolder = NSMenuItem(
            title: localized("Show Screenshots Folder"),
            action: #selector(revealScreenshots),
            keyEquivalent: ""
        )
        openFolder.target = self
        menu.addItem(openFolder)

        // Screenshots accumulate forever by design — nothing in that folder is
        // deleted behind the user's back. This is the other half of that deal:
        // one visible, hand-operated way out, with the current size right in
        // the title so the offer names its price.
        let clearVault = NSMenuItem(
            title: localized("Clear Screenshots Folder"),
            action: #selector(clearScreenshots),
            keyEquivalent: ""
        )
        clearVault.target = self
        menu.addItem(clearVault)
        clearVaultItem = clearVault

        let openSnippets = NSMenuItem(
            title: localized("Show Snippets File"),
            action: #selector(revealSnippets),
            keyEquivalent: ""
        )
        openSnippets.target = self
        menu.addItem(openSnippets)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: localized("Quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        controller?.toggle()
    }

    // MARK: - Timer in the menu bar
    //
    // The notch is black while the panel is collapsed and stays that way, so a
    // running countdown would otherwise be invisible unless the panel were held
    // open. The menu bar item is already on screen at all times and costs
    // nothing to write to, which makes it the right place for the one number
    // this app produces that is useless if you cannot see it.

    private func observeTimer() {
        guard let timer = controller?.timer else { return }
        timer.objectWillChange
            // objectWillChange fires *before* the value lands, so reading it
            // synchronously would render the previous second, forever one behind.
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)
    }

    /// Shows the countdown beside the icon while one is running, and nothing at
    /// all when it is not: an idle app should look idle in the menu bar too.
    private func refreshStatusTitle() {
        guard let button = statusItem?.button, let timer = controller?.timer else { return }
        if timer.isFinished {
            button.title = " \(localized("Done"))"
        } else if timer.isIdle {
            button.title = ""
        } else {
            // A leading space, because the image and the title butt up against
            // each other otherwise.
            button.title = " \(timer.clock)"
        }
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
    }

    /// Everything shown is re-read when the menu opens, not kept fresh in
    /// between: a menu nobody is looking at deserves no bookkeeping — and a
    /// state set once at launch quietly goes stale. Launch-at-login is the
    /// live case: System Settings can switch it off from outside, and the
    /// checkmark here used to keep claiming otherwise until relaunch (#11).
    func menuWillOpen(_ menu: NSMenu) {
        refreshPrivacyItems()
        loginItem?.state = launchAtLoginEnabled ? .on : .off
        saveShotsItem?.state = NotchViewModel.saveClipboardImagesEnabled ? .on : .off
        notifyItem?.state = TimerNotifier.isEnabled ? .on : .off

        guard let clearVaultItem else { return }
        // Off the main thread: walking the folder takes as long as the folder
        // is big, and this is the thread the whole panel lives on (#11). The
        // menu is already open when the answer lands; the title updates in
        // place.
        DispatchQueue.global(qos: .userInitiated).async { [weak clearVaultItem] in
            let usage = ScreenshotVault.usage()
            let size = ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file)
            DispatchQueue.main.async {
                guard let clearVaultItem else { return }
                if usage.files == 0 {
                    clearVaultItem.title = localized("Clear Screenshots Folder")
                    clearVaultItem.isEnabled = false
                } else {
                    clearVaultItem.title = localized("Clear Screenshots Folder (%@)", size)
                    clearVaultItem.isEnabled = true
                }
            }
        }
    }

    @objc private func clearScreenshots() {
        ScreenshotVault.clear()
        // The cards pointing into that folder just went to the Trash with it.
        controller?.reloadShelf()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func togglePrivacyAll(_ sender: NSMenuItem) {
        guard let privacy = controller?.privacy else { return }
        // Anything short of everything means "turn the rest on too"; only a
        // full house turns them all off. One press, and no state where the
        // item says All while half the sections are open.
        privacy.setCoveringAll(!privacy.coversAll)
        refreshPrivacyItems()
    }

    @objc private func togglePrivacySection(_ sender: NSMenuItem) {
        guard let privacy = controller?.privacy,
              let raw = sender.representedObject as? String,
              let section = PrivacyMode.Section(rawValue: raw) else { return }
        privacy.setCovering(section, !privacy.covers(section))
        refreshPrivacyItems()
    }

    /// The parent item carries the summary: a tick when every section is
    /// covered, a dash when some are. Without it the state is a submenu away,
    /// and this is the one switch worth reading at a glance.
    private func refreshPrivacyItems() {
        guard let privacy = controller?.privacy else { return }
        privacyItem?.state = privacy.coversAll ? .on : (privacy.coversAny ? .mixed : .off)
        privacyAllItem?.state = privacy.coversAll ? .on : .off
        for (section, item) in privacySectionItems {
            item.state = privacy.covers(section) ? .on : .off
        }
    }

    @objc private func toggleSaveClipboardImages(_ sender: NSMenuItem) {
        UserDefaults.standard.set(
            !NotchViewModel.saveClipboardImagesEnabled,
            forKey: NotchViewModel.saveClipboardImagesKey
        )
        sender.state = NotchViewModel.saveClipboardImagesEnabled ? .on : .off
    }

    /// Turning them off also drops whatever is already booked: the switch is
    /// read when a timer starts, so without this the banner for a run started
    /// before the switch was flipped would still arrive.
    @objc private func toggleTimerNotifications(_ sender: NSMenuItem) {
        let next = !TimerNotifier.isEnabled
        UserDefaults.standard.set(next, forKey: TimerNotifier.enabledKey)
        sender.state = next ? .on : .off
        if next {
            TimerNotifier.requestIfNeeded()
        } else {
            TimerNotifier.cancel()
            TimerNotifier.clearDelivered()
        }
    }

    @objc private func showOnboarding() {
        onboarding?.show()
    }

    /// The appearance window. Plain and non-floating, unlike the onboarding: it
    /// is a settings window, and settings windows behave like windows.
    @objc private func showAppearance() {
        if appearanceWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = localized("Appearance")
            w.contentView = NSHostingView(rootView: AppearancePane(appearance: Appearance.shared))
            w.center()
            w.isReleasedWhenClosed = false
            appearanceWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        appearanceWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func revealScreenshots() {
        ScreenshotVault.reveal()
    }

    @objc private func revealSnippets() {
        SnippetStore.reveal()
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Cyclop: launch-at-login failed: \(error.localizedDescription)")
        }
        sender.state = launchAtLoginEnabled ? .on : .off
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}

