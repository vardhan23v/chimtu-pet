"""pytest suite for windows/chimtu_core.py. Mirrors Sources/ChimtuCoreChecks so the
two implementations cannot drift apart silently."""
import json, math, os, random, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "windows"))
import chimtu_core as c


def state_of(d): return d[1] if d[0] == "enter" else d[0]


def test_obligation_order():
    rng = random.Random(1)
    assert c.choose_next(c.Context("idle", focus_active=True, music_playing=True), rng) == ("enter", "focus", 0, None)
    assert c.choose_next(c.Context("idle", music_playing=True), rng) == ("enter", "groove", 0, None)
    assert state_of(c.choose_next(c.Context("sleep"), rng)) in ("yawn", "stretch")
    assert state_of(c.choose_next(c.Context("sad"), rng)) == "sleep"
    assert c.choose_next(c.Context("idle", user_idle=301), rng) == ("enter", "sad", 3, None)


def test_distribution_matches_weight_table():
    rng = random.Random(42); n = 100_000; hist = {}
    for _ in range(n):
        s = state_of(c.choose_next(c.Context("idle"), rng)); hist[s] = hist.get(s, 0) + 1
    share = lambda s: hist.get(s, 0) / n
    assert abs(share("idle") - 0.42) < 0.01
    assert abs(share("sit") - 0.22) < 0.01
    assert abs(share("sleep") - 0.12) < 0.01
    assert abs(share("scratch") - 0.06) < 0.005
    assert abs(share("walk") - 0.035) < 0.005
    assert abs(share("zoomies") - 0.01) < 0.003


def test_night_and_battery_and_energy():
    rng = random.Random(7)
    decisions = [c.choose_next(c.Context("idle", night=True), rng) for _ in range(20_000)]
    assert not any(d[0] == "zoomies" for d in decisions)
    assert any(d[0] == "enter" and d[1] == "sleep" and d[2] >= 90 for d in decisions)
    low = [c.choose_next(c.Context("idle", battery_low=True), rng) for _ in range(5000)]
    assert not any(d[0] == "enter" and d[1] == "idle" and d[2] > 4 for d in low)
    assert sum(1 for d in low if d[0] == "enter" and d[1] == "tired") > 1000
    def sleep_share(e):
        r = random.Random(9)
        return sum(1 for _ in range(20_000) if state_of(c.choose_next(c.Context("idle", mood=c.Mood(energy=e)), r)) == "sleep") / 20_000
    assert sleep_share(0.1) > sleep_share(1.0) + 0.1


def test_edges_force_walk_direction():
    rng = random.Random(5)
    for _ in range(2000):
        d = c.choose_next(c.Context("idle", near_left=True), rng)
        if d[0] == "walk": assert d[1] == 1
        d = c.choose_next(c.Context("idle", near_right=True), rng)
        if d[0] == "walk": assert d[1] == -1


def test_reaction_gate():
    g = c.ReactionGate(); t0 = 1000.0
    assert g.allows(t0, "idle", t0)
    g.record(t0)
    assert not g.allows(t0 + 1.0, "idle", t0)
    assert g.allows(t0 + 1.6, "idle", t0)
    assert g.allows(t0 + 0.1, "idle", t0, force=True)
    assert not g.allows(t0 + 5, "wave", t0 + 6)
    assert g.allows(t0 + 5, "wave", t0 + 6, force=True)
    assert not g.allows(t0 + 5, "held", 1e18, force=True)


def test_burst_counter():
    b = c.BurstCounter(*c.BURSTS["tickle"]); t0 = 100.0
    assert not b.record(t0) and not b.record(t0 + 0.5) and not b.record(t0 + 1.0)
    assert b.record(t0 + 1.5) and b.times == []
    p = c.BurstCounter(*c.BURSTS["pout"]); p.record(t0); p.record(t0 + 1)
    assert not p.record(t0 + 20) and len(p.times) == 1


def test_mood():
    m = c.Mood(happiness=1.0, energy=0.5, updatedAt=0.0)
    m.integrate(7200, asleep=False)
    assert abs(m.happiness - (0.6 + 0.4 * math.exp(-1))) < 1e-3
    assert abs(m.energy - (0.5 - 0.00003 * 7200)) < 1e-3
    m.integrate(86400, asleep=True); assert m.energy == 1.0
    for _ in range(50): m.apply("pouted")
    assert m.happiness == 0 and m.energy_bar == "▮▮▮▮▮"


def test_state_store_roundtrip_and_quarantine(tmp_path):
    path = str(tmp_path / "state.json"); store = c.StateStore(path)
    s = c.PetState(); s.totals.pets = 7; s.streakDays = 3; store.save(s)
    back = store.load(); assert back.totals.pets == 7 and back.streakDays == 3
    with open(path, "w") as f: f.write("not json")
    fresh = store.load()
    assert fresh.totals == c.Totals() and os.path.exists(path + ".bad") and not os.path.exists(path)


def test_launch_greeting_and_streak():
    s = c.PetState(); day1 = 1_700_000_000.0
    assert s.register_launch(day1)[0] is None and s.streakDays == 1
    assert s.register_launch(day1 + 3600)[0] == "backAlready" and s.streakDays == 1
    assert s.register_launch(day1 + 86_460)[0] == "missedYou" and s.streakDays == 2
    s.register_launch(day1 + 86_460 + 3 * 86_400); assert s.streakDays == 1 and s.totals.launches == 4


def test_phrases(tmp_path):
    p = c.Phrases().overlaying({"bark": ["WOOF"], "empty": []})
    assert p.pick("bark") == "WOOF" and p.pick("empty") == "empty"
    assert p.pick("appSwitch", app="Safari") == "Safari?"
    assert c.Phrases.greeting_key(8) == "morning" and c.Phrases.greeting_key(23) == "lateNight"
    bad = tmp_path / "phrases.json"; bad.write_text("{ nope")
    assert c.Phrases.load(str(bad)).lines == c.DEFAULT_PHRASES


def test_weights_match_swift_source():
    """Guard against drift: parse the numbers out of Behaviour.swift and compare."""
    src = open(os.path.join(os.path.dirname(__file__), "..", "Sources", "ChimtuCore", "Behaviour.swift")).read()
    import re
    for name, value in c.WEIGHTS.items():
        m = re.search(rf"static let {name} = ([0-9.]+)", src)
        assert m, name
        assert float(m.group(1)) == value, name
    assert float(re.search(r"reactionCooldown: TimeInterval = ([0-9.]+)", src).group(1)) == c.REACTION_COOLDOWN
    assert float(re.search(r"lonelyAfter: TimeInterval = ([0-9.]+)", src).group(1)) == c.LONELY_AFTER
