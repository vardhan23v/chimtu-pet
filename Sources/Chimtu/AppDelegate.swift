import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pet: PetController!
    private var toggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var followItem: NSMenuItem!
    private var typingItem: NSMenuItem!
    private var friends: [PetController] = []
    private var focusItem: NSMenuItem!
    private var animations: [String: Animation] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let animations = Sprites.load()
        guard !animations.isEmpty else {
            let alert = NSAlert(); alert.messageText = "Chimtu could not find its sprite frames."; alert.runModal()
            NSApp.terminate(nil); return
        }
        self.animations = animations
        pet = PetController(animations: animations)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🐕"
        statusItem.button?.toolTip = "Chimtu"
        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Hide Chimtu", action: #selector(toggle), keyEquivalent: "h")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        for (title, sel) in [("Jump", #selector(doJump)), ("Dance", #selector(doDance)), ("Spin", #selector(doSpin)), ("Shake", #selector(doShake)), ("Roll Over", #selector(doRoll)), ("Howl", #selector(doHowl)), ("Give Treat", #selector(doTreat)), ("Bark", #selector(doBark)), ("Beg", #selector(doBeg)), ("Zoomies", #selector(doZoomies)), ("Stretch", #selector(doStretch)), ("Salute", #selector(doSalute)), ("Sit Down", #selector(doSit)), ("Go to Sleep", #selector(doSleep))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        focusItem = NSMenuItem(title: "Start Focus (25 min)", action: #selector(toggleFocus), keyEquivalent: ""); focusItem.target = self
        menu.addItem(focusItem)
        let remindMenu = NSMenu()
        for m in [5, 10, 30, 60] {
            let it = NSMenuItem(title: "In \(m) minutes…", action: #selector(remind(_:)), keyEquivalent: ""); it.target = self; it.tag = m; remindMenu.addItem(it)
        }
        let remindItem = NSMenuItem(title: "Remind Me", action: nil, keyEquivalent: ""); remindItem.submenu = remindMenu; menu.addItem(remindItem)
        let dayItem = NSMenuItem(title: "How's your day?", action: #selector(howsYourDay), keyEquivalent: ""); dayItem.target = self; menu.addItem(dayItem)
        let hatMenu = NSMenu()
        for (title, key) in [("None", "none"), ("Party Hat", "party"), ("Cap", "cap"), ("Crown", "crown")] {
            let it = NSMenuItem(title: title, action: #selector(setHat(_:)), keyEquivalent: ""); it.target = self; it.representedObject = key
            it.state = pet.hatName == key ? .on : .off; hatMenu.addItem(it)
        }
        let hatItem = NSMenuItem(title: "Hat", action: nil, keyEquivalent: ""); hatItem.submenu = hatMenu; menu.addItem(hatItem)
        let friendItem = NSMenuItem(title: "Add a Friend", action: #selector(addFriend), keyEquivalent: ""); friendItem.target = self; menu.addItem(friendItem)
        menu.addItem(.separator())
        let sizeMenu = NSMenu()
        for (title, pct) in [("Small", 70), ("Normal", 100), ("Large", 140), ("Huge", 200)] {
            let it = NSMenuItem(title: title, action: #selector(setSize(_:)), keyEquivalent: ""); it.target = self; it.tag = pct
            it.state = Int(pet.scale * 100) == pct ? .on : .off
            sizeMenu.addItem(it)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: ""); sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        followItem = NSMenuItem(title: "Follow Cursor", action: #selector(toggleFollow), keyEquivalent: "f")
        followItem.target = self
        menu.addItem(followItem)
        typingItem = NSMenuItem(title: "Typing Reactions", action: #selector(toggleTyping), keyEquivalent: "")
        typingItem.target = self
        typingItem.state = pet.typingEnabled ? .on : .off
        menu.addItem(typingItem)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "Click: wave · Double-click: jump · Hold: pet him · Drop a file: fetch · Type: he taps along", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Chimtu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleFollow() {
        pet.setFollowCursor(!pet.followsCursor)
        followItem.state = pet.followsCursor ? .on : .off
    }

    @objc private func toggleTyping() {
        pet.setTypingReactions(!pet.typingEnabled)
        typingItem.state = pet.typingEnabled ? .on : .off
        if pet.typingEnabled && !pet.hasInputMonitoring {
            let a = NSAlert()
            a.messageText = "Allow Input Monitoring for Chimtu"
            a.informativeText = "Chimtu only counts keystrokes so he can tap along while you type. He never reads what you type.\n\nTurn on Chimtu under System Settings → Privacy & Security → Input Monitoring, then relaunch him."
            a.addButton(withTitle: "Open Settings"); a.addButton(withTitle: "Later")
            if a.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func toggleFocus() {
        if pet.focusActive { pet.stopFocus(); focusItem.title = "Start Focus (25 min)" }
        else { pet.startFocus(minutes: 25); focusItem.title = "Stop Focus" ; scheduleFocusTitleReset(after: 25 * 60 + 5) }
    }
    private func scheduleFocusTitleReset(after s: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in if self?.pet.focusActive == false { self?.focusItem.title = "Start Focus (25 min)" } }
    }
    @objc private func remind(_ sender: NSMenuItem) {
        let a = NSAlert(); a.messageText = "Remind you about what?"; a.informativeText = "Chimtu will bark and show it in \(sender.tag) minutes."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); field.placeholderString = "Drink water"
        a.accessoryView = field; a.addButton(withTitle: "Set"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { pet.remind(in: sender.tag, text: field.stringValue) }
    }
    @objc private func howsYourDay() { pet.howIsYourDay() }
    @objc private func setHat(_ sender: NSMenuItem) {
        pet.setHat(sender.representedObject as? String ?? "none")
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
    }
    @objc private func addFriend() {
        guard friends.count < 4 else { pet.say("That's enough friends!"); return }
        let friend = PetController(animations: animations)
        friends.append(friend)
        friend.say(["Hi!", "Bow!", "Namaste!"].randomElement()!)
    }

    @objc private func doJump() { pet.jump() }
    @objc private func doDance() { pet.dance() }
    @objc private func doSpin() { pet.spin() }
    @objc private func doShake() { pet.shake() }
    @objc private func doRoll() { pet.rollOver() }
    @objc private func doHowl() { pet.howl() }
    @objc private func doTreat() { pet.giveTreat() }
    @objc private func doBark() { pet.bark() }
    @objc private func doBeg() { pet.beg() }
    @objc private func doZoomies() { pet.zoomies() }
    @objc private func doStretch() { pet.stretch() }
    @objc private func doSalute() { pet.salute() }
    @objc private func setSize(_ sender: NSMenuItem) {
        pet.apply(scale: CGFloat(sender.tag) / 100)
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
    }
    @objc private func doSit() { pet.sitDown() }
    @objc private func doSleep() { pet.goToSleep() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Could not change Launch at Login"
            alert.informativeText = "Move Chimtu.app into /Applications first, then try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggle() {
        pet.setVisible(!pet.isVisible)
        friends.forEach { $0.setVisible(pet.isVisible) }
        toggleItem.title = pet.isVisible ? "Hide Chimtu" : "Show Chimtu"
    }
}
