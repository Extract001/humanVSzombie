# Original synthesized placeholder SFX for LAST SIGNAL (deterministic, no external samples).
import math, random, struct, wave, sys
OUT = sys.argv[1]
SR = 22050
R = random.Random(42)

def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    k = 0.89 / peak
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))

def lowpass(x, a):
    y, p = [], 0.0
    for s in x:
        p += a * (s - p); y.append(p)
    return y

def env(n, attack, decay_k):
    return [min(1.0, i / max(1, attack)) * math.exp(-decay_k * i / SR) for i in range(n)]

def noise(n): return [R.uniform(-1, 1) for _ in range(n)]

# pistol shot: sharp crack + low thump + tail
n = int(SR * 0.45)
crack = [a * b for a, b in zip(noise(n), env(n, 10, 28))]
thump = [math.sin(2 * math.pi * (110 - 60 * i / n) * i / SR) * math.exp(-14 * i / SR) for i in range(n)]
tail = lowpass([a * b for a, b in zip(noise(n), env(n, 200, 6))], 0.08)
write("pistol_shot", [0.9 * c + 0.8 * t + 0.35 * tl for c, t, tl in zip(crack, thump, tail)])

# dry fire click
n = int(SR * 0.05)
write("dry_fire", [s * math.exp(-120 * i / SR) for i, s in enumerate(noise(n))])

# reload: two mechanical clicks
n = int(SR * 0.5); out = [0.0] * n
for start, f in ((0.02, 2600), (0.32, 1900)):
    s0 = int(start * SR)
    for i in range(int(SR * 0.04)):
        if s0 + i < n:
            out[s0 + i] += (R.uniform(-1, 1) * 0.6 + math.sin(2 * math.pi * f * i / SR) * 0.4) * math.exp(-90 * i / SR)
write("reload", out)

# whoosh (swing / shove): band-limited noise with a rise-fall envelope
def whoosh(dur, cutoff_start, cutoff_end):
    n = int(SR * dur); x = noise(n); y = []; p = 0.0
    for i, s in enumerate(x):
        a = cutoff_start + (cutoff_end - cutoff_start) * i / n
        p += a * (s - p)
        e = math.sin(math.pi * i / n) ** 2
        y.append(p * e)
    return y
write("bat_swing", whoosh(0.2, 0.05, 0.25))
write("shove", whoosh(0.18, 0.03, 0.12))

# melee impact: low thud + short noise
n = int(SR * 0.18)
write("melee_hit", [0.9 * math.sin(2 * math.pi * (95 - 40 * i / n) * i / SR) * math.exp(-22 * i / SR)
                    + 0.5 * s * math.exp(-60 * i / SR) for i, s in enumerate(noise(n))])

# bullet impact on zombie: wet, muffled
n = int(SR * 0.15)
write("flesh_hit", [x * math.exp(-30 * i / SR) for i, x in enumerate(lowpass(noise(n), 0.12))])

# zombie grunt: low growl (saw with jitter and pitch drop)
def growl(dur, f0, f1):
    n = int(SR * dur); ph = 0.0; y = []
    for i in range(n):
        f = f0 + (f1 - f0) * i / n + R.uniform(-6, 6)
        ph += f / SR
        saw = 2 * (ph % 1.0) - 1
        y.append(saw * math.sin(math.pi * i / n) * (0.7 + 0.3 * R.random()))
    return lowpass(y, 0.15)
write("zombie_grunt", growl(0.35, 120, 80))
write("zombie_death", growl(0.7, 110, 55))

# player hurt: short low grunt
write("player_hurt", growl(0.2, 170, 120))
print("sfx ok")
