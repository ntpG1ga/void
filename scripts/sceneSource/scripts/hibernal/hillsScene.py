"""The campfire hills scene -> glTF for hibernal's assets/environment/. Standalone: Blender only.

Kept in t3ssel8r-lab (scripts/hibernal/), not in hibernal: the user wants only the .glb files there
(2026-09-25). Rerun from the lab:
  "$B" -b --factory-startup -P "$(wslpath -w scripts/hibernal/hillsScene.py)"   [HIBERNAL=../hibernal]
Writes <hibernal>/assets/environment/ (hillsScene.json goes to out/hibernal_stage/ instead):
  hillsGround.glb     the ground, 60 m square round the fire on a 1 m grid, in 36 chunks of 200 tris
                      (art/README.md: <=200 per environment piece); 1.5 cm mean / 15 cm worst height
                      error against groundHeight() over the middle 28 m. Smooth: each vertex takes the
                      normal of groundHeight() itself, so the light bands curve like the hills instead
                      of stepping along triangle edges, and chunk borders share normals (no seams)
  pillars.glb         13 standing stones: 9 placed by hand (INNER_PILLARS), 4 low ones scattered
                      12.5-21.5 m out by a seeded roll (OUTER_PILLARS), all sunk 0.3 m below their lowest corner
  campfireLogs.glb    the 4 logs of the fire, on the flat pad
  hillsScene.json     numbers the renderer and the pet need: the fire's ground point, map size, the
                      pet's roam radius and the fixed camera's limits
glTF 2.0 with position, normal and vertex colour only (no materials, textures or UVs), Y up, in the
subset void's loader takes (void/src/void3d/gltf.ms): FLOAT VEC3 POSITION / NORMAL / COLOR_0, uint16
indices, one buffer, one buffer view per accessor. Blender's exporter writes COLOR_0 as normalized
uint16 VEC4, which void refuses, so voidSubset() rewrites each file after export. The
vertex colours only tag the surface (grass / stone / wood); the palette LUT decides the final look.

Ported from t3ssel8r-lab (scripts/grass_lab.py, LAB_TERRAIN=hills, 2026-09-25): rolling hills after
t3ssel8r's "Isometric Camera" clip, four value-noise layers (big swells, a mid layer, small humps and
long low ridges lying across the camera's view), doubled in height (3.8 m relief, 95% of slopes
under 30 deg), flattened into a pad under the fire. The fixed fire camera, turned any way and zoomed
out 1.25x, sees ground 23.2 m out, hence the 60 m map; a 2 m pet stays in frame out to 10 m.
"""
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
LAB = os.path.dirname(os.path.dirname(HERE))
HIBERNAL = os.path.join(LAB, os.environ.get("HIBERNAL", os.path.join("..", "hibernal")))
OUT = os.path.join(HIBERNAL, "assets", "environment")
JSON_OUT = os.path.join(LAB, "out", "hibernal_stage", "hillsScene.json")

CAMERA_YAW = -45.0                    # deg round from -Y: the camera the ridges and the hand layout face
HILL_GAIN = 2.0
HILL_BIG = (13.0, 1.5)                # m per noise cell, m of height (before HILL_GAIN)
HILL_MID = (7.5, 0.7)
HILL_DETAIL = (4.5, 0.35)
HILL_RIDGE = (9.0, 3.2, 0.3, 12.0)    # m along, m across, m of height, deg off the screen's right
FIRE_PAD = (2.2, 4.0)                 # m: flat inside, blended back to the hills by here
MAP_SIZE = 60.0
GRID = 1.0                            # m per ground cell
CHUNKS = 6                            # per side: 10 x 10 cells, 200 tris each
SINK = 0.3                            # m a pillar goes below its lowest corner
# (screen right m, towards camera m, size x, size y, height, yaw deg): the hand-placed stones.
# 0, 2 and 4 sit 9.8 m out so a pet with a 1.82 m clearance can circle the fire in its light.
INNER_PILLARS = [
    (-8.6, -4.69, 1.0, 1.0, 3.4, 0), (3.0, -4.5, 1.2, 1.2, 4.6, 0), (9.69, -1.49, 1.0, 1.0, 1.0, 0),
    (-2.8, 3.6, 1.1, 1.1, 2.8, 0), (7.24, 6.61, 1.0, 1.0, 3.8, 0), (-8.2, 1.4, 1.2, 1.2, 0.9, 0),
    (8.6, 3.4, 1.1, 1.1, 3.0, 0), (0.6, -6.2, 1.3, 1.3, 5.4, 0), (-4.2, -8.4, 1.0, 1.0, 2.6, 0),
]
OUTER_PILLARS = (4, 12.5, 21.5, 6.0)            # how many, from / to m off the fire, least m apart
OUTER_HEIGHTS = (0.8, 1.2, 1.6, 2.0, 2.4)       # kept low: with the camera turning, any may end up in front
SEED = 3
LOGS = [((-0.9, -0.5, 0.05), (0.5, 0.3, 0.8)), ((0.8, -0.6, 0.05), (-0.4, 0.3, 0.8)),
        ((0.1, 1.0, 0.05), (-0.1, -0.4, 0.75)), ((-1.0, 0.6, 0.1), (0.9, -0.2, 0.3))]
LOG_THICKNESS = 0.22
FIRE_HEIGHT = 1.0                     # m above the pad: where the fire's light sits
PET_ROAM_RADIUS = 10.0
CAMERA = {"yawDeg": CAMERA_YAW, "pitchDeg": 30.0, "orthoWidthM": 20.0, "maxZoomOut": 1.25}
COLOURS = {"grass": "#5f8f55", "stone": "#8e8e96", "wood": "#6b4a32"}   # surface tags, sRGB


def screenToWorld(u, v):
    """screen right / towards the camera (m) -> world x, y (Blender, Z up) for CAMERA_YAW"""
    yaw = math.radians(CAMERA_YAW)
    return (math.cos(yaw) * u - math.sin(yaw) * v, -math.sin(yaw) * u - math.cos(yaw) * v)


def rawHills(x, y):
    yaw = math.radians(CAMERA_YAW)
    u = x * math.cos(yaw) - y * math.sin(yaw)
    v = -x * math.sin(yaw) - y * math.cos(yaw)
    a = math.radians(HILL_RIDGE[3])
    ridgeU, ridgeV = u * math.cos(a) + v * math.sin(a), -u * math.sin(a) + v * math.cos(a)
    z = HILL_BIG[1] * noise.noise(Vector((x / HILL_BIG[0], y / HILL_BIG[0], 5.1)))
    z += HILL_MID[1] * noise.noise(Vector((x / HILL_MID[0], y / HILL_MID[0], 6.3)))
    z += HILL_DETAIL[1] * noise.noise(Vector((x / HILL_DETAIL[0], y / HILL_DETAIL[0], 8.7)))
    z += HILL_RIDGE[2] * noise.noise(Vector((ridgeU / HILL_RIDGE[0], ridgeV / HILL_RIDGE[1], 7.9)))
    return z * HILL_GAIN


def groundHeight(x, y):
    """the true ground (m, Blender axes): the hills, flattened into a pad under the fire"""
    r = math.hypot(x, y)
    w = min(1.0, max(0.0, (FIRE_PAD[1] - r) / (FIRE_PAD[1] - FIRE_PAD[0])))
    w = w * w * (3 - 2 * w)
    return rawHills(x, y) * (1 - w) + rawHills(0.0, 0.0) * w


def pillarBoxes():
    """[(name, centre, size xyz, yaw deg)] for every standing stone"""
    boxes = []

    def place(name, x, y, sx, sy, h, yaw):
        z0 = min(groundHeight(x + dx, y + dy) for dx in (-sx / 2, sx / 2) for dy in (-sy / 2, sy / 2)) - SINK
        boxes.append((name, Vector((x, y, z0 + (h + SINK) / 2)), Vector((sx, sy, h + SINK)), yaw))

    for i, (u, v, sx, sy, h, yaw) in enumerate(INNER_PILLARS):
        place("pillar%02d" % i, *screenToWorld(u, v), sx, sy, h, yaw)
    roll = random.Random(SEED)
    taken = [screenToWorld(u, v) for u, v, *_ in INNER_PILLARS]
    count, r0, r1, gap = OUTER_PILLARS
    k = 0
    while k < count:
        a, r = roll.uniform(0, 2 * math.pi), math.sqrt(roll.uniform(r0 * r0, r1 * r1))
        x, y = r * math.cos(a), r * math.sin(a)
        if any(math.hypot(x - px, y - py) < gap for px, py in taken):
            continue
        sx = roll.uniform(1.0, 1.4)
        place("pillarOuter%02d" % k, x, y, sx, sx * roll.uniform(0.85, 1.15), roll.choice(OUTER_HEIGHTS), 0)
        taken.append((x, y))
        k += 1
    return boxes


def logBoxes():
    """[(name, centre, size xyz, rotation)] for the fire's logs, on the pad"""
    pad = groundHeight(0.0, 0.0)
    out = []
    for i, (a, b) in enumerate(LOGS):
        a, b = Vector(a), Vector(b)
        d = b - a
        out.append(("campfireLog%02d" % i, (a + b) / 2 + Vector((0, 0, pad)),
                    Vector((LOG_THICKNESS, LOG_THICKNESS, d.length)), d.to_track_quat("Z", "Y")))
    return out


def srgbToLinear(hexColour):
    c = [int(hexColour[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c) + (1.0,)


def groundNormal(x, y, e=0.25):
    """the true ground's normal at (x, y), from groundHeight()'s slope"""
    dx = (groundHeight(x + e, y) - groundHeight(x - e, y)) / (2 * e)
    dy = (groundHeight(x, y + e) - groundHeight(x, y - e)) / (2 * e)
    return Vector((-dx, -dy, 1.0)).normalized()


def meshObject(name, bm, colour, collection, smooth=False):
    layer = bm.loops.layers.color.new("Col")
    rgba = srgbToLinear(COLOURS[colour])
    for f in bm.faces:
        for loop in f.loops:
            loop[layer] = rgba
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    if smooth:
        me.normals_split_custom_set_from_vertices([groundNormal(v.co.x, v.co.y) for v in me.vertices])
    me.color_attributes.active_color_index = me.color_attributes.render_color_index = 0
    o = bpy.data.objects.new(name, me)
    collection.objects.link(o)
    return o


def box(name, centre, size, rotation, colour, collection):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    rot = rotation.to_matrix().to_4x4() if hasattr(rotation, "to_matrix") else Matrix.Rotation(math.radians(rotation), 4, "Z")
    bm.transform(Matrix.Translation(centre) @ rot @ Matrix.Diagonal((*size, 1)))
    return meshObject(name, bm, colour, collection)


def groundChunks(collection):
    cells = int(MAP_SIZE / GRID)
    per = cells // CHUNKS
    out = []
    for cj in range(CHUNKS):
        for ci in range(CHUNKS):
            bm = bmesh.new()
            verts = {}
            for j in range(cj * per, (cj + 1) * per + 1):
                for i in range(ci * per, (ci + 1) * per + 1):
                    x, y = -MAP_SIZE / 2 + i * GRID, -MAP_SIZE / 2 + j * GRID
                    verts[i, j] = bm.verts.new((x, y, groundHeight(x, y)))
            for j in range(cj * per, (cj + 1) * per):
                for i in range(ci * per, (ci + 1) * per):
                    bm.faces.new((verts[i, j], verts[i + 1, j], verts[i + 1, j + 1], verts[i, j + 1]))
            out.append(meshObject("hillsGround%d%d" % (cj, ci), bm, "grass", collection, smooth=True))
    return out


def voidSubset(path):
    """rewrite a .glb so void's loader takes it: COLOR_0 as FLOAT VEC3, every accessor in a buffer
    view of its own, packed into one buffer (4-byte aligned)"""
    import struct
    import numpy as np
    raw = open(path, "rb").read()
    magic, version, _ = struct.unpack_from("<III", raw, 0)
    assert magic == 0x46546C67 and version == 2
    jlen, _ = struct.unpack_from("<II", raw, 12)
    doc = json.loads(raw[20:20 + jlen])
    blen, _ = struct.unpack_from("<II", raw, 20 + jlen)
    blob = raw[28 + jlen:28 + jlen + blen]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    colours = {p["attributes"]["COLOR_0"] for m in doc["meshes"] for p in m["primitives"] if "COLOR_0" in p["attributes"]}
    out, views = bytearray(), []
    for i, acc in enumerate(doc["accessors"]):
        view = doc["bufferViews"][acc["bufferView"]]
        assert "byteStride" not in view, "interleaved views are outside void's subset"
        n, k = acc["count"], width[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        data = np.frombuffer(blob, comp[acc["componentType"]], n * k, start).reshape(n, k)
        if i in colours:
            scale = float(np.iinfo(data.dtype).max) if data.dtype != np.float32 else 1.0
            data = (data[:, :3].astype(np.float32) / scale).astype(np.float32)
            acc.update(componentType=5126, type="VEC3")
            acc.pop("normalized", None)
            acc["min"], acc["max"] = data.min(0).tolist(), data.max(0).tolist()
        payload = np.ascontiguousarray(data).tobytes()
        out += b"\0" * (-len(out) % 4)
        views.append({"buffer": 0, "byteOffset": len(out), "byteLength": len(payload)})
        out += payload
        acc["bufferView"] = i
        acc.pop("byteOffset", None)
    doc["bufferViews"] = views
    out += b"\0" * (-len(out) % 4)
    doc["buffers"] = [{"byteLength": len(out)}]
    j = json.dumps(doc, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(out)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
        f.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))


def export(objs, path):
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="NONE",
                              export_texcoords=False, export_normals=True, export_vertex_color="ACTIVE",
                              export_animations=False, export_yup=True)
    voidSubset(path)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    collection = bpy.context.scene.collection
    os.makedirs(OUT, exist_ok=True)
    ground = groundChunks(collection)
    pillars = [box(n, c, s, yaw, "stone", collection) for n, c, s, yaw in pillarBoxes()]
    logs = [box(n, c, s, q, "wood", collection) for n, c, s, q in logBoxes()]
    export(ground, os.path.join(OUT, "hillsGround.glb"))
    export(pillars, os.path.join(OUT, "pillars.glb"))
    export(logs, os.path.join(OUT, "campfireLogs.glb"))
    pad = groundHeight(0.0, 0.0)
    toYUp = lambda v: [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]   # the glTF exporter's axes
    scene = {
        "units": "metres, glTF axes (Y up)",
        "fire": toYUp((0.0, 0.0, pad + FIRE_HEIGHT)), "firePad": toYUp((0.0, 0.0, pad)),
        "mapSizeM": MAP_SIZE, "petRoamRadiusM": PET_ROAM_RADIUS, "camera": CAMERA,
        "pillars": [{"name": n, "centre": toYUp(c), "size": [round(s.x, 4), round(s.z, 4), round(s.y, 4)], "yawDeg": yaw}
                    for n, c, s, yaw in pillarBoxes()],
    }
    os.makedirs(os.path.dirname(JSON_OUT), exist_ok=True)
    with open(JSON_OUT, "w") as f:
        json.dump(scene, f, indent=1)
    tris = lambda objs: sum(len(o.data.polygons) for o in objs)
    print(f"HILLS ground {len(ground)} chunks, {max(len(o.data.polygons) for o in ground)} tris max each "
          f"({tris(ground)} total); pillars {len(pillars)} ({tris(pillars)} tris); logs {len(logs)} ({tris(logs)} tris)")


if __name__ == "__main__":
    main()
