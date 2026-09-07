#!/usr/bin/env python3
"""Render Chimtu: a side-view Shiba in a spiky black dino hoodie with a red bandana."""
from PIL import Image, ImageDraw
import math, os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/frames"
SS, SCALE = 4, 2
W, H = 112, 96

ORANGE = (226, 150, 78); DARK_OR = (200, 122, 56); CREAM = (255, 246, 228); WHITE = (255, 251, 242)
HOOD = (46, 44, 50); HOOD_LT = (72, 70, 78); HOOD_DK = (28, 26, 30); SPIKE = (150, 150, 158); SPIKE_DK = (105, 105, 112)
RED = (196, 40, 48); RED_DK = (150, 26, 34); PINK = (238, 120, 150); BLACK = (30, 24, 24); NOSE = (26, 18, 18)
EYE_RING = (235, 235, 240); EYE_IRIS = (225, 40, 60); EYE_PUPIL = (40, 10, 14)

def E(d, cx, cy, rx, ry, fill): d.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=fill)

def draw(pose):
    s = SS*SCALE
    img = Image.new("RGBA", (W*s, H*s), (0,0,0,0)); d = ImageDraw.Draw(img)
    bob = pose.get("bob", 0)*s; legs = pose.get("legs"); blink = pose.get("blink", False)
    lie = pose.get("lie", False); sit = pose.get("sit", False); wave = pose.get("wave", 0)
    tongue = pose.get("tongue", True); wag = pose.get("wag", 0)
    base = (H-6)*s
    # body geometry (facing right)
    bx, by = W*0.46*s, base - 30*s - bob
    if lie: by = base - 20*s
    if sit: by = base - 26*s - bob
    brx, bry = 30*s, 18*s

    # tail: curled over the rump
    tx, ty = bx - 26*s, by - 14*s + wag*s
    E(d, tx, ty, 9*s, 9*s, ORANGE); E(d, tx-1*s, ty-1*s, 4.5*s, 4.5*s, CREAM)

    # hind legs (black pants + white paws)
    def leg(x, top, h, swing=0):
        d.rounded_rectangle([x-5*s+swing, top, x+5*s+swing, top+h], radius=4*s, fill=HOOD)
        E(d, x+swing, top+h, 6*s, 4*s, WHITE)
    if lie:
        E(d, bx-18*s, base-4*s, 9*s, 4.5*s, WHITE); E(d, bx+16*s, base-4*s, 9*s, 4.5*s, WHITE)
    elif sit:
        E(d, bx-14*s, base-5*s, 10*s, 5*s, WHITE)
        leg(bx+14*s, by+4*s, base-8*s-(by+4*s)); leg(bx+22*s, by+4*s, base-8*s-(by+4*s))
    else:
        sw = 0 if legs is None else math.sin(legs)*4*s
        leg(bx-18*s, by+6*s, base-8*s-(by+6*s), sw); leg(bx-10*s, by+6*s, base-8*s-(by+6*s), -sw)
        leg(bx+12*s, by+6*s, base-8*s-(by+6*s), -sw)
        if not wave:
            leg(bx+22*s, by+6*s, base-8*s-(by+6*s), sw)

    # body: black hoodie
    E(d, bx, by, brx, bry, HOOD)
    E(d, bx-4*s, by-3*s, brx*0.8, bry*0.55, HOOD_LT)     # top highlight
    E(d, bx, by+8*s, brx*0.9, bry*0.45, HOOD_DK)         # underside
    # grey spikes along the back
    for i, sx in enumerate([-22, -12, -2, 8]):
        x = bx + sx*s; top = by - bry + 2*s
        d.polygon([(x-5*s, top), (x+5*s, top), (x, top-9*s-(i%2)*2*s)], fill=SPIKE)
        d.polygon([(x, top), (x+5*s, top), (x, top-9*s-(i%2)*2*s)], fill=SPIKE_DK)

    # head (front-right), hood covers top and back
    hx, hy = bx + 26*s, by - 16*s
    hr = 17*s
    E(d, hx, hy, hr+3*s, hr+2*s, HOOD)                     # hood shell
    # hood spikes
    for sx in (-8, 2):
        x = hx + sx*s; top = hy - hr - 1*s
        d.polygon([(x-4*s, top), (x+4*s, top), (x, top-8*s)], fill=SPIKE)
    # big dino "eye" on the hood
    ex, ey = hx - 9*s, hy - 8*s
    E(d, ex, ey, 6.5*s, 6.5*s, EYE_RING); E(d, ex, ey, 4.5*s, 4.5*s, EYE_IRIS); E(d, ex+0.5*s, ey, 2*s, 2*s, EYE_PUPIL); E(d, ex-1.5*s, ey-1.5*s, 1*s, 1*s, WHITE)
    # face opening: shiba face
    E(d, hx+4*s, hy+3*s, 13*s, 12*s, ORANGE)
    E(d, hx+7*s, hy+7*s, 9*s, 7*s, CREAM)                   # muzzle / cheek
    E(d, hx+3*s, hy+1*s, 6*s, 5*s, ORANGE)
    # shiba ear poking out of the hood
    d.polygon([(hx-2*s, hy-8*s), (hx+8*s, hy-9*s), (hx+2*s, hy-19*s)], fill=ORANGE)
    d.polygon([(hx, hy-9*s), (hx+6*s, hy-10*s), (hx+2*s, hy-16*s)], fill=PINK)
    # eye (side view: one visible)
    eyx, eyy = hx+7*s, hy
    if blink: d.line([(eyx-3*s, eyy), (eyx+3*s, eyy)], fill=BLACK, width=int(2*s))
    else:
        E(d, eyx, eyy, 3*s, 3.3*s, BLACK); E(d, eyx+1*s, eyy-1*s, 1*s, 1*s, WHITE)
    # nose + mouth + tongue
    nx, ny = hx+15*s, hy+5*s
    E(d, nx, ny, 3*s, 2.4*s, NOSE)
    d.arc([nx-8*s, ny+1*s, nx+1*s, ny+8*s], 0, 140, fill=NOSE, width=int(1.3*s))
    if tongue: E(d, nx-4*s, ny+8*s, 3*s, 3.5*s, PINK)
    if wave:
        # raised front paw, in front of the body
        px, py = bx+30*s, by+2*s-wave*14*s
        d.rounded_rectangle([px-5*s, py, px+5*s, by+10*s], radius=4*s, fill=HOOD); E(d, px, py, 6*s, 5*s, WHITE)
    # red bandana at the neck
    d.polygon([(hx-12*s, hy+12*s), (hx+8*s, hy+14*s), (hx-2*s, hy+24*s)], fill=RED)
    d.polygon([(hx-12*s, hy+12*s), (hx+8*s, hy+14*s), (hx-1*s, hy+18*s)], fill=RED_DK)
    return img.resize((W*SCALE, H*SCALE), Image.LANCZOS)

def save(name, frames):
    os.makedirs(OUT, exist_ok=True)
    for i, f in enumerate(frames): f.save(f"{OUT}/{name}_{i:02d}.png")

idle = [draw({"bob": b, "blink": bl, "wag": w}) for b, bl, w in [(0,False,0),(0.6,False,-1.5),(1.2,False,-3),(0.6,False,-1.5),(0,False,0),(0,True,0)]]
walk_r = [draw({"bob": abs(math.sin(p))*2, "legs": p, "wag": math.sin(p)*2}) for p in [i*math.pi/3 for i in range(6)]]
walk_l = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in walk_r]
sit = [draw({"sit": True, "bob": b, "blink": bl, "wag": w}) for b, bl, w in [(0,False,0),(0.5,False,-2),(0,True,0),(0.5,False,-2)]]
sleep = [draw({"lie": True, "blink": True, "tongue": False, "wag": w}) for w in (0, 1)]
wave = [draw({"wave": w}) for w in (0.3, 1.0, 0.5, 1.0)]
save("idle", idle); save("walk_right", walk_r); save("walk_left", walk_l); save("sit", sit); save("sleep", sleep); save("wave", wave)
names = [("idle",idle),("walk_right",walk_r),("walk_left",walk_l),("sit",sit),("sleep",sleep),("wave",wave)]
sheet = Image.new("RGBA", (W*SCALE*6, H*SCALE*len(names)), (60,60,70,255))
for r,(n,fr) in enumerate(names):
    for c,f in enumerate(fr): sheet.paste(f,(c*W*SCALE, r*H*SCALE), f)
sheet.save(f"{OUT}/../contact-sheet.png")
sheet.crop((0,0,W*SCALE*3,H*SCALE)).resize((W*SCALE*6,H*SCALE*2),Image.LANCZOS).save(f"{OUT}/../peek.png")
print("ok")
