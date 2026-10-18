import Cocoa
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hud = HUD()
    private lazy var settingsWindow = SettingsWindow { [weak self] in self?.previewHUD() }
    private var statusItem: NSStatusItem!
    private var lastSourceID: String?
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch Apple event is only available at this point.
        launchedAtLogin = LoginItem.launchedAtLogin()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()

        if Settings.capsLockSwitch {
            CapsLockSwitch.enable()
        }
        if Settings.hideSystemInputMenu {
            SystemInputMenu.setVisible(false)
        }

        lastSourceID = InputSource.current()?.id
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceDidChange),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
        // Picks up icon style changes from the settings window.
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshStatusIcon),
            name: UserDefaults.didChangeNotification, object: nil)

        setUpMenus()

        // Start at login once the app has been installed (not while running from the DMG).
        let defaults = UserDefaults.standard
        if isInApplicationsFolder && !defaults.bool(forKey: Settings.Key.loginItemConfigured) {
            defaults.set(true, forKey: Settings.Key.loginItemConfigured)
            LoginItem.setEnabled(true)
        }

        // Opened by the user (Apps, Launchpad, Finder) rather than at login: show settings.
        if !launchedAtLogin {
            settingsWindow.show()
        }
    }

    /// Clicking the app while it is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    // MARK: Input source changes

    @objc private func inputSourceDidChange() {
        // The notification can arrive in bursts, so read the source on the next run loop
        // turn and only react when it really changed.
        DispatchQueue.main.async { [weak self] in
            guard let self, let source = InputSource.current(), source.id != self.lastSourceID else { return }
            self.lastSourceID = source.id
            self.refreshStatusIcon()
            if Settings.showHUD {
                self.hud.show(glyph: source.glyph, caption: source.caption)
            }
        }
    }

    private func previewHUD() {
        guard let source = InputSource.current() else { return }
        hud.show(glyph: source.glyph, caption: source.caption)
    }

    // MARK: Menus

    private func setUpMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusIcon()

        // Hidden main menu so ⌘W closes the settings window. ⌘Q is left out on purpose:
        // quitting would also stop the popup.
        let fileMenu = NSMenu(title: "파일")
        fileMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem())
        mainMenu.addItem(fileItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func refreshStatusIcon() {
        statusItem?.button?.image = MenuBarIcon.image(for: InputSource.current(), style: Settings.menuBarIcon)
    }

    /// Rebuilt each time it opens: the input sources (so they can still be picked when the
    /// system input menu is hidden), then CapsHan's own items.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let currentID = InputSource.current()?.id
        for (source, _) in InputSource.selectable() {
            let item = menuItem(source.localizedName, #selector(selectInputSource(_:)))
            item.representedObject = source.id
            item.state = source.id == currentID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("설정…", #selector(openSettings), key: ","))
        menu.addItem(menuItem("팝업 미리보기", #selector(previewFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("CapsHan 종료", #selector(quit), key: "q"))
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func selectInputSource(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let match = InputSource.selectable().first(where: { $0.source.id == id }) else { return }
        TISSelectInputSource(match.ref)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func previewFromMenu() {
        previewHUD()
    }

    @objc private func quit() {
        quitCapsHan()
    }

    private var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
}

// Only one copy should run; a second launch just exits.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
