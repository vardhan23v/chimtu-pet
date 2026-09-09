import AppKit
import SwiftUI
import ServiceManagement
import ChimtuCore

/// Lazily created settings window. Costs nothing while closed.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(delegate: AppDelegate) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(delegate: delegate))
            let w = NSWindow(contentViewController: host)
            w.title = "Chimtu Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 460, height: 420))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Observable bridge over Preferences for SwiftUI bindings.
final class PrefsModel: ObservableObject {
    private let p = Preferences.shared
    @Published var scale: Double { didSet { p.scale = scale } }
    @Published var hat: String { didSet { p.hat = hat } }
    @Published var skin: String { didSet { p.skin = skin } }
    @Published var typing: Bool { didSet { p.typingReactions = typing } }
    @Published var sounds: Bool { didSet { p.soundsEnabled = sounds } }
    @Published var volume: Double { didSet { p.soundVolume = volume } }
    @Published var chattiness: Int { didSet { p.chattiness = chattiness } }
    @Published var quietStart: Int { didSet { p.quietStart = quietStart } }
    @Published var quietEnd: Int { didSet { p.quietEnd = quietEnd } }
    @Published var categories: [Preferences.Category: Bool] { didSet { categories.forEach { p.setEnabled($0.key, $0.value) } } }
    @Published var launchAtLogin: Bool

    init() {
        let p = Preferences.shared
        scale = p.scale; hat = p.hat; skin = p.skin; typing = p.typingReactions
        sounds = p.soundsEnabled; volume = p.soundVolume; chattiness = p.chattiness
        quietStart = p.quietStart; quietEnd = p.quietEnd
        var cats: [Preferences.Category: Bool] = [:]
        for c in Preferences.Category.allCases { cats[c] = p.isEnabled(c) }
        categories = cats
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    let delegate: AppDelegate
    @StateObject private var m = PrefsModel()

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "pawprint") }
            behaviour.tabItem { Label("Behaviour", systemImage: "sparkles") }
            sound.tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            stats.tabItem { Label("Stats", systemImage: "chart.bar") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(16)
        .frame(width: 460, height: 420)
    }

    private var general: some View {
        Form {
            Toggle("Launch at Login", isOn: $m.launchAtLogin).onChange(of: m.launchAtLogin) { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { m.launchAtLogin = SMAppService.mainApp.status == .enabled }
            }
            Picker("Size", selection: $m.scale) {
                Text("Small").tag(0.7); Text("Normal").tag(1.0); Text("Large").tag(1.4); Text("Huge").tag(2.0)
            }
            Picker("Skin", selection: $m.skin) { Text("Shiba (red)").tag("shiba"); Text("Cream").tag("cream") }
                .onChange(of: m.skin) { s in delegate.applySkin(s) }
            Picker("Hat", selection: $m.hat) {
                ForEach([("None", "none"), ("Party Hat", "party"), ("Cap", "cap"), ("Crown", "crown"), ("Beanie", "beanie"), ("Bow", "bow"), ("Flower", "flower")], id: \.1) { Text($0.0).tag($0.1) }
            }
            Toggle("Typing reactions", isOn: $m.typing).onChange(of: m.typing) { on in
                delegate.systemObservers.setTypingEnabled(on)
                if on && !delegate.systemObservers.hasInputMonitoring { delegate.explainInputMonitoring() }
            }
            Text("Typing needs Input Monitoring. Chimtu only counts keystrokes; he never reads them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var behaviour: some View {
        Form {
            Picker("Chattiness", selection: $m.chattiness) { Text("Quiet").tag(0); Text("Normal").tag(1); Text("Chatty").tag(2) }
            HStack {
                Text("Quiet hours")
                Picker("", selection: $m.quietStart) { ForEach(0..<24, id: \.self) { Text(hour($0)).tag($0) } }.frame(width: 90)
                Text("to")
                Picker("", selection: $m.quietEnd) { ForEach(0..<24, id: \.self) { Text(hour($0)).tag($0) } }.frame(width: 90)
            }
            Text("During quiet hours he naps far more and skips zoomies and sounds.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("React to").font(.headline)
            toggle("App launches, quits and switches", .appEvents)
            toggle("Clipboard (sniff / think)", .clipboard)
            toggle("Downloads and USB drives", .filesAndDrives)
            toggle("Music and Spotify", .music)
            toggle("Clicks anywhere on screen", .globalClicks)
            toggle("Howl on the hour", .hourlyHowl)
            Text("Turning a category off removes its system observer entirely.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ title: String, _ c: Preferences.Category) -> some View {
        Toggle(title, isOn: Binding(get: { m.categories[c] ?? true }, set: { m.categories[c] = $0 }))
    }
    private func hour(_ h: Int) -> String { h == 0 ? "12 am" : h < 12 ? "\(h) am" : h == 12 ? "12 pm" : "\(h - 12) pm" }

    private var sound: some View {
        Form {
            Toggle("Enable sounds", isOn: $m.sounds)
            Slider(value: $m.volume, in: 0...1) { Text("Volume") }.disabled(!m.sounds)
            Button("Preview bark") { delegate.primaryPet.sounds?.preview() }.disabled(!m.sounds)
            Text("Short synthesized clips: bark, yip, howl, sniff, snore, boing, chomp, ding. At most one every 6 seconds, never during focus or quiet hours. Off by default so idle battery use stays at ~0.1%.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stats: some View {
        let s = delegate.primaryPet.state
        return Form {
            LabeledContent("Mood", value: "\(s.mood.emoji)  happiness \(Int(s.mood.happiness * 100))%")
            LabeledContent("Energy", value: "\(s.mood.energyBar)  \(Int(s.mood.energy * 100))%")
            LabeledContent("Day streak", value: "\(s.streakDays)")
            LabeledContent("Launches", value: "\(s.totals.launches)")
            LabeledContent("Minutes together", value: "\(Int(s.totals.minutes))")
            LabeledContent("Pets · treats · clicks · keys", value: "\(s.totals.pets) · \(s.totals.treats) · \(s.totals.clicks) · \(s.totals.keys)")
            LabeledContent("First met", value: s.firstLaunch.formatted(date: .abbreviated, time: .omitted))
            Divider()
            HStack {
                Button("Edit Phrases…") { delegate.editPhrases() }
                Button("Reload Phrases") { delegate.reloadPhrases() }
                Spacer()
                Button("Reset Chimtu", role: .destructive) { delegate.resetChimtu() }
            }
            Text("Phrases live in a JSON file you can edit; malformed files are ignored. Reset deletes his memory (mood, streak, totals).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        VStack(spacing: 10) {
            Text("🐕").font(.system(size: 48))
            Text("Chimtu").font(.title2.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))").foregroundStyle(.secondary)
            Text("A tiny Shiba desktop pet named after the Telugu meme. No network, no analytics, ~0.1% CPU.").multilineTextAlignment(.center).font(.callout)
            Link("github.com/vardhan23v/chimtu-pet", destination: URL(string: "https://github.com/vardhan23v/chimtu-pet")!)
            Spacer()
        }.padding(.top, 20)
    }
}
