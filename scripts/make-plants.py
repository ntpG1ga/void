#!/usr/bin/env python3
"""A few round-crowned trees and bushes round the grass lab's camp (user, 2026-10-02), from
t3ssel8r-lab's Tripo broadleaf sheet (assets/trees/broadleaf/parts/*.glb: one textured mesh each).

  uvx --with numpy --with pillow python scripts/make-plants.py   -> assets/grassLab/plants.gltf + .bin

The scene lights everything through ramps, so the texture is not shipped: each triangle takes the
texture's colour at its centre, brown-and-dull triangles become the TRUNK mesh (lit as the logs'
wood) and the rest the LEAF mesh (its own ramp row, scripts/make-grass-atlas.py leaf_ramp), and a
leaf triangle brighter than most of its crown gets vertex red 1, which the ramp shader draws one step
up (rampRow.w), so the texture's light clumps survive as banded highlights. Each model is scaled to
its height below, stood on its lowest point and turned/placed per PLACES on the ground mesh of
grass_lab.gltf (u metres right of the fire, v towards the camera, as pillars.json).
"""
import io, json, math, os, struct

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LAB = os.path.join(os.path.dirname(ROOT), "t3ssel8r-lab", "assets", "trees", "broadleaf", "parts")
OUT = os.path.join(ROOT, "assets", "grassLab")

HEIGHTS = {"broadleaf_orange": 6.6, "broadleaf_red": 6.0, "bush_round": 1.5, "bush_flower": 1.4}
# (model, u, v, yaw deg): outside the walker's stations (|u| <= 5.5, |v| <= 8.5) and its routes,
# clear of the pillars; the trees on the frame's sides (|u| ~6.3: about 3/4 of a 6.4 m crown inside
# the +-7.8 m portrait frame, user wanted at least 65%), the bushes scattered.
PLACES = [
    ("broadleaf_orange", -6.3, -13.0, 20),
    ("broadleaf_red", 6.4, -8.0, 140),
    ("broadleaf_orange", 6.3, 15.5, 250),
    ("bush_round", -6.8, -4.0, 0),
    ("bush_flower", 6.6, 4.6, 70),
    ("bush_round", -2.4, -11.5, 200),
    ("bush_flower", -5.2, 11.0, 300),
    ("bush_round", 3.6, 12.0, 120),
]
HIGHLIGHT = 0.62
# Leaf cards over the crowns, as t3ssel8r's trees: grass-rosette sprites (the scene draws them from
# atlas_short) rooted on the crown's camera-facing surface, LEAF_DENSITY a square metre, pushed
# LEAF_OUT off it and sunk half a card so they sit on the surface and fluff its outline. Each
# card's moon step comes from its face's normal (the sprite shader lights a card as facing up,
# which is the top moon step, so the card carries steps down to it: 0, -1 or -2).
LEAF_DENSITY = 6.0
LEAF_OUT = 0.08
LEAF_SINK = 0.4
# and this far toward the camera along its view: the image stays (orthographic) but a card no longer
# dips into the crown's mesh, which hid half of each.
LEAF_FORWARD = 0.7
MOON = np.array([-0.45, 0.86, -0.25]) / np.linalg.norm([-0.45, 0.86, -0.25])
TO_CAMERA = np.array([0.612, 0.5, 0.612])
MOON_CUTS = (0.35, 0.75)     # share of a crown's triangles below the highlight's luminance


def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    j = json.loads(data[20:20 + jlen])
    blen = struct.unpack_from("<I", data, 20 + jlen)[0]
    blob = data[28 + jlen:28 + jlen + blen]

    def accessor(i):
        a = j["accessors"][i]
        view = j["bufferViews"][a["bufferView"]]
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        kind = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
        out = np.frombuffer(blob, kind, a["count"] * width, start)
        return out.reshape(a["count"], width) if width > 1 else out

    prim = j["meshes"][0]["primitives"][0]
    pos = accessor(prim["attributes"]["POSITION"]).astype(np.float64)
    uv = accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    idx = accessor(prim["indices"]).astype(np.int64).reshape(-1, 3)
    node = j["nodes"][0]
    if "matrix" in node or "rotation" in node or "scale" in node:
        print("note: node transform ignored in", os.path.basename(path))
    img = j["images"][0]
    view = j["bufferViews"][img["bufferView"]]
    tex = Image.open(io.BytesIO(blob[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]])).convert("RGB")
    return pos, uv, idx, np.asarray(tex).astype(np.float64) / 255.0


def ground_height():
    j = json.load(open(os.path.join(OUT, "grass_lab.gltf")))
    blob = open(os.path.join(OUT, j["buffers"][0]["uri"]), "rb").read()
    ground = next(m for m in j["meshes"] if m["name"] == "GROUND")
    a = j["accessors"][ground["primitives"][0]["attributes"]["POSITION"]]
    view = j["bufferViews"][a["bufferView"]]
    pos = np.frombuffer(blob, np.float32, a["count"] * 3, view.get("byteOffset", 0) + a.get("byteOffset", 0)).reshape(-1, 3)
    n = int(round(math.sqrt(len(pos))))
    order = np.lexsort((pos[:, 0], pos[:, 2]))
    grid = pos[order].reshape(n, n, 3)            # [z][x]
    x0, x1 = grid[0, 0, 0], grid[0, -1, 0]
    z0, z1 = grid[0, 0, 2], grid[-1, 0, 2]

    def at(x, z):
        fx = (x - x0) / (x1 - x0) * (n - 1)
        fz = (z - z0) / (z1 - z0) * (n - 1)
        ix, iz = min(max(int(fx), 0), n - 2), min(max(int(fz), 0), n - 2)
        tx, tz = fx - ix, fz - iz
        h = grid[:, :, 1]
        return float((h[iz, ix] * (1 - tx) + h[iz, ix + 1] * tx) * (1 - tz) + (h[iz + 1, ix] * (1 - tx) + h[iz + 1, ix + 1] * tx) * tz)
    return at


def split(name):
    pos, uv, idx, tex = read_glb(os.path.join(LAB, name + ".glb"))
    # glTF is Y up already; stand the model on its lowest point, centred, at its height
    lo, hi = pos.min(0), pos.max(0)
    scale = HEIGHTS[name] / (hi[1] - lo[1])
    pos = (pos - np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])) * scale
    h, w, _ = tex.shape
    centre_uv = uv[idx].mean(1)
    px = np.clip((centre_uv[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    py = np.clip((centre_uv[:, 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
    col = tex[py, px]
    mx, mn = col.max(1), col.min(1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    luma = col @ np.array([0.2126, 0.7152, 0.0722])
    # trunk (trees only): bark brown, green about 0.7 of red and blue about half (0.35 0.24 0.16
    # measured), in the lower half; the crowns are red and orange (green under 0.4 of red). The
    # bushes are all foliage (their olive leaves would pass for bark).
    height = pos[idx][:, :, 1].mean(1) / HEIGHTS[name]
    r = np.maximum(col[:, 0], 1e-6)
    trunk = name.startswith("broadleaf") & (col[:, 1] / r > 0.55) & (col[:, 2] / r > 0.3) & (mx < 0.5) & (height < 0.5)
    leaf = ~trunk
    cut = np.quantile(luma[leaf], HIGHLIGHT) if leaf.any() else 1.0
    bright = (luma > cut) & leaf
    print(f"{name}: {len(idx)} tris, {int(trunk.sum())} trunk, {int(bright.sum())} highlit, scale {scale:.3f}")
    return pos, idx, trunk, bright


def flat(pos, idx, faces, red):
    """unshared vertices for the chosen faces, face normals, vertex red per face"""
    tri = pos[idx[faces]]                              # (f, 3, 3)
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    v = tri.reshape(-1, 3)
    nn = np.repeat(n, 3, axis=0)
    c = np.zeros((len(v), 3))
    c[:, 0] = np.repeat(red[faces].astype(float), 3)
    return v.astype(np.float32), nn.astype(np.float32), c.astype(np.float32)


def leaf_cards(pos, idx, trunk, place, rnd):
    """card roots (world) and their moon steps for one placed model"""
    x, y, z, yaw = place
    c, s_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    # glTF yaw about +Y: x' = x cos + z sin, z' = -x sin + z cos
    rot = np.array([[c, 0, s_], [0, 1, 0], [-s_, 0, c]])
    tri = pos[idx[~trunk]] @ rot.T
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    area = np.linalg.norm(n, axis=1) / 2
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    keep = (n @ TO_CAMERA > -0.1) & (area > 0)
    tri, n, area = tri[keep], n[keep], area[keep]
    count = int(area.sum() * LEAF_DENSITY)
    pick = rnd.choice(len(tri), count, p=area / area.sum())
    a, b = rnd.random(count), rnd.random(count)
    flip = a + b > 1
    a[flip], b[flip] = 1 - a[flip], 1 - b[flip]
    t = tri[pick]
    at = t[:, 0] + (t[:, 1] - t[:, 0]) * a[:, None] + (t[:, 2] - t[:, 0]) * b[:, None]
    at = at + n[pick] * LEAF_OUT + TO_CAMERA / np.linalg.norm(TO_CAMERA) * LEAF_FORWARD + np.array([x, y - LEAF_SINK, z])
    d = n[pick] @ MOON
    steps = (d > MOON_CUTS[0]).astype(float) + (d > MOON_CUTS[1]).astype(float) - 2.0
    return at, steps


def main():
    at = ground_height()
    models = {}
    for name in HEIGHTS:
        models[name] = split(name)
    gltf = {"asset": {"version": "2.0", "generator": "void-touch make-plants.py"}, "scene": 0,
            "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "accessors": [], "bufferViews": [], "buffers": []}
    blob = bytearray()

    def add_view(arr, target):
        nonlocal blob
        while len(blob) % 4:
            blob += b"\0"
        off = len(blob)
        blob += arr.tobytes()
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes, "target": target})
        return len(gltf["bufferViews"]) - 1

    def add_accessor(arr, kind, comp, target):
        view = add_view(arr, target)
        acc = {"bufferView": view, "componentType": comp, "count": len(arr), "type": kind}
        if kind == "VEC3":
            acc["min"] = arr.min(0).tolist()
            acc["max"] = arr.max(0).tolist()
        gltf["accessors"].append(acc)
        return len(gltf["accessors"]) - 1

    mesh_of = {}
    for name, (pos, idx, trunk, bright) in models.items():
        for part, faces in (("LEAF", np.nonzero(~trunk)[0]), ("TRUNK", np.nonzero(trunk)[0])):
            if len(faces) == 0:
                continue
            v, nn, c = flat(pos, idx, faces, bright)
            ind = np.arange(len(v), dtype=np.uint16)   # void's glTF reader takes 16-bit indices only
            prim = {"attributes": {"POSITION": add_accessor(v, "VEC3", 5126, 34962),
                                   "NORMAL": add_accessor(nn, "VEC3", 5126, 34962),
                                   "COLOR_0": add_accessor(c, "VEC3", 5126, 34962)},
                    "indices": add_accessor(ind, "SCALAR", 5123, 34963), "mode": 4}
            gltf["meshes"].append({"name": f"{part}_{name}", "primitives": [prim]})
            mesh_of[(name, part)] = len(gltf["meshes"]) - 1
    cards = []
    rnd = np.random.default_rng(31)
    for k, (name, u, v, yaw) in enumerate(PLACES):
        x, z = (u + v) * math.sqrt(0.5), (v - u) * math.sqrt(0.5)
        y = at(x, z) - 0.05
        half = math.radians(yaw) / 2
        for part in ("LEAF", "TRUNK"):
            if (name, part) not in mesh_of:
                continue
            gltf["nodes"].append({"name": f"{part}_{k:02d}", "mesh": mesh_of[(name, part)],
                                  "translation": [x, y, z], "rotation": [0.0, math.sin(half), 0.0, math.cos(half)]})
            gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]) - 1)
        roots, steps = leaf_cards(models[name][0], models[name][1], models[name][2], (x, y, z, yaw), rnd)
        for p_, st in zip(roots, steps):
            cards.append([p_[0], p_[1], p_[2], float(rnd.integers(0, 4)), 0.0, 0.0, st, 0.0])
        print(f"{name} at u {u} v {v}: x {x:.2f} y {y:.2f} z {z:.2f}, {len(roots)} leaf cards")
    while len(blob) % 4:          # the scene reads .bin files a 32-bit word at a time
        blob += b"\0"
    gltf["buffers"].append({"byteLength": len(blob), "uri": "plants.bin"})
    open(os.path.join(OUT, "plants.bin"), "wb").write(blob)
    json.dump(gltf, open(os.path.join(OUT, "plants.gltf"), "w"))
    np.array(cards, np.float32).tofile(os.path.join(OUT, "plant_leaves.f32"))
    print("plant_leaves.f32:", len(cards), "cards")
    print("plants.gltf:", len(gltf["meshes"]), "meshes,", len(gltf["nodes"]), "nodes,", len(blob), "bytes")


main()
