import AppKit
import IOKit.ps
import IOKit.hid

/// Something the system told us about. Emitted by `SystemObservers`, handled by every pet.
enum SystemEvent {
    case suspend(Bool)                 // display/system asleep or screen locked
    case unlocked
    case appActivated(String)
    case appLaunched(String)
    case appQuit(String)
    case spaceChanged
    case mounted(String)
    case unmounted(String)
    case download(String)
    case globalClick(CGPoint)
    case power(charging: Bool)
    case appearance(dark: Bool)
    case music(playing: Bool, title: String)
    case key(code: UInt16)
    case lowPowerModeChanged
}

/// All system observation in one place, shared by every pet on screen. Every
/// source is event-driven: notifications, a click monitor, a file-system
/// dispatch source, IOKit callbacks. Nothing polls.
final class SystemObservers {
    var handler: (SystemEvent) -> Void = { _ in }
    private let prefs = Preferences.shared
    private var tokens: [NSObjectProtocol] = []
    private var globalClickMonitor: Any?
    private var keyMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?
    private var downloadsSource: DispatchSourceFileSystemObject?
    private var downloadsSeen: Set<String> = []
    private var lastCharging: Bool?
    private var powerSource: CFRunLoopSource?

    // MARK: power helpers (read on demand, never polled)

    /// True when running on battery below 20%.
    static var batteryIsLow: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let cap = (d[kIOPSCurrentCapacityKey] as? Int) ?? 100
            let max = (d[kIOPSMaxCapacityKey] as? Int) ?? 100
            if !charging, max > 0, cap * 100 / max < 20 { return true }
        }
        return false
    }

    static var isCharging: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for src in list {
            if let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
               let state = d[kIOPSPowerSourceStateKey] as? String { return state == kIOPSACPowerValue }
        }
        return false
    }

    var hasInputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    // MARK: lifecycle

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ center: NotificationCenter = NSWorkspace.shared.notificationCenter, _ block: @escaping (Notification) -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main, using: block))
        }
        on(NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.handler(.suspend(true)) }
        on(NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.handler(.suspend(false)) }
        on(NSWorkspace.willSleepNotification) { [weak self] _ in self?.handler(.suspend(true)) }
        on(NSWorkspace.didWakeNotification) { [weak self] _ in self?.handler(.suspend(false)) }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] n in if let a = Self.appName(n) { self?.emitIf(.appEvents, .appActivated(a)) } }
        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] n in if let a = Self.appName(n) { self?.emitIf(.appEvents, .appLaunched(a)) } }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] n in if let a = Self.appName(n) { self?.emitIf(.appEvents, .appQuit(a)) } }
        on(NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.emitIf(.appEvents, .spaceChanged) }
        on(NSWorkspace.didMountNotification) { [weak self] n in self?.emitIf(.filesAndDrives, .mounted(Self.volumeName(n))) }
        on(NSWorkspace.didUnmountNotification) { [weak self] n in self?.emitIf(.filesAndDrives, .unmounted(Self.volumeName(n))) }
        _ = ws

        let dc = DistributedNotificationCenter.default()
        on(Notification.Name("com.apple.Music.playerInfo"), dc) { [weak self] n in self?.music(n) }
        on(Notification.Name("com.spotify.client.PlaybackStateChanged"), dc) { [weak self] n in self?.music(n) }
        on(Notification.Name("com.apple.screenIsLocked"), dc) { [weak self] _ in self?.handler(.suspend(true)) }
        on(Notification.Name("com.apple.screenIsUnlocked"), dc) { [weak self] _ in self?.handler(.suspend(false)); self?.handler(.unlocked) }
        on(.NSProcessInfoPowerStateDidChange, NotificationCenter.default) { [weak self] _ in self?.handler(.lowPowerModeChanged) }

        // Global mouse clicks need no permission; they only tell us where a click happened.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.emitIf(.globalClicks, .globalClick(NSEvent.mouseLocation))
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            self?.handler(.appearance(dark: dark))
        }

        lastCharging = Self.isCharging
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<SystemObservers>.fromOpaque(ctx).takeUnretainedValue().powerChanged()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }

        watchDownloads()
        setTypingEnabled(prefs.typingReactions)
    }

    private func emitIf(_ c: Preferences.Category, _ e: SystemEvent) { if prefs.isEnabled(c) { handler(e) } }

    private static func appName(_ note: Notification) -> String? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app.localizedName ?? "that"
    }
    private static func volumeName(_ note: Notification) -> String {
        (note.userInfo?["NSWorkspaceVolumeLocalizedNameKey"] as? String) ?? "drive"
    }

    private func music(_ note: Notification) {
        guard prefs.isEnabled(.music) else { return }
        let playing = ((note.userInfo?["Player State"] as? String) ?? "") == "Playing"
        handler(.music(playing: playing, title: (note.userInfo?["Name"] as? String) ?? ""))
    }

    private func powerChanged() {
        let charging = Self.isCharging
        defer { lastCharging = charging }
        if let was = lastCharging, was != charging { handler(.power(charging: charging)) }
    }

    /// Event-driven watch on ~/Downloads.
    private func watchDownloads() {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        downloadsSeen = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            let added = now.subtracting(self.downloadsSeen).filter {
                !$0.hasPrefix(".") && !$0.hasSuffix(".download") && !$0.hasSuffix(".crdownload") && !$0.hasSuffix(".part")
            }
            self.downloadsSeen = now
            if let name = added.sorted().first { self.emitIf(.filesAndDrives, .download(name)) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        downloadsSource = src
    }

    // MARK: typing (keystrokes are counted, never read)

    func setTypingEnabled(_ on: Bool) {
        if on {
            guard keyMonitor == nil else { return }
            if !hasInputMonitoring { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }   // one-time system prompt
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handler(.key(code: e.keyCode)) }
        } else if let m = keyMonitor {
            NSEvent.removeMonitor(m); keyMonitor = nil
        }
    }
}
