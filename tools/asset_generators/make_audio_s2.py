# LAST SIGNAL Slice 2 sounds: original, synthesized from code (no samples).
# Usage: python3 make_audio_s2.py <project folder>
import sys, os, wave, numpy as np
from scipy.signal import lfilter, butter

OUT = sys.argv[1]
SFX = os.path.join(OUT, "assets/audio/sfx")
SR = 22050
rng = np.random.default_rng(2026)

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

# Shotgun: a deep boom with a long tail, then the pump (two clacks).
def shotgun_shot():
    d = 1.1; tt = t(d); n = len(tt)
    blast = lp(noise(n), 2200) * np.exp(-tt * 9) * 1.4 + bp(noise(n), 2000, 7000) * np.exp(-tt * 40) * 0.6
    boom = np.sin(2 * np.pi * (70 * np.exp(-tt * 6) + 35) * tt) * np.exp(-tt * 7) * 1.5
    out = blast + boom
    for at in (0.55, 0.72):
        s = int(at * SR); m = int(0.05 * SR)
        clack = bp(noise(m), 900, 4500) * np.exp(-np.arange(m) / SR / 0.01) * 0.35
        out[s:s + m] += clack
    return out

# Fire axe hitting: a heavy, wet chop.
def axe_hit():
    d = 0.35; tt = t(d); n = len(tt)
    chop = bp(noise(n), 300, 2500) * np.exp(-tt * 25) * 1.2
    thud = np.sin(2 * np.pi * (110 * np.exp(-tt * 10) + 50) * tt) * np.exp(-tt * 12)
    wet = lp(noise(n), 1200) * np.exp(-tt * 14) * 0.5
    return chop + thud * 1.3 + wet

for name, fn in [("shotgun_shot", shotgun_shot), ("axe_hit", axe_hit)]:
    wav(name, fn())
    print("wrote", name)
