import Foundation

/// Tunable constants shared by the macOS app and (by convention) the Windows port.
/// Numbers here are the single source of truth; `tests/fixtures/behaviour_vectors.json`
/// pins them for both implementations.
public enum Behaviour {
    /// States that count as a "gesture": short, user-visible actions that other
    /// reactions must not interrupt while they are still playing.
    public static let gestures: Set<String> = [
        "wave", "jump", "scratch", "yawn", "alert", "happy", "held", "land", "dance", "spin", "shake",
        "eat", "love", "howl", "sneeze", "dig", "roll", "sniff", "fetch", "bark", "beg", "typing",
        "wink", "celebrate", "stretch", "peek", "think", "laugh", "pout", "salute", "hiccup", "chase",
    ]

    /// Poses where the head moves too much for a hat overlay to stay put.
    public static let hatHiddenStates: Set<String> = ["roll", "spin", "held", "sneeze", "shake"]

    /// States that must not be interrupted by typing.
    public static let typingBlockedStates: Set<String> = ["held", "focus", "groove"]

    /// Minimum gap between two reactions (seconds).
    public static let reactionCooldown: TimeInterval = 1.5

    /// Idle mouse time (seconds) before he gets lonely.
    public static let lonelyAfter: TimeInterval = 300

    /// Quiet hours default: 23:00 → 06:00.
    public static let defaultQuietStart = 23
    public static let defaultQuietEnd = 6

    public static func isNight(hour: Int, start: Int = defaultQuietStart, end: Int = defaultQuietEnd) -> Bool {
        start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
    }

    /// Burst thresholds (count within window seconds).
    public enum Bursts {
        public static let tickle = (count: 4, window: 2.0)        // clicks on him → laugh
        public static let shy = (count: 8, window: 5.0)           // clicks on him → peek
        public static let pout = (count: 3, window: 15.0)         // drags → pout
        public static let busyClicks = (count: 6, window: 2.0)    // clicks anywhere → bark
        public static let deletes = (count: 6, window: 2.0)       // deletes → "Oops?"
        public static let typing = (count: 8, window: 3.0)        // keys → tap along
        public static let speedTyper = (count: 12, window: 3.0)   // keys → "Speed typer!"
    }

    /// The random mood table. Weights sum to 1.0 at baseline mood; Brain rescales
    /// sleep and antic weights by mood and renormalises.
    public enum Weights {
        public static let idle = 0.40
        public static let sit = 0.22
        public static let sleep = 0.12
        public static let scratch = 0.06
        public static let jump = 0.03
        public static let dance = 0.02
        public static let spinOrShake = 0.02
        public static let sneezeDigRoll = 0.02
        public static let barkOrBeg = 0.02
        public static let idleLine = 0.02
        public static let wink = 0.01
        public static let chase = 0.015
        public static let zoomies = 0.01
        public static let walk = 0.035
    }
}
