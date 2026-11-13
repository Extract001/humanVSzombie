# Tiles, roof, vehicles, containers, safehouse furniture, item icons, game icon (original art).
import sys, random, math
sys.path.insert(0, __import__("os").path.dirname(__file__))
from pix import *

OUT = sys.argv[1]  # project root
T = 16

def tile_canvas(): return Canvas(T, T)

def asphalt(rng, line=False):
    c = tile_canvas()
    noise_fill(c, 0, 0, T, T, (60, 61, 62), 0.07, rng, speck=(74, 74, 72), speck_chance=0.06)
    for _ in range(3):
        c.put(rng.randrange(T), rng.randrange(T), (46, 47, 48))
    if rng.random() < 0.5:  # hairline crack
        x, y = rng.randrange(2, 14), rng.randrange(2, 14)
        for i in range(4):
            c.put(x, y, (42, 42, 43)); x += rng.choice((-1, 0, 1)); y += 1
    if line:
        for x in range(2, 14):
            if rng.random() < 0.85:
                c.put(x, 7, (176, 152, 82)); c.put(x, 8, (160, 138, 74))
    return c

def sidewalk(rng):
    c = tile_canvas()
    noise_fill(c, 0, 0, T, T, (124, 120, 110), 0.05, rng, speck=(106, 102, 94), speck_chance=0.08)
    c.hline(0, 0, T, (96, 92, 84)); c.vline(0, 0, T, (96, 92, 84))
    c.hline(1, 1, 15, (138, 134, 124))
    return c

def grass(rng):
    c = tile_canvas()
    noise_fill(c, 0, 0, T, T, (66, 78, 50), 0.08, rng)
    for _ in range(18):
        x, y = rng.randrange(T), rng.randrange(1, T)
        col = rng.choice([(84, 98, 60), (54, 64, 42), (92, 102, 64)])
        c.put(x, y, col); c.put(x, y - 1, shade(col, 1.1))
    return c

def concrete(rng):
    c = tile_canvas()
    noise_fill(c, 0, 0, T, T, (100, 98, 92), 0.05, rng, speck=(88, 86, 80), speck_chance=0.05)
    if rng.random() < 0.6:
        cx, cy = rng.randrange(3, 13), rng.randrange(3, 13)
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if dx * dx + dy * dy <= 4 and rng.random() < 0.8:
                    c.put(cx + dx, cy + dy, (86, 84, 78))
    return c

def wood(rng):
    c = tile_canvas()
    for p in range(4):
        base = rng.choice([(108, 78, 52), (100, 72, 48), (114, 84, 56)])
        noise_fill(c, 0, p * 4, T, 4, base, 0.05, rng)
        c.hline(0, p * 4 + 3, T, (66, 46, 32))
        off = rng.randrange(4, 12)
        c.vline(off, p * 4, 3, (78, 56, 38))
        c.put(rng.randrange(T), p * 4 + 1, shade(base, 0.85))
    return c

def wall(rng):
    c = tile_canvas()
    for row in range(4):
        y = row * 4
        shift = 4 if row % 2 else 0
        for b in range(-1, 3):
            x = b * 8 + shift
            base = rng.choice([(86, 74, 68), (80, 68, 62), (92, 78, 70)])
            c.rect(x, y, 7, 3, base)
            c.hline(x, y, 7, shade(base, 1.18))
        c.hline(0, y + 3, T, (48, 42, 40))
    for x in range(T):
        for y in range(T):
            if c.get(x, y)[3] == 0:
                c.put(x, y, (48, 42, 40))
    return c

def crate(rng):
    c = tile_canvas()
    noise_fill(c, 1, 1, 14, 14, (128, 96, 58), 0.05, rng)
    for i in range(14):
        c.put(1 + i, 1 + i, (96, 70, 42)); c.put(14 - i, 1 + i, (96, 70, 42))
    c.rect(1, 1, 14, 2, (146, 112, 70)); c.rect(1, 13, 14, 2, (104, 76, 46))
    c.rect(1, 1, 2, 14, (140, 106, 66)); c.rect(13, 1, 2, 14, (104, 76, 46))
    c.outline((48, 36, 26))
    for x in range(T):
        for y in range(T):
            if c.get(x, y)[3] == 0: c.put(x, y, (48, 36, 26))
    return c

def roof(rng):
    c = tile_canvas()
    for row in range(4):
        y = row * 4
        shift = 2 if row % 2 else 0
        for b in range(-1, 5):
            x = b * 4 + shift
            base = rng.choice([(70, 56, 52), (64, 52, 48), (76, 60, 54)])
            c.rect(x, y, 3, 3, base)
            c.hline(x, y + 2, 3, shade(base, 0.8))
        c.hline(0, y + 3, T, (40, 32, 30))
    for x in range(T):
        for y in range(T):
            if c.get(x, y)[3] == 0: c.put(x, y, (40, 32, 30))
    return c

def shelf(rng):
    c = tile_canvas()
    c.rect(0, 0, T, T, (58, 52, 46))
    c.rect(1, 1, 14, 14, (84, 76, 66))
    c.hline(1, 7, 14, (58, 52, 46))
    goods = [(132, 70, 58), (70, 96, 120), (156, 136, 82), (92, 112, 74), (150, 146, 136), (120, 90, 120)]
    for half in (1, 8):
        x = 2
        while x < 14:
            w = rng.choice((2, 3))
            col = rng.choice(goods)
            h = rng.choice((4, 5))
            c.rect(x, half + (6 - h), min(w, 14 - x), h, col)
            c.hline(x, half + (6 - h), min(w, 14 - x), shade(col, 1.25))
            x += w + rng.choice((0, 1))
    return c

def counter(rng):
    c = tile_canvas()
    noise_fill(c, 0, 0, T, T, (146, 128, 100), 0.04, rng)
    c.hline(0, 0, T, (172, 154, 124)); c.hline(0, 14, T, (100, 86, 66)); c.hline(0, 15, T, (70, 60, 46))
    return c

def fence(rng):
    c = tile_canvas()
    noise_fill(c, 0, 0, T, T, (90, 78, 58), 0.07, rng)   # dirt seen between the rails
    for y in (4, 11):
        c.rect(0, y, T, 2, (122, 98, 66)); c.hline(0, y, T, (148, 120, 82)); c.hline(0, y + 2, T, (60, 48, 34))
    c.rect(7, 1, 3, 14, (108, 84, 56)); c.vline(7, 1, 14, (132, 104, 70)); c.vline(10, 1, 14, (60, 46, 32))
    return c

def tilefloor(rng):
    c = tile_canvas()
    for ty in range(2):
        for tx in range(2):
            base = rng.choice([(176, 176, 168), (168, 168, 160), (180, 178, 170)])
            noise_fill(c, tx * 8, ty * 8, 8, 8, base, 0.025, rng)
    for i in range(T):
        c.put(i, 0, (120, 118, 112)); c.put(0, i, (120, 118, 112)); c.put(i, 8, (128, 126, 120)); c.put(8, i, (128, 126, 120))
    if rng.random() < 0.5:
        c.put(rng.randrange(1, 15), rng.randrange(1, 15), (140, 138, 128))
    return c

def dirt(rng):
    c = tile_canvas()
    noise_fill(c, 0, 0, T, T, (92, 76, 58), 0.09, rng)
    for _ in range(5):
        x, y = rng.randrange(T), rng.randrange(T)
        c.put(x, y, (124, 112, 96)); c.put(x + 1, y, (72, 60, 46))
    return c

def tiles():
    rng = random.Random(9)
    makers = [lambda r: asphalt(r), lambda r: asphalt(r, True), sidewalk, grass, concrete, wood, wall, crate,
              roof, shelf, counter, fence, tilefloor, dirt]
    sheet = Canvas(T * len(makers), T)
    for i, m in enumerate(makers):
        sheet.paste(m(rng), i * T, 0)
    sheet.save(f"{OUT}/assets/tiles/tiles.png")
    roof(random.Random(3)).save(f"{OUT}/assets/tiles/roof.png")

# ---------------- vehicles (drawn pointing right) ----------------
def car(w, h, body, rng, pickup=False, bus=False):
    c = Canvas(w, h)
    glass, glass_hi = (52, 66, 76), (96, 118, 128)
    c.rect(1, 1, w - 2, h - 2, body)
    c.hline(2, 1, w - 4, shade(body, 1.22))
    c.hline(2, h - 2, w - 4, shade(body, 0.68))
    c.vline(w - 2, 2, h - 4, shade(body, 1.1))
    if bus:
        c.rect(3, 3, w - 6, h - 6, shade(body, 1.06))                 # roof
        for x in range(6, w - 8, 6):                                   # roof ribs
            c.vline(x, 3, h - 6, shade(body, 0.9))
        c.rect(20, 8, 8, 8, (120, 124, 120)); c.hline(20, 8, 8, (150, 154, 150))   # AC unit
        c.rect(48, 9, 6, 6, shade(body, 0.8))                          # roof hatch
        c.rect(w - 5, 3, 3, h - 6, glass); c.vline(w - 5, 3, h - 6, glass_hi)       # windscreen
    else:
        hood_end = w - 2
        ws = w - 12 if not pickup else 22        # windscreen x
        roof_x0 = ws - (9 if not pickup else 8)
        c.rect(ws, 2, 3, h - 4, glass); c.vline(ws + 2, 3, h - 6, glass_hi)       # windscreen
        c.rect(roof_x0, 2, ws - roof_x0, h - 4, shade(body, 1.08))               # roof
        c.hline(roof_x0, 2, ws - roof_x0, shade(body, 1.3))
        c.rect(roof_x0 - 2, 2, 2, h - 4, glass)                                     # rear window
        c.vline(hood_end - 6, 3, h - 6, shade(body, 0.85))                          # hood line
        c.put(ws + 1, 1, shade(body, 0.6)); c.put(ws + 1, h - 2, shade(body, 0.6))  # mirrors
        if pickup:
            c.rect(2, 2, roof_x0 - 5, h - 4, shade(body, 0.72))                     # bed walls
            c.rect(3, 3, roof_x0 - 7, h - 6, (56, 46, 40))                          # bed floor
            for x in range(4, roof_x0 - 5, 3):
                c.vline(x, 3, h - 6, (66, 54, 46))
    for _ in range(int(w * h * 0.015)):          # rust and grime
        x, y = rng.randrange(2, w - 2), rng.randrange(2, h - 2)
        if c.get(x, y)[:3] not in (glass, glass_hi):
            c.put(x, y, rng.choice([(110, 70, 44), (84, 70, 56)]))
    for wx in (4, w - 10):                      # wheels peeking out
        c.rect(wx, 0, 6, 1, (30, 28, 26)); c.rect(wx, h - 1, 6, 1, (30, 28, 26))
    c.put(w - 2, 3, (214, 204, 160)); c.put(w - 2, h - 4, (214, 204, 160))  # headlights
    c.put(1, 3, (140, 44, 38)); c.put(1, h - 4, (140, 44, 38))              # tail lights
    c.outline()
    return c

def vehicles():
    rng = random.Random(21)
    car(32, 16, (122, 66, 58), rng).save(f"{OUT}/assets/sprites/car.png")
    car(40, 18, (82, 98, 112), rng, pickup=True).save(f"{OUT}/assets/sprites/pickup.png")
    car(80, 24, (168, 138, 72), rng, bus=True).save(f"{OUT}/assets/sprites/bus.png")

# ---------------- containers (16x16 frames) ----------------
def containers():
    rng = random.Random(5)
    sheet = Canvas(16 * 8, 16)
    def frame(i): return Canvas(16, 16)
    f = []
    # 0 shelf goods
    a = frame(0); a.rect(1, 3, 14, 11, (88, 78, 66)); a.hline(1, 3, 14, (110, 98, 84))
    for x in range(2, 14, 3): col = rng.choice([(140, 72, 60), (74, 100, 124), (160, 140, 84)]); a.rect(x, 5, 2, 7, col); a.put(x, 5, shade(col, 1.3))
    f.append(a)
    # 1 medical cabinet (green cross)
    a = frame(1); a.rect(2, 1, 12, 14, (196, 196, 186)); a.hline(2, 1, 12, (224, 224, 214)); a.vline(8, 2, 12, (150, 150, 142))
    a.rect(6, 5, 4, 1, (62, 140, 82)); a.rect(7, 4, 2, 3, (62, 140, 82)); a.rect(6, 5, 4, 1, (62, 140, 82))
    f.append(a)
    # 2 toolbox
    a = frame(2); a.rect(2, 6, 12, 7, (164, 58, 46)); a.hline(2, 6, 12, (196, 82, 64)); a.rect(6, 3, 4, 1, (60, 60, 60)); a.vline(5, 3, 3, (60, 60, 60)); a.vline(10, 3, 3, (60, 60, 60)); a.hline(2, 9, 12, (120, 40, 32))
    f.append(a)
    # 3 storage box
    a = frame(3); a.rect(2, 3, 12, 10, (150, 118, 76)); a.hline(2, 3, 12, (178, 144, 96)); a.vline(8, 3, 10, (190, 170, 120)); a.hline(2, 12, 12, (118, 90, 56))
    f.append(a)
    # 4 locker
    a = frame(4); a.rect(3, 0, 10, 16, (88, 102, 108)); a.hline(3, 0, 10, (116, 130, 136)); a.vline(8, 1, 15, (60, 70, 76))
    for y in (2, 3, 4): a.hline(4, y, 3, (60, 70, 76)); a.hline(9, y, 3, (60, 70, 76))
    a.put(7, 9, (190, 180, 130)); a.put(9, 9, (190, 180, 130))
    f.append(a)
    # 5 kitchen cupboard
    a = frame(5); a.rect(1, 2, 14, 12, (126, 104, 80)); a.hline(1, 2, 14, (150, 126, 98)); a.vline(8, 3, 11, (90, 72, 54))
    a.put(6, 8, (200, 190, 150)); a.put(10, 8, (200, 190, 150))
    f.append(a)
    # 6 backpack (olive canvas, distinct from the player's jacket: lighter khaki + orange tag)
    a = frame(6); a.rect(4, 3, 8, 11, (128, 118, 74)); a.hline(4, 3, 8, (156, 146, 96)); a.rect(5, 8, 6, 4, (110, 100, 62)); a.hline(5, 8, 6, (140, 130, 84))
    a.rect(6, 1, 4, 2, (86, 78, 50)); a.put(11, 5, (214, 120, 48)); a.put(11, 6, (214, 120, 48))
    f.append(a)
    # 7 dropped pile
    a = frame(7)
    for (x, y, col) in [(4, 9, (140, 72, 60)), (7, 8, (74, 100, 124)), (10, 10, (160, 140, 84)), (6, 11, (200, 200, 190)), (9, 7, (110, 120, 80))]:
        a.rect(x, y, 3, 3, col); a.hline(x, y, 3, shade(col, 1.25))
    f.append(a)
    for i, a in enumerate(f):
        a.outline()
        sheet.paste(a, i * 16, 0)
    sheet.save(f"{OUT}/assets/sprites/containers.png")

# ---------------- safehouse furniture (32x32 frames) ----------------
def safehouse():
    sheet = Canvas(128, 32)
    # bed
    a = Canvas(32, 32); a.rect(9, 1, 14, 30, (96, 66, 44)); a.rect(10, 2, 12, 6, (214, 206, 186)); a.hline(10, 2, 12, (234, 228, 210))
    a.rect(10, 9, 12, 21, (78, 96, 112)); a.hline(10, 9, 12, (98, 116, 132))
    for y in range(12, 30, 4): a.hline(11, y, 10, (70, 86, 102))
    a.rect(10, 9, 12, 3, (196, 188, 168))  # folded sheet
    a.outline(); sheet.paste(a, 0, 0)
    # stash (heavy chest)
    a = Canvas(32, 32); a.rect(2, 9, 28, 15, (118, 84, 50)); a.rect(2, 9, 28, 5, (140, 102, 60)); a.hline(2, 9, 28, (164, 122, 74))
    for x in (8, 16, 24): a.vline(x, 14, 10, (92, 64, 38))
    a.rect(1, 13, 30, 1, (70, 70, 72)); a.rect(14, 12, 4, 4, (190, 168, 92)); a.put(15, 14, (60, 50, 30))
    a.outline(); sheet.paste(a, 32, 0)
    # radio desk
    a = Canvas(32, 32); a.rect(1, 12, 30, 13, (104, 78, 54)); a.hline(1, 12, 30, (126, 96, 66))
    a.rect(4, 7, 15, 10, (58, 62, 56)); a.hline(4, 7, 15, (76, 82, 74)); a.rect(6, 9, 6, 4, (126, 168, 116)); a.put(14, 10, (200, 190, 150)); a.put(16, 10, (200, 190, 150))
    a.vline(17, 1, 6, (150, 150, 150)); a.put(18, 1, (190, 60, 50))
    a.rect(21, 15, 7, 6, (206, 200, 182)); a.hline(22, 17, 5, (120, 116, 104)); a.hline(22, 19, 4, (120, 116, 104))
    a.outline(); sheet.paste(a, 64, 0)
    # objective board
    a = Canvas(32, 32); a.rect(3, 4, 26, 19, (144, 106, 66)); a.rect(5, 6, 22, 15, (172, 132, 86))
    notes = [(6, 7, (232, 226, 200)), (15, 8, (204, 222, 230)), (8, 14, (232, 212, 160)), (19, 14, (232, 226, 200))]
    for (x, y, col) in notes:
        a.rect(x, y, 7, 5, col); a.hline(x + 1, y + 2, 5, shade(col, 0.75)); a.put(x + 3, y, (180, 40, 40))
    a.hline(10, 11, 10, (150, 40, 36))
    a.outline(); sheet.paste(a, 96, 0)
    sheet.save(f"{OUT}/assets/sprites/safehouse.png")

# ---------------- item icons (16x16) ----------------
def items():
    sheet = Canvas(192, 16)
    def icon(i, draw):
        a = Canvas(16, 16); draw(a); a.outline(); sheet.paste(a, i * 16, 0)
    def can(a):
        a.rect(4, 3, 8, 11, (168, 168, 160)); a.hline(4, 3, 8, (204, 204, 196)); a.rect(4, 6, 8, 5, (176, 64, 50)); a.hline(4, 6, 8, (204, 90, 70)); a.hline(4, 13, 8, (120, 120, 114))
    def water(a):
        a.rect(5, 4, 6, 10, (110, 160, 196)); a.vline(6, 5, 8, (170, 210, 230)); a.rect(6, 2, 4, 2, (60, 90, 150)); a.rect(5, 8, 6, 2, (230, 230, 220))
    def bandage(a):
        a.rect(3, 5, 10, 7, (226, 220, 204)); a.hline(3, 5, 10, (246, 242, 230)); a.rect(6, 5, 4, 7, (200, 192, 172)); a.rect(7, 7, 2, 3, (176, 70, 60))
    def medkit(a):
        a.rect(2, 4, 12, 10, (196, 196, 186)); a.hline(2, 4, 12, (226, 226, 216)); a.rect(6, 2, 4, 2, (120, 120, 114)); a.rect(7, 6, 2, 6, (62, 140, 82)); a.rect(5, 8, 6, 2, (62, 140, 82))
    def ammo_p(a):
        for x in (3, 7, 11):
            a.rect(x, 6, 2, 7, (196, 160, 70)); a.rect(x, 4, 2, 2, (160, 120, 80)); a.put(x, 6, (230, 200, 110))
    def ammo_s(a):
        for x in (3, 8):
            a.rect(x, 4, 4, 7, (176, 52, 44)); a.hline(x, 4, 4, (210, 80, 64)); a.rect(x, 11, 4, 3, (196, 160, 70))
    def scrap(a):
        a.rect(3, 8, 7, 4, (120, 124, 128)); a.hline(3, 8, 7, (160, 164, 168)); a.rect(8, 4, 5, 3, (140, 96, 60)); a.vline(5, 3, 5, (100, 104, 108)); a.put(11, 11, (90, 92, 96))
    def battery(a):
        a.rect(5, 4, 6, 10, (46, 48, 50)); a.rect(5, 4, 6, 3, (196, 160, 60)); a.rect(7, 2, 2, 2, (180, 180, 172)); a.vline(6, 8, 5, (70, 72, 76))
    def cutters(a):
        for i in range(8):
            a.put(3 + i, 12 - i, (150, 150, 156)); a.put(12 - i, 12 - i, (150, 150, 156))
        a.rect(2, 12, 3, 3, (176, 52, 44)); a.rect(11, 12, 3, 3, (176, 52, 44)); a.put(7, 5, (90, 90, 96)); a.put(8, 5, (90, 90, 96))
    def radio_part(a):
        a.rect(3, 5, 10, 8, (60, 112, 72)); a.hline(3, 5, 10, (84, 140, 96))
        for x in (5, 8, 11): a.rect(x - 1, 7, 2, 2, (40, 40, 40))
        for x in range(4, 13, 2): a.put(x, 13, (196, 170, 90)); a.put(x, 14, (196, 170, 90))
        a.put(6, 10, (210, 80, 60)); a.put(9, 10, (230, 200, 110))
    def shotgun(a):   # Slice 2
        a.rect(2, 8, 4, 3, (120, 84, 50)); a.hline(2, 8, 4, (150, 108, 66))
        a.rect(6, 7, 8, 2, (64, 66, 70)); a.hline(6, 7, 8, (104, 106, 112)); a.rect(7, 9, 4, 2, (134, 96, 58)); a.rect(5, 8, 1, 3, (52, 50, 50))
    def fire_axe(a):
        for i in range(9):
            a.put(3 + i, 13 - i, (132, 94, 56)); a.put(4 + i, 13 - i, (164, 120, 74))
        a.rect(9, 2, 5, 5, (176, 46, 40)); a.hline(9, 2, 5, (204, 70, 58)); a.vline(13, 2, 5, (196, 200, 206))
    for i, d in enumerate([can, water, bandage, medkit, ammo_p, ammo_s, scrap, battery, cutters, radio_part, shotgun, fire_axe]):
        icon(i, d)
    sheet.save(f"{OUT}/assets/sprites/items.png")

# ---------------- game icon (64x64) ----------------
def game_icon():
    c = Canvas(64, 64)
    c.rect(0, 0, 64, 64, (18, 18, 17))
    cx, cy = 32, 30
    for i, r in enumerate((10, 17, 24, 30)):
        col = mix((158, 219, 230), (18, 18, 17), i * 0.22)
        for a in range(0, 360, 2):
            ang = math.radians(a)
            if abs(math.cos(ang)) < 0.55:
                continue
            c.put(int(cx + math.cos(ang) * r), int(cy + math.sin(ang) * r), col)
    c.rect(30, 30, 4, 26, (108, 94, 70)); c.rect(26, 54, 12, 3, (108, 94, 70))
    c.rect(29, 26, 6, 6, (222, 196, 120)); c.rect(30, 27, 4, 4, (246, 226, 160))
    c.rect(0, 0, 64, 1, (60, 54, 42)); c.rect(0, 63, 64, 1, (60, 54, 42)); c.rect(0, 0, 1, 64, (60, 54, 42)); c.rect(63, 0, 1, 64, (60, 54, 42))
    c.save(f"{OUT}/icon.png")

tiles(); vehicles(); containers(); safehouse(); items(); game_icon()
print("world art done")
