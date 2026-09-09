import Foundation

/// Everything the Brain needs to know to pick the next state. Built by the
/// controller from live values; contains no platform types so it is testable.
public struct BrainContext {
    public var current: String
    public var stateAge: TimeInterval
    public var focusActive: Bool
    public var musicPlaying: Bool
    public var userIdleSeconds: TimeInterval
    public var isNight: Bool
    public var batteryLow: Bool
    public var nearLeftEdge: Bool
    public var nearRightEdge: Bool
    public var mood: Mood

    public init(current: String, stateAge: TimeInterval = 0, focusActive: Bool = false, musicPlaying: Bool = false,
                userIdleSeconds: TimeInterval = 0, isNight: Bool = false, batteryLow: Bool = false,
                nearLeftEdge: Bool = false, nearRightEdge: Bool = false, mood: Mood = Mood()) {
        self.current = current; self.stateAge = stateAge; self.focusActive = focusActive; self.musicPlaying = musicPlaying
        self.userIdleSeconds = userIdleSeconds; self.isNight = isNight; self.batteryLow = batteryLow
        self.nearLeftEdge = nearLeftEdge; self.nearRightEdge = nearRightEdge; self.mood = mood
    }
}

/// What the controller should do next. `say` is a phrase *key* (see Phrases), not final text.
public enum Decision: Equatable {
    case enter(String, TimeInterval, say: String? = nil)
    case walk(direction: Int, TimeInterval)
    case zoomies
}

public enum Brain {
    /// Pure, deterministic given the generator. Mirrors `Brain.choose_next` in windows/chimtu_core.py.
    public static func chooseNext<G: RandomNumberGenerator>(_ ctx: BrainContext, rng: inout G) -> Decision {
        // Obligations first, in priority order.
        if ctx.focusActive { return .enter("focus", 0) }
        if ctx.musicPlaying { return .enter("groove", 0) }
        if ctx.current == "sleep" { return .enter(Bool.random(using: &rng) ? "yawn" : "stretch", 1.5) }
        if ctx.current == "sit", ctx.stateAge > 12, Double.random(in: 0..<1, using: &rng) < 0.5 { return .enter("stretch", 1.5) }
        if ctx.current == "eat", Double.random(in: 0..<1, using: &rng) < 0.3 { return .enter("hiccup", 2.0, say: "hiccup") }
        if ctx.current == "sad" { return .enter("sleep", Double.random(in: 60...180, using: &rng)) }
        if ctx.userIdleSeconds > Behaviour.lonelyAfter { return .enter("sad", 3) }

        // Weighted random table, re-weighted by mood.
        typealias W = Behaviour.Weights
        let sleepW = W.sleep + 0.25 * (1 - ctx.mood.energy)                 // tired → naps more
        let antic = min(max(ctx.mood.happiness / Mood.baselineHappiness, 0.5), 1.5)   // 1.0 at baseline
        let table: [(Double, String)] = [
            (W.idle, "idle"), (W.sit, "sit"), (sleepW, "sleep"), (W.scratch * antic, "scratch"),
            (W.jump * antic, "jump"), (W.dance * antic, "dance"), (W.spinOrShake * antic, "spinOrShake"),
            (W.sneezeDigRoll, "sneezeDigRoll"), (W.barkOrBeg * antic, "barkOrBeg"), (W.idleLine * antic, "idleLine"),
            (W.wink * antic, "wink"), (W.chase * antic, "chase"), (W.zoomies * antic, "zoomies"), (W.walk, "walk"),
        ]
        let total = table.reduce(0) { $0 + $1.0 }
        var roll = Double.random(in: 0..<total, using: &rng)
        var slot = "walk"
        for (w, name) in table { if roll < w { slot = name; break }; roll -= w }

        switch slot {
        case "idle":
            if ctx.batteryLow { return .enter("tired", Double.random(in: 5...12, using: &rng)) }
            if ctx.mood.happiness < 0.3, Double.random(in: 0..<1, using: &rng) < 0.3 { return .enter("sad", 3) }
            return .enter("idle", Double.random(in: 5...12, using: &rng))
        case "sit": return .enter("sit", Double.random(in: 6...15, using: &rng))
        case "sleep": return .enter("sleep", ctx.isNight ? Double.random(in: 90...240, using: &rng) : Double.random(in: 15...40, using: &rng))
        case "scratch": return .enter("scratch", 1.5)
        case "jump": return .enter("jump", 0.6)
        case "dance": return .enter("dance", 2.5)
        case "spinOrShake": return .enter(Bool.random(using: &rng) ? "spin" : "shake", 0.9)
        case "sneezeDigRoll": return .enter(["sneeze", "dig", "roll"].randomElement(using: &rng)!, 1.2)
        case "barkOrBeg":
            if ctx.isNight { return .enter("sleep", 120) }
            return Bool.random(using: &rng) ? .enter("bark", 1.0, say: "bark") : .enter("beg", 2.5, say: "beg")
        case "idleLine": return .enter("idle", 4, say: "idle")
        case "wink": return .enter("wink", 1.0)
        case "chase": return .enter("chase", 1.8, say: "chase")
        case "zoomies": return ctx.isNight ? .enter("sleep", 120) : .zoomies
        default:
            var dir = Bool.random(using: &rng) ? 1 : -1
            if ctx.nearLeftEdge { dir = 1 }
            if ctx.nearRightEdge { dir = -1 }
            return .walk(direction: dir, Double.random(in: 2...5, using: &rng))
        }
    }
}
