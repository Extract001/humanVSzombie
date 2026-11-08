# Phase 5 original synthesized placeholder SFX (deterministic, no samples).
import math, random, struct, wave, sys
OUT = sys.argv[1]; SR = 22050; R = random.Random(55)
def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples)); k = 0.85 / peak
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))
# search: rustling = several short filtered noise bursts
n = int(SR * 0.6); out = [0.0] * n
for start in (0.0, 0.12, 0.27, 0.41):
    s0 = int(start * SR); p = 0.0
    for i in range(int(SR * 0.11)):
        if s0 + i < n:
            p += 0.35 * (R.uniform(-1, 1) - p)
            out[s0 + i] += p * math.sin(math.pi * i / (SR * 0.11))
write("search", out)
# pickup: short soft two-note blip
n = int(SR * 0.14)
write("pickup", [math.sin(2 * math.pi * (520 if i < n // 2 else 780) * i / SR) * math.exp(-18 * (i % (n // 2)) / SR) * 0.6 for i in range(n)])
# use item: unwrapping/tearing noise with a soft tone
n = int(SR * 0.35); p = 0.0; y = []
for i in range(n):
    p += 0.6 * (R.uniform(-1, 1) - p)
    y.append(p * (0.5 + 0.5 * math.sin(2 * math.pi * 23 * i / SR)) * math.exp(-5 * i / SR) + 0.2 * math.sin(2 * math.pi * 330 * i / SR) * math.exp(-9 * i / SR))
write("use_item", y)
# flashlight click: two tiny clicks
n = int(SR * 0.08); y = [0.0] * n
for start in (0, int(SR * 0.035)):
    for i in range(int(SR * 0.006)):
        if start + i < n:
            y[start + i] += R.uniform(-1, 1) * (1 - i / (SR * 0.006)) + 0.5 * math.sin(2 * math.pi * 2400 * i / SR)
write("flashlight_click", y)
