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
    tongue = pose.get("tongue", True); wag = pose.get("wag", 0); face = pose.get("facing", 0)
    base = (H-6)*s
    cx = W/2*s
    # body: rounded, seen from the front, behind the head
    brx, bry = 24*s, 22*s
    by = base - bry - bob
    if lie: bry = 15*s; by = base - bry
    if sit: bry = 24*s; by = base - bry - bob

    # tail curl peeking above the back
    tx, ty = cx - 20*s, by - bry + 4*s + wag*s
    E(d, tx, ty, 8*s, 8*s, ORANGE); E(d, tx, ty, 3.8*s, 3.8*s, CREAM)

    # back legs (slightly wider apart, behind)
    if not lie:
        for lx in (-19*s, 19*s):
            E(d, cx+lx, base-4*s, 8*s, 4.5*s, DARK_OR)

    E(d, cx, by, brx, bry, ORANGE)
    E(d, cx, by+6*s, brx*0.7, bry*0.75, CREAM)            # chest / belly

    # front legs with cream paws
    def leg(x, lift=0):
        top = by + 4*s
        d.rounded_rectangle([x-5.5*s, top, x+5.5*s, base-lift], radius=4*s, fill=ORANGE)
        E(d, x, base-lift-2*s, 7*s, 4.5*s, CREAM)
    if lie:
        E(d, cx-14*s, base-3*s, 10*s, 5*s, CREAM); E(d, cx+14*s, base-3*s, 10*s, 5*s, CREAM)
    else:
        sw = 0 if legs is None else max(0, math.sin(legs))*4*s
        sw2 = 0 if legs is None else max(0, -math.sin(legs))*4*s
        leg(cx-12*s, sw)
        if wave:
            px, py = cx+22*s, by-8*s-wave*12*s
            d.rounded_rectangle([px-5.5*s, py, px+5.5*s, by+8*s], radius=4*s, fill=ORANGE); E(d, px, py, 7*s, 6*s, CREAM)
        else:
            leg(cx+12*s, sw2)

    # head: front view, round and wide
    hx = cx + face*4*s
    hy = by - bry + 2*s
    hrx, hry = 25*s, 21*s
    # ears
    for e in (-1, 1):
        ex = hx + e*17*s
        d.polygon([(ex-8*s, hy-10*s), (ex+8*s, hy-10*s), (ex+e*2*s, hy-30*s)], fill=ORANGE)
        d.polygon([(ex-4.5*s, hy-12*s), (ex+4.5*s, hy-12*s), (ex+e*1*s, hy-25*s)], fill=PINK)
    E(d, hx, hy, hrx, hry, ORANGE)
    E(d, hx, hy-9*s, hrx*0.75, hry*0.45, DARK_OR)          # forehead shading
    # cream cheeks + muzzle mask
    for e in (-1, 1): E(d, hx+e*14*s, hy+9*s, 12*s, 10*s, CREAM)
    E(d, hx+face*2*s, hy+8*s, 12*s, 10*s, CREAM)
    d.polygon([(hx-4*s, hy+2*s), (hx+4*s, hy+2*s), (hx+face*1*s, hy-9*s)], fill=CREAM)   # blaze
    for e in (-1, 1): E(d, hx+e*10*s+face*1.5*s, hy-10*s, 2.6*s, 1.7*s, CREAM)           # eyebrow spots
    # eyes
    for e in (-1, 1):
        ex, ey = hx+e*10*s+face*2*s, hy-2*s
        if blink: d.line([(ex-3.5*s, ey), (ex+3.5*s, ey)], fill=BLACK, width=int(2*s))
        else:
            E(d, ex, ey, 3.4*s, 3.8*s, BLACK); E(d, ex+1.2*s, ey-1.2*s, 1.1*s, 1.1*s, WHITE)
    # nose, mouth, tongue
    nx, ny = hx+face*3*s, hy+6*s
    E(d, nx, ny, 4*s, 3*s, NOSE)
    d.line([(nx, ny+2.5*s), (nx, ny+6*s)], fill=NOSE, width=int(1.3*s))
    d.arc([nx-7*s, ny+2*s, nx-0.5*s, ny+9*s], 0, 120, fill=NOSE, width=int(1.3*s))
    d.arc([nx+0.5*s, ny+2*s, nx+7*s, ny+9*s], 60, 180, fill=NOSE, width=int(1.3*s))
    if tongue: E(d, nx, ny+10*s, 3.5*s, 3.5*s, PINK)
    return img.resize((W*SCALE, H*SCALE), Image.LANCZOS)

def save(name, frames):
    os.makedirs(OUT, exist_ok=True)
    for i, f in enumerate(frames): f.save(f"{OUT}/{name}_{i:02d}.png")

idle = [draw({"bob": b, "blink": bl, "wag": w}) for b, bl, w in [(0,False,0),(0.6,False,-1.5),(1.2,False,-3),(0.6,False,-1.5),(0,False,0),(0,True,0)]]
walk_r = [draw({"bob": abs(math.sin(p))*2, "legs": p, "wag": math.sin(p)*2, "facing": 1}) for p in [i*math.pi/3 for i in range(6)]]
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
