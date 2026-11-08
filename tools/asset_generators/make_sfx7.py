# Phase 7 original synthesized placeholder SFX (deterministic, no samples).
import math, random, struct, wave, sys
OUT = sys.argv[1]; SR = 22050; R = random.Random(77)
def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples)); k = 0.85 / peak
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))
# chain cut: hard metallic snap + ringing + chain rattle
n = int(SR * 0.9); y = []
for i in range(n):
    t = i / SR
    snap = R.uniform(-1, 1) * math.exp(-60 * t)
    ring = sum(math.sin(2 * math.pi * f * t) for f in (1870, 2630, 3410)) / 3 * math.exp(-7 * t) * 0.5
    rattle = 0.0
    if 0.12 < t < 0.8:
        rattle = R.uniform(-1, 1) * 0.35 * abs(math.sin(2 * math.pi * 14 * t)) * math.exp(-3 * (t - 0.12))
    y.append(snap + ring + rattle)
write("chain_cut", y)
# radio: static that resolves into a steady tone
n = int(SR * 2.0); y = []; p = 0.0
for i in range(n):
    t = i / SR
    p += 0.5 * (R.uniform(-1, 1) - p)
    clear = min(1.0, t / 1.4)
    y.append(p * (1 - clear) * 0.8 + math.sin(2 * math.pi * 640 * t) * clear * 0.25 * (0.6 + 0.4 * math.sin(2 * math.pi * 3 * t)))
write("radio_on", y)
