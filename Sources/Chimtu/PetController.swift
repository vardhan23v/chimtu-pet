import AppKit

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
        window = PetWindow(size: Sprites.size)
        placeAtBottom()
        view.onClick = { [weak self] in self?.enter("wave", for: 1.2) }
        observeSystem()
        window.orderFrontRegardless()
        enter("idle", for: 6)
    }

    // MARK: state machine

    private func enter(_ name: String, for seconds: TimeInterval) {
        guard let anim = animations[name] else { return }
        current = anim
        frame = 0
        stateEndsAt = Date().addingTimeInterval(seconds)
        restartTimer()
        tick()
    }

    private func chooseNextState() {
        // Mostly rests. Walking is the only state that moves the window.
        let roll = Double.random(in: 0..<1)
        switch roll {
        case ..<0.45: enter("idle", for: .random(in: 5...12))
        case ..<0.75: enter("sit", for: .random(in: 6...15))
        case ..<0.88: enter("sleep", for: .random(in: 15...40))
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
        guard isVisible, !isSuspended else { return }
        var fps = current.fps
        if ProcessInfo.processInfo.isLowPowerModeEnabled { fps = max(1, fps / 2) }
        let interval = 1.0 / fps
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.5   // lets the system batch wakeups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        view.show(current.frames[frame])
        frame = (frame + 1) % current.frames.count
        if current.name.hasPrefix("walk") {
            var f = window.frame
            f.origin.x += walkDirection * 2.5
            window.setFrameOrigin(f.origin)
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
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.suspend(true) }
        dc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.suspend(false) }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.restartTimer() }
    }

    private func placeAtBottom() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: vf.midX - Sprites.size.width / 2, y: vf.minY))
    }
}
