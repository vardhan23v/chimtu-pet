import Foundation

/// Lifetime counters shown by "How's your day?".
public struct Totals: Codable, Equatable {
    public var pets = 0, treats = 0, clicks = 0, keys = 0, launches = 0
    public var minutes: Double = 0
    public init() {}
}

/// Everything that survives a relaunch. Versioned so future fields can migrate.
public struct PetState: Codable, Equatable {
    public var version = 1
    public var mood = Mood()
    public var totals = Totals()
    public var firstLaunch = Date()
    public var lastSeen = Date()
    public var streakDays = 0
    public var lastStreakDay = ""      // "yyyy-MM-dd" of the last day counted
    public init() {}

    /// Update streak + launch counters for a launch happening at `now`.
    /// Returns a greeting key: "missedYou", "backAlready", or nil for the very first launch.
    @discardableResult
    public mutating func registerLaunch(at now: Date = Date(), calendar: Calendar = .current) -> (greeting: String?, awayHours: Double) {
        let away = now.timeIntervalSince(lastSeen) / 3600
        let first = totals.launches == 0
        totals.launches += 1
        let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: now)
        if lastStreakDay != today {
            if let last = f.date(from: lastStreakDay), let days = calendar.dateComponents([.day], from: last, to: now).day, days == 1 {
                streakDays += 1
            } else {
                streakDays = 1
            }
            lastStreakDay = today
        }
        mood.integrate(to: now, asleep: true)   // he "slept" while the app was closed
        lastSeen = now
        if first { return (nil, 0) }
        return (away > 8 ? "missedYou" : "backAlready", away)
    }
}

/// Atomic JSON persistence with quarantine of corrupt files.
public final class StateStore {
    public let url: URL
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public init(url: URL) { self.url = url }

    /// Default location: ~/Library/Application Support/Chimtu/state.json.
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Chimtu", isDirectory: true).appendingPathComponent("state.json")
    }

    /// Never throws: a missing file yields defaults; a corrupt file is renamed to `.bad` and defaults are returned.
    public func load() -> PetState {
        guard let data = try? Data(contentsOf: url) else { return PetState() }
        do { return try decoder.decode(PetState.self, from: data) }
        catch {
            let bad = url.appendingPathExtension("bad")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: url, to: bad)
            return PetState()
        }
    }

    public func save(_ state: PetState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }
}
