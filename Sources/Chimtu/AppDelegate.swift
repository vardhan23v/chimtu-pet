import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pet: PetController!
    private var toggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var followItem: NSMenuItem!

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
        for (title, sel) in [("Jump", #selector(doJump)), ("Sit Down", #selector(doSit)), ("Go to Sleep", #selector(doSleep))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        followItem = NSMenuItem(title: "Follow Cursor", action: #selector(toggleFollow), keyEquivalent: "f")
        followItem.target = self
        menu.addItem(followItem)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "Click: wave / wiggle · Double-click: jump · He perks up when you switch apps", action: nil, keyEquivalent: "")
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

    @objc private func doJump() { pet.jump() }
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
