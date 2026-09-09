import Foundation

/// Two slow-moving values that re-weight the random behaviour table.
/// Integrated lazily whenever read, so it costs no timers.
public struct Mood: Codable, Equatable {
    /// 0…1, baseline 0.6. Rises when you interact kindly, decays back toward baseline.
    public var happiness: Double
    /// 0…1. Drains slowly while awake, recovers while asleep.
    public var energy: Double
    public var updatedAt: Date

    public static let baselineHappiness = 0.6
    public static let happinessDecayTau: TimeInterval = 2 * 3600
    /// Full recharge in ~80 min of sleep; full drain over ~9 h awake.
    public static let energyRecoveryPerSecond = 0.0002
    public static let energyDrainPerSecond = 0.00003

    public init(happiness: Double = Mood.baselineHappiness, energy: Double = 1.0, updatedAt: Date = Date()) {
        self.happiness = happiness; self.energy = energy; self.updatedAt = updatedAt
    }

    public enum Event { case petted, treat, clicked, pouted, lonely, exertion, played }

    /// Advance to `now`. Happiness decays toward baseline; energy recovers asleep and drains awake.
    public mutating func integrate(to now: Date, asleep: Bool) {
        let dt = max(0, now.timeIntervalSince(updatedAt))
        guard dt > 0 else { return }
        let k = exp(-dt / Mood.happinessDecayTau)
        happiness = Mood.baselineHappiness + (happiness - Mood.baselineHappiness) * k
        energy += (asleep ? Mood.energyRecoveryPerSecond : -Mood.energyDrainPerSecond) * dt
        clamp()
        updatedAt = now
    }

    public mutating func apply(_ e: Event) {
        switch e {
        case .petted: happiness += 0.08
        case .treat: happiness += 0.10; energy += 0.05
        case .clicked: happiness += 0.02
        case .pouted: happiness -= 0.05
        case .lonely: happiness -= 0.02
        case .exertion: energy -= 0.05
        case .played: happiness += 0.04; energy -= 0.02
        }
        clamp()
    }

    private mutating func clamp() {
        happiness = min(max(happiness, 0), 1)
        energy = min(max(energy, 0), 1)
    }

    public var emoji: String {
        switch happiness {
        case ..<0.3: return "😞"
        case ..<0.5: return "😐"
        case ..<0.8: return "😊"
        default: return "😄"
        }
    }
    public var energyBar: String {
        let filled = Int((energy * 5).rounded())
        return String(repeating: "▮", count: filled) + String(repeating: "▯", count: 5 - filled)
    }
}
