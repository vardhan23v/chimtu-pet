import AppKit
import IOKit.ps
import IOKit.hid

/// Drives Chimtu's behaviour with a single low-rate timer.
///
/// Energy design:
///  - one NSTimer whose interval is the current animation's frame period, with
///    a large tolerance so the kernel can coalesce it with other wakeups;
///  - the timer is invalidated (not just paused) while hidden, while the
///    screen is asleep, or while the display is locked;
///  - Low Power Mode halves the frame rate; the sleep state runs at 1 fps;
///  - no display link, no per-frame drawing: frames are pre-decoded CGImages
///    swapped in as layer contents.
final class PetController {
    private let animations: [String: Animation]
    private let window: PetWindow
    private var view: PetView { window.contentView as! PetView }

    private var current: Animation
    private var frame = 0
    private var timer: Timer?
    private var stateEndsAt = Date()
    private var walkDirection: CGFloat = 1
    private(set) var isVisible = true
    private var isSuspended = false

    init(animations: [String: Animation]) {
        self.animations = animations
        self.current = animations["idle"]!
        window = PetWindow(size: Sprites.windowSize)
        placeAtBottom()
        view.onClick = { [weak self] in
            guard let self else { return }
            self.clickCount += 1
            self.enter(self.clickCount % 2 == 0 ? "happy" : "wave", for: 1.2)
        }
        view.onDoubleClick = { [weak self] in self?.jump() }
        view.onLongPress = { [weak self] in self?.enter("love", for: 2.0); self?.say(["❤️", "Good boy vibes", "Chimtuuu"].randomElement()!) }
        view.onFileDrop = { [weak self] urls in self?.fetch(urls) }
        apply(scale: UserDefaults.standard.double(forKey: "petScale").nonZeroOr(1))
        clipboardCount = NSPasteboard.general.changeCount
        scheduleHourlyHowl()
        window.onDragStart = { [weak self] in
            guard let self, !self.programmaticMove else { return }
            self.stopMover(); self.enter("held", for: 0)
        }
        window.onDragEnd = { [weak self] in
            guard let self, self.current.name == "held" else { return }
            self.enter("land", for: 0.45)
        }
        observeSystem()
        window.orderFrontRegardless()
        enter("idle", for: 6)
    }

    // MARK: state machine

    private var wasAsleep = false
    private var clickCount = 0
    private var programmaticMove = false
    private var lastMouse = NSEvent.mouseLocation
    private var lastMouseMove = Date()

    func dance() { enter("dance", for: 2.5) }
    func bark() { enter("bark", for: 1.0); say(["Bow!", "Bow bow!", "Chimtu!"].randomElement()!) }
    func beg() { enter("beg", for: 2.5); say(["Treat?", "Pleeease", "Em chestunnav?"].randomElement()!) }
    func say(_ text: String) { view.say(text) }

    // MARK: size
    private(set) var scale: CGFloat = 1
    func apply(scale newScale: CGFloat) {
        scale = newScale
        UserDefaults.standard.set(Double(newScale), forKey: "petScale")
        var f = window.frame
        let newSize = CGSize(width: Sprites.windowSize.width * newScale, height: Sprites.windowSize.height * newScale)
        f.origin.x += (f.width - newSize.width) / 2   // keep the pet centred on its old spot
        f.size = newSize
        window.setFrame(f, display: true)
        view.apply(scale: newScale)
    }

    // MARK: clipboard sniffing
    private var clipboardCount = 0
    private func checkClipboard() {
        let c = NSPasteboard.general.changeCount
        guard c != clipboardCount else { return }
        clipboardCount = c
        guard current.name != "sleep", !(gestureActive) else { return }
        enter("sniff", for: 1.2); say("sniff sniff")
    }
    private var gestureActive: Bool { ["jump","wave","happy","eat","love","howl","roll","held","fetch","bark","beg","sniff"].contains(current.name) && Date() < stateEndsAt }

    // MARK: fetch dropped files
    private func fetch(_ urls: [URL]) {
        guard let url = urls.first else { return }
        enter("fetch", for: 2.0)
        say("Fetched \(url.lastPathComponent)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { NSWorkspace.shared.open(url) }
    }

    private var isNight: Bool { let h = Calendar.current.component(.hour, from: Date()); return h >= 23 || h < 6 }
    private static let idleLines = ["Chimtu!", "Bow bow!", "Em chestunnav?", "Pet me?", "Zzz... no wait", "Treat unda?", "Hi hooman"]
    func giveTreat() { enter("eat", for: 2.5) }
    func howl() { enter("howl", for: 2.0) }
    func rollOver() { enter("roll", for: 1.2) }

    /// One timer wake per hour, on the hour, with a minute of tolerance.
    private var hourlyTimer: Timer?
    private func scheduleHourlyHowl() {
        hourlyTimer?.invalidate()
        let cal = Calendar.current
        guard let next = cal.nextDate(after: Date(), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.isVisible, !self.isSuspended, self.current.name != "sleep" {
                self.howl()
                let f = DateFormatter(); f.dateFormat = "h a"; self.say("Awooo, it's \(f.string(from: Date()))")
            }
            self.scheduleHourlyHowl()
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        hourlyTimer = t
    }
    func spin() { enter("spin", for: 0.9) }
    func shake() { enter("shake", for: 0.6) }

    /// True when running on battery below 20%.
    private var batteryIsLow: Bool {
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

    /// Seconds since the user last moved the mouse (sampled on the tick).
    private func noteMouseActivity() {
        let m = NSEvent.mouseLocation
        if m != lastMouse { lastMouse = m; lastMouseMove = Date() }
    }
    private var userIdleSeconds: TimeInterval { Date().timeIntervalSince(lastMouseMove) }

    // MARK: reactions to what the user does
    private var lastReaction = Date.distantPast
    private var lookTarget: CGPoint?          // screen point the eyes glance at (set by global clicks)
    private var lookUntil = Date.distantPast
    private var clickTimes: [Date] = []
    private var downloadsSource: DispatchSourceFileSystemObject?
    private var downloadsSeen: Set<String> = []
    private var appearanceObservation: NSKeyValueObservation?
    private var globalClickMonitor: Any?
    private var lastCharging: Bool?

    // MARK: typing reactions (keystrokes are counted, never read)
    private var keyMonitor: Any?
    private var keyTimes: [Date] = []
    private var deleteTimes: [Date] = []
    private var typingSessionStart: Date?
    private var typingStopTimer: Timer?
    private var speedCelebrated = false
    private(set) var typingEnabled = UserDefaults.standard.object(forKey: "typingReactions") as? Bool ?? true

    /// Whether macOS has granted Input Monitoring to this app.
    var hasInputMonitoring: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    func setTypingReactions(_ on: Bool) {
        typingEnabled = on
        UserDefaults.standard.set(on, forKey: "typingReactions")
        if on { startKeyMonitor() } else { stopKeyMonitor() }
    }

    private func startKeyMonitor() {
        guard keyMonitor == nil, typingEnabled else { return }
        if !hasInputMonitoring {
            // Shows the system permission prompt once; the monitor stays silent until granted.
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.reactToKey(e) }
    }
    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil; keyTimes.removeAll(); typingSessionStart = nil; typingStopTimer?.invalidate()
    }

    private func reactToKey(_ e: NSEvent) {
        guard isVisible, !isSuspended else { return }
        let now = Date()
        keyTimes = keyTimes.filter { now.timeIntervalSince($0) < 3 } + [now]
        if typingSessionStart == nil { typingSessionStart = now; speedCelebrated = false }
        typingStopTimer?.invalidate()
        typingStopTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in self?.typingStopped() }

        switch e.keyCode {
        case 36, 76:   // Return / Enter
            if current.name == "typing" || current.name.hasPrefix("idle") { react("jump", for: 0.6, say: "Sent!") }
            return
        case 51, 117:  // Delete / Forward delete
            deleteTimes = deleteTimes.filter { now.timeIntervalSince($0) < 2 } + [now]
            if deleteTimes.count >= 6 { deleteTimes.removeAll(); react("sad", for: 1.5, say: "Oops?") }
            return
        default: break
        }
        // Steady typing (>= 8 keys in the last 3 s): tap along.
        if keyTimes.count >= 8, current.name != "typing", !gestureActive, current.name != "held" {
            enter("typing", for: 4); say("tak tak tak")
        } else if current.name == "typing" {
            stateEndsAt = now.addingTimeInterval(3)   // keep tapping while keys keep coming
        }
        // Fast streak: 60 keys in 20 s, once per session.
        if !speedCelebrated, let start = typingSessionStart, now.timeIntervalSince(start) >= 20 || keyTimes.count >= 12 {
            if keyTimes.count >= 12 { speedCelebrated = true; react("happy", for: 1.5, say: "Speed typer!", force: true) }
        }
    }

    private func typingStopped() {
        defer { typingSessionStart = nil }
        if current.name == "typing" { stateEndsAt = Date() }   // let the state machine move on
        if let start = typingSessionStart, Date().timeIntervalSince(start) > 600 {
            react("yawn", for: 1.5, say: "Break?", force: true)
        }
    }

    /// Play a reaction unless one just played or he is mid-gesture. Returns whether it ran.
    @discardableResult
    private func react(_ state: String, for seconds: TimeInterval, say line: String? = nil, force: Bool = false) -> Bool {
        guard isVisible, !isSuspended else { return false }
        if !force {
            if Date().timeIntervalSince(lastReaction) < 1.5 { return false }
            if gestureActive || current.name == "held" { return false }
        } else if current.name == "held" { return false }
        lastReaction = Date()
        enter(state, for: seconds)
        if let line { say(line) }
        return true
    }

    private func appName(_ note: Notification) -> String? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app.localizedName ?? "that"
    }

    private func reactToAppSwitch(_ note: Notification) {
        guard let name = appName(note) else { return }
        react("alert", for: 1.1, say: Bool.random() ? "\(name)?" : nil)
    }
    private func reactToAppLaunch(_ note: Notification) {
        guard let name = appName(note) else { return }
        react("happy", for: 1.5, say: "Ooh, \(name)!", force: true)
    }
    private func reactToAppQuit(_ note: Notification) {
        guard let name = appName(note) else { return }
        react("wave", for: 1.2, say: "Bye \(name)", force: true)
    }
    private func reactToSpaceChange() { react("jump", for: 0.6, say: "Whee!") }
    private func reactToMount(_ note: Notification) {
        let name = (note.userInfo?["NSWorkspaceVolumeLocalizedNameKey"] as? String) ?? "drive"
        react("sniff", for: 1.4, say: "New drive: \(name)", force: true)
    }
    private func reactToUnmount(_ note: Notification) {
        let name = (note.userInfo?["NSWorkspaceVolumeLocalizedNameKey"] as? String) ?? "drive"
        react("wave", for: 1.2, say: "Bye \(name)", force: true)
    }
    private func reactToGlobalClick(_ event: NSEvent) {
        // Glance toward the click; a burst of clicks gets a bark.
        lookTarget = NSEvent.mouseLocation; lookUntil = Date().addingTimeInterval(1.5)
        let now = Date()
        clickTimes = clickTimes.filter { now.timeIntervalSince($0) < 2 } + [now]
        if clickTimes.count >= 6 { clickTimes.removeAll(); react("bark", for: 1.0, say: "Busy busy!") }
    }
    fileprivate func reactToPowerChange() {
        let charging = isCharging
        defer { lastCharging = charging }
        guard let was = lastCharging, was != charging else { return }
        if charging { react("happy", for: 1.5, say: "Charging!", force: true) }
        else { react("alert", for: 1.1, say: "Unplugged", force: true) }
    }
    private var isCharging: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for src in list {
            if let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
               let state = d[kIOPSPowerSourceStateKey] as? String { return state == kIOPSACPowerValue }
        }
        return false
    }
    private func reactToAppearanceChange() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark { react("yawn", for: 1.5, say: "Night night", force: true) }
        else { react("alert", for: 1.1, say: "Bright!", force: true) }
    }

    /// Event-driven watch on ~/Downloads: a new file gets fetched.
    private func watchDownloads() {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        downloadsSeen = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            let added = now.subtracting(self.downloadsSeen).filter { !$0.hasPrefix(".") && !$0.hasSuffix(".download") && !$0.hasSuffix(".crdownload") && !$0.hasSuffix(".part") }
            self.downloadsSeen = now
            if let name = added.sorted().first { self.react("fetch", for: 2.0, say: "New download: \(name)", force: true) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        downloadsSource = src
    }

    /// Follow-cursor mode: Chimtu trots toward the mouse and idles beside it.
    private(set) var followsCursor = false
    func setFollowCursor(_ on: Bool) {
        followsCursor = on
        if on { enter("idle", for: 0) } else { stopMover(); chooseNextState() }
    }

    /// Public commands (menu + gestures).
    func jump() { enter("jump", for: 0.6) }
    func sitDown() { enter("sit", for: .random(in: 10...20)) }
    func goToSleep() { enter("sleep", for: .random(in: 30...90)) }

    private var moveTimer: Timer?
    private var velocity = CGPoint.zero

    /// Called from the sprite tick: decides the pose; movement itself runs on
    /// the smooth mover below so it isn't quantised to the sprite frame rate.
    private func followTick() {
        let mouse = NSEvent.mouseLocation
        let f = window.frame
        let dx = mouse.x - f.midX, dy = mouse.y - f.midY
        let dist = hypot(dx, dy)
        let arrived = abs(dx) < 50 && abs(dy) < 60
        if arrived {
            stopMover()
            if !current.name.hasPrefix("idle") { enter("idle", for: 0) }
            return
        }
        startMover()
        let dir: CGFloat = dx > 0 ? 1 : -1
        let gait = dist > 260 ? "run" : "walk"
        let want = "\(gait)_\(dir > 0 ? "right" : "left")"
        if current.name != want { walkDirection = dir; enter(want, for: 0) }
    }

    /// 60 Hz mover, alive only while chasing. Uses a critically-damped spring
    /// toward the cursor so motion accelerates, glides, and settles smoothly.
    private func startMover() {
        guard moveTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.moveStep() }
        t.tolerance = 1.0 / 240.0
        RunLoop.main.add(t, forMode: .common)
        moveTimer = t
    }
    private func stopMover() { moveTimer?.invalidate(); moveTimer = nil; velocity = .zero }

    private func moveStep() {
        let mouse = NSEvent.mouseLocation
        var f = window.frame
        let dx = mouse.x - f.midX, dy = mouse.y - f.midY
        let dt: CGFloat = 1.0 / 60.0
        let stiffness: CGFloat = 30, damping: CGFloat = 2 * sqrt(stiffness)   // critically damped
        velocity.x += (stiffness * dx - damping * velocity.x) * dt
        velocity.y += (stiffness * dy - damping * velocity.y) * dt
        let maxSpeed: CGFloat = 900
        let sp = hypot(velocity.x, velocity.y)
        if sp > maxSpeed { velocity.x *= maxSpeed / sp; velocity.y *= maxSpeed / sp }
        f.origin.x += velocity.x * dt
        f.origin.y += velocity.y * dt
        if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
            f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
            f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
        }
        programmaticMove = true; window.setFrameOrigin(f.origin); programmaticMove = false
    }

    private func enter(_ name: String, for seconds: TimeInterval) {
        guard let anim = animations[name] else { return }
        wasAsleep = current.name == "sleep"
        current = anim
        frame = 0
        stateEndsAt = seconds > 0 ? Date().addingTimeInterval(seconds) : .distantFuture
        restartTimer()
        tick()
    }

    private func chooseNextState() {
        // Waking up always starts with a yawn and stretch.
        if current.name == "sleep" { enter("yawn", for: 1.5); return }
        if current.name == "sad" { enter("sleep", for: .random(in: 60...180)); return }
        // Nobody around for 5 minutes: get lonely, then nap.
        if userIdleSeconds > 300, current.name != "sleep" { enter("sad", for: 3); return }
        // Mostly rests. Walking is the only state that moves the window.
        let roll = Double.random(in: 0..<1)
        switch roll {
        case ..<0.40: enter(batteryIsLow ? "tired" : "idle", for: .random(in: 5...12))
        case ..<0.62: enter("sit", for: .random(in: 6...15))
        case ..<0.74: enter("sleep", for: isNight ? .random(in: 90...240) : .random(in: 15...40))
        case ..<0.80: enter("scratch", for: 1.5)
        case ..<0.83: enter("jump", for: 0.6)
        case ..<0.85: enter("dance", for: 2.5)
        case ..<0.87: enter(Bool.random() ? "spin" : "shake", for: 0.9)
        case ..<0.89: enter(["sneeze", "dig", "roll"].randomElement()!, for: 1.2)
        case ..<0.91: if isNight { enter("sleep", for: 120) } else { Bool.random() ? bark() : beg() }
        case ..<0.93: enter("idle", for: 4); say(Self.idleLines.randomElement()!)
        default:
            walkDirection = Bool.random() ? 1 : -1
            if let screen = window.screen ?? NSScreen.main {
                let x = window.frame.minX
                if x < screen.visibleFrame.minX + 40 { walkDirection = 1 }
                if x > screen.visibleFrame.maxX - Sprites.size.width - 40 { walkDirection = -1 }
            }
            enter(walkDirection > 0 ? "walk_right" : "walk_left", for: .random(in: 2...5))
        }
    }

    // MARK: timer

    private func restartTimer() {
        timer?.invalidate()
        guard isVisible, !isSuspended else { stopMover(); return }
        var fps = current.fps
        if ProcessInfo.processInfo.isLowPowerModeEnabled { fps = max(1, fps / 2) }
        let interval = 1.0 / fps
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.5   // lets the system batch wakeups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// While idling, pick the idle variant whose eyes point toward the cursor.
    /// Uses the cached mouse location on the existing tick: no extra wakeups.
    private func idleVariantForCursor() -> Animation? {
        var point = NSEvent.mouseLocation
        if let t = lookTarget, Date() < lookUntil { point = t }
        let dx = point.x - window.frame.midX
        let name = dx < -60 ? "idle_left" : (dx > 60 ? "idle_right" : "idle")
        return animations[name]
    }

    private func tick() {
        noteMouseActivity()
        checkClipboard()
        if current.name.hasPrefix("idle"), let variant = idleVariantForCursor(), variant.name != current.name {
            current = variant   // same frame count and rate, so keep the frame index
        }
        view.show(current.frames[frame])
        frame = (frame + 1) % current.frames.count
        if followsCursor {
            let gesture = ["wave", "jump", "scratch", "yawn", "alert", "happy", "held", "land", "dance", "spin", "shake", "eat", "love", "howl", "sneeze", "dig", "roll", "sniff", "fetch", "bark", "beg", "typing"].contains(current.name)
            if gesture && Date() < stateEndsAt { return }
            followTick()
            return
        }
        if current.name.hasPrefix("walk") {
            var f = window.frame
            f.origin.x += walkDirection * 2.5
            programmaticMove = true; window.setFrameOrigin(f.origin); programmaticMove = false
        }
        if Date() >= stateEndsAt { chooseNextState() }
    }

    // MARK: visibility & power

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { window.orderFrontRegardless() } else { window.orderOut(nil) }
        restartTimer()
    }

    private func suspend(_ suspended: Bool) {
        isSuspended = suspended
        restartTimer()
    }

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend(true) }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend(false) }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend(true) }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend(false) }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in self?.reactToAppSwitch(n) }
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in self?.reactToAppLaunch(n) }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in self?.reactToAppQuit(n) }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.reactToSpaceChange() }
        ws.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] n in self?.reactToMount(n) }
        ws.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] n in self?.reactToUnmount(n) }
        // Global mouse clicks need no special permission (keyboard would, so we don't watch typing).
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in self?.reactToGlobalClick(e) }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in self?.reactToAppearanceChange() }
        lastCharging = isCharging
        watchDownloads()
        startKeyMonitor()
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.suspend(true) }
        dc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.suspend(false); self?.enter("happy", for: 1.5); self?.say("Welcome back!")
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.restartTimer() }
        // Charger plug/unplug: IOKit power-source notifications, event-driven.
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PetController>.fromOpaque(ctx).takeUnretainedValue().reactToPowerChange()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func placeAtBottom() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: vf.midX - Sprites.size.width / 2, y: vf.minY))
    }
}


private extension Double {
    func nonZeroOr(_ fallback: Double) -> CGFloat { self == 0 ? CGFloat(fallback) : CGFloat(self) }
}
