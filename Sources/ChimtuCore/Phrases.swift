import Foundation

/// All of Chimtu's lines, keyed by situation. Defaults live here; a bundled
/// `phrases.json` and a user file in Application Support can override any key.
public struct Phrases: Equatable {
    public private(set) var lines: [String: [String]]

    public static let defaults: [String: [String]] = [
        "idle": ["Chimtu!", "Bow bow!", "Em chestunnav?", "Pet me?", "Zzz... no wait", "Treat unda?", "Hi hooman"],
        "bark": ["Bow!", "Bow bow!", "Chimtu!"],
        "beg": ["Treat?", "Pleeease", "Em chestunnav?"],
        "love": ["❤️", "Good boy vibes", "Chimtuuu"],
        "friendHello": ["Hi!", "Bow!", "Namaste!"],
        "tickle": ["Hehehe, tickles!"],
        "shy": ["Shy!"],
        "pout": ["Hey! Put me down"],
        "hiccup": ["hic!"],
        "chase": ["Gotcha... almost"],
        "zoomies": ["ZOOMIES!"],
        "sniff": ["sniff sniff"],
        "think": ["Hmm, long one"],
        "typing": ["tak tak tak"],
        "sent": ["Sent!"],
        "oops": ["Oops?"],
        "speedTyper": ["Speed typer!"],
        "break": ["Break?"],
        "welcomeBack": ["Welcome back!"],
        "missedYou": ["Missed you!"],
        "backAlready": ["Back already?"],
        "morning": ["Morning!"],
        "afternoon": ["Afternoon, hooman"],
        "evening": ["Evening!"],
        "lateNight": ["Late night, hooman?"],
        "appLaunch": ["Ooh, {app}!"],
        "appQuit": ["Bye {app}"],
        "appSwitch": ["{app}?"],
        "space": ["Whee!"],
        "mount": ["New drive: {name}"],
        "unmount": ["Bye {name}"],
        "download": ["New download: {name}"],
        "busy": ["Busy busy!"],
        "charging": ["Charging!"],
        "unplugged": ["Unplugged"],
        "dark": ["Night night"],
        "light": ["Bright!"],
        "fetched": ["Fetched {name}"],
        "fancy": ["Fancy!"],
        "focusStart": ["Focus: {minutes} min. Let's go!"],
        "focusHalf": ["Halfway. Nice."],
        "focusDone": ["Break time! 🎉"],
        "focusEnd": ["Focus ended"],
        "remindSet": ["Okay! In {minutes} min."],
        "reminder": ["Reminder!"],
        "howl": ["Awooo, it's {time}"],
        "tooManyFriends": ["That's enough friends!"],
        "music": ["🎵 {title}"],
        "musicNoTitle": ["🎵"],
    ]

    public init(lines: [String: [String]] = Phrases.defaults) { self.lines = lines }

    /// Overlay another table on top: keys in `other` replace keys here.
    public func overlaying(_ other: [String: [String]]) -> Phrases {
        var merged = lines
        for (k, v) in other where !v.isEmpty { merged[k] = v }
        return Phrases(lines: merged)
    }

    /// Load defaults, then overlay the bundled file, then the user's file. Malformed files are ignored.
    public static func load(bundled: URL?, user: URL?) -> Phrases {
        var p = Phrases()
        for url in [bundled, user].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let table = try? JSONDecoder().decode([String: [String]].self, from: data) {
                p = p.overlaying(table)
            }
        }
        return p
    }

    /// Pick a random line for `key`, substituting `{placeholders}`. Falls back to the key itself.
    public func pick<G: RandomNumberGenerator>(_ key: String, _ vars: [String: String] = [:], rng: inout G) -> String {
        var line = lines[key]?.randomElement(using: &rng) ?? key
        for (k, v) in vars { line = line.replacingOccurrences(of: "{\(k)}", with: v) }
        return line
    }

    public func pick(_ key: String, _ vars: [String: String] = [:]) -> String {
        var g = SystemRandomNumberGenerator()
        return pick(key, vars, rng: &g)
    }

    /// Time-of-day greeting key.
    public static func greetingKey(hour: Int) -> String {
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<23: return "evening"
        default: return "lateNight"
        }
    }

    /// JSON of the defaults, for writing a starter file the user can edit.
    public static func defaultsJSON() -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(defaults)) ?? Data()
    }
}
