# LAST SIGNAL Phase 9 audio: original sounds synthesized from code (no samples, no recordings).
# SFX -> 16-bit WAV, loops (ambience, music) -> Ogg Vorbis via ffmpeg.
import sys, os, subprocess, numpy as np
from scipy.signal import lfilter, butter

OUT = sys.argv[1]
SFX = os.path.join(OUT, "assets/audio/sfx")
LOOPS = os.path.join(OUT, "assets/audio/music")
os.makedirs(LOOPS, exist_ok=True)
SR = 22050
rng = np.random.default_rng(2026)

def norm(x, peak=0.89):
    m = np.max(np.abs(x)) or 1.0
    return x * (peak / m)

def wav(name, x, sr=SR):
    import wave
    y = (np.clip(norm(x), -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(SFX, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(y.tobytes())

def ogg(name, x, sr=SR, peak=0.8):
    import wave, tempfile
    y = (np.clip(norm(x, peak), -1, 1) * 32767).astype("<i2")
    tmp = os.path.join(tempfile.gettempdir(), name + ".wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(y.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "3",
                    os.path.join(LOOPS, name + ".ogg")], check=True)

def t(dur, sr=SR): return np.arange(int(dur * sr)) / sr
def noise(n): return rng.uniform(-1, 1, n)
def lp(x, hz, sr=SR, order=2):
    b, a = butter(order, min(hz / (sr / 2), 0.99), "low"); return lfilter(b, a, x)
def hp(x, hz, sr=SR, order=2):
    b, a = butter(order, hz / (sr / 2), "high"); return lfilter(b, a, x)
def bp(x, lo, hi, sr=SR, order=2):
    b, a = butter(order, [lo / (sr / 2), min(hi / (sr / 2), 0.99)], "band"); return lfilter(b, a, x)
def resonator(x, f, bw, sr=SR):
    r = np.exp(-np.pi * bw / sr); th = 2 * np.pi * f / sr
    return lfilter([1 - r], [1, -2 * r * np.cos(th), r * r], x)
def reverb(x, sr=SR, mix=0.25, decay=0.35):
    # small "room": a few feedback-free echoes with lowpass
    out = x.copy()
    for d, g in ((0.031, 0.5), (0.047, 0.4), (0.071, 0.3), (0.103, 0.22), (0.149, 0.15)):
        k = int(d * sr); e = np.zeros_like(x); e[k:] = x[:-k] * g
        out += lp(e, 3000) * mix / 0.5
    return out
def pad(x, dur):
    n = int(dur * SR); return np.concatenate([x, np.zeros(max(0, n - len(x)))])
def seamless(x, fade_s, sr=SR):
    """Make a loop: crossfade the last fade_s seconds into the start."""
    f = int(fade_s * sr); body = x[:-f].copy(); tail = x[-f:]
    w = np.linspace(0, 1, f)
    body[:f] = body[:f] * w + tail * (1 - w)
    return body

# ---------------- improved SFX ----------------
def pistol():
    n = t(0.6)
    crack = noise(len(n)) * np.exp(-n * 60)
    crack = hp(crack, 1200) * 1.0
    body = np.sin(2 * np.pi * (140 * np.exp(-n * 9)) * n) * np.exp(-n * 16)
    rumble = lp(noise(len(n)), 300) * np.exp(-n * 5) * 2.0
    return reverb(crack + body * 0.9 + rumble * 0.6, mix=0.35)

def growl(dur, f0, f1, formants, rough=0.35, seed=0):
    g = np.random.default_rng(seed)
    n = t(dur); f = np.linspace(f0, f1, len(n)) * (1 + 0.04 * np.sin(2 * np.pi * 7 * n)) + g.normal(0, 4, len(n))
    ph = np.cumsum(f / SR); src = 2 * (ph % 1.0) - 1
    src = src * (1 - rough) + g.uniform(-1, 1, len(n)) * rough
    out = sum(resonator(src, fq, bw) * gain for fq, bw, gain in formants)
    e = np.sin(np.pi * np.linspace(0, 1, len(n))) ** 0.6
    return out * e

def flesh():
    n = t(0.2); x = lp(noise(len(n)), 900) * np.exp(-n * 25)
    return x + np.sin(2 * np.pi * 70 * n) * np.exp(-n * 30) * 0.5

def melee():
    n = t(0.22)
    thud = np.sin(2 * np.pi * (90 * np.exp(-n * 6)) * n) * np.exp(-n * 20)
    crack = bp(noise(len(n)), 600, 3000) * np.exp(-n * 50)
    return thud + crack * 0.6

def step(seed, dur=0.09, bright=1800):
    g = np.random.default_rng(seed); n = t(dur)
    x = bp(g.uniform(-1, 1, len(n)), 120, bright) * np.exp(-n * 55)
    x += np.sin(2 * np.pi * 60 * n) * np.exp(-n * 60) * 0.6
    return x

def shuffle(seed):
    g = np.random.default_rng(seed); n = t(0.28)
    x = bp(g.uniform(-1, 1, len(n)), 200, 1400) * (np.sin(np.pi * np.linspace(0, 1, len(n))) ** 2)
    return x * 0.8

def ui_click():
    n = t(0.05)
    return np.sin(2 * np.pi * 1300 * n) * np.exp(-n * 120) + hp(noise(len(n)), 3000) * np.exp(-n * 200) * 0.3

def distant_groan(seed):
    x = growl(1.6, 95, 70, [(400, 120, 1.0), (900, 200, 0.5), (2400, 300, 0.15)], 0.3, seed)
    x = lp(x, 900)
    return reverb(x, mix=0.6)

# ---------------- loops ----------------
def amb_outside(dur=32.0):
    n = t(dur + 3)
    wind = lp(noise(len(n)), 500) * (0.55 + 0.45 * np.sin(2 * np.pi * n / 11.0) ** 2)
    gust = bp(noise(len(n)), 500, 1400) * np.clip(np.sin(2 * np.pi * n / 7.3 + 1.0), 0, 1) ** 4 * 0.35
    city = lp(noise(len(n)), 90) * 1.5
    x = wind + gust + city
    for k in range(5):                          # far-off clanks / dog barks as soft pings
        at = rng.uniform(1, dur); i = int(at * SR)
        m = t(0.6); ping = np.sin(2 * np.pi * rng.uniform(300, 700) * m) * np.exp(-m * 8) * 0.12
        x[i:i + len(ping)] += lp(ping, 1200)[: len(x[i:i + len(ping)])]
    return seamless(x, 3.0)

def amb_safehouse(dur=32.0):
    n = t(dur + 3)
    rain = hp(noise(len(n)), 1500) * 0.35 + bp(noise(len(n)), 300, 1200) * 0.25
    drops = np.zeros(len(n))
    for k in range(int(dur * 18)):
        i = rng.integers(0, len(n) - 400); m = np.arange(300) / SR
        drops[i:i + 300] += np.sin(2 * np.pi * rng.uniform(1800, 3400) * m) * np.exp(-m * 160) * rng.uniform(0.05, 0.25)
    static = bp(noise(len(n)), 2000, 5000) * 0.05 * (0.6 + 0.4 * np.sin(2 * np.pi * n / 5.0))
    return seamless(rain + drops + static, 3.0)

def note(f, dur, kind="pad"):
    n = t(dur)
    if kind == "pad":
        x = sum(np.sin(2 * np.pi * f * h * n + h) / h for h in (1, 2, 3)) * np.sin(np.pi * np.linspace(0, 1, len(n))) ** 1.5
    elif kind == "pluck":
        x = (np.sin(2 * np.pi * f * n) + 0.4 * np.sin(2 * np.pi * 2.01 * f * n)) * np.exp(-n * 3.5)
    else:  # drone
        x = sum(np.sin(2 * np.pi * f * h * n) / h for h in (1, 2, 4))
    return x

def music_outside(dur=48.0):
    n = t(dur + 4); x = np.zeros(len(n))
    x += note(55.0, dur + 4, "drone") * 0.5 * (0.7 + 0.3 * np.sin(2 * np.pi * n / 12))     # A1 drone
    x += note(82.4, dur + 4, "drone") * 0.18 * (0.5 + 0.5 * np.sin(2 * np.pi * n / 9 + 1))  # E2
    swell = lp(noise(len(n)), 250) * np.sin(np.pi * ((n % 16) / 16)) ** 3 * 1.2
    x += swell
    plucks = [(2.0, 220.0), (6.5, 233.1), (11.0, 207.7), (18.0, 220.0), (22.5, 261.6), (27.0, 246.9), (34.0, 233.1), (40.0, 207.7)]
    for at, f in plucks:                      # sparse, slightly dissonant piano-like notes
        i = int(at * SR); p = note(f, 3.0, "pluck") * 0.35
        x[i:i + len(p)] += p[: len(x[i:i + len(p)])]
    heartbeat = np.zeros(len(n))
    for k in range(int(dur / 1.6)):
        for off in (0.0, 0.22):
            i = int((k * 1.6 + off) * SR); m = t(0.15)
            b = np.sin(2 * np.pi * 48 * m) * np.exp(-m * 30) * (0.5 if off else 0.7)
            heartbeat[i:i + len(b)] += b[: len(heartbeat[i:i + len(b)])]
    x += heartbeat * 0.5 * np.clip(np.sin(2 * np.pi * n / 24), 0, 1)
    return seamless(lp(x, 3000), 4.0)

def music_safehouse(dur=48.0):
    n = t(dur + 4); x = np.zeros(len(n))
    chords = [(146.8, 220.0, 293.7), (130.8, 196.0, 261.6), (110.0, 164.8, 220.0), (123.5, 185.0, 246.9)]  # Dm, C, Am, Bdim-ish
    for k in range(int((dur + 4) / 6)):
        for f in chords[k % 4]:
            i = int(k * 6 * SR); p = note(f, 7.5, "pad") * 0.18
            x[i:i + len(p)] += p[: len(x[i:i + len(p)])]
    for k in range(int(dur / 3)):              # soft guitar-ish plucks
        f = [293.7, 261.6, 220.0, 246.9, 329.6, 293.7][k % 6]
        i = int((k * 3 + 1.5) * SR); p = note(f, 2.5, "pluck") * 0.16
        x[i:i + len(p)] += p[: len(x[i:i + len(p)])]
    return seamless(lp(x, 2500), 4.0)

# write everything
wav("pistol_shot", pistol())
wav("zombie_grunt", growl(0.45, 125, 85, [(450, 120, 1.0), (1100, 180, 0.6), (2500, 250, 0.2)], 0.3, 1))
wav("zombie_death", growl(0.9, 115, 50, [(400, 120, 1.0), (950, 200, 0.6), (2300, 300, 0.15)], 0.4, 2))
wav("player_hurt", growl(0.22, 190, 140, [(700, 150, 1.0), (1200, 180, 0.7), (2600, 300, 0.25)], 0.2, 3))
wav("flesh_hit", flesh())
wav("melee_hit", melee())
wav("step_1", step(11)); wav("step_2", step(12)); wav("step_3", step(13, 0.1, 1400))
wav("zombie_shuffle", shuffle(21))
wav("groan_distant_1", distant_groan(31)); wav("groan_distant_2", distant_groan(32))
wav("ui_click", ui_click())
ogg("amb_outside", amb_outside(), peak=0.6)
ogg("amb_safehouse", amb_safehouse(), peak=0.55)
ogg("music_outside", music_outside(), peak=0.7)
ogg("music_safehouse", music_safehouse(), peak=0.6)
print("audio done")
