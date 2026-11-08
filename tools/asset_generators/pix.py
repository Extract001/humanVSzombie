# Small pixel-art toolkit for LAST SIGNAL (original art, generated from code).
import random
from PIL import Image

OUTLINE = (22, 19, 17, 255)

def rgba(c, a=255):
    return (c[0], c[1], c[2], a) if len(c) == 3 else c

def shade(c, k):
    """k < 1 darker, > 1 lighter."""
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)

def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)

class Canvas:
    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.img.load()
        self.w, self.h = w, h
    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = rgba(c)
    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, c)
    def hline(self, x, y, w, c): self.rect(x, y, w, 1, c)
    def vline(self, x, y, h, c): self.rect(x, y, 1, h, c)
    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y]
        return (0, 0, 0, 0)
    def outline(self, color=OUTLINE, region=None):
        x0, y0, x1, y1 = region or (0, 0, self.w, self.h)
        add = []
        for y in range(y0, y1):
            for x in range(x0, x1):
                if self.px[x, y][3] != 0:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if x0 <= nx < x1 and y0 <= ny < y1 and self.px[nx, ny][3] != 0 and self.px[nx, ny] != color:
                        add.append((x, y)); break
        for x, y in add:
            self.px[x, y] = color
    def paste(self, other, x, y):
        self.img.alpha_composite(other.img, (x, y))
        self.px = self.img.load()
    def save(self, path):
        self.img.save(path)

def noise_fill(cv, x, y, w, h, base, amount, rng, speck=None, speck_chance=0.0):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            k = 1.0 + rng.uniform(-amount, amount)
            c = shade(base, k)
            if speck and rng.random() < speck_chance:
                c = rgba(speck)
            cv.put(xx, yy, c)
