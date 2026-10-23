import Foundation

enum HUDTheme: String, CaseIterable {
    case system, light, dark
}

enum HUDStyle: String, CaseIterable {
    case liquidGlass, classic
}

/// Liquid Glass variant: regular is frosted, clear shows (and bends) more of what's behind.
enum GlassStyle: String, CaseIterable {
    case regular, clear
}

/// What the CapsHan menu bar icon shows.
enum MenuBarIconStyle: String, CaseIterable {
    case hanYeong   // 한 / 영
    case hanA       // 한 / A
    case keyboard   // plain keyboard symbol
}

/// User settings. They live in UserDefaults so the SwiftUI settings window (@AppStorage)
/// and the rest of the app always see the same values.
enum Settings {
    enum Key {
        static let showHUD = "showHUD"
        static let hudDuration = "hudDuration"
        static let hudFade = "hudFade"
        static let hudFadeDuration = "hudFadeDuration"
        static let hudTheme = "hudTheme"
        static let hudStyle = "hudStyle"
        static let glassStyle = "glassStyle"
        static let liquidStrength = "liquidStrength"
        static let hudScale = "hudScale"
        static let capsLockSwitch = "capsLockSwitch"
        static let longPressCapsLock = "longPressCapsLock"
        static let longPressDuration = "longPressDuration"
        static let menuBarIcon = "menuBarIcon"
        static let hideSystemInputMenu = "hideSystemInputMenu"
        static let loginItemConfigured = "loginItemConfigured"
    }

    static let durationRange: ClosedRange<Double> = 0.3...3.0
    static let fadeDurationRange: ClosedRange<Double> = 0.1...1.0
    static let liquidStrengthRange: ClosedRange<Double> = 0...1
    static let hudScaleRange: ClosedRange<Double> = 0.8...1.6
    static let longPressRange: ClosedRange<Double> = 0.3...1.0

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.showHUD: true,
            Key.hudDuration: 0.8,
            Key.hudFade: true,
            Key.hudFadeDuration: 0.3,
            Key.hudTheme: HUDTheme.system.rawValue,
            Key.hudStyle: HUDStyle.liquidGlass.rawValue,
            Key.glassStyle: GlassStyle.clear.rawValue,
            Key.liquidStrength: 0.8,
            Key.hudScale: 1.0,
            Key.capsLockSwitch: true,
            Key.longPressCapsLock: true,
            Key.longPressDuration: 0.5,
            Key.menuBarIcon: MenuBarIconStyle.hanYeong.rawValue,
            Key.hideSystemInputMenu: false,
        ])
    }

    static var showHUD: Bool { defaults.bool(forKey: Key.showHUD) }
    static var capsLockSwitch: Bool { defaults.bool(forKey: Key.capsLockSwitch) }
    static var longPressCapsLock: Bool { defaults.bool(forKey: Key.longPressCapsLock) }

    static var longPressDuration: Double {
        defaults.double(forKey: Key.longPressDuration).clamped(to: longPressRange)
    }
    static var hideSystemInputMenu: Bool { defaults.bool(forKey: Key.hideSystemInputMenu) }

    static var menuBarIcon: MenuBarIconStyle {
        MenuBarIconStyle(rawValue: defaults.string(forKey: Key.menuBarIcon) ?? "") ?? .hanYeong
    }

    static var hudDuration: Double {
        defaults.double(forKey: Key.hudDuration).clamped(to: durationRange)
    }

    /// Fade-in and fade-out time, or 0 when fading is turned off.
    static var hudFadeDuration: Double {
        defaults.bool(forKey: Key.hudFade) ? defaults.double(forKey: Key.hudFadeDuration).clamped(to: fadeDurationRange) : 0
    }

    static var glassStyle: GlassStyle {
        GlassStyle(rawValue: defaults.string(forKey: Key.glassStyle) ?? "") ?? .clear
    }

    /// 0 = heavily frosted, 1 = pure glass.
    static var liquidStrength: Double {
        defaults.double(forKey: Key.liquidStrength).clamped(to: liquidStrengthRange)
    }

    static var hudScale: Double {
        defaults.double(forKey: Key.hudScale).clamped(to: hudScaleRange)
    }

    static var hudTheme: HUDTheme {
        HUDTheme(rawValue: defaults.string(forKey: Key.hudTheme) ?? "") ?? .system
    }

    /// The chosen style, falling back to classic where Liquid Glass doesn't exist.
    static var hudStyle: HUDStyle {
        let chosen = HUDStyle(rawValue: defaults.string(forKey: Key.hudStyle) ?? "") ?? .liquidGlass
        return isLiquidGlassAvailable ? chosen : .classic
    }

    static var isLiquidGlassAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
