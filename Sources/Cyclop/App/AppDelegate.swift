import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()
        controller?.install()
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.teardown()
    }

    // MARK: - Menu bar item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "eye.fill",
            accessibilityDescription: "Cyclop"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Cyclop \(Bundle.main.shortVersion)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: "Открыть панель",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let login = NSMenuItem(
            title: "Запускать при входе",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        let saveShots = NSMenuItem(
            title: "Сохранять скриншоты из буфера",
            action: #selector(toggleSaveClipboardImages),
            keyEquivalent: ""
        )
        saveShots.target = self
        saveShots.state = saveClipboardImagesEnabled ? .on : .off
        menu.addItem(saveShots)

        let airdrop = NSMenuItem(
            title: "Ловить картинки из AirDrop",
            action: #selector(toggleCatchAirDrops),
            keyEquivalent: ""
        )
        airdrop.target = self
        airdrop.state = AirDropWatcher.isEnabled ? .on : .off
        menu.addItem(airdrop)

        let inbox = NSMenuItem(
            title: "Принимать снимки с телефона",
            action: #selector(togglePhoneInbox),
            keyEquivalent: ""
        )
        inbox.target = self
        inbox.state = DropInbox.isEnabled ? .on : .off
        menu.addItem(inbox)

        let inboxAddress = NSMenuItem(
            title: "Скопировать адрес для телефона",
            action: #selector(copyInboxAddress),
            keyEquivalent: ""
        )
        inboxAddress.target = self
        menu.addItem(inboxAddress)

        let openFolder = NSMenuItem(
            title: "Показать папку скриншотов",
            action: #selector(revealScreenshots),
            keyEquivalent: ""
        )
        openFolder.target = self
        menu.addItem(openFolder)

        let openSnippets = NSMenuItem(
            title: "Показать файл заготовок",
            action: #selector(revealSnippets),
            keyEquivalent: ""
        )
        openSnippets.target = self
        menu.addItem(openSnippets)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        controller?.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Defaults to on: the feature is the reason the folder exists.
    private var saveClipboardImagesEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: NotchViewModel.saveClipboardImagesKey) != nil else { return true }
        return defaults.bool(forKey: NotchViewModel.saveClipboardImagesKey)
    }

    @objc private func toggleSaveClipboardImages(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!saveClipboardImagesEnabled, forKey: NotchViewModel.saveClipboardImagesKey)
        sender.state = saveClipboardImagesEnabled ? .on : .off
    }

    @objc private func toggleCatchAirDrops(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!AirDropWatcher.isEnabled, forKey: AirDropWatcher.enabledKey)
        sender.state = AirDropWatcher.isEnabled ? .on : .off
        controller?.refreshServices()
    }

    @objc private func togglePhoneInbox(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!DropInbox.isEnabled, forKey: DropInbox.enabledKey)
        sender.state = DropInbox.isEnabled ? .on : .off
        controller?.refreshServices()
    }

    /// The address carries the secret, so it is handed over by copying rather
    /// than shown in a menu somebody could read over a shoulder.
    @objc private func copyInboxAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DropInbox.address, forType: .string)
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
