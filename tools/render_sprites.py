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
    look = pose.get("look", 0); air = pose.get("air", 0)*s; run = pose.get("run", False); alert = pose.get("alert", False); happy = pose.get("happy", False); held = pose.get("held", False); sad = pose.get("sad", False); tired = pose.get("tired", False); back = pose.get("back", False); shake = pose.get("shake", 0); eat = pose.get("eat", 0); love = pose.get("love", False); howl = pose.get("howl", 0); sneeze = pose.get("sneeze", 0); dig = pose.get("dig", 0); sq = pose.get("squash", 1.0); scratch = pose.get("scratch", 0); yawn = pose.get("yawn", 0)
    base = (H-6)*s
    cx = W/2*s
    # body: rounded, seen from the front, behind the head
    brx, bry = 24*s/math.sqrt(sq), 22*s*sq
    by = base - bry - bob - air
    base = base - air
    if lie: bry = 15*s; by = base - bry
    if sit: bry = 24*s; by = base - bry - bob
    if held: by = base - bry - 8*s

    if back:
        # seen from behind: body, big tail curl, head with ears, no face
        E(d, cx, by, brx, bry, ORANGE); E(d, cx, by+2*s, brx*0.85, bry*0.6, DARK_OR)
        for lx in (-14*s, 14*s): E(d, cx+lx, base-3*s, 8*s, 4.5*s, ORANGE)
        hy = by - bry + 2*s
        for e in (-1, 1):
            ex = cx + e*17*s
            d.polygon([(ex-8*s, hy-10*s), (ex+8*s, hy-10*s), (ex+e*2*s, hy-30*s)], fill=ORANGE)
            d.polygon([(ex-4*s, hy-12*s), (ex+4*s, hy-12*s), (ex+e*1*s, hy-26*s)], fill=DARK_OR)
        E(d, cx, hy, 25*s, 21*s, ORANGE); E(d, cx, hy-6*s, 19*s, 11*s, DARK_OR)
        E(d, cx, by-bry+8*s, 11*s, 11*s, ORANGE); E(d, cx, by-bry+8*s, 5.5*s, 5.5*s, CREAM)   # tail curl over the rump
        return img.resize((W*SCALE, H*SCALE), Image.LANCZOS)

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
    elif held:
        for lx in (-12*s, 12*s):
            d.rounded_rectangle([cx+lx-5*s, by+bry-8*s, cx+lx+5*s, by+bry+8*s], radius=4*s, fill=ORANGE)
            E(d, cx+lx, by+bry+8*s, 6.5*s, 4.5*s, CREAM)
    elif air > 0:
        E(d, cx-12*s, by+bry-2*s, 7*s, 4.5*s, CREAM); E(d, cx+12*s, by+bry-2*s, 7*s, 4.5*s, CREAM)
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
    hx = cx + face*(9*s if run else 4*s)
    hy = by - bry + (5*s if run else 2*s) - howl*6*s + (sneeze if sneeze > 0 else 0)*7*s + dig*6*s
    hrx, hry = 25*s, 21*s
    # ears
    for e in (-1, 1):
        ex = hx + e*17*s
        tipx, tipy = (e*6*s, -24*s) if air > 0 else (e*2*s, -30*s)
        if run: tipx, tipy = (e*9*s - face*6*s, -22*s)   # ears swept back
        if alert: tipx, tipy = (e*1*s, -35*s)             # ears straight up
        if sad: tipx, tipy = (e*14*s, -14*s)              # drooping outward
        if shake: tipx, tipy = (e*4*s + shake*8*s, -26*s) # flapping side to side
        if howl: tipx, tipy = (e*10*s, -20*s - 4*s*(1-howl))  # laid back while howling
        if sneeze > 0: tipx, tipy = (e*11*s, -18*s)          # flattened by the sneeze
        if scratch and e == 1: tipx, tipy = e*8*s, -22*s
        d.polygon([(ex-8*s, hy-10*s), (ex+8*s, hy-10*s), (ex+tipx, hy+tipy)], fill=ORANGE)
        d.polygon([(ex-4.5*s, hy-12*s), (ex+4.5*s, hy-12*s), (ex+tipx*0.5, hy+tipy*0.82)], fill=PINK)
    E(d, hx, hy, hrx, hry, ORANGE)
    E(d, hx, hy-9*s, hrx*0.75, hry*0.45, DARK_OR)          # forehead shading
    # cream cheeks + muzzle mask
    for e in (-1, 1): E(d, hx+e*14*s, hy+9*s, 12*s, 10*s, CREAM)
    E(d, hx+face*2*s, hy+8*s, 12*s, 10*s, CREAM)
    d.polygon([(hx-4*s, hy+2*s), (hx+4*s, hy+2*s), (hx+face*1*s, hy-9*s)], fill=CREAM)   # blaze
    for e in (-1, 1): E(d, hx+e*10*s+face*1.5*s, hy-10*s, 2.6*s, 1.7*s, CREAM)           # eyebrow spots
    # eyes
    for e in (-1, 1):
        ex, ey = hx+e*10*s+face*2*s+look*2.2*s, hy-2*s
        if yawn or (scratch and e == 1):
            d.arc([ex-3.5*s, ey-2*s, ex+3.5*s, ey+3*s], 200, 340, fill=BLACK, width=int(2*s)); continue
        if love or howl or sneeze:
            d.arc([ex-3.8*s, ey-1*s, ex+3.8*s, ey+5*s], 200, 340, fill=BLACK, width=int(2.2*s)); continue
        if happy:
            d.arc([ex-3.8*s, ey-1*s, ex+3.8*s, ey+5*s], 200, 340, fill=BLACK, width=int(2.2*s)); continue
        if alert or held:
            E(d, ex, ey, 4.3*s, 4.7*s, BLACK); E(d, ex+1.3*s, ey-1.5*s, 1.5*s, 1.5*s, WHITE); continue
        if tired:
            E(d, ex, ey, 3.4*s, 3.8*s, BLACK)
            d.chord([ex-4*s, ey-5*s, ex+4*s, ey+1*s], 0, 180, fill=ORANGE); continue
        if sad:
            E(d, ex, ey, 3.4*s, 3.8*s, BLACK); E(d, ex+1.2*s, ey-1.2*s, 1.1*s, 1.1*s, WHITE)
            d.line([(ex-e*4*s, ey-7*s), (ex+e*3*s, ey-5*s)], fill=DARK_OR, width=int(1.6*s)); continue
        if blink: d.line([(ex-3.5*s, ey), (ex+3.5*s, ey)], fill=BLACK, width=int(2*s))
        else:
            E(d, ex, ey, 3.4*s, 3.8*s, BLACK); E(d, ex+1.2*s, ey-1.2*s, 1.1*s, 1.1*s, WHITE)
    # nose, mouth, tongue
    nx, ny = hx+face*3*s, hy+6*s
    E(d, nx, ny, 4*s, 3*s, NOSE)
    d.line([(nx, ny+2.5*s), (nx, ny+6*s)], fill=NOSE, width=int(1.3*s))
    d.arc([nx-7*s, ny+2*s, nx-0.5*s, ny+9*s], 0, 120, fill=NOSE, width=int(1.3*s))
    d.arc([nx+0.5*s, ny+2*s, nx+7*s, ny+9*s], 60, 180, fill=NOSE, width=int(1.3*s))
    if howl or sneeze > 0:
        r = 4.5*s*max(howl, sneeze)
        E(d, nx, ny+9*s, r*0.8+1*s, r+1*s, BLACK)
    elif sneeze < 0:
        d.line([(nx-4*s, ny+8*s), (nx+4*s, ny+8*s)], fill=NOSE, width=int(1.6*s))   # pre-sneeze "ah" grimace
    elif eat:
        if eat > 0.5:
            E(d, nx, ny+9*s, 3.5*s, 3*s, BLACK)
        else:
            d.line([(nx-4*s, ny+9*s), (nx+4*s, ny+9*s)], fill=NOSE, width=int(1.6*s))
        E(d, hx+14*s, hy+9*s, 15*s*(0.6+0.4*(1-eat)), 12*s, CREAM)   # puffed cheek
    elif sad:
        pass  # keep the neutral mouth; drooping ears + brows carry the emotion
    elif held:
        E(d, nx, ny+9*s, 2.6*s, 3*s, BLACK)
    elif yawn:
        E(d, nx, ny+9*s, 5*s, 4.5*s*yawn+1*s, BLACK); E(d, nx, ny+11*s, 3*s, 2*s*yawn, PINK)
    elif tongue: E(d, nx, ny+10*s, 3.5*s, 3.5*s, PINK)
    if love:
        for e in (-1, 1): E(d, hx+e*17*s, hy+7*s, 5*s, 3*s, (245, 150, 150))
    if dig:
        for i, lx in enumerate((-12*s, 12*s)):
            ext = (dig if i == 0 else 1-dig)*8*s
            d.rounded_rectangle([cx+lx-5.5*s, by+6*s, cx+lx+5.5*s, base+2*s-ext*0.3], radius=4*s, fill=ORANGE)
            E(d, cx+lx+(-1 if i==0 else 1)*ext*0.4, base-2*s, 7.5*s, 4.5*s, CREAM)
    if scratch:
        # hind leg raised up to the ear, mid-scratch
        lx, ly = hx+22*s, hy-2*s-scratch*4*s
        d.rounded_rectangle([lx-5*s, ly, lx+5*s, by+bry-6*s], radius=4*s, fill=ORANGE); E(d, lx, ly, 6.5*s, 5*s, CREAM)
    return img.resize((W*SCALE, H*SCALE), Image.LANCZOS)

def compress(img):
    """Palette PNG (128 colours) with alpha preserved; ~4-6x smaller than RGBA."""
    return img.quantize(colors=128, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)

def save(name, frames):
    os.makedirs(OUT, exist_ok=True)
    for i, f in enumerate(frames): compress(f).save(f"{OUT}/{name}_{i:02d}.png", optimize=True)

idle = [draw({"bob": b, "blink": bl, "wag": w}) for b, bl, w in [(0,False,0),(0.6,False,-1.5),(1.2,False,-3),(0.6,False,-1.5),(0,False,0),(0,True,0)]]
walk_r = [draw({"bob": abs(math.sin(p))*2, "legs": p, "wag": math.sin(p)*2, "facing": 1}) for p in [i*math.pi/3 for i in range(6)]]
walk_l = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in walk_r]
sit = [draw({"sit": True, "bob": b, "blink": bl, "wag": w}) for b, bl, w in [(0,False,0),(0.5,False,-2),(0,True,0),(0.5,False,-2)]]
sleep = [draw({"lie": True, "blink": True, "tongue": False, "wag": w}) for w in (0, 1)]
wave = [draw({"wave": w}) for w in (0.3, 1.0, 0.5, 1.0)]
idle_left  = [draw({"bob": b, "blink": bl, "wag": w, "look": -1}) for b, bl, w in [(0,False,0),(0.6,False,-1.5),(1.2,False,-3),(0.6,False,-1.5),(0,False,0),(0,True,0)]]
idle_right = [draw({"bob": b, "blink": bl, "wag": w, "look": 1})  for b, bl, w in [(0,False,0),(0.6,False,-1.5),(1.2,False,-3),(0.6,False,-1.5),(0,False,0),(0,True,0)]]
jump = [draw(p) for p in [{"squash": 0.88}, {"air": 10, "squash": 1.06}, {"air": 20}, {"air": 12, "squash": 1.04}, {"squash": 0.9}, {}]]
scratch = [draw({"scratch": v, "tongue": False, "wag": 1}) for v in (0.2, 1.0, 0.3, 1.0, 0.2, 0.8)]
yawn = [draw({"yawn": v, "tongue": False, "squash": q}) for v, q in [(0.3,1.0),(0.7,1.03),(1.0,1.06),(1.0,1.06),(0.6,1.02),(0.2,1.0)]]
run_r = [draw({"bob": abs(math.sin(p))*4, "legs": p*1.0, "wag": math.sin(p)*3, "facing": 1, "run": True, "squash": 1.0 + 0.04*math.sin(p)}) for p in [i*math.pi/3 for i in range(6)]]
run_l = [f.transpose(Image.FLIP_LEFT_RIGHT) for f in run_r]
save("run_right", run_r); save("run_left", run_l)
alert = [draw(p) for p in [{"alert":True,"tongue":False,"squash":0.94},{"alert":True,"tongue":False,"air":9,"squash":1.04},{"alert":True,"tongue":False},
                           {"alert":True,"tongue":False,"face":-1},{"alert":True,"tongue":False,"face":1},{"alert":True,"tongue":False}]]
happy = [draw({"happy":True,"face":f,"bob":b,"wag":w,"squash":q}) for f,b,w,q in [(-1,0,-3,0.97),(-1,2,3,1.03),(0,3,-3,1.04),(1,2,3,1.03),(1,0,-3,0.97),(0,1,3,1.0)]]
save("alert", alert); save("happy", happy)
held = [draw({"held":True,"tongue":False,"wag":w}) for w in (0, 2, 0, -2)]
land = [draw(p) for p in [{"squash":0.82,"tongue":False},{"squash":0.9,"tongue":False},{"squash":1.05},{}]]
spin = [draw({"face":0}), walk_r[0], draw({"back":True}), walk_l[0], draw({"face":0}), draw({"happy":True,"bob":2,"wag":3})]
dance = [draw({"face":f,"air":a,"squash":q,"happy":True,"wag":w}) for f,a,q,w in [(-1,0,0.94,3),(-1,8,1.04,-3),(0,12,1.0,3),(1,8,1.04,-3),(1,0,0.94,3),(0,4,1.02,-3)]]
shake = [draw({"shake":v,"face":f,"tongue":False,"blink":True}) for v,f in [(-1,-1),(1,1),(-1,-1),(1,1),(0,0),(0,0)]]
sad = [draw({"sad":True,"tongue":False,"bob":b}) for b in (0,0.4,0.8,0.4,0,0)]
tired = [draw({"tired":True,"tongue":False,"bob":b,"blink":bl}) for b,bl in [(0,False),(0.3,False),(0.6,False),(0.3,False),(0,True),(0,True)]]
eat = [draw({"eat":v,"tongue":False,"wag":w}) for v,w in [(1.0,-2),(0.3,2),(1.0,-2),(0.3,2),(0.8,-2),(0.1,2)]]
love = [draw({"love":True,"tongue":True,"bob":b,"wag":w,"squash":q}) for b,w,q in [(0,-3,1.0),(1,3,1.02),(2,-3,1.03),(1,3,1.02),(0,-3,1.0),(1,3,1.01)]]
howl = [draw({"howl":v,"tongue":False,"squash":q}) for v,q in [(0.3,1.0),(0.7,1.03),(1.0,1.05),(1.0,1.05),(1.0,1.05),(0.5,1.02)]]
sneeze = [draw(p) for p in [{"sneeze":-1,"tongue":False,"squash":1.04},{"sneeze":-1,"tongue":False,"squash":1.06},{"sneeze":1,"tongue":False,"squash":0.86,"shake":-1},{"sneeze":0.6,"tongue":False,"squash":0.92},{"tongue":False,"blink":True},{}]]
dig = [draw({"dig":v,"tongue":True,"squash":0.96}) for v in (0.0,0.5,1.0,0.5,0.0,0.5)]
_lie = draw({"lie":True,"tongue":True,"wag":1})
_lieback = _lie.transpose(Image.FLIP_TOP_BOTTOM)
roll = [draw({"sit":True,"tongue":True}), _lie, walk_r[0].transpose(Image.ROTATE_90), _lieback, walk_l[0].transpose(Image.ROTATE_270), draw({"happy":True,"bob":2,"wag":3})]
for n,f in [("held",held),("land",land),("eat",eat),("love",love),("howl",howl),("sneeze",sneeze),("dig",dig),("roll",roll),("spin",spin),("dance",dance),("shake",shake),("sad",sad),("tired",tired),("eat",eat),("love",love),("howl",howl),("sneeze",sneeze),("dig",dig),("roll",roll)]: save(n,f)
save("idle_left", idle_left); save("idle_right", idle_right); save("jump", jump); save("scratch", scratch); save("yawn", yawn)
save("idle", idle); save("walk_right", walk_r); save("walk_left", walk_l); save("sit", sit); save("sleep", sleep); save("wave", wave)
names = [("idle",idle),("idle_left",idle_left),("idle_right",idle_right),("walk_right",walk_r),("walk_left",walk_l),("run_right",run_r),("run_left",run_l),("sit",sit),("sleep",sleep),("wave",wave),("jump",jump),("scratch",scratch),("yawn",yawn),("alert",alert),("happy",happy),("held",held),("land",land),("spin",spin),("dance",dance),("shake",shake),("sad",sad),("tired",tired),("eat",eat),("love",love),("howl",howl),("sneeze",sneeze),("dig",dig),("roll",roll)]
sheet = Image.new("RGBA", (W*SCALE*6, H*SCALE*len(names)), (60,60,70,255))
for r,(n,fr) in enumerate(names):
    for c,f in enumerate(fr): sheet.paste(f,(c*W*SCALE, r*H*SCALE), f)
sheet.save(f"{OUT}/../contact-sheet.png")
sheet.crop((0,0,W*SCALE*3,H*SCALE)).resize((W*SCALE*6,H*SCALE*2),Image.LANCZOS).save(f"{OUT}/../peek.png")
print("ok")
