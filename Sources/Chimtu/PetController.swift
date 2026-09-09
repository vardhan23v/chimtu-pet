import AppKit
import ChimtuCore

/// One pet on screen. Owns the window, the frame timer, and the live state;
/// asks `Brain` what to do next and `ReactionGate` whether a reaction may play.
///
/// Energy design:
///  - one Timer whose interval is the current animation's frame period, with a
///    large tolerance so the kernel can coalesce it with other wakeups;
///  - the timer is invalidated (not paused) while hidden, while the display is
///    asleep, or while the screen is locked;
///  - Low Power Mode halves the frame rate; sleep runs at 1 fps;
///  - no display link, no per-frame drawing: pre-decoded CGImages are swapped
///    in as layer contents;
///  - a 60 Hz mover exists only while Follow Cursor is actually moving him.
final class PetController {
    private var animations: [String: Animation]
    private let window: PetWindow
    private let view: PetView
    private let prefs = Preferences.shared
    private(set) var phrases: Phrases
    private var rng = SystemRandomNumberGenerator()

    private var current: Animation
    private var frame = 0
    private var timer: Timer?
    private var stateEndsAt = Date()
    private var stateStartedAt = Date()
    private var walkDirection: CGFloat = 1
    private(set) var isVisible = true
    private var isSuspended = false
    private var programmaticMove = false

    // Persistence (primary pet only). Friends are ephemeral.
    private let store: StateStore?
    private(set) var state: PetState
    private var dirty = false
    private var saveTimer: Timer?
    private let launchedAt = Date()

    // Gates and burst counters (pure values from ChimtuCore).
    private var gate = ReactionGate()
    private var tickle = BurstCounter(Behaviour.Bursts.tickle)
    private var shy = BurstCounter(Behaviour.Bursts.shy)
    private var pouts = BurstCounter(Behaviour.Bursts.pout)
    private var busyClicks = BurstCounter(Behaviour.Bursts.busyClicks)
    private var deletes = BurstCounter(Behaviour.Bursts.deletes)
    private var keys = BurstCounter(threshold: Int.max, window: Behaviour.Bursts.typing.window)

    private var clickCount = 0
    private var lastMouse = NSEvent.mouseLocation
    private var lastMouseMove = Date()
    private var lookTarget: CGPoint?
    private var lookUntil = Date.distantPast
    private var zoomiesUntil = Date.distantPast
    private var clipboardCount = NSPasteboard.general.changeCount
    private var musicPlaying = false
    var sounds: SoundPlayer?

    init?(animations: [String: Animation], isPrimary: Bool, phrases: Phrases) {
        guard let idle = animations["idle"] else { return nil }
        self.animations = animations
        self.current = idle
        self.phrases = phrases
        window = PetWindow(size: Sprites.windowSize)
        guard let v = window.contentView as? PetView else { return nil }
        view = v
        store = isPrimary ? StateStore(url: StateStore.defaultURL()) : nil
        state = store?.load() ?? PetState()

        placeAtBottom(primary: isPrimary)
        wireGestures()
        apply(scale: CGFloat(prefs.scale))
        if prefs.hat != "none" { view.setHat(Sprites.hat(prefs.hat, skin: prefs.skin)) }
        scheduleHourlyHowl()
        NotificationCenter.default.addObserver(forName: .chimtuPreferencesChanged, object: nil, queue: .main) { [weak self] _ in self?.preferencesChanged() }
        window.orderFrontRegardless()
        enter("idle", for: 6)
        if isPrimary { greetOnLaunch() }
    }

    // MARK: launch greeting + memory

    private func greetOnLaunch() {
        let (key, away) = state.registerLaunch()
        markDirty()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if key == "missedYou" {
                let days = Int(away / 24)
                self.enter("happy", for: 1.5)
                self.say(days >= 1 ? "\(self.phrases.pick("missedYou")) (\(days)d)" : self.phrases.pick("missedYou"))
            } else {
                self.say(self.phrases.pick(key ?? Phrases.greetingKey(hour: Calendar.current.component(.hour, from: Date()))))
            }
        }
    }

    private func markDirty() {
        guard store != nil else { return }
        if !dirty { ProcessInfo.processInfo.disableSuddenTermination() }
        dirty = true
        if saveTimer == nil {
            let t = Timer(timeInterval: 300, repeats: false) { [weak self] _ in self?.saveTimer = nil; self?.saveState() }
            t.tolerance = 60
            RunLoop.main.add(t, forMode: .common)
            saveTimer = t
        }
    }

    /// Persist now (called on quit, hide, suspend, and by the dirty timer).
    func saveState() {
        guard let store, dirty else { return }
        state.mood.integrate(to: Date(), asleep: current.name == "sleep")
        state.totals.minutes += Date().timeIntervalSince(lastSaveMark) / 60
        lastSaveMark = Date()
        state.lastSeen = Date()
        try? store.save(state)
        dirty = false
        ProcessInfo.processInfo.enableSuddenTermination()
    }
    private lazy var lastSaveMark = launchedAt

    private func mood(_ e: Mood.Event) {
        state.mood.integrate(to: Date(), asleep: current.name == "sleep")
        state.mood.apply(e)
        markDirty()
    }

    // MARK: gestures on the pet

    private func wireGestures() {
        view.onClick = { [weak self] in
            guard let self else { return }
            self.clickCount += 1; self.state.totals.clicks += 1; self.mood(.clicked)
            let now = Date()
            if self.shy.record(now: now) { self.tickle.reset(); self.enter("peek", for: 2.5); self.say(self.phrases.pick("shy")) }
            else if self.tickle.record(now: now) { self.enter("laugh", for: 1.5); self.say(self.phrases.pick("tickle")) }
            else { self.enter(self.clickCount % 2 == 0 ? "happy" : "wave", for: 1.2) }
        }
        view.onDoubleClick = { [weak self] in self?.jump(userInitiated: true) }
        view.onLongPress = { [weak self] in
            guard let self else { return }
            self.state.totals.pets += 1; self.mood(.petted)
            self.enter("love", for: 2.0); self.say(self.phrases.pick("love"))
        }
        view.onFileDrop = { [weak self] urls in self?.fetch(urls) }
        window.onDragStart = { [weak self] in
            guard let self, !self.programmaticMove else { return }
            self.stopMover(); self.enter("held", for: 0)
        }
        window.onDragEnd = { [weak self] in
            guard let self, self.current.name == "held" else { return }
            if self.pouts.record() { self.mood(.pouted); self.enter("pout", for: 2.5); self.say(self.phrases.pick("pout")) }
            else { self.enter("land", for: 0.45, userInitiated: true) }
        }
    }

    // MARK: public commands (menu)

    func jump(userInitiated: Bool = true) { enter("jump", for: 0.6, userInitiated: userInitiated) }
    func dance() { mood(.played); enter("dance", for: 2.5) }
    func spin() { enter("spin", for: 0.9) }
    func shake() { enter("shake", for: 0.6) }
    func rollOver() { enter("roll", for: 1.2) }
    func howl() { enter("howl", for: 2.0) }
    func giveTreat() { state.totals.treats += 1; mood(.treat); enter("eat", for: 2.5) }
    func bark() { enter("bark", for: 1.0); say(phrases.pick("bark")) }
    func beg() { enter("beg", for: 2.5); say(phrases.pick("beg")) }
    func stretch() { enter("stretch", for: 1.5) }
    func salute() { enter("salute", for: 1.5) }
    func sitDown() { enter("sit", for: .random(in: 10...20)) }
    func goToSleep() { enter("sleep", for: .random(in: 30...90)) }
    func zoomies() {
        mood(.exertion)
        zoomiesUntil = Date().addingTimeInterval(3.5)
        walkDirection = Bool.random() ? 1 : -1
        enter(walkDirection > 0 ? "run_right" : "run_left", for: 3.5)
        say(phrases.pick("zoomies"))
    }
    func say(_ text: String) { view.say(text) }

    func howIsYourDay() {
        state.mood.integrate(to: Date(), asleep: current.name == "sleep")
        let t = state.totals
        let mins = Int(t.minutes + Date().timeIntervalSince(lastSaveMark) / 60)
        enter("wink", for: 1.5)
        let streak = state.streakDays > 1 ? " · day \(state.streakDays) streak" : ""
        view.say("\(state.mood.emoji) \(state.mood.energyBar) · \(mins) min · \(t.pets) pets · \(t.treats) treats · \(t.keys) keys\(streak)", for: 5)
    }

    // MARK: hats, size, skin (preferences)

    var hatName: String { prefs.hat }
    func setHat(_ name: String) {
        prefs.hat = name
        if name != "none" { react("happy", for: 1.2, say: phrases.pick("fancy"), force: true) }
    }
    private(set) var scale: CGFloat = 1
    func apply(scale newScale: CGFloat) {
        scale = newScale
        var f = window.frame
        let newSize = CGSize(width: Sprites.windowSize.width * newScale, height: Sprites.windowSize.height * newScale)
        f.origin.x += (f.width - newSize.width) / 2
        f.size = newSize
        window.setFrame(f, display: true)
        view.apply(scale: newScale)
    }
    private func preferencesChanged() {
        if CGFloat(prefs.scale) != scale { apply(scale: CGFloat(prefs.scale)) }
        view.setHat(prefs.hat == "none" ? nil : Sprites.hat(prefs.hat, skin: prefs.skin))
    }
    /// Swap the whole frame set (skin change). Keeps the current state if it exists in the new set.
    func replaceAnimations(_ new: [String: Animation]) {
        guard new["idle"] != nil else { return }
        animations = new
        enter(animations[current.name] != nil ? current.name : "idle", for: 3)
    }
    func reloadPhrases(_ p: Phrases) { phrases = p }

    // MARK: focus timer

    private var focusTimers: [Timer] = []
    private var focusEnds: Date?
    var focusActive: Bool { focusEnds != nil }
    func startFocus(minutes: Int) {
        stopFocus(quiet: true)
        let ends = Date().addingTimeInterval(Double(minutes) * 60)
        focusEnds = ends
        enter("focus", for: 0); say(phrases.pick("focusStart", ["minutes": "\(minutes)"]))
        let half = Timer(fire: Date().addingTimeInterval(Double(minutes) * 30), interval: 0, repeats: false) { [weak self] _ in
            guard let self, self.focusActive else { return }
            self.say(self.phrases.pick("focusHalf")); if self.current.name != "focus" { self.enter("focus", for: 0) }
        }
        let end = Timer(fire: ends, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.focusEnds = nil; self.focusTimers.removeAll()
            self.enter("celebrate", for: 3); self.say(self.phrases.pick("focusDone")); self.sounds?.play(.ding)
        }
        half.tolerance = 30; end.tolerance = 15
        RunLoop.main.add(half, forMode: .common); RunLoop.main.add(end, forMode: .common)
        focusTimers = [half, end]
    }
    func stopFocus(quiet: Bool = false) {
        focusTimers.forEach { $0.invalidate() }; focusTimers.removeAll()
        guard focusEnds != nil else { return }
        focusEnds = nil
        if !quiet { say(phrases.pick("focusEnd")); chooseNextState() }
    }

    // MARK: reminders

    func remind(in minutes: Int, text: String) {
        let line = text.isEmpty ? phrases.pick("reminder") : text
        let t = Timer(fire: Date().addingTimeInterval(Double(minutes) * 60), interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.react("bark", for: 1.5, say: nil, force: true)
            self.view.say(line, for: 8)
            self.sounds?.play(.ding)
        }
        t.tolerance = 10; RunLoop.main.add(t, forMode: .common)
        say(phrases.pick("remindSet", ["minutes": "\(minutes)"]))
    }

    /// One wake per hour, on the hour, with a minute of tolerance.
    private var hourlyTimer: Timer?
    private func scheduleHourlyHowl() {
        hourlyTimer?.invalidate()
        guard let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.prefs.isEnabled(.hourlyHowl), self.isVisible, !self.isSuspended, self.current.name != "sleep", !self.focusActive {
                self.howl()
                let f = DateFormatter(); f.dateFormat = "h a"
                self.say(self.phrases.pick("howl", ["time": f.string(from: Date())]))
            }
            self.scheduleHourlyHowl()
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        hourlyTimer = t
    }

    // MARK: reactions

    /// Play a reaction unless the gate says no. Returns whether it ran.
    @discardableResult
    private func react(_ stateName: String, for seconds: TimeInterval, say line: String?, force: Bool = false) -> Bool {
        guard isVisible, !isSuspended else { return false }
        let now = Date()
        guard gate.allows(now: now, current: current.name, currentEndsAt: stateEndsAt, force: force) else { return false }
        gate.record(now: now)
        enter(stateName, for: seconds)
        if let line { say(line) }
        return true
    }
    private var gestureActive: Bool { ReactionGate.gestureActive(current: current.name, currentEndsAt: stateEndsAt, now: Date()) }

    /// Entry point for everything `SystemObservers` reports.
    func handle(_ event: SystemEvent) {
        switch event {
        case .suspend(let s): suspend(s)
        case .unlocked: enter("happy", for: 1.5); say(phrases.pick("welcomeBack"))
        case .appActivated(let app): react("alert", for: 1.1, say: Bool.random() ? phrases.pick("appSwitch", ["app": app]) : nil)
        case .appLaunched(let app): react("happy", for: 1.5, say: phrases.pick("appLaunch", ["app": app]), force: true)
        case .appQuit(let app): react(Bool.random() ? "wave" : "salute", for: 1.3, say: phrases.pick("appQuit", ["app": app]), force: true)
        case .spaceChanged: react("jump", for: 0.6, say: phrases.pick("space"))
        case .mounted(let name): react("sniff", for: 1.4, say: phrases.pick("mount", ["name": name]), force: true)
        case .unmounted(let name): react("wave", for: 1.2, say: phrases.pick("unmount", ["name": name]), force: true)
        case .download(let name): react("fetch", for: 2.0, say: phrases.pick("download", ["name": name]), force: true)
        case .globalClick(let p):
            lookTarget = p; lookUntil = Date().addingTimeInterval(1.5)
            if busyClicks.record() { react("bark", for: 1.0, say: phrases.pick("busy")) }
        case .power(let charging):
            if charging { react("happy", for: 1.5, say: phrases.pick("charging"), force: true) }
            else { react("alert", for: 1.1, say: phrases.pick("unplugged"), force: true) }
        case .appearance(let dark):
            if dark { react("yawn", for: 1.5, say: phrases.pick("dark"), force: true) }
            else { react("alert", for: 1.1, say: phrases.pick("light"), force: true) }
        case .music(let playing, let title):
            guard playing != musicPlaying else { return }
            musicPlaying = playing
            if playing {
                if current.name != "held", !focusActive { enter("groove", for: 0); say(title.isEmpty ? phrases.pick("musicNoTitle") : phrases.pick("music", ["title": title])) }
            } else if current.name == "groove" { chooseNextState() }
        case .key(let code): reactToKey(code)
        case .lowPowerModeChanged: restartTimer()
        }
    }

    // MARK: typing (counts only; never reads characters)

    private var typingSessionStart: Date?
    private var typingStopTimer: Timer?
    private var speedCelebrated = false

    private func reactToKey(_ code: UInt16) {
        guard isVisible, !isSuspended else { return }
        let now = Date()
        state.totals.keys += 1
        if state.totals.keys % 200 == 0 { markDirty() }
        keys.record(now: now)
        if typingSessionStart == nil { typingSessionStart = now; speedCelebrated = false }
        typingStopTimer?.invalidate()
        typingStopTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in self?.typingStopped() }

        switch code {
        case 36, 76:   // Return / Enter
            if current.name == "typing" || current.name.hasPrefix("idle") { react("jump", for: 0.6, say: phrases.pick("sent")) }
            return
        case 51, 117:  // Delete / Forward delete
            if deletes.record(now: now) { react("sad", for: 1.5, say: phrases.pick("oops")) }
            return
        default: break
        }
        let recent = keys.count(within: Behaviour.Bursts.typing.window, now: now)
        if recent >= Behaviour.Bursts.typing.count, current.name != "typing", !gestureActive, !Behaviour.typingBlockedStates.contains(current.name) {
            enter("typing", for: 4); say(phrases.pick("typing"))
        } else if current.name == "typing" {
            stateEndsAt = now.addingTimeInterval(3)
        }
        if !speedCelebrated, recent >= Behaviour.Bursts.speedTyper.count {
            speedCelebrated = true; react("happy", for: 1.5, say: phrases.pick("speedTyper"), force: true)
        }
    }
    private func typingStopped() {
        defer { typingSessionStart = nil }
        if current.name == "typing" { stateEndsAt = Date() }
        if let start = typingSessionStart, Date().timeIntervalSince(start) > 600 { react("yawn", for: 1.5, say: phrases.pick("break"), force: true) }
    }

    // MARK: clipboard (change counter only, plus text length)

    private func checkClipboard() {
        let c = NSPasteboard.general.changeCount
        guard c != clipboardCount else { return }
        clipboardCount = c
        guard prefs.isEnabled(.clipboard), current.name != "sleep", !gestureActive else { return }
        let len = NSPasteboard.general.string(forType: .string)?.count ?? 0
        if len > 200 { enter("think", for: 2.0); say(phrases.pick("think")) } else { enter("sniff", for: 1.2); say(phrases.pick("sniff")) }
    }

    private func fetch(_ urls: [URL]) {
        guard let url = urls.first else { return }
        enter("fetch", for: 2.0)
        say(phrases.pick("fetched", ["name": url.lastPathComponent]))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { NSWorkspace.shared.open(url) }
    }

    // MARK: follow cursor

    private(set) var followsCursor = false
    func setFollowCursor(_ on: Bool) {
        followsCursor = on
        if on { enter("idle", for: 0) } else { stopMover(); chooseNextState() }
    }
    private var moveTimer: Timer?
    private var velocity = CGPoint.zero

    private func followTick() {
        let mouse = NSEvent.mouseLocation
        let f = window.frame
        let dx = mouse.x - f.midX, dy = mouse.y - f.midY
        if abs(dx) < 50 && abs(dy) < 60 {
            stopMover()
            if !current.name.hasPrefix("idle") { enter("idle", for: 0) }
            return
        }
        startMover()
        let dir: CGFloat = dx > 0 ? 1 : -1
        let want = "\(hypot(dx, dy) > 260 ? "run" : "walk")_\(dir > 0 ? "right" : "left")"
        if current.name != want { walkDirection = dir; enter(want, for: 0) }
    }
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
        let k: CGFloat = 30, c: CGFloat = 2 * sqrt(30)
        velocity.x += (k * dx - c * velocity.x) * dt
        velocity.y += (k * dy - c * velocity.y) * dt
        let sp = hypot(velocity.x, velocity.y)
        if sp > 900 { velocity.x *= 900 / sp; velocity.y *= 900 / sp }
        f.origin.x += velocity.x * dt; f.origin.y += velocity.y * dt
        clampToScreen(&f)
        move(to: f.origin)
    }

    // MARK: state machine

    private func enter(_ name: String, for seconds: TimeInterval, userInitiated: Bool = false) {
        guard let anim = animations[name] else { return }
        let wasAsleep = current.name == "sleep"
        if wasAsleep != (name == "sleep") { state.mood.integrate(to: Date(), asleep: wasAsleep) }
        stateStartedAt = Date()
        current = anim
        frame = 0
        stateEndsAt = seconds > 0 ? Date().addingTimeInterval(seconds) : .distantFuture
        restartTimer()
        tick()
        sounds?.play(for: name, userInitiated: userInitiated, quiet: isNight || focusActive || isSuspended || !isVisible)
    }

    private var isNight: Bool { Behaviour.isNight(hour: Calendar.current.component(.hour, from: Date()), start: prefs.quietStart, end: prefs.quietEnd) }

    private func chooseNextState() {
        state.mood.integrate(to: Date(), asleep: current.name == "sleep")
        let vf = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = window.frame.minX
        let ctx = BrainContext(
            current: current.name,
            stateAge: Date().timeIntervalSince(stateStartedAt),
            focusActive: focusActive,
            musicPlaying: musicPlaying,
            userIdleSeconds: Date().timeIntervalSince(lastMouseMove),
            isNight: isNight,
            batteryLow: SystemObservers.batteryIsLow,
            nearLeftEdge: x < vf.minX + 40,
            nearRightEdge: x > vf.maxX - window.frame.width - 40,
            mood: state.mood)
        switch Brain.chooseNext(ctx, rng: &rng) {
        case .enter(let name, let secs, let key):
            if name == "sad", ctx.userIdleSeconds > Behaviour.lonelyAfter { mood(.lonely) }
            enter(name, for: secs)
            if let key, chattyEnough(for: key) { say(phrases.pick(key)) }
        case .walk(let dir, let secs):
            walkDirection = CGFloat(dir)
            enter(dir > 0 ? "walk_right" : "walk_left", for: secs)
        case .zoomies: zoomies()
        }
    }

    /// Chattiness: quiet → no idle chatter (reactions still speak); normal/chatty → as designed.
    private func chattyEnough(for key: String) -> Bool { prefs.chattiness == 0 ? key != "idle" : true }

    private func restartTimer() {
        timer?.invalidate()
        guard isVisible, !isSuspended else { stopMover(); return }
        var fps = current.fps
        if ProcessInfo.processInfo.isLowPowerModeEnabled { fps = max(1, fps / 2) }
        let interval = 1.0 / fps
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func idleVariantForCursor() -> Animation? {
        var point = NSEvent.mouseLocation
        if let t = lookTarget, Date() < lookUntil { point = t }
        let dx = point.x - window.frame.midX
        return animations[dx < -60 ? "idle_left" : (dx > 60 ? "idle_right" : "idle")]
    }

    private func tick() {
        let m = NSEvent.mouseLocation
        if m != lastMouse { lastMouse = m; lastMouseMove = Date() }
        checkClipboard()
        if current.name.hasPrefix("idle"), let v = idleVariantForCursor(), v.name != current.name { current = v }
        view.show(current.frames[frame % current.frames.count], hatVisible: !Behaviour.hatHiddenStates.contains(current.name))
        frame = (frame + 1) % current.frames.count

        if followsCursor {
            if !gestureActive { followTick() }
            return
        }
        if Date() < zoomiesUntil, current.name.hasPrefix("run") {
            var f = window.frame
            f.origin.x += walkDirection * 14
            if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
                if f.origin.x < vf.minX { f.origin.x = vf.minX; walkDirection = 1; if let a = animations["run_right"] { current = a } }
                if f.origin.x > vf.maxX - f.width { f.origin.x = vf.maxX - f.width; walkDirection = -1; if let a = animations["run_left"] { current = a } }
            }
            move(to: f.origin)
        } else if current.name.hasPrefix("walk") {
            var f = window.frame
            f.origin.x += walkDirection * 2.5
            move(to: f.origin)
        }
        if Date() >= stateEndsAt { chooseNextState() }
    }

    // MARK: window helpers

    private func move(to origin: NSPoint) { programmaticMove = true; window.setFrameOrigin(origin); programmaticMove = false }
    private func clampToScreen(_ f: inout NSRect) {
        guard let vf = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
    }
    private func placeAtBottom(primary: Bool) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = primary ? vf.midX - Sprites.size.width / 2 : CGFloat.random(in: vf.minX + 40 ... max(vf.minX + 41, vf.maxX - Sprites.size.width - 40))
        window.setFrameOrigin(NSPoint(x: x, y: vf.minY))
    }

    // MARK: visibility & power

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { window.orderFrontRegardless() } else { window.orderOut(nil); saveState() }
        restartTimer()
    }
    private func suspend(_ suspended: Bool) {
        isSuspended = suspended
        if suspended { saveState() }
        restartTimer()
    }
}
