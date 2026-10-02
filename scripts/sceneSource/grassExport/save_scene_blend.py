"""Grass lab -> void: exports the grass lab scene (scripts/grass_lab.py) in the form the void
engine's pixel-art renderer loads, so the same scene can be tried in real time.

  B="/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
  "$B" -b --factory-startup -P out/grass_lab/void/export_void.py

Writes next to this file, into data/:
  grass_lab.gltf + grass_lab.bin   ground, stones, slabs, logs: the void glTF subset (float
                                   POSITION / NORMAL / COLOR_0 VEC3, uint16 indices, one buffer),
                                   baked to world space, Y up (void is Y up, right-handed)
  clumps_short.f32, clumps_tall.f32
                                   grass billboard instances, 8 floats each (void's Billboard
                                   layout: root xyz, atlas cell, width, height, tint, emissive)
  atlas_short.rgba, atlas_tall.rgba, atlas_flame.rgba
                                   4-cell sprite atlases, raw RGBA8 rows top first
  palette.u32                      the lab's ramps as 0xRRGGBB, for the palette LUT
  ramps.rgba                       the same ramps as a texture, one row per material (RAMP_ROWS),
                                   then LENS_ROW: the walker's red lens, one colour at every level
  atlas_flame2.rgba                the flame's frames 4-5 (atlas_flame.rgba holds 0-3)
  atlas_tuft.rgba, tufts.f32       the lab's sparse pale V tufts
  walker.f32                       the lab's walker path, WALKER_FPS positions over one loop
  fire.f32                         the ground under the fire, void xyz: grassLab.ms stands the
                                   fire's light, flame and embers on it (the hills are 0.5 m lower)

The clumps are the lab's: one candidate per ROOT_CELL world cell at a hashed point, kept with
the lab's density, tall where the lab's tall-grass noise says so; shapes from clump_table.
"""
import json
import math
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = '\\\\wsl.localhost\\Ubuntu\\home\\trongphuc\\projects\\t3ssel8r-lab'
DATA = '\\\\wsl.localhost\\Ubuntu\\home\\trongphuc\\projects\\void-touch\\out\\grassExport\\data'
os.makedirs(DATA, exist_ok=True)

# the lab without its last line (it calls main() at import)
LAB = os.path.join(ROOT, 'scripts/grass_lab.py')
src = open(LAB).read()
assert src.rstrip().endswith('main()')
lab = {'__file__': LAB, '__name__': 'grass_lab'}
exec(compile(src.rstrip()[:-len('main()')], LAB, 'exec'), lab)

from mathutils import Vector, noise  # noqa: E402  (Blender)

# void-touch (user, 2026-10-01): grass over the whole map, long-grass patches anywhere the noise
# puts them instead of thickening round the fire. Every root cell keeps a clump (the lab's density
# left about half the cells empty, and those read as bare ground).
lab['TALL_FIRE_BOOST'] = 0.0
lab['TALL_CUT'] = 0.57
lab['CLUMP']['short']['p'] = 1.0
lab['CLUMP']['tall']['p'] = 1.0

# Pillars (user, 2026-10-01): 15 inside what the fixed portrait camera sees (the lab's 13 showed
# about 6 there) and 10 just past its sides, scattered at random, no taller than the lab's second tallest (4.6 m), each
# turned at random. Heights: the low ones close together, the gaps widening towards the tall ones
# (PILLAR_H[0] + span * (i / 11)^2, a little jitter), dealt out at random. Screen terms
# as the lab's PILLARS_UV: u metres right of the fire, v metres towards the camera. The layout is
# written to pillars.json so the walker's path bake can stand on the same scene.
import json as _json, random as _random
PILLAR_COUNT = 15
PILLAR_OUTSIDE = 10          # more just past the frame's sides, for a camera that zooms out
PILLAR_OUTSIDE_U = (8.6, 12.5)  # m right or left of the fire
PILLAR_SEED = int(os.environ.get('PILLAR_SEED', '2026'))
PILLAR_U = 6.6              # the portrait frame is 15.5 m across: keep a pillar inside it
PILLAR_V = (-24.0, 24.0)    # far / near; past these the fog or the frame's foot take them
PILLAR_FIRE_CLEAR = 3.2     # m from the fire
PILLAR_GAP = 3.5            # m between any two
PILLAR_H = (0.9, 4.6)
_rnd = _random.Random(PILLAR_SEED)
_placed = []
_tries = 0
while len(_placed) < PILLAR_COUNT + PILLAR_OUTSIDE and _tries < 40000:
    _tries += 1
    if len(_placed) < PILLAR_COUNT:
        u = _rnd.uniform(-PILLAR_U, PILLAR_U)
    else:
        u = _rnd.choice((-1.0, 1.0)) * _rnd.uniform(*PILLAR_OUTSIDE_U)
    v = _rnd.uniform(*PILLAR_V)
    if math.hypot(u, v) < PILLAR_FIRE_CLEAR:
        continue
    if any(math.hypot(u - p[0], v - p[1]) < PILLAR_GAP for p in _placed):
        continue
    sx = _rnd.uniform(1.0, 1.3)
    _placed.append([round(u, 2), round(v, 2), round(sx, 2), round(sx * _rnd.uniform(0.85, 1.15), 2),
                    0.0, round(_rnd.uniform(0.0, 90.0), 1)])
assert len(_placed) == PILLAR_COUNT + PILLAR_OUTSIDE, len(_placed)
for _group in (_placed[:PILLAR_COUNT], _placed[PILLAR_COUNT:]):
    _n = len(_group)
    _heights = [PILLAR_H[0] + (PILLAR_H[1] - PILLAR_H[0]) * (i / (_n - 1)) ** 2 for i in range(_n)]
    _heights = [round(min(PILLAR_H[1], h * _rnd.uniform(0.97, 1.03)), 2) for h in _heights]
    _rnd.shuffle(_heights)
    for _p, _h in zip(_group, _heights):
        _p[4] = _h
_placed = [tuple(p) for p in _placed]
lab['PILLARS_UV'] = _placed
lab['OUTER_PILLARS'] = (0, 0.0, 0.0, 0.0)
_json.dump({'seed': PILLAR_SEED, 'pillars_uv': _placed, 'fields': 'u v sizeX sizeY height yawDeg'},
           open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pillars.json'), 'w'), indent=1)
import bmesh  # noqa: E402
import bpy  # noqa: E402

GRASS_RADIUS = 43.0          # m around the fire that gets clumps: the fixed fire camera sees ground
                             # out to 23.2 m at its widest zoom (1.25x, scripts/view_rings.py)
GROUND_EDGE = 0.3            # m: and none closer than this to the ground mesh's edge
FIRE_CLEAR = 0.8             # m: no grass in the fire
STONE_MARGIN = 0.12          # m: no grass this close to a stone's footprint
ROOT_LIFT = 0.02             # m: clumps sit this far above the ground so it never covers their foot
WORLD_PER_TEXEL = 20.0 / 640.0   # the lab's frame: 20 m across 640 px
SHORT_CELL = (16, 10)        # atlas cell (w, h) in texels
TALL_CELL = (20, 18)
FLAME_CELL = (20, 28)


def to_void(v):
    """Blender (x, y, z), Z up -> void (x, y, z), Y up, right-handed"""
    return (v[0], v[2], -v[1])


# ---------------------------------------------------------------- meshes
BASE = {                      # vertex colours: the albedo the toon shader lights
    'grass': (0.22, 0.30, 0.52),
    'stone': (0.20, 0.22, 0.40),
    'top': (0.30, 0.32, 0.48),
    'wood': (0.16, 0.12, 0.20),
    'tall': (0.26, 0.30, 0.52),       # grass, red above TALL_MARK: a long-grass patch
}
TALL_MARK = 0.24


def is_tall(x, y):
    tn = noise.noise(Vector((x / lab['TALL_SCALE'], y / lab['TALL_SCALE'], 4.2)))
    near = max(0.0, 1.0 - math.hypot(x, y) / lab['TALL_FIRE_R'])
    return (tn * 0.5 + 0.5) > lab['TALL_CUT'] - lab['TALL_FIRE_BOOST'] * near


def mesh_arrays(ob, origin):
    """triangulated, world-oriented, around `origin` (the node's translation); flat objects
    get a vertex per face corner"""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.transform(ob.matrix_world)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    kind = ob['lab_mat']
    smooth = ob.name == 'GROUND'
    pos, nrm, col, idx = [], [], [], []
    if smooth:
        for v in bm.verts:
            pos.append(to_void(v.co))
            nrm.append(to_void(v.normal.normalized()))
            # the lab's long-grass patches (world noise, thicker towards the fire): the base a
            # little redder, which LitRamp reads as one ramp step up (rampRow.w, TALL_MARK)
            col.append(BASE['tall'] if is_tall(v.co.x, v.co.y) else BASE[kind])
        for f in bm.faces:
            idx.extend(v.index for v in f.verts)
    else:
        for f in bm.faces:
            n = f.normal.normalized()
            c = BASE['top'] if (kind == 'stone' and n.z > 0.8) else BASE[kind]
            for v in f.verts:
                idx.append(len(pos))
                pos.append(to_void(v.co - origin))
                nrm.append(to_void(n))
                col.append(c)
    bm.free()
    assert len(pos) < 65536, ob.name
    return (np.array(pos, np.float32), np.array(nrm, np.float32),
            np.array(col, np.float32), np.array(idx, np.uint16))


def write_gltf(objs):
    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def add(arr, gltf_type, component):
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': arr.nbytes})
        blob.extend(arr.tobytes())
        acc = {'bufferView': len(views) - 1, 'componentType': component,
               'count': int(arr.shape[0]), 'type': gltf_type}
        if gltf_type == 'VEC3' and arr.dtype == np.float32:
            acc['min'] = [float(x) for x in arr.min(0)]
            acc['max'] = [float(x) for x in arr.max(0)]
        accessors.append(acc)
        return len(accessors) - 1

    for ob in objs:
        # Stones and logs are modelled around their own origin and placed by the node, so
        # LitRamp can light a wall from its object's origin (one colour per face); the ground
        # stays in world space at the identity.
        origin = Vector((0.0, 0.0, 0.0)) if ob.name == 'GROUND' else ob.matrix_world.translation.copy()
        p, n, c, i = mesh_arrays(ob, origin)
        prim = {'attributes': {'POSITION': add(p, 'VEC3', 5126), 'NORMAL': add(n, 'VEC3', 5126),
                               'COLOR_0': add(c, 'VEC3', 5126)},
                'indices': add(i, 'SCALAR', 5123), 'mode': 4}
        meshes.append({'name': ob.name, 'primitives': [prim]})
        node = {'name': ob.name, 'mesh': len(meshes) - 1}
        if ob.name != 'GROUND':
            node['translation'] = [float(v) for v in to_void(origin)]
        nodes.append(node)
    while len(blob) % 4:
        blob.append(0)
    doc = {'asset': {'version': '2.0', 'generator': 'grass_lab export_void.py'},
           'scene': 0, 'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': nodes,
           'meshes': meshes, 'accessors': accessors, 'bufferViews': views,
           'buffers': [{'byteLength': len(blob), 'uri': 'grass_lab.bin'}]}
    open(os.path.join(DATA, 'grass_lab.bin'), 'wb').write(blob)
    open(os.path.join(DATA, 'grass_lab.gltf'), 'w').write(json.dumps(doc))
    return sum(a['count'] for a in accessors if a['type'] == 'SCALAR') // 3


# ---------------------------------------------------------------- clumps
def on_ground(x, y, objs):
    """within the ground mesh's footprint (less GROUND_EDGE): the lab's ground is a square that
    does not reach GRASS_RADIUS everywhere"""
    if not hasattr(on_ground, 'box'):
        g = next(o for o in objs if o.name == 'GROUND')
        xs = [(g.matrix_world @ v.co).x for v in g.data.vertices]
        ys = [(g.matrix_world @ v.co).y for v in g.data.vertices]
        on_ground.box = (min(xs), max(xs), min(ys), max(ys))
    x0, x1, y0, y1 = on_ground.box
    return x0 + GROUND_EDGE < x < x1 - GROUND_EDGE and y0 + GROUND_EDGE < y < y1 - GROUND_EDGE


def inside_stone(x, y, boxes):
    for inv in boxes:
        q = inv @ Vector((x, y, 0.0))
        if abs(q.x) < 0.5 and abs(q.y) < 0.5:
            return True
    return False


def stone_boxes(objs):
    """the stones' and logs' footprints grown by STONE_MARGIN, as matrices into a unit square"""
    from mathutils import Matrix
    boxes = []
    for ob in objs:
        if ob['lab_mat'] in ('stone', 'wood'):
            sx, sy = ob.scale.x, ob.scale.y
            grow = ((sx + 2 * STONE_MARGIN) / sx, (sy + 2 * STONE_MARGIN) / sy)
            boxes.append(Matrix.Diagonal((1 / grow[0], 1 / grow[1], 1, 1)) @ ob.matrix_world.inverted())
    return boxes


def clump_instances(objs):
    hash01, ground_z = lab['hash01'], lab['ground_z']
    cell = lab['ROOT_CELL']
    px_area = WORLD_PER_TEXEL ** 2 / math.sin(math.radians(lab['CAM_ELEV']))
    boxes = stone_boxes(objs)
    n = int(GRASS_RADIUS / cell) + 1
    cx, cy = np.meshgrid(np.arange(-n, n + 1), np.arange(-n, n + 1))
    cx, cy = cx.ravel(), cy.ravel()
    wx = (cx + hash01(cx, cy, 1)) * cell
    wy = (cy + hash01(cx, cy, 2)) * cell
    r = np.hypot(wx, wy)
    ok = (r < GRASS_RADIUS) & (r > FIRE_CLEAR)
    ok &= np.array([on_ground(x, y, objs) for x, y in zip(wx, wy)])
    cx, cy, wx, wy = cx[ok], cy[ok], wx[ok], wy[ok]
    tn = np.array([noise.noise(Vector((x / lab['TALL_SCALE'], y / lab['TALL_SCALE'], 4.2))) for x, y in zip(wx, wy)])
    near = np.clip(1 - np.hypot(wx, wy) / lab['TALL_FIRE_R'], 0, 1)
    tall = (tn * 0.5 + 0.5) > lab['TALL_CUT'] - lab['TALL_FIRE_BOOST'] * near
    p = np.where(tall, lab['CLUMP']['tall']['p'], lab['CLUMP']['short']['p']) * cell ** 2 / px_area
    keep = hash01(cx, cy, 3) < p
    out = {'short': [], 'tall': []}
    for x, y, t, a, b, c in zip(wx[keep], wy[keep], tall[keep], hash01(cx[keep], cy[keep], 4),
                                hash01(cx[keep], cy[keep], 5), hash01(cx[keep], cy[keep], 6)):
        if inside_stone(x, y, boxes):
            continue
        kind = 'tall' if t else 'short'
        cw, ch = TALL_CELL if t else SHORT_CELL
        z = ground_z(x, y) + ROOT_LIFT
        vx, vy, vz = to_void((x, y, z))
        # atlas cell; the clump's ramp step: a step darker / as lit / a step lighter as the
        # lab's CLUMP_STEP_P (the long grass's step up is its material's; grassLab turns the
        # steps into a tint when it draws without the ramp programs)
        step = -1 if b < lab['CLUMP_STEP_P'][0] else (1 if b > 1 - lab['CLUMP_STEP_P'][2] else 0)
        out[kind] += [vx, vy, vz, float(int(a * 4) % 4),
                      cw * WORLD_PER_TEXEL, ch * WORLD_PER_TEXEL, float(step), 0.0]
    return out


def atlas(kind, cell, heights, seed):
    """4 clumps from the lab's clump_table, white silhouettes on transparent, root at the
    bottom centre of each cell"""
    c = lab['CLUMP'][kind]
    reach = cell[0] // 2
    hmax = max(heights)
    T = lab['clump_table']([(4, c['halfw'], c['leafw'])], hmax, reach, seed)
    w, h = cell
    img = np.zeros((h, 4 * w, 4), np.uint8)
    for p in range(4):
        m = T[p, heights[p]]                 # [k, dx + reach], k = rows up from the root
        for k in range(1, min(h, m.shape[0])):
            for j in range(m.shape[1]):
                x = j - reach + w // 2
                if m[k, j] and 0 <= x < w:
                    img[h - k, p * w + x] = (255, 255, 255, 255)
        # the root row itself, so the clump stands on its root pixel
        img[h - 1, p * w + w // 2] = (255, 255, 255, 255)
    img.tofile(os.path.join(DATA, 'atlas_%s.rgba' % kind))
    return img


FLAME_COLOURS = []


def flame_atlas():
    """the lab's flame strip (assets/flame_strip.png, 6 frames) as two 4-cell atlases:
    frames 0-3, and frames 4-5 (the billboard programs read 4 cells across)"""
    import bpy
    path = os.path.join(ROOT, 'assets/flame_strip.png')
    im = bpy.data.images.load(path)
    fw, fh = im.size
    px = (np.array(im.pixels[:]).reshape(fh, fw, 4)[::-1] * 255 + 0.5).astype(np.uint8)
    frames = 6
    cw = fw // frames
    w, h = FLAME_CELL
    for name, cells in (('atlas_flame.rgba', (0, 1, 2, 3)), ('atlas_flame2.rgba', (4, 5, 4, 5))):
        img = np.zeros((h, 4 * w, 4), np.uint8)
        for i, f in enumerate(cells):
            cellpx = px[:, f * cw:(f + 1) * cw]
            cellpx = cellpx[-h:, :w] if cellpx.shape[0] >= h else cellpx
            ch_, cw_ = cellpx.shape[:2]
            img[h - ch_:, i * w:i * w + cw_] = cellpx
        img[..., 3] = np.where(img[..., 3] > 127, 255, 0)
        img.tofile(os.path.join(DATA, name))
        for r, g, b, a in img.reshape(-1, 4):
            if a:
                FLAME_COLOURS.append((int(r) << 16) | (int(g) << 8) | int(b))
    print('flame strip', fw, fh, 'frames', frames)


RAMP_ROWS = ('grass', 'stone', 'top', 'wood', 'tuft')
# The four-legged walker's lens (export_walker.py) glows: the same hot red whatever the light,
# a little brighter than anything firelit, as scripts/walker_lab_render.py paints it.
LENS_ROW = '#ff5a40'

# the lab's pale tufts: three blades in a V, sparse, one per TUFT_SPRITE_EVERY world cell
TUFT_SPRITE = ['....1..',
               '1...1..',
               '1..1..1',
               '.1.1.1.',
               '.1.1.1.',
               '..111..',
               '...1...']
TUFT_CELL = (8, 7)
TUFT_KEEP = 0.35
TUFT_FORWARD = 0.15                  # m towards the camera
# The lab keeps TUFT_KEEP of its 4.5 m cells, rooting each on the first grass pixel of the cell
# the frame shows - partly visible cells count, so it shows ~13 tufts where 4.5 m world cells
# give ~3. Half the cell gives the lab's count while staying anchored to the world.
TUFT_CELL_M = lab['TUFT_SPRITE_EVERY'] / 2


def tufts(objs):
    """the V tuft atlas (4 cells: as drawn and mirrored, twice) and one instance per kept cell,
    at a hashed point in it, off stones and out of the fire"""
    w, h = TUFT_CELL
    img = np.zeros((h, 4 * w, 4), np.uint8)
    for c in range(4):
        for y, row in enumerate(TUFT_SPRITE):
            for x, ch in enumerate(row if c % 2 == 0 else row[::-1]):
                if ch == '1':
                    img[y, c * w + x] = (255, 255, 255, 255)
    img.tofile(os.path.join(DATA, 'atlas_tuft.rgba'))
    hash01, cell = lab['hash01'], TUFT_CELL_M
    n = int(GRASS_RADIUS / cell) + 1
    boxes = stone_boxes(objs)
    inst = []
    for cy in range(-n, n + 1):
        for cx in range(-n, n + 1):
            if hash01(cx, cy, 21) > TUFT_KEEP:
                continue
            x, y = (cx + hash01(cx, cy, 22)) * cell, (cy + hash01(cx, cy, 23)) * cell
            if (math.hypot(x, y) > GRASS_RADIUS or math.hypot(x, y) < FIRE_CLEAR or inside_stone(x, y, boxes)
                    or not on_ground(x, y, objs)):
                continue
            # the lab draws a tuft over clumps within 0.2 of its depth: stand it a little
            # towards the camera so the clumps around it do not cover it
            tx, ty = lab['uv_to_xy'](0.0, TUFT_FORWARD)
            gx, gy = x + tx, y + ty
            vx, vy, vz = to_void((gx, gy, lab['ground_z'](gx, gy) + ROOT_LIFT))
            inst += [vx, vy, vz, float(int(hash01(cx, cy, 24) * 4) % 4),
                     w * WORLD_PER_TEXEL, h * WORLD_PER_TEXEL, 0.0, 0.0]
    np.array(inst, np.float32).tofile(os.path.join(DATA, 'tufts.f32'))
    return len(inst) // 8


def walker_path():
    """the lab's walker (--walker): WALKER_FPS positions over one LOOP_S, on the ground, void xyz"""
    n = int(lab['LOOP_S'] * lab['WALKER_FPS'])
    out = []
    for i in range(n):
        x, y, z = lab['walker_at'](i / lab['WALKER_FPS'])
        out += list(to_void((x, y, z)))
    np.array(out, np.float32).tofile(os.path.join(DATA, 'walker.f32'))
    return n


def ramps():
    """the lab's RAMPS, one row per material in RAMP_ROWS order, dark to light (its night steps,
    then one colour per fire band): the texture the ramp programs look colours up in"""
    rows = [lab['RAMPS'][k] for k in RAMP_ROWS]
    width = len(rows[0])
    rows.append([LENS_ROW] * width)
    assert all(len(r) == width for r in rows)
    img = np.zeros((len(rows), width, 4), np.uint8)
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            img[y, x] = lab['hex_rgb'](c) + [255]
    img.tofile(os.path.join(DATA, 'ramps.rgba'))
    return width


def palette():
    """palette.u32: every ramp and the flame, for the ramp look (its colours are exact ramp
    colours already; the LUT only snaps what the outline pass darkens). palette_toon.u32: the
    same without the pale tuft ramp, for the toon looks, where it would catch the dim edge of
    the firelight."""
    for name, skip in (('palette.u32', ()), ('palette_toon.u32', ('tuft',))):
        cols = [int(h[1:], 16) for kind, ramp in lab['RAMPS'].items() if kind not in skip for h in ramp]
        cols.append(0x05030F)
        cols += FLAME_COLOURS                # the flame keeps its own colours through the LUT
        cols = sorted(set(cols))
        np.array(cols, np.uint32).tofile(os.path.join(DATA, name))
    return len(cols)


def main():
    sc, cam, objs = lab['build']()
    # build() sets each object's transform after adding it, and matrix_world only catches up on
    # the next depsgraph update: without this the last log exports as the untransformed 1 m cube
    bpy.context.view_layer.update()
    tris = write_gltf(objs)
    inst = clump_instances(objs)
    ns, nt = len(inst['short']) // 8, len(inst['tall']) // 8
    for kind in ('short', 'tall'):
        np.array(inst[kind], np.float32).tofile(os.path.join(DATA, 'clumps_%s.f32' % kind))
    atlas('short', SHORT_CELL, (4, 5, 5, 6), lab['SEED'])
    atlas('tall', TALL_CELL, (11, 13, 14, 16), lab['SEED'] + 7)
    flame_atlas()
    npal = palette()
    nramp = ramps()
    ntuft = tufts(objs)
    nwalk = walker_path()
    fire = to_void((0.0, 0.0, 1.0 + ground_z0()))
    np.array(to_void((0.0, 0.0, ground_z0())), np.float32).tofile(os.path.join(DATA, 'fire.f32'))
    print('EXPORT objects=%d tris=%d clumps short=%d tall=%d tufts=%d walker=%d palette=%d ramps=%dx%d fire=%s'
          % (len(objs), tris, ns, nt, ntuft, nwalk, npal, nramp, len(RAMP_ROWS) + 1, tuple(round(v, 3) for v in fire)))


def ground_z0():
    return lab['ground_z'](0.0, 0.0)



# ---- save_scene_blend: the same scene as a .blend to look at (no grass: 120k clumps), with the
# game's portrait camera (45 deg round, 30 deg down, 15.5 m across, 360x800)
sc, cam, objs = lab['build']()
bpy.context.view_layer.update()
cam.data.ortho_scale = 20.0 / 640.0 * 360.0 * 1.38
cam.data.sensor_fit = 'HORIZONTAL'
sc.render.resolution_x, sc.render.resolution_y = 360, 800
mats = {}
for name, rgb in (('grass', (0.08, 0.13, 0.24)), ('stone', (0.25, 0.22, 0.30)), ('wood', (0.18, 0.09, 0.06))):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgb + (1.0,)
    mats[name] = m
for o in objs:
    o.data.materials.clear()
    o.data.materials.append(mats[o['lab_mat']])
fire = bpy.data.lights.new('FIRE', 'POINT')
fire.energy, fire.color, fire.shadow_soft_size = 600.0, (1.0, 0.45, 0.16), 0.1
fo = bpy.data.objects.new('FIRE', fire)
fo.location = (0.0, 0.0, lab['ground_z'](0.0, 0.0) + 1.0)
sc.collection.objects.link(fo)
moon = bpy.data.lights.new('MOON', 'SUN')
moon.energy, moon.color = 0.4, (0.6, 0.7, 1.0)
mo = bpy.data.objects.new('MOON', moon)
mo.rotation_euler = (0.7, 0.3, 2.6)
sc.collection.objects.link(mo)
sc.world = bpy.data.worlds.new('NIGHT')
sc.world.color = (0.02, 0.02, 0.05)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'scene_pillars.blend')
bpy.ops.wm.save_as_mainfile(filepath=out)
print('SAVED', out, len(objs), 'objects')
