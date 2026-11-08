# LAST SIGNAL fun pass sounds: original, synthesized from code (no samples).
# Usage: python3 make_audio_fun.py <project folder>
import sys, os, wave, numpy as np
from scipy.signal import lfilter, butter

OUT = sys.argv[1]
SFX = os.path.join(OUT, "assets/audio/sfx")
SR = 22050
rng = np.random.default_rng(777)

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

# Kill: a wet crunch + low thump.
def kill_crunch():
    d = 0.32; n = int(d * SR); tt = t(d)
    crunch = np.zeros(n)
    for k in range(6):
        s = int(rng.uniform(0, 0.08) * SR); m = int(0.03 * SR)
        crunch[s:s + m] += bp(noise(m), 700, 3500) * np.exp(-np.arange(m) / SR / 0.008) * rng.uniform(0.5, 1)
    thump = np.sin(2 * np.pi * (90 * np.exp(-tt * 8) + 40) * tt) * np.exp(-tt * 14)
    squish = lp(noise(n), 900) * np.exp(-tt * 18) * 0.6
    return crunch + thump * 1.2 + squish

# Streak: a short rising two-note chime.
def streak():
    out = np.zeros(int(0.35 * SR))
    for at, f in ((0.0, 660), (0.08, 990)):
        s = int(at * SR); u = t(0.27)
        tone = (np.sin(2 * np.pi * f * u) + 0.3 * np.sin(2 * np.pi * 2 * f * u)) * np.exp(-u * 12)
        out[s:s + len(u)] += tone[: len(out) - s]
    return out

# Low health: one heartbeat (lub-dub).
def heartbeat():
    out = np.zeros(int(0.6 * SR))
    for at, a in ((0.0, 1.0), (0.17, 0.7)):
        u = t(0.16); beat = np.sin(2 * np.pi * (55 + 25 * np.exp(-u * 30)) * u) * np.exp(-u * 22) * a
        s = int(at * SR); out[s:s + len(u)] += beat
    return lp(out, 300)

for name, fn in [("kill_crunch", kill_crunch), ("streak", streak), ("heartbeat", heartbeat)]:
    wav(name, fn())
    print("wrote", name)
