import Carbon

/// The keyboard input source that is currently selected (e.g. ABC, 2-Set Korean).
struct InputSource: Equatable {
    let id: String
    let localizedName: String
    let language: String

    static func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        let languages = property(source, kTISPropertyInputSourceLanguages) as? [String] ?? []
        return InputSource(
            id: property(source, kTISPropertyInputSourceID) as? String ?? "",
            localizedName: property(source, kTISPropertyLocalizedName) as? String ?? "",
            language: languages.first ?? ""
        )
    }

    /// Big character shown in the popup.
    var glyph: String {
        switch language {
        case "ko": return "가"
        case "en": return "A"
        case "ja": return "あ"
        case let lang where lang.hasPrefix("zh"): return "中"
        default: return String(localizedName.prefix(1)).uppercased()
        }
    }

    /// Small caption under the glyph.
    var caption: String {
        switch language {
        case "ko": return "한글"
        case "en": return "영어"
        default: return localizedName
        }
    }

    /// One character for the menu bar icon.
    func menuBarText(_ style: MenuBarIconStyle) -> String {
        switch language {
        case "ko": return "한"
        case "en": return style == .hanYeong ? "영" : "A"
        default: return glyph
        }
    }

    /// Keyboard input sources the user can switch to (the ones in the system input menu).
    static func selectable() -> [(source: InputSource, ref: TISInputSource)] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.map { ref in
            let languages = property(ref, kTISPropertyInputSourceLanguages) as? [String] ?? []
            let source = InputSource(id: property(ref, kTISPropertyInputSourceID) as? String ?? "",
                                     localizedName: property(ref, kTISPropertyLocalizedName) as? String ?? "",
                                     language: languages.first ?? "")
            return (source, ref)
        }
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}
