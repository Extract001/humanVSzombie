# Player + Walker animation sheets (16x24 frames), Walker eyes, weapons, muzzle flash. Original art.
import sys, random
sys.path.insert(0, __import__("os").path.dirname(__file__))
from pix import *

OUT = sys.argv[1]
FW, FH = 16, 24
DIRS = ["down", "left", "right", "up"]

SURVIVOR = dict(skin=(198, 156, 122), skin_d=(166, 126, 98), hair=(62, 44, 34), top=(84, 98, 60), top_hi=(104, 120, 76),
                top_d=(60, 70, 44), legs=(56, 62, 78), legs_d=(42, 46, 60), feet=(44, 36, 30), pack=(108, 90, 60), eye=(30, 24, 22),
                blood=None)
WALKER = dict(skin=(136, 150, 110), skin_d=(108, 120, 86), hair=(58, 56, 48), top=(86, 98, 114), top_hi=(104, 116, 132),
              top_d=(60, 68, 82), legs=(80, 68, 56), legs_d=(62, 52, 42), feet=(96, 104, 80), pack=None, eye=(26, 20, 20),
              blood=(116, 30, 26))

# Animation layout: (name, frames). Same column order for every direction row.
PLAYER_ANIMS = [("idle", 2), ("walk", 4), ("run", 4), ("melee", 3), ("shoot", 2), ("reload", 3), ("hurt", 1), ("shove", 2), ("death", 4)]
WALKER_ANIMS = [("idle", 2), ("walk", 4), ("attack", 3), ("hurt", 1), ("death", 4)]

# Eye pixels of the Walker per direction (the unshaded glow overlay uses the same spots).
WALKER_EYES = {"down": [(6, 6), (9, 6)], "left": [(5, 6)], "right": [(10, 6)], "up": []}


def pose_for(anim, f):
    """Returns a pose dict: leg strides, arm offsets, special arm mode, body shift."""
    p = dict(stride=0, arm=0, mode="", dy=0, lean=0)
    if anim == "idle":
        p["arm"] = 0 if f == 0 else 1
    elif anim in ("walk", "run"):
        big = 2 if anim == "run" else 1
        p["stride"] = [big, 0, -big, 0][f]
        p["arm"] = [-big, 0, big, 0][f]
        p["lean"] = 1 if anim == "run" else 0
    elif anim == "melee":
        p["mode"] = ["raise", "swing", "follow"][f]
    elif anim == "shoot":
        p["mode"] = "aim"; p["recoil"] = f
    elif anim == "reload":
        p["mode"] = ["reload0", "reload1", "reload0"][f]
    elif anim == "hurt":
        p["mode"] = "hurt"; p["dy"] = 0
    elif anim == "shove":
        p["mode"] = ["shove0", "shove1"][f]
    elif anim == "attack":
        p["mode"] = ["claw0", "claw1", "claw2"][f]
    elif anim == "death":
        p["mode"] = "death%d" % f
    return p


def draw_body(c, d, pal, pose, walker):
    """Standing body, 3/4 top-down view. Head fixed at rows 2-8 (the Walker's eye overlay relies on it)."""
    mode = pose["mode"]
    side = d in ("left", "right")
    fx = -1 if d == "left" else 1
    s = pose["stride"]
    arm = pose["arm"]
    # ---- legs (rows 16-22)
    if side:
        back_x, front_x = 6 - s * fx, 8 + s * fx
        for lx, col in ((back_x, pal["legs_d"]), (front_x, pal["legs"])):
            c.rect(lx, 16, 2, 6, col); c.rect(lx + (1 if fx > 0 else -1) * 0, 21, 3 if fx > 0 else 3, 1, pal["feet"])
    else:
        ly = [0, 0]
        if s:
            ly = [-abs(s) if s > 0 else 0, -abs(s) if s < 0 else 0]
        c.rect(5, 16 + ly[0], 3, 6 - ly[0] * 0, pal["legs"]); c.rect(9, 16 + ly[1], 3, 6, pal["legs_d"] if d == "up" else pal["legs"])
        c.vline(8, 16, 4, pal["legs_d"])
        c.rect(5, 21 + ly[0], 3, 1, pal["feet"]); c.rect(9, 21 + ly[1], 3, 1, pal["feet"])
    # ---- torso (rows 9-16)
    tx = 4 + (pose["lean"] * fx if side else 0)
    c.rect(tx, 9, 8, 8, pal["top"])
    c.hline(tx + 1, 9, 6, pal["top_hi"])
    c.rect(tx, 15, 8, 2, pal["top_d"])
    if not walker:
        c.hline(tx, 15, 8, (40, 34, 28))   # belt
        c.put(tx + 4, 15, (150, 130, 80))
    else:
        for (x, y) in ((tx + 2, 11), (tx + 5, 13), (tx + 6, 10)):   # tears and blood
            c.put(x, y, pal["blood"])
        c.put(tx + 1, 14, pal["top_d"]); c.put(tx + 6, 16, (0, 0, 0, 0))
    if d == "up" and pal["pack"]:
        c.rect(tx + 1, 9, 6, 6, pal["pack"]); c.hline(tx + 1, 9, 6, shade(pal["pack"], 1.2)); c.hline(tx + 1, 12, 6, shade(pal["pack"], 0.8))
    # ---- arms
    def arm_px(x, y, h, col):
        c.rect(x, y, 2, h, col); c.rect(x, y + h, 2, 1, pal["skin_d"] if walker else pal["skin"])
    if mode in ("", "hurt"):
        if side:
            ax = tx + 3 + arm * fx
            arm_px(ax, 10, 5, pal["top_hi"])
        else:
            arm_px(2, 10 + max(0, arm), 5, pal["top"]); arm_px(12, 10 + max(0, -arm), 5, pal["top"])
    elif mode in ("aim", "shove0", "shove1", "claw0", "claw1", "claw2", "raise", "swing", "follow", "reload0", "reload1"):
        reach = {"aim": 4, "shove0": 3, "shove1": 5, "claw0": 2, "claw1": 5, "claw2": 3, "raise": 1, "swing": 4, "follow": 3,
                 "reload0": 2, "reload1": 2}[mode]
        if pose.get("recoil"):
            reach -= 1
        sk = pal["skin_d"] if walker else pal["skin"]
        if d == "down":
            y = 12 + reach
            c.rect(4, 11, 2, reach + 1, pal["top"]); c.rect(10, 11, 2, reach + 1, pal["top"])
            c.rect(4, y, 2, 2, sk); c.rect(10, y, 2, 2, sk)
            if mode == "raise": c.rect(11, 7, 2, 4, pal["top"]); c.rect(11, 6, 2, 1, sk)
            if mode == "reload1": c.rect(9, 15, 2, 2, sk)
        elif d == "up":
            y = 9 - reach
            c.rect(4, y + 1, 2, reach + 1, pal["top"]); c.rect(10, y + 1, 2, reach + 1, pal["top"])
            c.put(4, y, sk); c.put(5, y, sk); c.put(10, y, sk); c.put(11, y, sk)
        else:
            x0 = 8 if fx > 0 else 8 - reach - 3
            c.rect(x0, 11, reach + 3, 2, pal["top_hi"])
            hx = x0 + reach + 3 if fx > 0 else x0 - 1
            c.rect(hx, 11, 1, 2, sk)
            if mode == "raise": c.rect(6 + (2 if fx > 0 else -2), 6, 2, 5, pal["top_hi"])
    # ---- head (rows 2-8), fixed position
    hx = 5 + (1 if d == "right" else (-1 if d == "left" else 0))
    c.rect(hx, 2, 6, 7, pal["skin"])
    c.hline(hx, 8, 6, pal["skin_d"])
    if d == "down":
        c.rect(hx, 2, 6, 2, pal["hair"]); c.put(hx, 4, pal["hair"]); c.put(hx + 5, 4, pal["hair"])
        for (ex, ey) in ((6, 6), (9, 6)):
            c.put(ex, ey, pal["eye"])
        if walker:
            c.hline(hx + 2, 7, 2, (70, 30, 28))
    elif d == "up":
        c.rect(hx, 2, 6, 6, pal["hair"]); c.hline(hx + 1, 2, 4, shade(pal["hair"], 1.25))
    else:
        back = hx + (0 if fx > 0 else 3)
        c.rect(back, 2, 3, 6, pal["hair"]); c.rect(hx, 2, 6, 2, pal["hair"])
        ex = 10 if fx > 0 else 5
        c.put(ex, 6, pal["eye"])
    if walker:
        c.put(hx + 1, 3, pal["skin"]); c.put(hx + 4, 2, pal["skin_d"])   # patchy hair
        if d != "up":
            c.put(hx + 4, 4, pal["blood"])


def draw_dead(c, pal, f, walker):
    """Death: knees buckle (0), falling (1), lying flat seen from above (2, 3 with blood)."""
    if f <= 1:
        drop = 3 if f == 0 else 6
        tmp = Canvas(FW, FH)
        draw_body(tmp, "down", pal, dict(stride=0, arm=1, mode="", dy=0, lean=0), walker)
        crop = tmp.img.crop((0, 0, FW, FH - drop - 2))
        c.img.alpha_composite(crop, (0 if f == 0 else 1, drop))
        c.px = c.img.load()
        c.rect(5, 21, 7, 1, pal["legs_d"])
        return
    blood = pal["blood"] or (104, 28, 24)
    if f == 3:
        for (x, y, w) in ((3, 9, 10), (2, 10, 12), (2, 11, 12), (3, 12, 10), (4, 13, 8)):
            c.rect(x, y, w, 1, (86, 22, 20))
    # lying body: head at top, arms spread, legs together
    c.rect(5, 3, 6, 6, pal["skin_d"]); c.rect(5, 3, 6, 2, pal["hair"])
    c.rect(4, 9, 8, 7, shade(pal["top"], 0.78)); c.hline(4, 9, 8, shade(pal["top"], 0.9))
    c.rect(1, 9, 3, 2, shade(pal["top"], 0.8)); c.rect(12, 10, 3, 2, shade(pal["top"], 0.8))
    c.put(0, 10, pal["skin_d"]); c.put(15, 11, pal["skin_d"])
    c.rect(5, 16, 6, 6, shade(pal["legs"], 0.78)); c.vline(8, 16, 6, pal["legs_d"])
    c.rect(5, 22, 2, 1, pal["feet"]); c.rect(9, 22, 2, 1, pal["feet"])
    c.put(7, 12, blood); c.put(8, 13, blood)


def frame(pal, d, anim, f, walker):
    c = Canvas(FW, FH)
    pose = pose_for(anim, f)
    if anim == "death":
        draw_dead(c, pal, f, walker)
    else:
        draw_body(c, d, pal, pose, walker)
        if anim == "hurt":   # flinch: knocked back one pixel, lighter (reads as a hit flash)
            shifted = Canvas(FW, FH)
            shifted.img.alpha_composite(c.img, (0, 0), (0, 1, FW, FH))
            from PIL import ImageEnhance
            shifted.img = ImageEnhance.Brightness(shifted.img).enhance(1.25)
            shifted.px = shifted.img.load()
            c = shifted
    c.outline()
    # soft ground shadow (added after the outline so it doesn't get outlined)
    sh = Canvas(FW, FH)
    for x in range(3, 13):
        sh.put(x, 22, (0, 0, 0, 70)); sh.put(x, 23, (0, 0, 0, 40))
    sh.img.alpha_composite(c.img)
    return sh


def sheet(pal, anims, walker, path):
    cols = sum(n for _, n in anims)
    out = Canvas(cols * FW, 4 * FH)
    for row, d in enumerate(DIRS):
        col = 0
        for anim, n in anims:
            for f in range(n):
                out.paste(frame(pal, d, anim, f, walker), col * FW, row * FH)
                col += 1
    out.save(path)


def eyes(path):
    c = Canvas(4 * FW, FH)
    for i, d in enumerate(DIRS):
        for (x, y) in WALKER_EYES[d]:
            c.put(i * FW + x, y, (236, 214, 120)); c.put(i * FW + x, y - 1, (150, 110, 60, 160))
    c.save(path)


def weapons():
    bat = Canvas(16, 4)
    bat.rect(0, 1, 5, 2, (44, 40, 36)); bat.rect(5, 1, 9, 2, (156, 118, 74)); bat.rect(10, 0, 5, 4, (166, 128, 82))
    bat.hline(5, 1, 10, (186, 148, 98)); bat.put(13, 2, (110, 30, 26)); bat.put(12, 3, (110, 30, 26))
    bat.save(f"{OUT}/assets/sprites/bat.png")
    pistol = Canvas(10, 5)
    pistol.rect(2, 0, 8, 2, (70, 72, 76)); pistol.hline(2, 0, 8, (110, 112, 116)); pistol.rect(2, 2, 3, 3, (52, 46, 42)); pistol.put(5, 2, (60, 62, 66))
    pistol.save(f"{OUT}/assets/sprites/pistol.png")
    flash = Canvas(16, 8)   # 2 frames 8x8
    for fr, r in ((0, 3), (1, 2)):
        ox = fr * 8
        for y in range(8):
            for x in range(8):
                dx, dy = x - 3.5, y - 3.5
                dist = (dx * dx * 0.5 + dy * dy) ** 0.5
                if dist <= r:
                    col = (255, 244, 200) if dist < r * 0.45 else (250, 196, 96) if dist < r * 0.8 else (220, 120, 50)
                    flash.put(ox + x, y, col)
    flash.save(f"{OUT}/assets/sprites/muzzle_flash.png")


sheet(SURVIVOR, PLAYER_ANIMS, False, f"{OUT}/assets/sprites/player.png")
sheet(WALKER, WALKER_ANIMS, True, f"{OUT}/assets/sprites/walker.png")
eyes(f"{OUT}/assets/sprites/walker_eyes.png")
weapons()
print("chars done")
