#!/usr/bin/env python3
"""Chimtu for Windows: the same Shiba desktop pet, in Tk.

Shares the sprite frames rendered by tools/render_sprites.py. Designed to stay
cheap: one `after()` timer at the current animation's frame rate, frames
pre-loaded as PhotoImages, and a 60 Hz mover only while chasing the cursor.
Right-click Chimtu for the menu.
"""
import os, sys, math, random, time, tkinter as tk

IS_WIN = sys.platform.startswith("win")
KEY = "#ff00fe"   # transparent colour key (never appears in the art)

def resource_dir():
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    for cand in (os.path.join(base, "frames"), os.path.join(base, "..", "Resources", "frames")):
        if os.path.isdir(cand): return cand
    raise SystemExit("Chimtu could not find its sprite frames.")

SPECS = {  # name: (frames, fps)
    "idle": (6, 4), "idle_left": (6, 4), "idle_right": (6, 4),
    "walk_right": (6, 12), "walk_left": (6, 12), "run_right": (6, 16), "run_left": (6, 16),
    "sit": (4, 3), "sleep": (2, 1), "wave": (4, 6), "jump": (6, 10), "scratch": (6, 6), "yawn": (6, 4),
    "alert": (6, 6), "happy": (6, 8), "held": (4, 4), "land": (4, 10), "spin": (6, 7), "dance": (6, 8),
    "shake": (6, 12), "sad": (6, 3), "tired": (6, 3), "eat": (6, 6), "love": (6, 6), "howl": (6, 5),
    "sneeze": (6, 8), "dig": (6, 8), "roll": (6, 6), "sniff": (6, 8), "fetch": (6, 6), "bark": (6, 8), "beg": (6, 4), "typing": (6, 10),
}
GESTURES = {"wave", "jump", "scratch", "yawn", "alert", "happy", "held", "land", "dance", "spin",
            "shake", "eat", "love", "howl", "sneeze", "dig", "roll", "sniff", "fetch", "bark", "beg", "typing"}
W, H = 224, 192 + 40   # 40 px headroom for the speech bubble
SPRITE_Y = 40
IDLE_LINES = ["Chimtu!", "Bow bow!", "Em chestunnav?", "Pet me?", "Zzz... no wait", "Treat unda?", "Hi hooman"]

class Chimtu:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Chimtu")
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg=KEY)
        if IS_WIN:
            self.root.attributes("-transparentcolor", KEY)
            try: self.root.attributes("-toolwindow", True)   # keep off the taskbar
            except tk.TclError: pass
        self.canvas = tk.Canvas(self.root, width=W, height=H, bg=KEY, highlightthickness=0, bd=0)
        self.canvas.pack()
        self.item = self.canvas.create_image(0, SPRITE_Y, anchor="nw")
        self.bubble_bg = self.canvas.create_rectangle(0, 0, 0, 0, fill="white", outline="#de9652", width=2, state="hidden")
        self.bubble_tx = self.canvas.create_text(0, 0, text="", font=("Segoe UI", 10, "bold"), fill="#4d3320", state="hidden")
        self.bubble_after = None
        self.clip = self.clipboard()

        d = resource_dir()
        self.anim = {}
        for name, (n, fps) in SPECS.items():
            frames = [tk.PhotoImage(file=os.path.join(d, f"{name}_{i:02d}.png")) for i in range(n)]
            self.anim[name] = (frames, fps)

        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        self.x, self.y = (sw - W) // 2, sh - H - 48
        self.place()
        self.state, self.frame, self.ends = "idle", 0, 0
        self.follow = False; self.visible = True
        self.vx = self.vy = 0.0; self.moving = False
        self.walk_dir = 1; self.click_count = 0
        self.last_mouse = self.mouse(); self.last_move = time.time()
        self.press_t = 0; self.press_pos = None; self.dragging = False
        self.fg_window = self.foreground()
        self.after_id = None

        c = self.canvas
        c.bind("<ButtonPress-1>", self.on_press); c.bind("<B1-Motion>", self.on_drag); c.bind("<ButtonRelease-1>", self.on_release)
        c.bind("<Double-Button-1>", lambda e: self.enter("jump", 0.6))
        c.bind("<Button-3>", self.popup); c.bind("<Button-2>", self.popup)
        self.build_menu()
        self.enter("idle", 6)
        self.root.after(60 * 60 * 1000, self.hourly)

    # ---------- helpers
    def mouse(self): return self.root.winfo_pointerxy()
    def clipboard(self):
        try: return self.root.clipboard_get()
        except tk.TclError: return None
    def say(self, text, seconds=2.5):
        c = self.canvas
        c.itemconfig(self.bubble_tx, text=text, state="normal")
        x0, y0, x1, y1 = c.bbox(self.bubble_tx)
        w = min(max(x1 - x0 + 18, 40), W)
        c.coords(self.bubble_bg, (W - w) / 2, 6, (W + w) / 2, 32); c.coords(self.bubble_tx, W / 2, 19)
        c.itemconfig(self.bubble_bg, state="normal"); c.tag_raise(self.bubble_bg); c.tag_raise(self.bubble_tx)
        if self.bubble_after: self.root.after_cancel(self.bubble_after)
        self.bubble_after = self.root.after(int(seconds * 1000), lambda: [c.itemconfig(i, state="hidden") for i in (self.bubble_bg, self.bubble_tx)])
    def keys_down(self):
        """Count of keys currently held (letters/digits/space/punct). Windows only; cheap."""
        if not IS_WIN: return 0, False, False
        import ctypes
        g = ctypes.windll.user32.GetAsyncKeyState
        n = sum(1 for vk in list(range(0x30, 0x5B)) + [0x20] + list(range(0xBA, 0xC0)) if g(vk) & 0x8000)
        return n, bool(g(0x0D) & 0x0001), bool(g(0x08) & 0x0001)   # enter / backspace pressed since last call
    def is_night(self): h = time.localtime().tm_hour; return h >= 23 or h < 6
    def place(self): self.root.geometry(f"{W}x{H}+{int(self.x)}+{int(self.y)}")
    def foreground(self):
        if not IS_WIN: return None
        import ctypes; return ctypes.windll.user32.GetForegroundWindow()
    def foreground_title(self):
        if not IS_WIN: return ""
        import ctypes
        h = ctypes.windll.user32.GetForegroundWindow(); n = ctypes.windll.user32.GetWindowTextLengthW(h)
        buf = ctypes.create_unicode_buffer(n + 1); ctypes.windll.user32.GetWindowTextW(h, buf, n + 1)
        t = buf.value.split(" - ")[-1].split(" — ")[-1].strip()
        return t[:18]
    def battery_low(self):
        if not IS_WIN: return False
        import ctypes
        class S(ctypes.Structure):
            _fields_ = [("ACLineStatus", ctypes.c_byte), ("BatteryFlag", ctypes.c_byte), ("BatteryLifePercent", ctypes.c_byte),
                        ("Reserved1", ctypes.c_byte), ("BatteryLifeTime", ctypes.c_ulong), ("BatteryFullLifeTime", ctypes.c_ulong)]
        s = S(); ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(s))
        return s.ACLineStatus == 0 and 0 <= s.BatteryLifePercent < 20

    # ---------- state machine
    def enter(self, name, seconds):
        self.state, self.frame = name, 0
        self.ends = time.time() + seconds if seconds > 0 else float("inf")
        self.schedule()
        self.tick()

    def schedule(self):
        if self.after_id: self.root.after_cancel(self.after_id); self.after_id = None
        if not self.visible: return
        fps = self.anim[self.state][1]
        self.after_id = self.root.after(int(1000 / fps), self.tick)

    def next_state(self):
        if self.state == "sleep": return self.enter("yawn", 1.5)
        if self.state == "sad": return self.enter("sleep", random.uniform(60, 180))
        if time.time() - self.last_move > 300: return self.enter("sad", 3)
        r = random.random()
        if r < 0.40: self.enter("tired" if self.battery_low() else "idle", random.uniform(5, 12))
        elif r < 0.62: self.enter("sit", random.uniform(6, 15))
        elif r < 0.74: self.enter("sleep", random.uniform(90, 240) if self.is_night() else random.uniform(15, 40))
        elif r < 0.80: self.enter("scratch", 1.5)
        elif r < 0.83: self.enter("jump", 0.6)
        elif r < 0.85: self.enter("dance", 2.5)
        elif r < 0.87: self.enter(random.choice(["spin", "shake"]), 0.9)
        elif r < 0.89: self.enter(random.choice(["sneeze", "dig", "roll"]), 1.2)
        elif r < 0.91:
            if self.is_night(): self.enter("sleep", 120)
            elif random.random() < 0.5: self.enter("bark", 1.0); self.say(random.choice(["Bow!", "Bow bow!", "Chimtu!"]))
            else: self.enter("beg", 2.5); self.say(random.choice(["Treat?", "Pleeease", "Em chestunnav?"]))
        elif r < 0.93: self.enter("idle", 4); self.say(random.choice(IDLE_LINES))
        else:
            sw = self.root.winfo_screenwidth()
            self.walk_dir = random.choice([1, -1])
            if self.x < 40: self.walk_dir = 1
            if self.x > sw - W - 40: self.walk_dir = -1
            self.enter("walk_right" if self.walk_dir > 0 else "walk_left", random.uniform(2, 5))

    def tick(self):
        self.after_id = None
        mx, my = self.mouse()
        if (mx, my) != self.last_mouse: self.last_mouse = (mx, my); self.last_move = time.time()
        clip = self.clipboard()
        if clip != self.clip:
            self.clip = clip
            if self.state != "sleep" and not (self.state in GESTURES and time.time() < self.ends) and not self.dragging:
                self.state, self.frame, self.ends = "sniff", 0, time.time() + 1.2; self.say("sniff sniff")
        n, enter, back = self.keys_down()
        now = time.time()
        if n: self.key_times = [t for t in getattr(self, "key_times", []) if now - t < 3] + [now] * n
        else: self.key_times = [t for t in getattr(self, "key_times", []) if now - t < 3]
        busy = self.state in GESTURES and now < self.ends
        if enter and (self.state == "typing" or self.state.startswith("idle")) and not self.dragging:
            self.state, self.frame, self.ends = "jump", 0, now + 0.6; self.say("Sent!")
        elif back:
            self.back_times = [t for t in getattr(self, "back_times", []) if now - t < 2] + [now]
            if len(self.back_times) >= 6: self.back_times = []; self.state, self.frame, self.ends = "sad", 0, now + 1.5; self.say("Oops?")
        elif len(self.key_times) >= 6 and self.state != "typing" and not busy and not self.dragging:
            self.state, self.frame, self.ends = "typing", 0, now + 4; self.say("tak tak tak")
        elif self.state == "typing" and n:
            self.ends = now + 3
        fg = self.foreground()
        if fg != self.fg_window:
            self.fg_window = fg
            if self.state not in {"jump", "wave", "happy", "eat", "love", "howl", "roll", "held"} or time.time() >= self.ends:
                if not self.dragging:
                    self.state, self.frame, self.ends = "alert", 0, time.time() + 1.1
                    t = self.foreground_title()
                    if t and random.random() < 0.5: self.say(f"{t}?")
        if self.state.startswith("idle"):
            dx = mx - (self.x + W / 2)
            want = "idle_left" if dx < -60 else "idle_right" if dx > 60 else "idle"
            if want != self.state: self.state = want
        frames, fps = self.anim[self.state]
        self.canvas.itemconfig(self.item, image=frames[self.frame % len(frames)])
        self.frame = (self.frame + 1) % len(frames)
        if self.follow and not self.dragging:
            if not (self.state in GESTURES and time.time() < self.ends): self.follow_tick(mx, my)
        elif self.state.startswith("walk"):
            self.x += self.walk_dir * 2.5; self.place()
        if time.time() >= self.ends and not self.dragging:
            if self.follow: self.enter("idle", 0)
            else: return self.next_state()
        self.schedule()

    # ---------- follow cursor
    def follow_tick(self, mx, my):
        dx, dy = mx - (self.x + W / 2), my - (self.y + SPRITE_Y + 96)
        if abs(dx) < 50 and abs(dy) < 60:
            self.stop_mover()
            if not self.state.startswith("idle"): self.state, self.frame, self.ends = "idle", 0, float("inf")
            return
        self.start_mover()
        gait = "run" if math.hypot(dx, dy) > 260 else "walk"
        want = f"{gait}_{'right' if dx > 0 else 'left'}"
        if self.state != want: self.state, self.frame, self.ends = want, 0, float("inf")

    def start_mover(self):
        if not self.moving: self.moving = True; self.move_step()
    def stop_mover(self): self.moving = False; self.vx = self.vy = 0.0
    def move_step(self):
        if not self.moving or not self.follow: self.moving = False; return
        mx, my = self.mouse(); dt = 1 / 60
        dx, dy = mx - (self.x + W / 2), my - (self.y + H / 2)
        k = 30; c = 2 * math.sqrt(k)
        self.vx += (k * dx - c * self.vx) * dt; self.vy += (k * dy - c * self.vy) * dt
        sp = math.hypot(self.vx, self.vy)
        if sp > 900: self.vx *= 900 / sp; self.vy *= 900 / sp
        self.x += self.vx * dt; self.y += self.vy * dt
        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        self.x = min(max(self.x, 0), sw - W); self.y = min(max(self.y, 0), sh - H)
        self.place()
        self.root.after(16, self.move_step)

    # ---------- mouse
    def on_press(self, e):
        self.press_t = time.time(); self.press_pos = (e.x_root, e.y_root); self.press_origin = (self.x, self.y)
    def on_drag(self, e):
        if not self.dragging:
            if abs(e.x_root - self.press_pos[0]) + abs(e.y_root - self.press_pos[1]) < 4: return
            self.dragging = True; self.stop_mover(); self.enter("held", 0)
        self.x = self.press_origin[0] + e.x_root - self.press_pos[0]
        self.y = self.press_origin[1] + e.y_root - self.press_pos[1]
        self.place()
    def on_release(self, e):
        if self.dragging:
            self.dragging = False; self.enter("land", 0.45); return
        if time.time() - self.press_t > 0.5: self.say(random.choice(["❤", "Good boy vibes", "Chimtuuu"])); return self.enter("love", 2.0)
        self.click_count += 1
        self.enter("happy" if self.click_count % 2 == 0 else "wave", 1.2)

    # ---------- menu
    def build_menu(self):
        m = tk.Menu(self.root, tearoff=0)
        self.follow_var = tk.BooleanVar(value=False)
        m.add_checkbutton(label="Follow Cursor", variable=self.follow_var, command=self.toggle_follow)
        m.add_separator()
        for label, st, secs in [("Jump", "jump", 0.6), ("Dance", "dance", 2.5), ("Spin", "spin", 0.9), ("Shake", "shake", 0.6),
                                ("Roll Over", "roll", 1.2), ("Howl", "howl", 2.0), ("Give Treat", "eat", 2.5), ("Bark", "bark", 1.0), ("Beg", "beg", 2.5),
                                ("Sit Down", "sit", 15), ("Go to Sleep", "sleep", 60)]:
            m.add_command(label=label, command=lambda s=st, t=secs: self.enter(s, t))
        m.add_separator()
        m.add_command(label="Quit Chimtu", command=self.root.destroy)
        self.menu = m
    def popup(self, e):
        try: self.menu.tk_popup(e.x_root, e.y_root)
        finally: self.menu.grab_release()
    def toggle_follow(self):
        self.follow = self.follow_var.get()
        if self.follow: self.enter("idle", 0)
        else: self.stop_mover(); self.next_state()
    def hourly(self):
        if self.state != "sleep": self.enter("howl", 2.0); self.say(time.strftime("Awooo, it's %I %p").replace(" 0", " "))
        self.root.after(60 * 60 * 1000, self.hourly)

    def run(self): self.root.mainloop()

if __name__ == "__main__":
    Chimtu().run()
