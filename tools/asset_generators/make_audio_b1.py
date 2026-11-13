# LAST SIGNAL batch 1 sounds: original, synthesized from code (no samples).
# Usage: python3 make_audio_b1.py <project folder>
import sys, os, wave, numpy as np
from scipy.signal import lfilter, butter

OUT = sys.argv[1]
SFX = os.path.join(OUT, "assets/audio/sfx")
SR = 22050
rng = np.random.default_rng(1113)

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

# Screamer: a rising, ragged shriek.
def scream():
    d = 1.3; tt = t(d)
    f = 500 + 900 * np.clip(tt / 0.35, 0, 1) - 250 * np.clip((tt - 0.6) / 0.7, 0, 1)
    f = f * (1 + 0.03 * np.sin(2 * np.pi * 23 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    voice = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3.01 * ph)
    rasp = bp(noise(len(tt)), 1500, 6000) * 0.6
    env = np.clip(tt / 0.05, 0, 1) * np.clip((d - tt) / 0.4, 0, 1)
    return bp(voice + rasp, 300, 7000) * env

# Supply drop: a plane passing over, then a heavy crate thud.
def supply_drop():
    d = 3.2; tt = t(d); n = len(tt)
    drone = lp(noise(n), 400) * np.sin(np.pi * np.clip(tt / 2.4, 0, 1)) ** 2 * 0.8
    hum = np.sin(2 * np.pi * (95 + 10 * np.sin(tt)) * tt) * np.sin(np.pi * np.clip(tt / 2.4, 0, 1)) * 0.3
    out = drone + hum
    s = int(2.6 * SR); u = t(0.5)
    thud = (np.sin(2 * np.pi * (60 * np.exp(-u * 8) + 40) * u) * np.exp(-u * 9) + lp(noise(len(u)), 800) * np.exp(-u * 15))
    out[s:s + len(u)] += thud[: n - s] * 1.6
    return out

# Special night announced: a low ominous swell with a metallic hit.
def event_sting():
    d = 2.6; tt = t(d)
    swell = sum(np.sin(2 * np.pi * f * tt) * a for f, a in ((55, 1), (82.4, 0.6), (110, 0.4), (116.5, 0.3)))
    swell *= np.clip(tt / 1.6, 0, 1) * np.clip((d - tt) / 0.6, 0, 1)
    hit = (np.sin(2 * np.pi * 440 * tt) + 0.6 * np.sin(2 * np.pi * 1187 * tt)) * np.exp(-tt * 3) * 0.4
    return lp(swell, 600) + hit

for name, fn in [("scream", scream), ("supply_drop", supply_drop), ("event_sting", event_sting)]:
    wav(name, fn())
    print("wrote", name)
