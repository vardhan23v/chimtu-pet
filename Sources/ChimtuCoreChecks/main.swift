import Foundation
import ChimtuCore

// Minimal assertion harness (no XCTest with Command Line Tools).
var failures = 0, checks = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: String = #file, line: Int = #line) {
    checks += 1
    if !cond() { failures += 1; print("FAIL \(URL(fileURLWithPath: file).lastPathComponent):\(line) \(msg)") }
}
func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
func stateName(_ d: Decision) -> String {
    switch d { case .enter(let s, _, _): return s; case .walk: return "walk"; case .zoomies: return "zoomies" }
}

// MARK: Brain
do {
    var rng = SeededRNG(1)
    check(Brain.chooseNext(BrainContext(current: "idle", focusActive: true, musicPlaying: true), rng: &rng) == .enter("focus", 0), "focus beats music")
    check(Brain.chooseNext(BrainContext(current: "idle", musicPlaying: true), rng: &rng) == .enter("groove", 0), "music → groove")
    check(["yawn", "stretch"].contains(stateName(Brain.chooseNext(BrainContext(current: "sleep"), rng: &rng))), "wake → yawn/stretch")
    check(stateName(Brain.chooseNext(BrainContext(current: "sad"), rng: &rng)) == "sleep", "sad → sleep")
    check(Brain.chooseNext(BrainContext(current: "idle", userIdleSeconds: 301), rng: &rng) == .enter("sad", 3), "lonely → sad")

    var hist: [String: Int] = [:]; let n = 100_000
    for _ in 0..<n { hist[stateName(Brain.chooseNext(BrainContext(current: "idle"), rng: &rng)), default: 0] += 1 }
    func share(_ s: String) -> Double { Double(hist[s, default: 0]) / Double(n) }
    check(near(share("idle"), 0.42, 0.01), "idle share \(share("idle"))")
    check(near(share("sit"), 0.22, 0.01), "sit share \(share("sit"))")
    check(near(share("sleep"), 0.12, 0.01), "sleep share \(share("sleep"))")
    check(near(share("scratch"), 0.06, 0.005), "scratch share \(share("scratch"))")
    check(near(share("walk"), 0.035, 0.005), "walk share \(share("walk"))")
    check(near(share("zoomies"), 0.01, 0.003), "zoomies share \(share("zoomies"))")

    var sawZoomies = false, longSleep = false
    for _ in 0..<20_000 {
        let d = Brain.chooseNext(BrainContext(current: "idle", isNight: true), rng: &rng)
        if case .zoomies = d { sawZoomies = true }
        if case .enter("sleep", let t, _) = d, t >= 90 { longSleep = true }
    }
    check(!sawZoomies, "no zoomies at night"); check(longSleep, "long sleeps at night")

    var idle = 0, tired = 0
    for _ in 0..<5000 {
        switch Brain.chooseNext(BrainContext(current: "idle", batteryLow: true), rng: &rng) {
        case .enter("idle", let t, _) where t > 4: idle += 1
        case .enter("tired", _, _): tired += 1
        default: break
        }
    }
    check(idle == 0 && tired > 1000, "low battery → tired (\(idle)/\(tired))")

    func sleepShare(_ energy: Double) -> Double {
        var r = SeededRNG(9); var s = 0
        for _ in 0..<20_000 { if stateName(Brain.chooseNext(BrainContext(current: "idle", mood: Mood(energy: energy)), rng: &r)) == "sleep" { s += 1 } }
        return Double(s) / 20_000
    }
    check(sleepShare(0.1) > sleepShare(1.0) + 0.1, "low energy sleeps more")

    for _ in 0..<2000 {
        if case .walk(let dir, _) = Brain.chooseNext(BrainContext(current: "idle", nearLeftEdge: true), rng: &rng) { check(dir == 1, "left edge walks right") }
        if case .walk(let dir, _) = Brain.chooseNext(BrainContext(current: "idle", nearRightEdge: true), rng: &rng) { check(dir == -1, "right edge walks left") }
    }
}

// MARK: ReactionGate
do {
    var gate = ReactionGate()
    let t0 = Date(timeIntervalSince1970: 1000)
    check(gate.allows(now: t0, current: "idle", currentEndsAt: t0, force: false), "fresh gate allows")
    gate.record(now: t0)
    check(!gate.allows(now: t0.addingTimeInterval(1.0), current: "idle", currentEndsAt: t0, force: false), "cooldown blocks")
    check(gate.allows(now: t0.addingTimeInterval(1.6), current: "idle", currentEndsAt: t0, force: false), "cooldown expires")
    check(gate.allows(now: t0.addingTimeInterval(0.1), current: "idle", currentEndsAt: t0, force: true), "force bypasses cooldown")
    check(!gate.allows(now: t0.addingTimeInterval(5), current: "wave", currentEndsAt: t0.addingTimeInterval(6), force: false), "gesture blocks")
    check(gate.allows(now: t0.addingTimeInterval(5), current: "wave", currentEndsAt: t0.addingTimeInterval(6), force: true), "force interrupts gesture")
    check(!gate.allows(now: t0.addingTimeInterval(5), current: "held", currentEndsAt: .distantFuture, force: true), "held never interrupted")
}

// MARK: BurstCounter
do {
    var tickle = BurstCounter(Behaviour.Bursts.tickle)
    let t0 = Date()
    check(!tickle.record(now: t0), "1"); check(!tickle.record(now: t0.addingTimeInterval(0.5)), "2")
    check(!tickle.record(now: t0.addingTimeInterval(1.0)), "3")
    check(tickle.record(now: t0.addingTimeInterval(1.5)), "4th click within 2 s fires")
    check(tickle.times.isEmpty, "counter resets after firing")
    var pout = BurstCounter(Behaviour.Bursts.pout)
    pout.record(now: t0); pout.record(now: t0.addingTimeInterval(1))
    check(!pout.record(now: t0.addingTimeInterval(20)), "old events expire")
    check(pout.times.count == 1, "only the fresh event remains")
}

// MARK: Mood
do {
    let t0 = Date(timeIntervalSince1970: 0)
    var m = Mood(happiness: 1.0, energy: 0.5, updatedAt: t0)
    m.integrate(to: t0.addingTimeInterval(2 * 3600), asleep: false)
    check(near(m.happiness, 0.6 + 0.4 * exp(-1), 0.001), "happiness decays with tau 2h")
    check(near(m.energy, 0.5 - 0.00003 * 7200, 0.001), "energy drains awake")
    m.integrate(to: t0.addingTimeInterval(24 * 3600), asleep: true)
    check(m.energy == 1.0, "energy clamps at 1")
    for _ in 0..<50 { m.apply(.pouted) }
    check(m.happiness == 0, "happiness clamps at 0")
    check(m.energyBar == "▮▮▮▮▮", "energy bar")
}

// MARK: PetState / StateStore
do {
    func tempURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("chimtu-check-\(UUID().uuidString)/state.json") }
    let store = StateStore(url: tempURL())
    var s = PetState(); s.totals.pets = 7; s.streakDays = 3
    try store.save(s)
    check(store.load().totals.pets == 7 && store.load().streakDays == 3, "round trip")

    let url = tempURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "not json".data(using: .utf8)!.write(to: url)
    let fresh = StateStore(url: url).load()
    check(fresh.totals == Totals() && fresh.streakDays == 0, "corrupt → defaults")
    check(FileManager.default.fileExists(atPath: url.appendingPathExtension("bad").path), "corrupt file quarantined")
    check(!FileManager.default.fileExists(atPath: url.path), "corrupt file moved away")

    var p = PetState()
    let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    check(p.registerLaunch(at: day1).greeting == nil, "first launch has no greeting")
    check(p.streakDays == 1, "streak starts at 1")
    check(p.registerLaunch(at: day1.addingTimeInterval(3600)).greeting == "backAlready", "short gap → backAlready")
    check(p.streakDays == 1, "same day keeps streak")
    let day2 = day1.addingTimeInterval(86_400 + 60)
    check(p.registerLaunch(at: day2).greeting == "missedYou", ">8h → missedYou")
    check(p.streakDays == 2, "next day extends streak")
    p.registerLaunch(at: day2.addingTimeInterval(3 * 86_400))
    check(p.streakDays == 1, "gap breaks streak")
    check(p.totals.launches == 4, "launch count")
}

// MARK: Phrases
do {
    let p = Phrases().overlaying(["bark": ["WOOF"], "empty": []])
    check(p.pick("bark") == "WOOF", "overlay replaces")
    check(p.pick("empty") == "empty", "empty arrays ignored → key fallback")
    check(p.pick("appLaunch", ["app": "Safari"]) == "Ooh, Safari!", "placeholder substitution")
    check(Phrases.greetingKey(hour: 8) == "morning" && Phrases.greetingKey(hour: 23) == "lateNight", "greeting keys")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("phrases-\(UUID().uuidString).json")
    try "{ nope".data(using: .utf8)!.write(to: url)
    check(Phrases.load(bundled: nil, user: url) == Phrases(), "malformed user file ignored")
}

print(failures == 0 ? "OK: \(checks) checks passed" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
