import Cocoa
import ServiceManagement

/// Starts the app at login (shows up under System Settings → General → Login Items).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("CapsHan: could not change login item: \(error)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// Whether this launch came from logging in (login item or reopened at login) rather
    /// than the user clicking the app. Call from applicationWillFinishLaunching.
    /// macOS has no single reliable flag for this, so two signals are combined.
    static func launchedAtLogin() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        // The Dock starts when the user logs in; a launch right after it is part of login.
        return secondsSinceDockStarted().map { $0 < 60 } ?? false
    }

    private static func secondsSinceDockStarted() -> TimeInterval? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, dock.processIdentifier]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        return Date().timeIntervalSince(started)
    }
}
