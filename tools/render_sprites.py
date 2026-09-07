#!/usr/bin/env python3
"""Procedurally render Chimtu (Cheems-style Shiba Inu) sprite frames as PNGs."""
from PIL import Image, ImageDraw
import math, os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/frames"
SS = 4           # supersample
W, H = 96, 96    # final frame size (points); rendered at 2x for retina below
SCALE = 2

CREAM = (250, 233, 200)
TAN = (226, 170, 96)
DARK_TAN = (205, 145, 70)
WHITE = (255, 252, 245)
BLACK = (40, 30, 28)
PINK = (236, 150, 150)
NOSE = (52, 40, 38)

def ellipse(d, cx, cy, rx, ry, fill, outline=None, w=0):
    d.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=fill, outline=outline, width=w)

def draw_frame(pose):
    """pose: dict with keys bob, squash, blink, legs(phase or None), facing(+1/-1), sit, wave, tail"""
    s = SS * SCALE
    img = Image.new("RGBA", (W*s, H*s), (0,0,0,0))
    d = ImageDraw.Draw(img)
    bob = pose.get("bob", 0) * s
    sq = pose.get("squash", 1.0)
    face = pose.get("facing", 1)
    sit = pose.get("sit", False)
    legs = pose.get("legs")
    blink = pose.get("blink", False)
    wave = pose.get("wave", 0)
    tail = pose.get("tail", 0)

    base = (H - 6) * s              # ground line
    cx = W/2 * s
    body_ry = (24 if not sit else 27) * s * sq
    body_rx = 26 * s / math.sqrt(sq)
    body_cy = base - body_ry - bob

    # tail (curly) behind body
    tx = cx - face * (22*s)
    ty = body_cy - 8*s + tail*s
    ellipse(d, tx, ty, 9*s, 9*s, TAN)
    ellipse(d, tx - face*2*s, ty + 2*s, 5*s, 5*s, CREAM)

    # legs
    leg_w, leg_h = 8*s, 12*s
    if not sit:
        swing = 0 if legs is None else math.sin(legs) * 5 * s
        for i, lx in enumerate((-14*s, 14*s)):
            off = swing if i == 0 else -swing
            d.rounded_rectangle([cx+lx-leg_w/2+off, base-leg_h-bob, cx+lx+leg_w/2+off, base-bob+1*s], radius=4*s, fill=CREAM)
    else:
        for lx in (-16*s, 16*s):
            ellipse(d, cx+lx, base-5*s, 9*s, 5*s, CREAM)

    # body (cream belly, tan back)
    ellipse(d, cx, body_cy, body_rx, body_ry, TAN)
    ellipse(d, cx, body_cy + 6*s, body_rx*0.72, body_ry*0.62, CREAM)


    # head
    hr = 24 * s
    hx = cx + face*4*s
    hy = body_cy - body_ry - 4*s
    # ears
    for e in (-1, 1):
        ex = hx + e*16*s
        d.polygon([(ex-8*s, hy-12*s), (ex+8*s, hy-12*s), (ex+e*2*s, hy-32*s)], fill=TAN)
        d.polygon([(ex-4*s, hy-13*s), (ex+4*s, hy-13*s), (ex+e*1*s, hy-26*s)], fill=PINK)
    ellipse(d, hx, hy, hr, hr*0.92, TAN)
    # cheeks (the Cheems chub)
    for e in (-1, 1):
        ellipse(d, hx + e*16*s, hy + 9*s, 13*s, 11*s, CREAM)
    # muzzle
    ellipse(d, hx + face*3*s, hy + 8*s, 15*s, 11*s, WHITE)
    # eyes
    for e in (-1, 1):
        ex, ey = hx + e*10*s + face*2*s, hy - 3*s
        if blink:
            d.line([(ex-4*s, ey), (ex+4*s, ey)], fill=BLACK, width=int(2*s))
        else:
            ellipse(d, ex, ey, 4*s, 4.5*s, BLACK)
            ellipse(d, ex+1.5*s, ey-1.5*s, 1.3*s, 1.3*s, WHITE)
    # nose + mouth
    nx, ny = hx + face*4*s, hy + 4*s
    ellipse(d, nx, ny, 4*s, 3*s, NOSE)
    d.arc([nx-6*s, ny+1*s, nx+6*s, ny+9*s], 20, 160, fill=NOSE, width=int(1.5*s))
    # waving paw drawn in front of the head
    if wave:
        px = cx + face*24*s
        py = hy + 6*s - wave*14*s
        d.rounded_rectangle([px-5*s, py, px+5*s, body_cy], radius=5*s, fill=CREAM)
        ellipse(d, px, py, 6.5*s, 6.5*s, CREAM)

    return img.resize((W*SCALE, H*SCALE), Image.LANCZOS)

def save(name, frames):
    os.makedirs(OUT, exist_ok=True)
    for i, f in enumerate(frames):
        f.save(f"{OUT}/{name}_{i:02d}.png")

idle = [draw_frame({"bob": b, "squash": q, "blink": bl, "tail": t}) for b, q, bl, t in
        [(0,1.0,False,0),(0.5,1.01,False,-1),(1,1.02,False,-2),(0.5,1.01,False,-1),(0,1.0,False,0),(0,1.0,True,0)]]
walk_r = [draw_frame({"bob": abs(math.sin(p))*2, "legs": p, "facing": 1, "tail": math.sin(p)*2}) for p in [i*math.pi/3 for i in range(6)]]
walk_l = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in walk_r]
sit = [draw_frame({"sit": True, "bob": b, "blink": bl, "squash": q}) for b, bl, q in [(0,False,1.0),(0,False,1.01),(0,True,1.0),(0,False,1.01)]]
sleep = [draw_frame({"sit": True, "blink": True, "squash": q}) for q in (1.0, 1.02)]
wave = [draw_frame({"wave": w, "facing": 1}) for w in (0.3, 1.0, 0.5, 1.0)]
save("idle", idle); save("walk_right", walk_r); save("walk_left", walk_l); save("sit", sit); save("sleep", sleep); save("wave", wave)
# contact sheet for review
names = [("idle",idle),("walk_right",walk_r),("walk_left",walk_l),("sit",sit),("sleep",sleep),("wave",wave)]
sheet = Image.new("RGBA", (W*SCALE*6, H*SCALE*len(names)), (60,60,70,255))
for r,(n,fr) in enumerate(names):
    for c,f in enumerate(fr): sheet.paste(f,(c*W*SCALE, r*H*SCALE), f)
sheet.save(f"{OUT}/../contact-sheet.png")
print("ok", OUT)
