import AppKit
import ServiceManagement
import ChimtuCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pet: PetController!
    private var friends: [PetController] = []
    private var allPets: [PetController] { [pet] + friends }
    private let observers = SystemObservers()
    private let prefs = Preferences.shared
    private var animations: [String: Animation] = [:]
    private var phrases = Phrases()
    private let sounds = SoundPlayer()
    private var userPhrasesURL: URL { StateStore.defaultURL().deletingLastPathComponent().appendingPathComponent("phrases.json") }

    private var toggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var followItem: NSMenuItem!
    private var typingItem: NSMenuItem!
    private var focusItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        animations = Sprites.load(skin: prefs.skin)
        phrases = Phrases.load(bundled: Bundle.main.url(forResource: "phrases", withExtension: "json"), user: userPhrasesURL)
        guard let primary = PetController(animations: animations, isPrimary: true, phrases: phrases) else {
            let alert = NSAlert(); alert.messageText = "Chimtu could not find his sprite frames."
            alert.informativeText = "Reinstall Chimtu.app; the frames folder inside it is missing or damaged."
            alert.runModal(); NSApp.terminate(nil); return
        }
        pet = primary
        primary.sounds = sounds
        observers.handler = { [weak self] e in self?.allPets.forEach { $0.handle(e) } }
        observers.start()
        buildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) { pet?.saveState() }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🐕"
        statusItem.button?.toolTip = "Chimtu"
        let menu = NSMenu()
        toggleItem = item("Hide Chimtu", #selector(toggle), "h"); menu.addItem(toggleItem)
        menu.addItem(.separator())
        for (title, sel) in [("Jump", #selector(doJump)), ("Dance", #selector(doDance)), ("Spin", #selector(doSpin)), ("Shake", #selector(doShake)), ("Roll Over", #selector(doRoll)), ("Howl", #selector(doHowl)), ("Give Treat", #selector(doTreat)), ("Bark", #selector(doBark)), ("Beg", #selector(doBeg)), ("Zoomies", #selector(doZoomies)), ("Stretch", #selector(doStretch)), ("Salute", #selector(doSalute)), ("Sit Down", #selector(doSit)), ("Go to Sleep", #selector(doSleep))] {
            menu.addItem(item(title, sel))
        }
        menu.addItem(.separator())
        focusItem = item("Start Focus (25 min)", #selector(toggleFocus)); menu.addItem(focusItem)
        let remindMenu = NSMenu()
        for m in [5, 10, 30, 60] { let it = item("In \(m) minutes…", #selector(remind(_:))); it.tag = m; remindMenu.addItem(it) }
        menu.addItem(submenu("Remind Me", remindMenu))
        menu.addItem(item("How's your day?", #selector(howsYourDay)))
        let hatMenu = NSMenu()
        for (title, key) in [("None", "none"), ("Party Hat", "party"), ("Cap", "cap"), ("Crown", "crown"), ("Beanie", "beanie"), ("Bow", "bow"), ("Flower", "flower")] {
            let it = item(title, #selector(setHat(_:))); it.representedObject = key; it.state = prefs.hat == key ? .on : .off; hatMenu.addItem(it)
        }
        menu.addItem(submenu("Hat", hatMenu))
        let skinMenu = NSMenu()
        for (title, key) in [("Shiba (red)", "shiba"), ("Cream", "cream")] {
            let it = item(title, #selector(setSkin(_:))); it.representedObject = key; it.state = prefs.skin == key ? .on : .off; skinMenu.addItem(it)
        }
        menu.addItem(submenu("Skin", skinMenu))
        menu.addItem(item("Add a Friend", #selector(addFriend)))
        menu.addItem(.separator())
        let sizeMenu = NSMenu()
        for (title, pct) in [("Small", 70), ("Normal", 100), ("Large", 140), ("Huge", 200)] {
            let it = item(title, #selector(setSize(_:))); it.tag = pct; it.state = Int(prefs.scale * 100) == pct ? .on : .off; sizeMenu.addItem(it)
        }
        menu.addItem(submenu("Size", sizeMenu))
        menu.addItem(.separator())
        followItem = item("Follow Cursor", #selector(toggleFollow), "f"); menu.addItem(followItem)
        typingItem = item("Typing Reactions", #selector(toggleTyping)); typingItem.state = prefs.typingReactions ? .on : .off; menu.addItem(typingItem)
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(.separator())
        loginItem = item("Launch at Login", #selector(toggleLogin)); loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off; menu.addItem(loginItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "Click: wave · Double-click: jump · Hold: pet him · Drop a file: fetch · Type: he taps along", action: nil, keyEquivalent: "")
        about.isEnabled = false; menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Chimtu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector, _ key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key); it.target = self; return it
    }
    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: ""); it.submenu = menu; return it
    }
    private func tickOnly(_ sender: NSMenuItem) { sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off } }

    // MARK: actions

    @objc private func toggleFollow() { pet.setFollowCursor(!pet.followsCursor); followItem.state = pet.followsCursor ? .on : .off }

    @objc private func toggleTyping() {
        prefs.typingReactions.toggle()
        typingItem.state = prefs.typingReactions ? .on : .off
        observers.setTypingEnabled(prefs.typingReactions)
        if prefs.typingReactions && !observers.hasInputMonitoring { explainInputMonitoring() }
    }
    func explainInputMonitoring() {
        let a = NSAlert()
        a.messageText = "Allow Input Monitoring for Chimtu"
        a.informativeText = "Chimtu only counts keystrokes so he can tap along while you type. He never reads what you type.\n\nTurn on Chimtu under System Settings → Privacy & Security → Input Monitoring, then relaunch him."
        a.addButton(withTitle: "Open Settings"); a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleFocus() {
        if pet.focusActive { pet.stopFocus(); focusItem.title = "Start Focus (25 min)" }
        else {
            pet.startFocus(minutes: 25); focusItem.title = "Stop Focus"
            DispatchQueue.main.asyncAfter(deadline: .now() + 25 * 60 + 5) { [weak self] in if self?.pet.focusActive == false { self?.focusItem.title = "Start Focus (25 min)" } }
        }
    }
    @objc private func remind(_ sender: NSMenuItem) {
        let a = NSAlert(); a.messageText = "Remind you about what?"; a.informativeText = "Chimtu will bark and show it in \(sender.tag) minutes."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); field.placeholderString = "Drink water"
        a.accessoryView = field; a.addButton(withTitle: "Set"); a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { pet.remind(in: sender.tag, text: field.stringValue) }
    }
    @objc private func howsYourDay() { pet.howIsYourDay() }
    @objc private func setHat(_ sender: NSMenuItem) { pet.setHat(sender.representedObject as? String ?? "none"); tickOnly(sender) }
    @objc private func setSkin(_ sender: NSMenuItem) {
        applySkin(sender.representedObject as? String ?? "shiba")
        tickOnly(sender)
    }
    /// Load a skin's frames and hand them to every pet. Falls back silently if the skin is missing.
    func applySkin(_ skin: String) {
        let new = Sprites.load(skin: skin)
        guard new["idle"] != nil else { pet.say("That skin is missing"); return }
        if prefs.skin != skin { prefs.skin = skin }
        animations = new
        allPets.forEach { $0.replaceAnimations(new) }
    }
    /// Write a starter phrases.json (if absent) and open it in the default editor.
    func editPhrases() {
        let url = userPhrasesURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Phrases.defaultsJSON().write(to: url)
        }
        NSWorkspace.shared.open(url)
    }
    func reloadPhrases() {
        phrases = Phrases.load(bundled: Bundle.main.url(forResource: "phrases", withExtension: "json"), user: userPhrasesURL)
        allPets.forEach { $0.reloadPhrases(phrases) }
        pet.say(phrases.pick("bark"))
    }
    @objc private func addFriend() {
        guard friends.count < 4 else { pet.say(phrases.pick("tooManyFriends")); return }
        guard let friend = PetController(animations: animations, isPrimary: false, phrases: phrases) else { return }
        friend.sounds = sounds
        friends.append(friend)
        friend.say(phrases.pick("friendHello"))
    }
    @objc private func openSettings() { SettingsWindow.shared.show(delegate: self) }

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
    @objc private func doSit() { pet.sitDown() }
    @objc private func doSleep() { pet.goToSleep() }
    @objc private func setSize(_ sender: NSMenuItem) { prefs.scale = Double(sender.tag) / 100; tickOnly(sender) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Could not change Launch at Login"
            alert.informativeText = "Move Chimtu.app into /Applications first, then try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggle() {
        let show = !pet.isVisible
        allPets.forEach { $0.setVisible(show) }
        toggleItem.title = show ? "Hide Chimtu" : "Show Chimtu"
    }

    // Exposed for the Settings window.
    var primaryPet: PetController { pet }
    var systemObservers: SystemObservers { observers }
    func resetChimtu() {
        try? FileManager.default.removeItem(at: StateStore.defaultURL())
        pet.say("Fresh start!")
    }
}
