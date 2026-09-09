import AVFoundation
import ChimtuCore

/// Tiny procedural clips, played with throwaway AVAudioPlayers. Off by default.
/// The gate (cooldown, quiet hours, focus, suspended) lives here so callers stay simple.
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    enum Clip: String, CaseIterable { case bark, yip, awoo, sniff, snore, boing, chomp, ding }

    private let prefs = Preferences.shared
    private var data: [Clip: Data] = [:]
    private var active: [AVAudioPlayer] = []
    private var lastPlayed = Date.distantPast
    static let cooldown: TimeInterval = 6

    /// Which clip a state triggers. Jump/land only when the user caused them.
    static let table: [String: (Clip, userOnly: Bool)] = [
        "bark": (.bark, false), "beg": (.yip, false), "love": (.yip, false), "wink": (.yip, false),
        "howl": (.awoo, false), "sniff": (.sniff, false), "sleep": (.snore, false),
        "jump": (.boing, true), "land": (.boing, true), "eat": (.chomp, false), "celebrate": (.ding, false),
    ]

    override init() {
        super.init()
        for c in Clip.allCases {
            if let url = Bundle.main.url(forResource: c.rawValue, withExtension: "wav", subdirectory: "sounds"),
               let d = try? Data(contentsOf: url) { data[c] = d }
        }
    }

    func play(for state: String, userInitiated: Bool, quiet: Bool) {
        guard let (clip, userOnly) = SoundPlayer.table[state] else { return }
        if userOnly && !userInitiated { return }
        guard !quiet else { return }
        play(clip)
    }

    /// Respects the enable switch and the cooldown; `force` skips the cooldown (reminders).
    func play(_ clip: Clip, force: Bool = false) {
        guard prefs.soundsEnabled, let d = data[clip] else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastPlayed) < SoundPlayer.cooldown { return }
        lastPlayed = now
        guard let p = try? AVAudioPlayer(data: d) else { return }
        p.volume = Float(prefs.soundVolume)
        p.delegate = self
        active.append(p)
        p.play()
    }

    func preview() { play(.bark, force: true) }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        active.removeAll { $0 === player }
    }
}
