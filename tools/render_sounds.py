#!/usr/bin/env python3
"""Synthesize Chimtu's tiny sound clips (stdlib only). 22.05 kHz mono 16-bit WAV."""
import math, os, random, struct, sys, wave

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/sounds"
SR = 22050
random.seed(7)

def env(i, n, attack=0.005, decay=None):
    t = i / SR; a = attack; d = decay if decay is not None else n / SR
    if t < a: return t / a
    return max(0.0, 1 - (t - a) / max(d - a, 1e-6))

def tone(dur, f0, f1=None, harmonics=1, noise=0.0, vib=0.0, attack=0.005, decay=None, shape="sine"):
    n = int(dur * SR); f1 = f0 if f1 is None else f1; out = []; ph = 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        if vib: f *= 1 + 0.03 * math.sin(2 * math.pi * vib * i / SR)
        ph += 2 * math.pi * f / SR
        if shape == "saw": v = sum(math.sin(ph * k) / k for k in range(1, harmonics + 1))
        else: v = math.sin(ph)
        v += noise * (random.random() * 2 - 1)
        out.append(v * env(i, n, attack, decay))
    return out

def concat(*parts, gap=0.0): 
    out = []
    for p in parts: out += p + [0.0] * int(gap * SR)
    return out

def lowpass(x, alpha=0.15):
    y = 0.0; out = []
    for v in x: y += alpha * (v - y); out.append(y)
    return out

def write(name, samples, gain=0.6):
    peak = max(1e-6, max(abs(v) for v in samples))
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v / peak * gain)) * 32767)) for v in samples))

bark = tone(0.09, 420, 260, harmonics=5, noise=0.1, shape="saw", decay=0.07)
write("bark", concat(bark, bark, gap=0.06))
write("yip", tone(0.06, 900, 1400, decay=0.05))
write("awoo", tone(0.5, 330, 520, vib=6, attack=0.08, decay=0.45) )
sniff = lowpass([random.random() * 2 - 1 for _ in range(int(0.04 * SR))])
write("sniff", concat([v * env(i, len(sniff)) for i, v in enumerate(sniff)], [v * env(i, len(sniff)) for i, v in enumerate(sniff)], gap=0.05))
snore = tone(0.3, 80, 80, harmonics=6, shape="saw", attack=0.05, decay=0.28)
write("snore", [v * (0.6 + 0.4 * math.sin(2 * math.pi * 4 * i / SR)) for i, v in enumerate(snore)])
write("boing", [v for v in tone(0.15, 500, 200, decay=0.14)])
write("chomp", concat([random.random() * 2 - 1 for _ in range(int(0.01 * SR))], tone(0.08, 200, 150, decay=0.07)))
ding = tone(0.6, 1320, 1320, attack=0.002, decay=0.6); ding2 = tone(0.6, 2640, 2640, attack=0.002, decay=0.35)
write("ding", [a + 0.4 * b for a, b in zip(ding, ding2)], gain=0.4)
print("ok", OUT)
