# LAST SIGNAL Slice 1 (night siege) sounds: original, synthesized from code (no samples).
# Usage: python3 make_audio_s1.py <project folder>
import sys, os, wave, numpy as np
from scipy.signal import lfilter, butter

OUT = sys.argv[1]
SFX = os.path.join(OUT, "assets/audio/sfx")
SR = 22050
rng = np.random.default_rng(1108)

def norm(x, peak=0.89):
    m = np.max(np.abs(x)) or 1.0
    return x * (peak / m)
def wav(name, x):
    y = (np.clip(norm(x), -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(SFX, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(y.tobytes())
def t(d): return np.arange(int(d * SR)) / SR
def noise(n): return rng.uniform(-1, 1, n)
def lp(x, hz, o=2):
    b, a = butter(o, min(hz / (SR / 2), 0.99), "low"); return lfilter(b, a, x)
def bp(x, lo, hi, o=2):
    b, a = butter(o, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band"); return lfilter(b, a, x)
def resonator(x, f, bw):
    r = np.exp(-np.pi * bw / SR); th = 2 * np.pi * f / SR
    return lfilter([1 - r], [1, -2 * r * np.cos(th), r * r], x)
def env(n, a, d):
    e = np.ones(n); ka = max(1, int(a * SR)); e[:ka] = np.linspace(0, 1, ka)
    return e * np.exp(-np.arange(n) / SR / d)

def wood_knock(d=0.25, f=180):
    n = int(d * SR); x = noise(n) * env(n, 0.002, 0.05)
    return resonator(x, f, 60) * 3 + resonator(x, f * 2.3, 120) + bp(x, 600, 3000) * 0.3

# Walker hitting the boards: a heavy thud + creak of wood.
def barricade_hit():
    x = wood_knock(0.35, 150) + wood_knock(0.35, 95) * 0.8
    tt = t(0.35); creak = np.sin(2 * np.pi * (300 + 60 * np.sin(tt * 30)) * tt) * np.exp(-tt * 9) * 0.15
    return x + creak

# Last plank breaks: splintering crack.
def barricade_break():
    n = int(0.7 * SR); crack = bp(noise(n), 900, 5000) * env(n, 0.001, 0.08)
    splinters = np.zeros(n)
    for k in range(9):
        s = int(rng.uniform(0.03, 0.5) * SR); m = int(0.04 * SR)
        splinters[s:s + m] += bp(noise(m), 1500, 6000) * np.exp(-np.arange(m) / SR / 0.01) * rng.uniform(0.2, 0.6)
    return crack * 1.4 + splinters + wood_knock(0.7, 120) * 0.9

# Nailing a plank: three hammer taps.
def barricade_build():
    out = np.zeros(int(0.75 * SR))
    for i, at in enumerate((0.0, 0.24, 0.48)):
        n = int(0.2 * SR); x = noise(n) * env(n, 0.001, 0.02)
        tap = resonator(x, 2100 + 150 * i, 200) * 2 + resonator(x, 420, 80) * 1.5
        s = int(at * SR); out[s:s + n] += tap[: len(out) - s]
    return out

# Dusk: a distant church bell, two strokes.
def dusk_bell():
    d = 4.0; tt = t(d); out = np.zeros(len(tt))
    for at in (0.0, 1.6):
        s = int(at * SR); u = tt[: len(tt) - s]
        tone = sum(a * np.sin(2 * np.pi * f * u) * np.exp(-u * dec) for f, a, dec in
                   ((196, 1.0, 0.9), (392, 0.5, 1.4), (467, 0.35, 1.8), (588, 0.25, 2.2), (98, 0.4, 0.7)))
        out[s:] += tone
    return lp(out, 2500) * np.minimum(1, tt * 50)

# Night falls: a chorus of distant moans rising together.
def horde_howl():
    d = 3.5; tt = t(d); out = np.zeros(len(tt))
    for k in range(7):
        f0 = rng.uniform(85, 150); vib = rng.uniform(3, 6); st = rng.uniform(0, 0.8)
        u = np.clip(tt - st, 0, None)
        f = f0 * (1 + 0.25 * np.clip(u / 1.5, 0, 1)) * (1 + 0.02 * np.sin(2 * np.pi * vib * u))
        ph = 2 * np.cumsum(f) * np.pi / SR
        voice = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)) * (u > 0)
        voice = bp(voice + noise(len(tt)) * 0.15, 200, 1400)
        out += voice * np.sin(np.pi * np.clip(u / (d - st), 0, 1)) * rng.uniform(0.5, 1.0)
    return lp(out, 1800)

for name, fn in [("barricade_hit", barricade_hit), ("barricade_break", barricade_break),
                 ("barricade_build", barricade_build), ("dusk_bell", dusk_bell), ("horde_howl", horde_howl)]:
    wav(name, fn())
    print("wrote", name)
