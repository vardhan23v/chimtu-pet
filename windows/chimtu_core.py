"""Chimtu core logic for the Windows/Tk port. Mirrors Sources/ChimtuCore exactly:
same weights, thresholds, mood maths and phrase keys. Pure Python, no Tk, so it
is testable with pytest and shared with any future Linux port."""
from __future__ import annotations
import json, math, os, random, time
from dataclasses import dataclass, field, asdict

# ---------------- Behaviour constants (keep in sync with Behaviour.swift)
GESTURES = {"wave", "jump", "scratch", "yawn", "alert", "happy", "held", "land", "dance", "spin", "shake",
            "eat", "love", "howl", "sneeze", "dig", "roll", "sniff", "fetch", "bark", "beg", "typing",
            "wink", "celebrate", "stretch", "peek", "think", "laugh", "pout", "salute", "hiccup", "chase"}
HAT_HIDDEN = {"roll", "spin", "held", "sneeze", "shake"}
TYPING_BLOCKED = {"held", "focus", "groove"}
REACTION_COOLDOWN = 1.5
LONELY_AFTER = 300
BURSTS = dict(tickle=(4, 2.0), shy=(8, 5.0), pout=(3, 15.0), busy=(6, 2.0), deletes=(6, 2.0), typing=(8, 3.0), speed=(12, 3.0))
WEIGHTS = dict(idle=0.40, sit=0.22, sleep=0.12, scratch=0.06, jump=0.03, dance=0.02, spinOrShake=0.02,
               sneezeDigRoll=0.02, barkOrBeg=0.02, idleLine=0.02, wink=0.01, chase=0.015, zoomies=0.01, walk=0.035)

def is_night(hour: int, start: int = 23, end: int = 6) -> bool:
    return (hour >= start or hour < end) if start > end else (start <= hour < end)

# ---------------- Mood
BASELINE_HAPPINESS = 0.6
HAPPINESS_TAU = 2 * 3600
ENERGY_RECOVERY = 0.0002
ENERGY_DRAIN = 0.00003
MOOD_EVENTS = dict(petted=(0.08, 0), treat=(0.10, 0.05), clicked=(0.02, 0), pouted=(-0.05, 0),
                   lonely=(-0.02, 0), exertion=(0, -0.05), played=(0.04, -0.02))

@dataclass
class Mood:
    happiness: float = BASELINE_HAPPINESS
    energy: float = 1.0
    updatedAt: float = field(default_factory=time.time)

    def integrate(self, now: float, asleep: bool) -> None:
        dt = max(0.0, now - self.updatedAt)
        if dt <= 0: return
        k = math.exp(-dt / HAPPINESS_TAU)
        self.happiness = BASELINE_HAPPINESS + (self.happiness - BASELINE_HAPPINESS) * k
        self.energy += (ENERGY_RECOVERY if asleep else -ENERGY_DRAIN) * dt
        self._clamp(); self.updatedAt = now

    def apply(self, event: str) -> None:
        dh, de = MOOD_EVENTS[event]
        self.happiness += dh; self.energy += de; self._clamp()

    def _clamp(self):
        self.happiness = min(max(self.happiness, 0.0), 1.0)
        self.energy = min(max(self.energy, 0.0), 1.0)

    @property
    def emoji(self) -> str:
        return "😞" if self.happiness < 0.3 else "😐" if self.happiness < 0.5 else "😊" if self.happiness < 0.8 else "😄"
    @property
    def energy_bar(self) -> str:
        f = int(round(self.energy * 5)); return "▮" * f + "▯" * (5 - f)

# ---------------- Brain
@dataclass
class Context:
    current: str
    state_age: float = 0.0
    focus_active: bool = False
    music_playing: bool = False
    user_idle: float = 0.0
    night: bool = False
    battery_low: bool = False
    near_left: bool = False
    near_right: bool = False
    mood: Mood = field(default_factory=Mood)

def choose_next(ctx: Context, rng: random.Random):
    """Returns ('enter', state, seconds, say_key|None) | ('walk', dir, seconds) | ('zoomies',)."""
    if ctx.focus_active: return ("enter", "focus", 0, None)
    if ctx.music_playing: return ("enter", "groove", 0, None)
    if ctx.current == "sleep": return ("enter", rng.choice(["yawn", "stretch"]), 1.5, None)
    if ctx.current == "sit" and ctx.state_age > 12 and rng.random() < 0.5: return ("enter", "stretch", 1.5, None)
    if ctx.current == "eat" and rng.random() < 0.3: return ("enter", "hiccup", 2.0, "hiccup")
    if ctx.current == "sad": return ("enter", "sleep", rng.uniform(60, 180), None)
    if ctx.user_idle > LONELY_AFTER: return ("enter", "sad", 3, None)

    W = WEIGHTS
    sleep_w = W["sleep"] + 0.25 * (1 - ctx.mood.energy)
    antic = min(max(ctx.mood.happiness / BASELINE_HAPPINESS, 0.5), 1.5)
    table = [(W["idle"], "idle"), (W["sit"], "sit"), (sleep_w, "sleep"), (W["scratch"] * antic, "scratch"),
             (W["jump"] * antic, "jump"), (W["dance"] * antic, "dance"), (W["spinOrShake"] * antic, "spinOrShake"),
             (W["sneezeDigRoll"], "sneezeDigRoll"), (W["barkOrBeg"] * antic, "barkOrBeg"), (W["idleLine"] * antic, "idleLine"),
             (W["wink"] * antic, "wink"), (W["chase"] * antic, "chase"), (W["zoomies"] * antic, "zoomies"), (W["walk"], "walk")]
    total = sum(w for w, _ in table)
    roll = rng.random() * total
    slot = "walk"
    for w, name in table:
        if roll < w: slot = name; break
        roll -= w

    if slot == "idle":
        if ctx.battery_low: return ("enter", "tired", rng.uniform(5, 12), None)
        if ctx.mood.happiness < 0.3 and rng.random() < 0.3: return ("enter", "sad", 3, None)
        return ("enter", "idle", rng.uniform(5, 12), None)
    if slot == "sit": return ("enter", "sit", rng.uniform(6, 15), None)
    if slot == "sleep": return ("enter", "sleep", rng.uniform(90, 240) if ctx.night else rng.uniform(15, 40), None)
    if slot == "scratch": return ("enter", "scratch", 1.5, None)
    if slot == "jump": return ("enter", "jump", 0.6, None)
    if slot == "dance": return ("enter", "dance", 2.5, None)
    if slot == "spinOrShake": return ("enter", rng.choice(["spin", "shake"]), 0.9, None)
    if slot == "sneezeDigRoll": return ("enter", rng.choice(["sneeze", "dig", "roll"]), 1.2, None)
    if slot == "barkOrBeg":
        if ctx.night: return ("enter", "sleep", 120, None)
        return ("enter", "bark", 1.0, "bark") if rng.random() < 0.5 else ("enter", "beg", 2.5, "beg")
    if slot == "idleLine": return ("enter", "idle", 4, "idle")
    if slot == "wink": return ("enter", "wink", 1.0, None)
    if slot == "chase": return ("enter", "chase", 1.8, "chase")
    if slot == "zoomies": return ("enter", "sleep", 120, None) if ctx.night else ("zoomies",)
    d = rng.choice([1, -1])
    if ctx.near_left: d = 1
    if ctx.near_right: d = -1
    return ("walk", d, rng.uniform(2, 5))

# ---------------- ReactionGate / BurstCounter
class ReactionGate:
    def __init__(self): self.last = -1e18
    def allows(self, now, current, ends_at, force=False):
        if current == "held": return False
        if force: return True
        if now - self.last < REACTION_COOLDOWN: return False
        if current in GESTURES and now < ends_at: return False
        return True
    def record(self, now): self.last = now

def gesture_active(current, ends_at, now): return current in GESTURES and now < ends_at

class BurstCounter:
    def __init__(self, threshold, window): self.threshold, self.window, self.times = threshold, window, []
    def record(self, now=None):
        now = time.time() if now is None else now
        self.times = [t for t in self.times if now - t < self.window] + [now]
        if len(self.times) >= self.threshold: self.times = []; return True
        return False
    def count(self, within, now=None):
        now = time.time() if now is None else now
        return len([t for t in self.times if now - t < within])
    def reset(self): self.times = []

# ---------------- Persistence
@dataclass
class Totals:
    pets: int = 0; treats: int = 0; clicks: int = 0; keys: int = 0; launches: int = 0; minutes: float = 0.0

@dataclass
class PetState:
    version: int = 1
    mood: Mood = field(default_factory=Mood)
    totals: Totals = field(default_factory=Totals)
    firstLaunch: float = field(default_factory=time.time)
    lastSeen: float = field(default_factory=time.time)
    streakDays: int = 0
    lastStreakDay: str = ""
    prefs: dict = field(default_factory=dict)   # Windows has no UserDefaults; prefs ride along here

    def register_launch(self, now=None):
        now = time.time() if now is None else now
        away_h = (now - self.lastSeen) / 3600
        first = self.totals.launches == 0
        self.totals.launches += 1
        today = time.strftime("%Y-%m-%d", time.localtime(now))
        if self.lastStreakDay != today:
            try:
                last = time.mktime(time.strptime(self.lastStreakDay, "%Y-%m-%d"))
                days = round((time.mktime(time.strptime(today, "%Y-%m-%d")) - last) / 86400)
            except ValueError:
                days = None
            self.streakDays = self.streakDays + 1 if days == 1 else 1
            self.lastStreakDay = today
        self.mood.integrate(now, asleep=True)
        self.lastSeen = now
        if first: return None, 0.0
        return ("missedYou" if away_h > 8 else "backAlready"), away_h

class StateStore:
    def __init__(self, path: str): self.path = path
    @staticmethod
    def default_path() -> str:
        base = os.environ.get("APPDATA") or os.path.expanduser("~/.config")
        return os.path.join(base, "Chimtu", "state.json")
    def load(self) -> PetState:
        try:
            with open(self.path, encoding="utf-8") as f: d = json.load(f)
            s = PetState(); s.version = d.get("version", 1)
            s.mood = Mood(**d.get("mood", {})); s.totals = Totals(**d.get("totals", {}))
            for k in ("firstLaunch", "lastSeen", "streakDays", "lastStreakDay", "prefs"):
                if k in d: setattr(s, k, d[k])
            return s
        except FileNotFoundError:
            return PetState()
        except Exception:
            try: os.replace(self.path, self.path + ".bad")
            except OSError: pass
            return PetState()
    def save(self, s: PetState) -> None:
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump(asdict(s), f, indent=2, sort_keys=True)
        os.replace(tmp, self.path)

# ---------------- Phrases
DEFAULT_PHRASES = {
    "idle": ["Chimtu!", "Bow bow!", "Em chestunnav?", "Pet me?", "Zzz... no wait", "Treat unda?", "Hi hooman"],
    "bark": ["Bow!", "Bow bow!", "Chimtu!"], "beg": ["Treat?", "Pleeease", "Em chestunnav?"],
    "love": ["❤", "Good boy vibes", "Chimtuuu"], "friendHello": ["Hi!", "Bow!", "Namaste!"],
    "tickle": ["Hehehe, tickles!"], "shy": ["Shy!"], "pout": ["Hey! Put me down"], "hiccup": ["hic!"],
    "chase": ["Gotcha... almost"], "zoomies": ["ZOOMIES!"], "sniff": ["sniff sniff"], "think": ["Hmm, long one"],
    "typing": ["tak tak tak"], "sent": ["Sent!"], "oops": ["Oops?"], "speedTyper": ["Speed typer!"], "break": ["Break?"],
    "welcomeBack": ["Welcome back!"], "missedYou": ["Missed you!"], "backAlready": ["Back already?"],
    "morning": ["Morning!"], "afternoon": ["Afternoon, hooman"], "evening": ["Evening!"], "lateNight": ["Late night, hooman?"],
    "appSwitch": ["{app}?"], "busy": ["Busy busy!"], "fancy": ["Fancy!"],
    "focusStart": ["Focus: {minutes} min. Let's go!"], "focusHalf": ["Halfway. Nice."], "focusDone": ["Break time!"],
    "focusEnd": ["Focus ended"], "remindSet": ["Okay! In {minutes} min."], "reminder": ["Reminder!"], "howl": ["Awooo, it's {time}"],
}

class Phrases:
    def __init__(self, lines=None): self.lines = dict(DEFAULT_PHRASES if lines is None else lines)
    def overlaying(self, other: dict) -> "Phrases":
        m = dict(self.lines); m.update({k: v for k, v in other.items() if v}); return Phrases(m)
    @staticmethod
    def load(*paths):
        p = Phrases()
        for path in paths:
            if not path: continue
            try:
                with open(path, encoding="utf-8") as f: p = p.overlaying(json.load(f))
            except Exception: pass
        return p
    def pick(self, key, rng=random, **vars):
        line = rng.choice(self.lines[key]) if self.lines.get(key) else key
        for k, v in vars.items(): line = line.replace("{" + k + "}", str(v))
        return line
    @staticmethod
    def greeting_key(hour):
        return "morning" if 5 <= hour < 12 else "afternoon" if 12 <= hour < 17 else "evening" if 17 <= hour < 23 else "lateNight"
