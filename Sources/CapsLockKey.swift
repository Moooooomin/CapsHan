import Carbon
import Cocoa
import IOKit.hidsystem

/// The real Caps Lock (uppercase lock). The physical key is remapped to F18, so CapsHan
/// turns the lock on and off itself through the HID system (this also drives the key's LED).
enum CapsLock {
    static var isOn: Bool {
        withConnection { connection in
            var state = false
            IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state)
            return state
        } ?? false
    }

    static func set(_ on: Bool) {
        _ = withConnection { IOHIDSetModifierLockState($0, Int32(kIOHIDCapsLockState), on) }
    }

    private static func withConnection<T>(_ body: (io_connect_t) -> T) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(connection) }
        return body(connection)
    }
}

/// Long-press handling for the Caps Lock key (remapped to F18).
///
/// macOS runs the "previous input source" shortcut when the key is *released*, and only
/// for a short press; a key held for a while switches nothing. CapsHan watches the key
/// itself (reading the key state needs no extra permission) and adds:
/// - held for the long-press time: Caps Lock toggles when the key is released (turning on
///   also selects English);
/// - a short press while Caps Lock is on: Caps Lock turns off and the 한/영 switch is undone;
/// - held too long for macOS but not long enough for Caps Lock: CapsHan switches 한/영 itself.
final class CapsLockKey {
    /// Called with the new Caps Lock state whenever a press changed it.
    var onCapsLockChange: ((Bool) -> Void)?

    private let f18KeyCode: CGKeyCode = 79
    private let pollInterval: TimeInterval = 0.03
    /// Presses at least this long may be ignored by macOS's shortcut.
    private let fallbackAfter: TimeInterval = 0.25

    private var pollTimer: Timer?
    private var pressStart: Date?
    private var pressHandled = false          // the current press is a Caps Lock press
    private var longPressPending = false      // held long enough; toggle on release
    private var undoSwitchUntil: Date?        // a 한/영 switch arriving before this is undone
    private var ownSwitchTarget: String?
    private var fallbackWork: DispatchWorkItem?

    /// Starts or stops watching the key to match the current settings.
    func updateWatching() {
        let wanted = Settings.capsLockSwitch && Settings.longPressCapsLock
        if wanted, pollTimer == nil {
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in self?.poll() }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !wanted {
            pollTimer?.invalidate()
            pollTimer = nil
            pressStart = nil
        }
    }

    /// Call when the input source changed. Returns true when CapsHan handled the change
    /// itself (Caps Lock press or its own switch), so the 한/영 popup should not be shown.
    func handleInputSourceChange(from previousID: String?, to id: String) -> Bool {
        fallbackWork?.cancel()
        fallbackWork = nil
        if ownSwitchTarget == id {
            ownSwitchTarget = nil
            return true
        }
        guard pollTimer != nil else { return false }

        // macOS switches a few milliseconds after the key goes up, possibly before this
        // class has noticed the release, so a press still marked as in progress counts too.
        let fromThisPress = pressStart != nil || (undoSwitchUntil.map { Date() < $0 } ?? false)
        guard fromThisPress else { return false }
        undoSwitchUntil = nil

        if pressHandled {
            // Long press already toggled Caps Lock; keep the language as it was.
            if let previousID { select(previousID) }
            return true
        }
        if CapsLock.isOn {
            pressHandled = true
            CapsLock.set(false)
            if let previousID { select(previousID) }
            onCapsLockChange?(false)
            return true
        }
        return false
    }

    // MARK: Watching the key

    private func poll() {
        let isDown = CGEventSource.keyState(.hidSystemState, key: f18KeyCode)
        if isDown {
            if pressStart == nil {
                pressStart = Date()
                pressHandled = false
            } else if !pressHandled, Date().timeIntervalSince(pressStart!) >= Settings.longPressDuration {
                // Toggled on release: changing the lock while the key is still down makes
                // macOS treat it as an input switch, which turns the lock straight back off.
                pressHandled = true
                longPressPending = true
            }
        } else if let start = pressStart {
            pressStart = nil
            keyReleased(after: Date().timeIntervalSince(start))
        }
    }

    private func toggleCapsLock() {
        let turnOn = !CapsLock.isOn
        // Switch to English first; the lock is set once that switch has settled.
        let switched = turnOn && selectEnglish()
        DispatchQueue.main.asyncAfter(deadline: .now() + (switched ? 0.12 : 0)) { [weak self] in
            CapsLock.set(turnOn)
            // Check it stuck (and set it once more if not) before telling the user.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if CapsLock.isOn != turnOn { CapsLock.set(turnOn) }
                self?.onCapsLockChange?(CapsLock.isOn)
            }
        }
    }

    private func keyReleased(after held: TimeInterval) {
        if pressHandled {
            // In case macOS still switches 한/영 for this press.
            undoSwitchUntil = Date().addingTimeInterval(0.4)
            if longPressPending {
                longPressPending = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.toggleCapsLock() }
            }
            return
        }
        if CapsLock.isOn {
            // Short press while Caps Lock is on: turn it off, and undo the switch macOS makes.
            pressHandled = true
            CapsLock.set(false)
            undoSwitchUntil = Date().addingTimeInterval(0.4)
            onCapsLockChange?(false)
            return
        }
        if held >= fallbackAfter {
            // macOS may have ignored this press; if it doesn't switch shortly, switch here.
            let work = DispatchWorkItem { [weak self] in self?.selectOther() }
            fallbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    // MARK: Selecting input sources

    /// Returns true when it had to switch.
    @discardableResult
    private func selectEnglish() -> Bool {
        guard InputSource.current()?.language != "en",
              let english = InputSource.selectable().first(where: { $0.source.language == "en" }) else { return false }
        select(english.source.id)
        return true
    }

    /// The source a short press would have switched to (the other one of the last two).
    private func selectOther() {
        guard let current = InputSource.current(),
              let other = InputSource.selectable().first(where: { $0.source.id != current.id }) else { return }
        ownSwitchTarget = nil  // let the popup show, as for a normal switch
        TISSelectInputSource(other.ref)
    }

    private func select(_ id: String) {
        guard InputSource.current()?.id != id,
              let match = InputSource.selectable().first(where: { $0.source.id == id }) else { return }
        ownSwitchTarget = id
        TISSelectInputSource(match.ref)
    }
}
