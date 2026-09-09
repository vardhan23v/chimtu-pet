import Foundation

/// Decides whether a reaction may play right now. Pure value; the controller
/// owns one and feeds it the live state.
public struct ReactionGate: Equatable {
    public private(set) var lastReaction = Date.distantPast
    public init() {}

    /// - Parameters:
    ///   - force: important events (app launch, reminder) bypass the cooldown and
    ///            in-progress gestures, but never interrupt being held.
    public func allows(now: Date, current: String, currentEndsAt: Date, force: Bool) -> Bool {
        if current == "held" { return false }
        if force { return true }
        if now.timeIntervalSince(lastReaction) < Behaviour.reactionCooldown { return false }
        if Behaviour.gestures.contains(current), now < currentEndsAt { return false }
        return true
    }

    public mutating func record(now: Date) { lastReaction = now }

    /// True when a gesture is still playing (used by clipboard/typing checks too).
    public static func gestureActive(current: String, currentEndsAt: Date, now: Date) -> Bool {
        Behaviour.gestures.contains(current) && now < currentEndsAt
    }
}

/// Counts events inside a sliding window; fires (and resets) when a threshold is hit.
/// Replaces the copy-pasted `times.filter { now - $0 < w } + [now]` pattern.
public struct BurstCounter: Equatable {
    public let window: TimeInterval
    public let threshold: Int
    public private(set) var times: [Date] = []

    public init(threshold: Int, window: TimeInterval) { self.threshold = threshold; self.window = window }
    public init(_ spec: (count: Int, window: Double)) { self.init(threshold: spec.count, window: spec.window) }

    /// Record one event. Returns true if the threshold was reached; the counter then resets.
    @discardableResult
    public mutating func record(now: Date = Date()) -> Bool {
        times = times.filter { now.timeIntervalSince($0) < window } + [now]
        if times.count >= threshold { times.removeAll(); return true }
        return false
    }

    /// Number of events inside the last `seconds` (≤ window) without recording.
    public func count(within seconds: TimeInterval, now: Date = Date()) -> Int {
        times.filter { now.timeIntervalSince($0) < seconds }.count
    }

    public mutating func reset() { times.removeAll() }
}
