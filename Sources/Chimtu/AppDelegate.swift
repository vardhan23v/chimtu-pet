import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pet: PetController!
    private var toggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var followItem: NSMenuItem!
    private var typingItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let animations = Sprites.load()
        guard !animations.isEmpty else {
            let alert = NSAlert(); alert.messageText = "Chimtu could not find its sprite frames."; alert.runModal()
            NSApp.terminate(nil); return
        }
        pet = PetController(animations: animations)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🐕"
        statusItem.button?.toolTip = "Chimtu"
        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Hide Chimtu", action: #selector(toggle), keyEquivalent: "h")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        for (title, sel) in [("Jump", #selector(doJump)), ("Dance", #selector(doDance)), ("Spin", #selector(doSpin)), ("Shake", #selector(doShake)), ("Roll Over", #selector(doRoll)), ("Howl", #selector(doHowl)), ("Give Treat", #selector(doTreat)), ("Bark", #selector(doBark)), ("Beg", #selector(doBeg)), ("Sit Down", #selector(doSit)), ("Go to Sleep", #selector(doSleep))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
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

    @objc private func doJump() { pet.jump() }
    @objc private func doDance() { pet.dance() }
    @objc private func doSpin() { pet.spin() }
    @objc private func doShake() { pet.shake() }
    @objc private func doRoll() { pet.rollOver() }
    @objc private func doHowl() { pet.howl() }
    @objc private func doTreat() { pet.giveTreat() }
    @objc private func doBark() { pet.bark() }
    @objc private func doBeg() { pet.beg() }
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
        toggleItem.title = pet.isVisible ? "Hide Chimtu" : "Show Chimtu"
    }
}
