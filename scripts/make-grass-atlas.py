#!/usr/bin/env python3
"""Draws the grass lab's clump atlases as broad-leaf rosettes, after Dylearn's grass
(youtube OxsuWDtjuGw: a clump is ~28 game px of serrated leaves; ours keep two of his three,
which read calmer when they overlap - user, 2026-10-01),
instead of the lab's thin 3-6 px lance blades.

  python3 scripts/make-grass-atlas.py        -> assets/grassLab/atlas_short.rgba, atlas_tall.rgba

Each atlas is 4 cells across, raw RGBA8 rows top first, white leaves on transparent; the root is
the bottom-centre texel of a cell (the billboard stands on it), the rosette centred above it. The lab's atlases are kept beside
them as *_lab.rgba the first time this runs.
"""
import math, os, random, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets", "grassLab")
SHORT = (22, 22)    # cell w, h in game px (grassLabScene.ms SHORT_CELL_*)
TALL = (28, 28)     # (TALL_CELL_*)
STEM = 0.0          # px of bare stem before a leaf widens (0: the leaves meet in the middle)
ROOT_Y = 3.5        # px above the cell's foot where the leaves meet
CORE = 2.6          # px radius of the solid heart the leaves grow from, so a rosette has no hole
# Smooth leaves (user, 2026-10-02: the serrated, needle-tipped leaves read as noise at their tips):
# no notches, an elliptic profile so the tip ends round, less turn per leaf, and a clean-up pass
# that drops lone pixels and fills one-pixel bites.
SERRATED = False
LEAF_TURN = 5.0     # deg of random turn per leaf (was 10)


def leaf_covers(px, py, root, angle, length, width, serr):
    """whether pixel centre (px, py) lies on a leaf from `root` along `angle` (rad, 0 = right,
    pi/2 = up, y up): half-width width * sin(pi t)^0.7 along t in [0, 1], with a stepped notch
    every 2.5 px on one side (the video's serrated edge)"""
    dx, dy = px - root[0], py - root[1]
    ca, sa = math.cos(angle), math.sin(angle)
    along = dx * ca + dy * sa
    across = -dx * sa + dy * ca
    along -= STEM          # leaves start a little off the root, so they read apart
    t = along / length
    if t <= 0.0 or t >= 1.0:
        return False
    if SERRATED:
        half = width * math.sin(math.pi * t ** 0.8)
        if across > 0 and int(along / 2.5) % 2 == 1:
            half -= serr
    else:
        # widest a little before the middle, then an ellipse's round end
        u = 2.0 * t ** 0.8 - 1.0
        half = width * math.sqrt(max(0.0, 1.0 - u * u))
    return abs(across) <= half


def cell(w, h, leaves, rnd, base):
    # The video's sprite is a pinwheel: leaves fanning out from the middle of the sprite, as a
    # rosette seen from the camera above, not blades rising from its foot.
    # Two leaves, the upper two of the video's three (user, 2026-10-01; tried one, went back), so the pinwheel's centre
    # sits low in the cell and the leaves open upward from it.
    root = (w / 2.0, ROOT_Y)
    spin = rnd.uniform(-6, 6)
    shapes = []
    for base_deg, length, width in leaves:
        a = math.radians(base_deg + spin + rnd.uniform(-LEAF_TURN, LEAF_TURN))
        shapes.append((a, length * rnd.uniform(0.82, 1.0), width * rnd.uniform(0.85, 1.1)))
    rows = []
    for y in range(h):
        py = (h - 1 - y) + 0.5           # rows top first, y up from the root row
        row = []
        for x in range(w):
            px = x + 0.5
            # the base: an upright block from the ground over the leaves' lower part (user,
            # 2026-10-01), (half-width, height) px, centred on the root
            in_base = abs(px - root[0]) <= base[0] and py <= base[1]
            on = (in_base or math.hypot(px - root[0], py - root[1]) <= CORE
                  or any(leaf_covers(px, py, root, a, l, wd, 0.9) for a, l, wd in shapes))
            row.append(on)
        rows.append(row)
    return rows if SERRATED else tidy(rows)


def tidy(rows):
    """drops pixels with at most one of their four neighbours on (a stray tip texel) and fills
    holes with three or four (a one-pixel bite in an edge)"""
    h, w = len(rows), len(rows[0])
    def on(x, y):
        return 0 <= x < w and 0 <= y < h and rows[y][x]
    out = []
    for y in range(h):
        row = []
        for x in range(w):
            n = on(x - 1, y) + on(x + 1, y) + on(x, y - 1) + on(x, y + 1)
            row.append(n >= 2 if rows[y][x] else n >= 3)
        out.append(row)
    return out


def atlas(name, size, leaves, seed, base):
    w, h = size
    rnd = random.Random(seed)
    cells = [cell(w, h, leaves, rnd, base) for _ in range(4)]
    out = bytearray()
    for y in range(h):
        for c in cells:
            for on in c[y]:
                out += bytes((255, 255, 255, 255)) if on else bytes((0, 0, 0, 0))
    path = os.path.join(OUT, name)
    keep = path.replace(".rgba", "_lab.rgba")
    if os.path.exists(path) and not os.path.exists(keep):
        shutil.copyfile(path, keep)
    open(path, "wb").write(out)
    print(name, w * 4, "x", h)
    for y in range(h):
        print("".join("#" if cells[0][y][x] else "." for x in range(w)) + "  " +
              "".join("#" if cells[1][y][x] else "." for x in range(w)))


# (direction in degrees round the centre, length px, max half-width px); each cell spins the set.
# Upright (user, 2026-10-02): 70 and 128 deg, were 62 and 160 (the second leaf lay nearly flat); leaves and base a little narrower so the two still read apart.
# base: an upright block over about the lower quarter of the leaves
atlas("atlas_short.rgba", SHORT, [(70, 12, 2.6), (128, 10, 2.3)], 7, (3.0, 5.0))
atlas("atlas_tall.rgba", TALL, [(70, 17, 3.2), (128, 14, 2.9)], 11, (4.0, 6.5))


# ---- pale sprigs (user, 2026-10-02): hibernal's broadleafSprig (assets/outdoor/assetLibrary.py
# fern(), the pale punctuation round its demo camp): five pointed leaves fanned up from one root,
# drawn as pixels. The plus-shaped flowers before them read as sparkle; the old cell is the sprig.
SPRIG = (15, 12)


def sprig_cell(w, h, rnd):
    root = (w / 2.0, 0.5)
    leaves = []
    for k, deg in enumerate((22, 58, 90, 122, 158)):
        a = math.radians(deg + rnd.uniform(-6, 6))
        length = (6.5 if k in (0, 4) else 11.0 if k == 2 else 9.0) * rnd.uniform(0.88, 1.05)
        leaves.append((a, length))
    rows = []
    for y in range(h):
        py = (h - 1 - y) + 0.5
        row = []
        for x in range(w):
            px = x + 0.5
            on = False
            for a, length in leaves:
                dx, dy = px - root[0], py - root[1]
                along = dx * math.cos(a) + dy * math.sin(a)
                across = -dx * math.sin(a) + dy * math.cos(a)
                t = along / length
                # a blade: ~2.5 px wide at its foot narrowing to a one-pixel point (no tidy pass,
                # which would eat the points)
                if 0.0 < t < 1.0 and abs(across) <= 0.5 + 0.8 * (1.0 - t):
                    on = True
            row.append(on)
        rows.append(row)
    return rows


def flower_atlas():
    w, h = SPRIG
    rnd = random.Random(23)
    cells = [sprig_cell(w, h, rnd) for _ in range(4)]
    out = bytearray()
    for y in range(h):
        for c in cells:
            for on in c[y]:
                out += bytes((255, 255, 255, 255)) if on else bytes((0, 0, 0, 0))
    open(os.path.join(OUT, "atlas_flower.rgba"), "wb").write(out)
    print("atlas_flower.rgba", w * 4, "x", h)
    for y in range(h):
        print("".join("#" if cells[0][y][x] else "." for x in range(w)) + "  " +
              "".join("#" if cells[1][y][x] else "." for x in range(w)))


# Their ramp: row 6 of ramps.rgba (grassLabScene ROW_FLOWER), 3 moonlit steps of hibernal's pale
# fern (879b90) in blue moonlight, then 16 fire bands warming to a cream white. Rows 0-5 are the export's, kept as they are.
RAMP_W, RAMP_KEEP = 19, 6


def flower_ramp():
    path = os.path.join(OUT, "ramps.rgba")
    data = bytearray(open(path, "rb").read()[:RAMP_W * RAMP_KEEP * 4])
    night = [(0x5e, 0x72, 0x86), (0x70, 0x86, 0x96), (0x86, 0x9c, 0xa8)]
    warm, white = (0xe8, 0xa0, 0x78), (0xff, 0xf2, 0xd8)
    row = list(night)
    for i in range(16):
        t = (i + 1) / 16.0
        a, b, u = (night[2], warm, t / 0.5) if t <= 0.5 else (warm, white, (t - 0.5) / 0.5)
        row.append(tuple(round(a[k] + (b[k] - a[k]) * u) for k in range(3)))
    for r, g, b in row:
        data += bytes((r, g, b, 255))
    # row 7 (grassLabScene ROW_LEAF): the round crowns and bushes (scripts/make-plants.py), a
    # cold dark teal by the moon a little apart from the grass, warming to autumn red and orange
    leaf_night = [(0x12, 0x1c, 0x2a), (0x1a, 0x27, 0x36), (0x24, 0x33, 0x42)]
    leaf_mid, leaf_top = (0xb4, 0x3e, 0x2a), (0xf2, 0x94, 0x44)
    row = list(leaf_night)
    for i in range(16):
        t = (i + 1) / 16.0
        a, b, u = (leaf_night[2], leaf_mid, t / 0.6) if t <= 0.6 else (leaf_mid, leaf_top, (t - 0.6) / 0.4)
        row.append(tuple(round(a[k] + (b[k] - a[k]) * u) for k in range(3)))
    for r, g, b in row:
        data += bytes((r, g, b, 255))
    open(path, "wb").write(data)
    print("ramps.rgba rows", RAMP_KEEP, "flowers,", RAMP_KEEP + 1, "leaves")


flower_atlas()
flower_ramp()
