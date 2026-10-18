import CoreGraphics  // links the private CGS* symbols declared below
import Foundation
import IOKit.hidsystem

/// Turns Caps Lock into an instant 한/영 key:
/// 1. the Caps Lock key is remapped to F18 in the HID event system, which skips macOS's
///    built-in Caps Lock delay (and the Caps Lock toggle itself), and
/// 2. F18 becomes the "Select the previous input source" shortcut.
enum CapsLockSwitch {
    private static let capsLockUsage: UInt64 = 0x7_0000_0039
    private static let f18Usage: UInt64 = 0x7_0000_006D
    private static let mappingKey = "UserKeyMapping" as CFString
    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"

    static func enable() {
        setCapsLockRemap(true)
        SymbolicHotKey.selectPreviousInputSource.saveOriginalIfNeeded()
        SymbolicHotKey.selectPreviousInputSource.set(.f18)
    }

    static func disable() {
        setCapsLockRemap(false)
        SymbolicHotKey.selectPreviousInputSource.restoreOriginal()
    }

    /// Changes only the Caps Lock entry, keeping any other remaps the user already has.
    /// The mapping lasts until restart; the app re-applies it at every launch.
    private static func setCapsLockRemap(_ remap: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        var mappings = IOHIDEventSystemClientCopyProperty(client, mappingKey) as? [[String: Any]] ?? []
        mappings.removeAll { ($0[sourceKey] as? NSNumber)?.uint64Value == capsLockUsage }
        if remap {
            mappings.append([sourceKey: capsLockUsage, destinationKey: f18Usage])
        }
        IOHIDEventSystemClientSetProperty(client, mappingKey, mappings as CFArray)
    }
}

// Private SkyLight calls that System Settings uses to apply a shortcut change immediately.
@_silgen_name("CGSSetSymbolicHotKeyValue")
func CGSSetSymbolicHotKeyValue(_ hotKey: Int32, _ keyEquivalent: UInt16, _ keyCode: UInt16, _ modifiers: UInt64) -> Int32
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32

/// A system keyboard shortcut ("symbolic hot key") stored in com.apple.symbolichotkeys.
/// Writing the preference alone only takes effect at the next login, so every change is
/// also pushed to the running session.
struct SymbolicHotKey {
    struct Shortcut: Equatable {
        var keyEquivalent: Int
        var keyCode: Int
        var modifiers: Int
        var enabled = true

        static let f18 = Shortcut(keyEquivalent: 65535, keyCode: 79, modifiers: 0x80_0000)
        static let controlSpace = Shortcut(keyEquivalent: 32, keyCode: 49, modifiers: 0x4_0000)
    }

    static let selectPreviousInputSource = SymbolicHotKey(id: 60, defaultShortcut: .controlSpace)

    let id: Int32
    let defaultShortcut: Shortcut

    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let listKey = "AppleSymbolicHotKeys" as CFString
    private var savedOriginalKey: String { "originalShortcut.\(id)" }

    var current: Shortcut? {
        guard let all = CFPreferencesCopyAppValue(Self.listKey, Self.domain) as? [String: Any],
              let entry = all[String(id)] as? [String: Any],
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count == 3 else { return nil }
        // Values written with `defaults write` in the old plist syntax come back as strings.
        let numbers = parameters.compactMap { ($0 as? NSNumber)?.intValue ?? Int("\($0)") }
        guard numbers.count == 3 else { return nil }
        let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? ("\(entry["enabled"] ?? 1)" != "0")
        return Shortcut(keyEquivalent: numbers[0], keyCode: numbers[1], modifiers: numbers[2], enabled: enabled)
    }

    func set(_ shortcut: Shortcut) {
        var all = CFPreferencesCopyAppValue(Self.listKey, Self.domain) as? [String: Any] ?? [:]
        all[String(id)] = [
            "enabled": shortcut.enabled,
            "value": [
                "parameters": [shortcut.keyEquivalent, shortcut.keyCode, shortcut.modifiers],
                "type": "standard",
            ] as [String: Any],
        ] as [String: Any]
        CFPreferencesSetAppValue(Self.listKey, all as CFDictionary, Self.domain)
        CFPreferencesAppSynchronize(Self.domain)

        _ = CGSSetSymbolicHotKeyValue(id, UInt16(shortcut.keyEquivalent), UInt16(shortcut.keyCode), UInt64(shortcut.modifiers))
        _ = CGSSetSymbolicHotKeyEnabled(id, shortcut.enabled)
    }

    /// Remembers the user's own shortcut so turning the feature off can put it back.
    func saveOriginalIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.array(forKey: savedOriginalKey) == nil,
              let shortcut = current, shortcut != .f18 else { return }
        defaults.set([shortcut.keyEquivalent, shortcut.keyCode, shortcut.modifiers, shortcut.enabled ? 1 : 0],
                     forKey: savedOriginalKey)
    }

    func restoreOriginal() {
        let defaults = UserDefaults.standard
        var original = defaultShortcut
        if let saved = defaults.array(forKey: savedOriginalKey) as? [Int], saved.count == 4 {
            original = Shortcut(keyEquivalent: saved[0], keyCode: saved[1], modifiers: saved[2], enabled: saved[3] != 0)
        }
        // Leave it alone if the user has since picked a different shortcut themselves.
        if current == nil || current == .f18 {
            set(original)
        }
        defaults.removeObject(forKey: savedOriginalKey)
    }
}
