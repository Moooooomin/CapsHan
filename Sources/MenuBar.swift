import Cocoa

/// Menu bar icon: the current input language in a rounded box (한 / 영 or 한 / A),
/// drawn as a template image so it follows the menu bar's light/dark tint.
enum MenuBarIcon {
    static func image(for source: InputSource?, style: MenuBarIconStyle) -> NSImage? {
        guard style != .keyboard, let source else {
            let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "CapsHan")
            symbol?.isTemplate = true
            return symbol
        }
        let text = source.menuBarText(style) as NSString
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { rect in
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5)
            box.lineWidth = 1.2
            NSColor.black.setStroke()
            box.stroke()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
                      withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = source.caption
        return image
    }
}

/// Quitting from CapsHan's own menu or settings window. If CapsHan hid the system input
/// menu, it is put back first so the menu bar isn't left without an input indicator.
func quitCapsHan() {
    if Settings.hideSystemInputMenu {
        SystemInputMenu.setVisible(true)
    }
    NSApp.terminate(nil)
}

/// The system's own input menu (the 한 / A icon macOS puts in the menu bar). It is the
/// "Show Input menu in menu bar" setting, which TextInputMenuAgent only reads at launch.
enum SystemInputMenu {
    private static let domain = "com.apple.TextInputMenu" as CFString
    private static let visibleKey = "visible" as CFString

    static var isVisible: Bool {
        (CFPreferencesCopyAppValue(visibleKey, domain) as? Bool) ?? true
    }

    static func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        CFPreferencesSetAppValue(visibleKey, visible as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
        // launchd restarts the agent right away, and it picks up the new setting.
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["TextInputMenuAgent"]
        try? killall.run()
    }
}
