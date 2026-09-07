import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pet: PetController!
    private var toggleItem: NSMenuItem!

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
        let about = NSMenuItem(title: "Chimtu is a chubby Telugu-meme Shiba. Click him to say hi.", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Chimtu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggle() {
        pet.setVisible(!pet.isVisible)
        toggleItem.title = pet.isVisible ? "Hide Chimtu" : "Show Chimtu"
    }
}
