#!/usr/bin/env python3
"""Chimtu for Windows: the same Shiba desktop pet, in Tk.

UI only. All behaviour (state selection, reaction gating, mood, persistence,
phrases) lives in chimtu_core.py, which mirrors the Swift ChimtuCore module.
Battery: one `after()` timer at the current animation's frame rate, frames
pre-loaded as PhotoImages, a 60 Hz mover only while chasing the cursor.
Right-click Chimtu for the menu.
"""
import math, os, random, sys, time, tkinter as tk
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chimtu_core as core

IS_WIN = sys.platform.startswith("win")
KEY = "#ff00fe"   # transparent colour key (never appears in the art)

def resource_dir(sub):
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    for cand in (os.path.join(base, sub), os.path.join(base, "..", "Resources", sub)):
        if os.path.isdir(cand): return cand
    return None

SPECS = {  # name: (frames, fps) — mirrors Sprites.specs
    "idle": (6, 4), "idle_left": (6, 4), "idle_right": (6, 4),
    "walk_right": (6, 12), "walk_left": (6, 12), "run_right": (6, 16), "run_left": (6, 16),
    "sit": (4, 3), "sleep": (2, 1), "wave": (4, 6), "jump": (6, 10), "scratch": (6, 6), "yawn": (6, 4),
    "alert": (6, 6), "happy": (6, 8), "held": (4, 4), "land": (4, 10), "spin": (6, 7), "dance": (6, 8),
    "shake": (6, 12), "sad": (6, 3), "tired": (6, 3), "eat": (6, 6), "love": (6, 6), "howl": (6, 5),
    "sneeze": (6, 8), "dig": (6, 8), "roll": (6, 6), "sniff": (6, 8), "fetch": (6, 6), "bark": (6, 8), "beg": (6, 4),
    "typing": (6, 10), "groove": (6, 8), "focus": (6, 3), "wink": (4, 6), "celebrate": (6, 10),
    "stretch": (6, 5), "peek": (6, 5), "think": (6, 3), "laugh": (6, 10), "pout": (6, 3), "salute": (6, 6), "hiccup": (6, 9), "chase": (6, 10),
}
HATS = ["none", "party", "cap", "crown", "beanie", "bow", "flower"]
SOUND_TABLE = {"bark": ("bark", False), "beg": ("yip", False), "love": ("yip", False), "wink": ("yip", False), "howl": ("awoo", False),
               "sniff": ("sniff", False), "sleep": ("snore", False), "jump": ("boing", True), "land": ("boing", True),
               "eat": ("chomp", False), "celebrate": ("ding", False)}
BASE_W, BASE_H, BUBBLE = 224, 192, 40


class Chimtu:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Chimtu")
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg=KEY)
        if IS_WIN:
            self.root.attributes("-transparentcolor", KEY)
            try: self.root.attributes("-toolwindow", True)
            except tk.TclError: pass

        self.store = core.StateStore(core.StateStore.default_path())
        self.state = self.store.load()
        self.prefs = self.state.prefs
        self.phrases = core.Phrases.load(os.path.join(os.path.dirname(self.store.path), "phrases.json"))
        self.rng = random.Random()
        self.zoom = int(self.prefs.get("zoom", 1))          # 1 = normal, 2 = huge; -2 = small (subsample)
        self.W, self.H = self.scaled(BASE_W), self.scaled(BASE_H) + BUBBLE
        self.SPRITE_Y = BUBBLE

        self.canvas = tk.Canvas(self.root, width=self.W, height=self.H, bg=KEY, highlightthickness=0, bd=0)
        self.canvas.pack()
        self.item = self.canvas.create_image(0, self.SPRITE_Y, anchor="nw")
        self.hat_item = self.canvas.create_image(0, self.SPRITE_Y, anchor="nw", state="hidden")
        self.bubble_bg = self.canvas.create_rectangle(0, 0, 0, 0, fill="white", outline="#de9652", width=2, state="hidden")
        self.bubble_tx = self.canvas.create_text(0, 0, text="", font=("Segoe UI", 10, "bold"), fill="#4d3320", state="hidden")
        self.bubble_after = None

        self.load_frames(self.prefs.get("skin", "shiba"))
        self.hat_images = {}
        self.set_hat(self.prefs.get("hat", "none"), announce=False)

        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        self.x, self.y = (sw - self.W) // 2, sh - self.H - 48
        self.place()

        self.cur, self.frame, self.ends, self.started = "idle", 0, 0.0, time.time()
        self.follow = False; self.visible = True; self.dragging = False
        self.vx = self.vy = 0.0; self.moving = False
        self.walk_dir = 1; self.click_count = 0
        self.gate = core.ReactionGate()
        self.b = {k: core.BurstCounter(*v) for k, v in core.BURSTS.items()}
        self.keys = core.BurstCounter(10**9, core.BURSTS["typing"][1])
        self.last_mouse = self.mouse(); self.last_move = time.time()
        self.clip = self.clipboard(); self.fg_window = self.foreground()
        self.focus_until = 0.0; self.zoom_until = 0.0; self.music = False
        self.press_t = 0.0; self.press_pos = (0, 0); self.press_origin = (0, 0)
        self.after_id = None; self.dirty = False; self.last_sound = 0.0
        self.session_minutes_mark = time.time()

        c = self.canvas
        c.bind("<ButtonPress-1>", self.on_press); c.bind("<B1-Motion>", self.on_drag); c.bind("<ButtonRelease-1>", self.on_release)
        c.bind("<Double-Button-1>", lambda e: self.enter("jump", 0.6, user=True))
        c.bind("<Button-3>", self.popup); c.bind("<Button-2>", self.popup)
        self.build_menu()
        self.enter("idle", 6)
        self.greet()
        self.schedule_hourly()
        self.root.protocol("WM_DELETE_WINDOW", self.quit)

    # ---------- assets
    def scaled(self, v): return v * self.zoom if self.zoom > 0 else v // -self.zoom
    def load_frames(self, skin):
        d = resource_dir(os.path.join("frames", skin)) or resource_dir("frames")
        if not d: raise SystemExit("Chimtu could not find his sprite frames.")
        self.anim = {}
        for name, (n, fps) in SPECS.items():
            frames = []
            for i in range(n):
                p = os.path.join(d, f"{name}_{i:02d}.png")
                if os.path.exists(p): frames.append(self.scale_image(tk.PhotoImage(file=p)))
            if frames: self.anim[name] = (frames, fps)
        self.frames_dir = d
    def scale_image(self, img):
        if self.zoom > 1: return img.zoom(self.zoom)
        if self.zoom < 0: return img.subsample(-self.zoom)
        return img
    def set_hat(self, name, announce=True):
        self.prefs["hat"] = name; self.dirty = True
        if name == "none": self.canvas.itemconfig(self.hat_item, state="hidden"); self.hat = None; return
        p = os.path.join(self.frames_dir, f"hat_{name}.png")
        if not os.path.exists(p): return
        self.hat = self.scale_image(tk.PhotoImage(file=p)); self.hat_images[name] = self.hat
        self.canvas.itemconfig(self.hat_item, image=self.hat, state="normal")
        if announce: self.enter("happy", 1.2); self.say(self.phrases.pick("fancy"))
    def set_zoom(self, z):
        self.prefs["zoom"] = z; self.dirty = True; self.save()
        self.say("Restart me to resize" if z != self.zoom else "Already this size")
    def set_skin(self, skin):
        self.prefs["skin"] = skin; self.dirty = True
        self.load_frames(skin); self.set_hat(self.prefs.get("hat", "none"), announce=False)
        self.enter("idle", 3)

    # ---------- helpers
    def mouse(self): return self.root.winfo_pointerxy()
    def place(self): self.root.geometry(f"{self.W}x{self.H}+{int(self.x)}+{int(self.y)}")
    def clipboard(self):
        try: return self.root.clipboard_get()
        except tk.TclError: return None
    def foreground(self):
        if not IS_WIN: return None
        import ctypes; return ctypes.windll.user32.GetForegroundWindow()
    def foreground_title(self):
        if not IS_WIN: return ""
        import ctypes
        h = ctypes.windll.user32.GetForegroundWindow(); n = ctypes.windll.user32.GetWindowTextLengthW(h)
        buf = ctypes.create_unicode_buffer(n + 1); ctypes.windll.user32.GetWindowTextW(h, buf, n + 1)
        return buf.value.split(" - ")[-1].split(" — ")[-1].strip()[:18]
    def battery_low(self):
        if not IS_WIN: return False
        import ctypes
        class S(ctypes.Structure):
            _fields_ = [("ACLineStatus", ctypes.c_byte), ("BatteryFlag", ctypes.c_byte), ("BatteryLifePercent", ctypes.c_byte),
                        ("Reserved1", ctypes.c_byte), ("BatteryLifeTime", ctypes.c_ulong), ("BatteryFullLifeTime", ctypes.c_ulong)]
        s = S(); ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(s))
        return s.ACLineStatus == 0 and 0 <= s.BatteryLifePercent < 20
    def keys_down(self):
        if not IS_WIN: return 0, False, False
        import ctypes
        g = ctypes.windll.user32.GetAsyncKeyState
        n = sum(1 for vk in list(range(0x30, 0x5B)) + [0x20] + list(range(0xBA, 0xC0)) if g(vk) & 0x8000)
        return n, bool(g(0x0D) & 0x0001), bool(g(0x08) & 0x0001)
    def night(self):
        return core.is_night(time.localtime().tm_hour, int(self.prefs.get("quietStart", 23)), int(self.prefs.get("quietEnd", 6)))
    def say(self, text, seconds=2.5):
        c = self.canvas
        c.itemconfig(self.bubble_tx, text=text, state="normal")
        x0, y0, x1, y1 = c.bbox(self.bubble_tx)
        w = min(max(x1 - x0 + 18, 40), self.W)
        c.coords(self.bubble_bg, (self.W - w) / 2, 6, (self.W + w) / 2, 32); c.coords(self.bubble_tx, self.W / 2, 19)
        c.itemconfig(self.bubble_bg, state="normal"); c.tag_raise(self.bubble_bg); c.tag_raise(self.bubble_tx)
        if self.bubble_after: self.root.after_cancel(self.bubble_after)
        self.bubble_after = self.root.after(int(seconds * 1000), lambda: [c.itemconfig(i, state="hidden") for i in (self.bubble_bg, self.bubble_tx)])
    def sound(self, clip, force=False):
        if not self.prefs.get("sounds", False) or not IS_WIN: return
        now = time.time()
        if not force and now - self.last_sound < 6: return
        d = resource_dir("sounds")
        if not d: return
        self.last_sound = now
        import winsound
        winsound.PlaySound(os.path.join(d, clip + ".wav"), winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT)
    def mood(self, event):
        self.state.mood.integrate(time.time(), asleep=self.cur == "sleep"); self.state.mood.apply(event); self.dirty = True
    def save(self):
        if not self.dirty: return
        self.state.mood.integrate(time.time(), asleep=self.cur == "sleep")
        self.state.totals.minutes += (time.time() - self.session_minutes_mark) / 60; self.session_minutes_mark = time.time()
        self.state.lastSeen = time.time(); self.state.prefs = self.prefs
        try: self.store.save(self.state); self.dirty = False
        except OSError: pass
    def greet(self):
        key, away = self.state.register_launch(); self.dirty = True
        def go():
            if key == "missedYou":
                self.enter("happy", 1.5); days = int(away / 24)
                self.say(self.phrases.pick("missedYou") + (f" ({days}d)" if days else ""))
            else:
                self.say(self.phrases.pick(key or core.Phrases.greeting_key(time.localtime().tm_hour)))
        self.root.after(1000, go)

    # ---------- state machine
    def enter(self, name, seconds, user=False):
        if name not in self.anim: return
        was_asleep = self.cur == "sleep"
        if was_asleep != (name == "sleep"): self.state.mood.integrate(time.time(), asleep=was_asleep)
        self.cur, self.frame, self.started = name, 0, time.time()
        self.ends = time.time() + seconds if seconds > 0 else float("inf")
        self.schedule(); self.tick()
        if name in SOUND_TABLE:
            clip, user_only = SOUND_TABLE[name]
            if (not user_only or user) and not (self.night() or self.focus_until > time.time()): self.sound(clip)

    def schedule(self):
        if self.after_id: self.root.after_cancel(self.after_id); self.after_id = None
        if not self.visible: return
        self.after_id = self.root.after(int(1000 / self.anim[self.cur][1]), self.tick)

    def react(self, name, seconds, line=None, force=False):
        now = time.time()
        if not self.visible or self.dragging: return False
        if not self.gate.allows(now, self.cur, self.ends, force): return False
        self.gate.record(now); self.enter(name, seconds)
        if line: self.say(line)
        return True

    def next_state(self):
        now = time.time()
        self.state.mood.integrate(now, asleep=self.cur == "sleep")
        if now < self.zoom_until: return
        sw = self.root.winfo_screenwidth()
        ctx = core.Context(self.cur, state_age=now - self.started, focus_active=self.focus_until > now, music_playing=self.music,
                           user_idle=now - self.last_move, night=self.night(), battery_low=self.battery_low(),
                           near_left=self.x < 40, near_right=self.x > sw - self.W - 40, mood=self.state.mood)
        d = core.choose_next(ctx, self.rng)
        if d[0] == "enter":
            _, name, secs, key = d
            if name == "sad" and ctx.user_idle > core.LONELY_AFTER: self.mood("lonely")
            self.enter(name, secs)
            if key and not (int(self.prefs.get("chattiness", 1)) == 0 and key == "idle"): self.say(self.phrases.pick(key))
        elif d[0] == "walk":
            self.walk_dir = d[1]; self.enter("walk_right" if d[1] > 0 else "walk_left", d[2])
        else:
            self.zoomies()

    def tick(self):
        self.after_id = None
        now = time.time()
        mx, my = self.mouse()
        if (mx, my) != self.last_mouse: self.last_mouse = (mx, my); self.last_move = now
        busy = core.gesture_active(self.cur, self.ends, now)

        clip = self.clipboard()
        if clip != self.clip:
            self.clip = clip
            if self.cur != "sleep" and not busy and not self.dragging:
                if isinstance(clip, str) and len(clip) > 200: self.enter("think", 2.0); self.say(self.phrases.pick("think"))
                else: self.enter("sniff", 1.2); self.say(self.phrases.pick("sniff"))

        n, enter_key, back = self.keys_down()
        if n: self.state.totals.keys += n
        for _ in range(n): self.keys.record(now)
        if enter_key and (self.cur == "typing" or self.cur.startswith("idle")) and not self.dragging:
            self.react("jump", 0.6, self.phrases.pick("sent"))
        elif back and self.b["deletes"].record(now):
            self.react("sad", 1.5, self.phrases.pick("oops"))
        elif self.keys.count(core.BURSTS["typing"][1], now) >= core.BURSTS["typing"][0] and self.cur != "typing" and not busy and self.cur not in core.TYPING_BLOCKED and not self.dragging:
            self.enter("typing", 4); self.say(self.phrases.pick("typing"))
        elif self.cur == "typing" and n:
            self.ends = now + 3

        fg = self.foreground()
        if fg != self.fg_window:
            self.fg_window = fg
            t = self.foreground_title()
            self.react("alert", 1.1, f"{t}?" if t and random.random() < 0.5 else None)

        if self.cur.startswith("idle"):
            dx = mx - (self.x + self.W / 2)
            want = "idle_left" if dx < -60 else "idle_right" if dx > 60 else "idle"
            if want != self.cur and want in self.anim: self.cur = want
        frames, fps = self.anim[self.cur]
        self.canvas.itemconfig(self.item, image=frames[self.frame % len(frames)])
        self.canvas.itemconfig(self.hat_item, state="hidden" if (self.cur in core.HAT_HIDDEN or not getattr(self, "hat", None)) else "normal")
        self.frame = (self.frame + 1) % len(frames)

        if self.follow and not self.dragging:
            if not busy: self.follow_tick(mx, my)
        elif self.cur.startswith("run") and now < self.zoom_until:
            self.x += self.walk_dir * 14; sw = self.root.winfo_screenwidth()
            if self.x < 0: self.x = 0; self.walk_dir = 1; self.cur = "run_right"
            if self.x > sw - self.W: self.x = sw - self.W; self.walk_dir = -1; self.cur = "run_left"
            self.place()
        elif self.cur.startswith("walk"):
            self.x += self.walk_dir * 2.5; self.place()
        if now >= self.ends and not self.dragging:
            if self.follow: self.enter("idle", 0)
            else: return self.next_state()
        self.schedule()

    # ---------- follow cursor
    def follow_tick(self, mx, my):
        dx, dy = mx - (self.x + self.W / 2), my - (self.y + self.SPRITE_Y + self.scaled(BASE_H) / 2)
        if abs(dx) < 50 and abs(dy) < 60:
            self.stop_mover()
            if not self.cur.startswith("idle"): self.cur, self.frame, self.ends = "idle", 0, float("inf")
            return
        self.start_mover()
        want = f"{'run' if math.hypot(dx, dy) > 260 else 'walk'}_{'right' if dx > 0 else 'left'}"
        if self.cur != want: self.cur, self.frame, self.ends = want, 0, float("inf")
    def start_mover(self):
        if not self.moving: self.moving = True; self.move_step()
    def stop_mover(self): self.moving = False; self.vx = self.vy = 0.0
    def move_step(self):
        if not self.moving or not self.follow: self.moving = False; return
        mx, my = self.mouse(); dt = 1 / 60
        dx, dy = mx - (self.x + self.W / 2), my - (self.y + self.H / 2)
        k = 30; c = 2 * math.sqrt(k)
        self.vx += (k * dx - c * self.vx) * dt; self.vy += (k * dy - c * self.vy) * dt
        sp = math.hypot(self.vx, self.vy)
        if sp > 900: self.vx *= 900 / sp; self.vy *= 900 / sp
        self.x += self.vx * dt; self.y += self.vy * dt
        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        self.x = min(max(self.x, 0), sw - self.W); self.y = min(max(self.y, 0), sh - self.H)
        self.place(); self.root.after(16, self.move_step)

    # ---------- mouse
    def on_press(self, e):
        self.press_t = time.time(); self.press_pos = (e.x_root, e.y_root); self.press_origin = (self.x, self.y)
    def on_drag(self, e):
        if not self.dragging:
            if abs(e.x_root - self.press_pos[0]) + abs(e.y_root - self.press_pos[1]) < 4: return
            self.dragging = True; self.stop_mover(); self.enter("held", 0)
        self.x = self.press_origin[0] + e.x_root - self.press_pos[0]
        self.y = self.press_origin[1] + e.y_root - self.press_pos[1]; self.place()
    def on_release(self, e):
        now = time.time()
        if self.dragging:
            self.dragging = False
            if self.b["pout"].record(now): self.mood("pouted"); self.say(self.phrases.pick("pout")); return self.enter("pout", 2.5)
            return self.enter("land", 0.45, user=True)
        if now - self.press_t > 0.5:
            self.state.totals.pets += 1; self.mood("petted"); self.say(self.phrases.pick("love")); return self.enter("love", 2.0)
        self.click_count += 1; self.state.totals.clicks += 1; self.mood("clicked")
        if self.b["shy"].record(now): self.b["tickle"].reset(); self.say(self.phrases.pick("shy")); return self.enter("peek", 2.5)
        if self.b["tickle"].record(now): self.say(self.phrases.pick("tickle")); return self.enter("laugh", 1.5)
        self.enter("happy" if self.click_count % 2 == 0 else "wave", 1.2)

    # ---------- commands
    def zoomies(self):
        self.mood("exertion"); self.zoom_until = time.time() + 3.5; self.walk_dir = random.choice([1, -1])
        self.enter("run_right" if self.walk_dir > 0 else "run_left", 3.5); self.say(self.phrases.pick("zoomies"))
    def treat(self): self.state.totals.treats += 1; self.mood("treat"); self.enter("eat", 2.5)
    def start_focus(self, minutes=25):
        self.focus_until = time.time() + minutes * 60
        self.enter("focus", 0); self.say(self.phrases.pick("focusStart", minutes=minutes))
        self.root.after(minutes * 30 * 1000, lambda: self.say(self.phrases.pick("focusHalf")) if self.focus_until > time.time() else None)
        def done():
            self.focus_until = 0; self.enter("celebrate", 3); self.say(self.phrases.pick("focusDone")); self.sound("ding", force=True)
        self.root.after(minutes * 60 * 1000, done)
    def remind(self, minutes):
        from tkinter import simpledialog
        text = simpledialog.askstring("Chimtu", f"Remind you about what? (in {minutes} min)") or self.phrases.pick("reminder")
        self.say(self.phrases.pick("remindSet", minutes=minutes))
        self.root.after(minutes * 60 * 1000, lambda: (self.react("bark", 1.5, force=True), self.say(text, 8), self.sound("ding", force=True)))
    def hows_your_day(self):
        self.state.mood.integrate(time.time(), asleep=self.cur == "sleep")
        t = self.state.totals; mins = int(t.minutes + (time.time() - self.session_minutes_mark) / 60)
        streak = f" · day {self.state.streakDays} streak" if self.state.streakDays > 1 else ""
        self.enter("wink", 1.5); self.say(f"{self.state.mood.emoji} {self.state.mood.energy_bar} · {mins} min · {t.pets} pets · {t.treats} treats · {t.keys} keys{streak}", 5)
    def schedule_hourly(self):
        now = time.time(); nxt = (int(now // 3600) + 1) * 3600
        self.root.after(int((nxt - now) * 1000), self.hourly)
    def hourly(self):
        if self.prefs.get("hourlyHowl", True) and self.cur != "sleep" and self.focus_until < time.time() and self.visible:
            self.enter("howl", 2.0); self.say(self.phrases.pick("howl", time=time.strftime("%I %p").lstrip("0")))
        self.save(); self.schedule_hourly()
    def toggle_follow(self):
        self.follow = self.follow_var.get()
        if self.follow: self.enter("idle", 0)
        else: self.stop_mover(); self.next_state()
    def toggle_visible(self):
        self.visible = not self.visible
        if self.visible: self.root.deiconify(); self.schedule()
        else: self.root.withdraw(); self.save()
    def set_pref(self, key, value): self.prefs[key] = value; self.dirty = True; self.save()
    def quit(self): self.save(); self.root.destroy()

    # ---------- menu
    def build_menu(self):
        m = tk.Menu(self.root, tearoff=0)
        self.follow_var = tk.BooleanVar(value=False)
        m.add_checkbutton(label="Follow Cursor", variable=self.follow_var, command=self.toggle_follow)
        m.add_command(label="Hide / Show (via tray-less toggle)", command=self.toggle_visible)
        m.add_separator()
        for label, st, secs in [("Jump", "jump", 0.6), ("Dance", "dance", 2.5), ("Spin", "spin", 0.9), ("Shake", "shake", 0.6),
                                ("Roll Over", "roll", 1.2), ("Howl", "howl", 2.0), ("Bark", "bark", 1.0), ("Beg", "beg", 2.5),
                                ("Stretch", "stretch", 1.5), ("Salute", "salute", 1.5), ("Sit Down", "sit", 15), ("Go to Sleep", "sleep", 60)]:
            m.add_command(label=label, command=lambda s=st, t=secs: self.enter(s, t, user=True))
        m.add_command(label="Give Treat", command=self.treat)
        m.add_command(label="Zoomies", command=self.zoomies)
        m.add_separator()
        m.add_command(label="Start Focus (25 min)", command=self.start_focus)
        rm = tk.Menu(m, tearoff=0)
        for mins in (5, 10, 30, 60): rm.add_command(label=f"In {mins} minutes", command=lambda t=mins: self.remind(t))
        m.add_cascade(label="Remind Me", menu=rm)
        m.add_command(label="How's your day?", command=self.hows_your_day)
        hm = tk.Menu(m, tearoff=0)
        for h in HATS: hm.add_command(label=h.title(), command=lambda n=h: self.set_hat(n))
        m.add_cascade(label="Hat", menu=hm)
        sk = tk.Menu(m, tearoff=0)
        for label, key in (("Shiba (red)", "shiba"), ("Cream", "cream")): sk.add_command(label=label, command=lambda k=key: self.set_skin(k))
        m.add_cascade(label="Skin", menu=sk)
        sz = tk.Menu(m, tearoff=0)
        for label, z in (("Small", -2), ("Normal", 1), ("Huge", 2)): sz.add_command(label=label, command=lambda v=z: self.set_zoom(v))
        m.add_cascade(label="Size (restart)", menu=sz)
        self.sound_var = tk.BooleanVar(value=bool(self.prefs.get("sounds", False)))
        m.add_checkbutton(label="Sounds", variable=self.sound_var, command=lambda: self.set_pref("sounds", self.sound_var.get()))
        self.howl_var = tk.BooleanVar(value=bool(self.prefs.get("hourlyHowl", True)))
        m.add_checkbutton(label="Howl on the hour", variable=self.howl_var, command=lambda: self.set_pref("hourlyHowl", self.howl_var.get()))
        m.add_separator()
        m.add_command(label="Quit Chimtu", command=self.quit)
        self.menu = m
    def popup(self, e):
        try: self.menu.tk_popup(e.x_root, e.y_root)
        finally: self.menu.grab_release()

    def run(self): self.root.mainloop()


if __name__ == "__main__":
    Chimtu().run()
