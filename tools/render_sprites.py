#!/usr/bin/env python3
"""Procedurally render Chimtu (Cheems-style Shiba Inu) sprite frames as PNGs."""
from PIL import Image, ImageDraw
import math, os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/frames"
SS = 4           # supersample
W, H = 96, 96    # final frame size (points); rendered at 2x for retina below
SCALE = 2

CREAM = (255, 246, 228)     # white-cream chest, cheeks, muzzle, paws
TAN = (224, 138, 58)        # Cheems ginger coat
DARK_TAN = (196, 110, 40)   # shading / ear rims
WHITE = (255, 250, 240)
BLACK = (34, 24, 22)
PINK = (222, 150, 140)
NOSE = (28, 20, 18)
LID = (216, 128, 52)        # fur colour used for heavy eyelids

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
    # ears: pointed, dark-rimmed, pink inside
    for e in (-1, 1):
        ex = hx + e*15*s
        d.polygon([(ex-9*s, hy-10*s), (ex+9*s, hy-10*s), (ex+e*3*s, hy-34*s)], fill=DARK_TAN)
        d.polygon([(ex-7*s, hy-11*s), (ex+7*s, hy-11*s), (ex+e*2*s, hy-30*s)], fill=TAN)
        d.polygon([(ex-3.5*s, hy-13*s), (ex+3.5*s, hy-13*s), (ex+e*1*s, hy-25*s)], fill=PINK)
    ellipse(d, hx, hy, hr, hr*0.9, TAN)
    # big white jowl cheeks (the Cheems chub)
    for e in (-1, 1):
        ellipse(d, hx + e*15*s, hy + 10*s, 14*s, 12*s, CREAM)
    # longer snout with white blaze up between the eyes
    ellipse(d, hx + face*4*s, hy + 9*s, 13*s, 11*s, WHITE)
    d.polygon([(hx-4*s, hy+2*s), (hx+4*s, hy+2*s), (hx+face*1*s, hy-14*s)], fill=WHITE)
    # sleepy half-lidded eyes with a light frown
    for e in (-1, 1):
        ex, ey = hx + e*11*s + face*2*s, hy - 3*s
        if blink:
            d.line([(ex-5*s, ey+1*s), (ex+5*s, ey+1*s)], fill=BLACK, width=int(2*s))
        else:
            ellipse(d, ex, ey, 5*s, 4.5*s, BLACK)
            # heavy upper lid: fur-coloured ellipse covering the top ~45%
            d.chord([ex-5.5*s, ey-8*s, ex+5.5*s, ey+1*s], 0, 180, fill=LID)
            ellipse(d, ex+1.5*s, ey+0.5*s, 1.3*s, 1.3*s, WHITE)
        # brow: slight inward tilt for the tired look
        d.line([(ex - e*6*s, ey-8*s), (ex + e*5*s, ey-6*s)], fill=DARK_TAN, width=int(1.6*s))
    # nose + neutral/slightly sad mouth
    nx, ny = hx + face*5*s, hy + 6*s
    ellipse(d, nx, ny, 5*s, 3.5*s, NOSE)
    d.line([(nx, ny+3*s), (nx, ny+7*s)], fill=NOSE, width=int(1.4*s))
    d.arc([nx-7*s, ny+3*s, nx-0.5*s, ny+9*s], 0, 120, fill=NOSE, width=int(1.4*s))
    d.arc([nx+0.5*s, ny+3*s, nx+7*s, ny+9*s], 60, 180, fill=NOSE, width=int(1.4*s))
    # white chest bib peeking below the head
    ellipse(d, cx, body_cy - body_ry + 8*s, 12*s, 6*s, CREAM)

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
