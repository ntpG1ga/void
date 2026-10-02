"""Grass lab: a copy of t3ssel8r's "Nighttime Lighting in a Pixel Art Scene"
(ref/t3ssel8r_night_lighting.mp4, youtube VEP4INri_1U) to get the grass right
on its own, away from the lake scene.

  B="/mnt/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
  "$B" -b --factory-startup -P scripts/grass_lab.py [-- --frames 96] [--walker 1]
      -> out/grass_lab/grass_lab.blend, review/grass_lab_640x360.png (+ _x3),
         review/grass_lab_vs_video.png; --frames N also writes out/grass_lab/anim/
  [-- --roots screen|world] [--wind noise|waves]   the old / the new way (default: world, noise)
  LAB_TERRAIN=hills (env, so export_void.py sees it too): rolling hills with long ridges and grey
      pillars, after t3ssel8r's "Isometric Camera" clip (youtube ij555s4mAuI), instead of the night
      video's gentle roll and stones; outputs get a _hills suffix, the default files are untouched
  [-- --pancheck 1]   pans the camera 7 x 4 px and counts the pixels that moved
                      -> review/grass_lab_pancheck.png (top: screen roots, bottom: world)

The scene: rolling grass, stone pillars and blocks, four stepping slabs, a
campfire; orthographic camera 45 deg round, 30 deg down, 640 x 360 like the video.

Blender only renders buffers (world position, world normal, material id) with
emission materials and no filtering. Everything else is numpy, the way the
engine will do it:
  * light = a dim moon (no shadow) + the fire, a point light with a ray-cast
    hard shadow; both cut into bands, and the band picks the colour on the
    material's ramp: night blues, then purple, rose, coral, orange;
  * tall grass: patches (world noise) one step lighter than the short grass;
  * blades: every grass pixel may root a tuft (tuft_table, as render_look.py)
    in the colour of its root, z-tested - short grass 1-3 px, tall grass up to
    8 px - so the lawn is flat and every light edge and patch edge goes ragged;
  * sparse pale tufts, the flame sprite, a banded vignette.
Nothing here touches the lake scene.
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector, noise

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'out/grass_lab')
REVIEW = os.path.join(ROOT, 'review')
VIDEO_FRAME = os.path.join(ROOT, 'ref/video_night_lighting_18s_640x360.png')
W, H = 640, 360
SCALE = 3
CAM_YAW, CAM_ELEV = -45.0, 30.0       # deg round from -Y (negative: from the south-east), deg down
BUF_OFFSET = 100.0                     # metres added to positions in the buffer (emission is >= 0)
ORTHO = 20.0                           # metres across the frame
TARGET = Vector((0.0, 0.0, 1.2))

FIRE = Vector((0.0, 0.0, 1.0))
FIRE_R = 7.5                          # metres: where the firelight runs out
FIRE_FALL = 1.5
FIRE_GAIN = 1.0                        # overall strength of the firelight
GRASS_WRAP = 0.75                      # grass: this much of the firelight whatever its normal
MOON_DIR = Vector((-0.45, 0.25, 0.86)).normalized()  # towards the moon
MOON_BANDS = (0.35, 0.75)                            # n.l above these: moon band 1..2
VIGNETTE = (0.55, 0.72, 0.9)                # radius (1 = frame corner) where it takes 1 / 2 steps
VIGNETTE_ON = 1                             # 0 for the pan check: the vignette is fixed to the screen

# ramps, dark to light: 3 night steps for the moon, then one colour per fire band,
# sampled evenly (in Oklab) along the key colours - more bands, more light edges,
# and every light edge is where the blades show
N_FIRE = 16
FIRE_BANDS = tuple(0.05 + i * 0.058 for i in range(N_FIRE))   # the top bands only right at the fire
KEYS = {
    'grass': (['#0f1830', '#15213d', '#1c2946'], ['#26284a', '#4a2c48', '#7a3446', '#a8423f', '#d0583f', '#ee7d45', '#f9a95a']),
    'stone': (['#0c0f22', '#121631', '#1a1f3c'], ['#231f36', '#44283a', '#6e303e', '#9c3c3a', '#c8523c', '#e8743f', '#f59c52']),
    'top':   (['#141a30', '#1e2440', '#2a2d4a'], ['#322d44', '#553a40', '#7a4a44', '#9e5c48', '#c07752', '#dd965e', '#efb877']),
    'wood':  (['#0b0a18', '#120f22', '#1a152c'], ['#22172a', '#3e2228', '#582c28', '#7a3a2a', '#a04e2c', '#c86a32', '#e89048']),
    'tuft':  (['#3c4a6e', '#48587e', '#56688e'], ['#62647f', '#8a6a84', '#aa707a', '#c88070', '#e09a72', '#f4b67c', '#fbd394']),
}


def _oklab(c):
    c = np.array(c, float) / 255
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    lms = np.cbrt(np.array([[0.4122, 0.5363, 0.0514], [0.2119, 0.6807, 0.1074], [0.0883, 0.2817, 0.6300]]) @ c)
    return np.array([[0.2105, 0.7936, -0.0041], [1.9780, -2.4286, 0.4506], [0.0259, 0.7828, -0.8087]]) @ lms


def _srgb(lab):
    lms = np.array([[1, 0.3964, 0.2158], [1, -0.1056, -0.0639], [1, -0.0895, -1.2915]]) @ lab
    c = np.array([[4.0767, -3.3077, 0.2310], [-1.2684, 2.6098, -0.3413], [-0.0042, -0.7034, 1.7076]]) @ lms ** 3
    c = np.clip(c, 0, 1)
    c = np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
    return '#%02x%02x%02x' % tuple(int(round(v * 255)) for v in c)


def _ramp(night, keys, n):
    labs = [_oklab([int(k[i:i + 2], 16) for i in (1, 3, 5)]) for k in keys]
    out = []
    for i in range(n):
        t = i / (n - 1) * (len(labs) - 1)
        j = min(int(t), len(labs) - 2)
        out.append(_srgb(labs[j] * (1 - (t - j)) + labs[j + 1] * (t - j)))
    return list(night) + out


RAMPS = {k: _ramp(nt, fk, N_FIRE) for k, (nt, fk) in KEYS.items()}
MAT_IDS = {'grass': 1, 'stone': 2, 'wood': 3}

# grass
TALL_SCALE = 5.5                       # metres per noise cell of the tall grass patches
TALL_CUT = 0.52 
TALL_FIRE_R, TALL_FIRE_BOOST = 6.0, 0.35   # long grass thickens towards the fire
BLADE_LIGHT_JITTER = 0.012
BLADE_TIP_STEPS = 3                    # firelit blades: this many ramp steps lighter at the tip
FIRE_SHADOW = False                    # the video's pillars cast no shadow on the grass             # per-blade spread of the light at the root                        # noise above this: tall grass
BLADE_PX = {'short': (2, 5), 'tall': (7, 12)}   # tuft height range, px
BLADE_P = {'short': 0.36, 'tall': 0.55}
BLADE_LEAN = 0.9                       # px at full height: the video's blades stand nearly straight
BLADE_REACH = 3
TUFT_SHAPES = 32
CLUMP = {                              # h px, half width px, chance a grass pixel roots one
    'tall': {'h': (8, 15), 'halfw': (2.6, 5.2), 'leafw': (3.1, 4.9), 'p': 0.030, 'shapes': 48},
    'short': {'h': (3, 6), 'halfw': (1.8, 3.5), 'leafw': (2.1, 3.0), 'p': 0.035, 'shapes': 24},
}
CLUMP_REACH = 14
CLUMP_STEP_P = (0.22, 0.56, 0.22)      # chance a clump sits a step darker / as lit / a step lighter
SWAY_PX = (-3, -2, -1, 0, 1, 2, 3)    # tip offsets the clump tables are drawn at
PERSP_Q = (-0.3, 0.0, 0.3)             # fake perspective the tables are drawn at (tip width scale)
WIND = 1.0                             # 1 = tall grass tips swing the full WIND_PX
FPS, LOOP_S = 24, 4.0

# Dylearn's grass (youtube OxsuWDtjuGw), ported to the lab:
# roots: 'world' = one clump per world grid cell, hashed, so a clump stays on its
# patch of ground whatever the camera does; 'screen' = the old per-pixel roll
ROOTS = 'world'
ROOT_CELL = 0.17                       # m: cell side; density matches the old per-pixel chance
ROOT_TOL = 0.06                        # m: the cell's point must land this close to a visible pixel
# wind: 'noise' = two value-noise fields scrolling downwind, their directions spread by
# +-WIND_DIV and their scale and speed apart by pi so the product never repeats;
# 'waves' = the old two sines
WIND_MODE = 'noise'
WIND_DIR_UV = (0.85, -0.5)             # blowing (screen right, towards camera): right and away
WIND_DIV = 20.0                        # deg
WIND_SCALE, WIND_SPEED = 3.2, 2.4      # m per noise cell, m/s
WIND_GAIN, WIND_BIAS = 3.2, -0.25      # gust = clamp(n1 * n2 * gain + bias, 0, 1)
WIND_PX = 3.0                          # px a tall clump's tips go at a full gust
WIND_PERSP = 0.3                       # tip width change at a full gust, along the view
WIGGLE_PX, WIGGLE_HZ = 0.55, 0.7       # the small idle sway on top, each clump its own phase
WIND_FPS = 8                           # the wind is sampled at this rate, each clump phase-shifted
# a walker pushing the grass aside (--walker): crosses the open lawn in front of the fire
WALKER_FROM_UV, WALKER_TO_UV = (-2.2, 4.2), (3.4, 4.6)   # screen right / towards camera, m; over one loop
WALKER_R, WALKER_EXP, WALKER_PX = 1.2, 1.0, 4.0
WALKER_FLAT = 0.55                     # share of its height a clump right at the feet loses (bent over)
WALKER_FPS = 12                        # a little above the wind's, as in the video
LEAF_N = (4, 7)                        # leaves per clump
LEAF_FAN = 18.0                        # deg: the outermost leaves lean out this far
LEAF_JITTER = 9.0                     # deg of lean of its own on top
LEAF_BEND = 0.18                       # share of its length a leaf's tip bends aside
CLUMP_BODY = 0.12                      # the low mass under the leaves, share of the height
TUFT_SPRITE_EVERY = 4.5                # metres between the pale tufts, on average
SEED = 3

# terrain: 'lab' = the night video's gentle roll + stones (default); 'hills' = the Isometric Camera
# clip's rolling hills: big swells, a mid layer, and long low ridges lying along the screen, which
# the light bands turn into the clip's streaks; a flat pad keeps the campfire level
TERRAIN = os.environ.get('LAB_TERRAIN', 'lab')
HILL_GAIN = float(os.environ.get('LAB_HILL_GAIN', '2.0'))   # scales every hill height below (x2 picked 2026-09-25)
HILL_BIG = (13.0, 1.5)                 # m per noise cell, m of height
HILL_MID = (7.5, 0.7)
HILL_DETAIL = (4.5, 0.35)              # the small humps that make the clip's lit and dark blobs
HILL_RIDGE = (9.0, 3.2, 0.3, 12.0)    # m along, m across, m of height, deg off the screen's right
FIRE_PAD = (2.2, 4.0)                  # m: flat inside, blended back to the hills by here
# the clip's grey blocks: (u, v, size x, size y, height, yaw deg), screen terms like STONES_UV
PILLARS_UV = [   # most stand 1.5-2.5x a 2 m walker; two stay low for contrast
    # 0, 2, 4 pushed out to 9.8 m along their bearing (2026-09-25): with the v2 legs the walker needs
    # 1.82 m clear of a pillar, and these three closed the firelit 5-7 m ring (22% walkable -> ~57%)
    (-8.6, -4.69, 1.0, 1.0, 3.4, 0), (3.0, -4.5, 1.2, 1.2, 4.6, 0), (9.69, -1.49, 1.0, 1.0, 1.0, 0),
    (-2.8, 3.6, 1.1, 1.1, 2.8, 0), (7.24, 6.61, 1.0, 1.0, 3.8, 0), (-8.2, 1.4, 1.2, 1.2, 0.9, 0),
    (8.6, 3.4, 1.1, 1.1, 3.0, 0), (0.6, -6.2, 1.3, 1.3, 5.4, 0), (-4.2, -8.4, 1.0, 1.0, 2.6, 0),
]
# the fixed fire camera, turned any way and zoomed out to 1.25x, sees ground 23.2 m from the fire
# (scripts/view_rings.py), so the hills ground is 60 m square round the fire instead of lab's 44 m
# (off-centre by 2 m), and a looser ring of pillars fills the 12-22 m band that now comes into frame
HILLS_MAP = 60.0
OUTER_PILLARS = (4, 12.5, 21.5, 6.0)   # user 2026-09-25: 10 was too many  # how many, from / to m off the fire, least m between any two pillars
OUTER_HEIGHTS = (0.8, 1.2, 1.6, 2.0, 2.4)   # kept low: with the camera turning, any of them can end up in front
DAY_GREENS = ['#2f6b4f', '#76ad63', '#c9e58d']   # the clip's shadow / mid / lit grass, for the relief check
DAY_SHARES = (0.16, 0.60)              # measured off the clip: ~16% dark, ~60% mid, the rest lit

# stones, laid out in SCREEN terms measured off the video: u = metres to the right
# of the fire, v = metres towards the camera; (u, v, size x, size y, height, yaw deg)
STONES_UV = [
    (0.2, -2.6, 1.1, 1.1, 7.2, 0),      # the tallest, right behind the fire
    (2.6, -2.2, 1.0, 1.0, 5.2, 0),      # second, behind and right
    (-4.0, -1.6, 1.1, 1.1, 3.4, 0),     # short, left
    (1.5, 1.6, 1.1, 1.1, 3.0, 0),       # in front, right of the fire
    (3.6, 0.6, 1.1, 1.1, 1.2, 0),       # low block right of the fire
    (4.6, 3.6, 1.1, 1.1, 1.4, 0), (5.5, 3.2, 1.0, 1.0, 0.8, 0), (5.0, 4.6, 1.2, 0.9, 0.6, 0),
    (9.0, 0.8, 1.1, 1.1, 1.3, 0), (9.8, 1.6, 1.0, 1.0, 0.8, 0),
    (-2.4, -5.8, 1.0, 1.0, 1.6, 0), (-0.2, -6.4, 1.3, 1.0, 1.0, 0),
    (-8.5, 1.0, 1.4, 1.4, 1.0, 0), (-7.8, -1.2, 1.0, 1.0, 1.5, 0),
    (8.0, -4.6, 1.2, 1.2, 1.8, 0), (8.8, -3.8, 1.0, 1.0, 1.0, 0),
]
SLABS_UV = [(-2.8, 0.9, 2.2, 0.9, 0.35, 8), (-3.6, 2.1, 2.2, 0.9, 0.35, 4),
            (-4.3, 3.3, 2.2, 0.9, 0.35, -3), (-5.0, 4.5, 2.2, 0.9, 0.35, -8)]


def uv_to_xy(u, v):
    """screen right / towards camera -> world x, y for the camera at CAM_YAW"""
    yaw = math.radians(CAM_YAW)
    right = Vector((math.cos(yaw), -math.sin(yaw)))
    toward = Vector((-math.sin(yaw), -math.cos(yaw)))
    p = right * u + toward * v
    return p.x, p.y


LOGS = [(Vector((-0.9, -0.5, 0.05)), Vector((0.5, 0.3, 0.8))), (Vector((0.8, -0.6, 0.05)), Vector((-0.4, 0.3, 0.8))),
        (Vector((0.1, 1.0, 0.05)), Vector((-0.1, -0.4, 0.75))), (Vector((-1.0, 0.6, 0.1)), Vector((0.9, -0.2, 0.3)))]


def arg(name, default=None):
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    return argv[argv.index(name) + 1] if name in argv else default


def hex_rgb(h):
    return [int(h[i:i + 2], 16) for i in (1, 3, 5)]


def _hills_z(x, y):
    yaw = math.radians(CAM_YAW)
    u = x * math.cos(yaw) - y * math.sin(yaw)             # screen right, as uv_to_xy
    v = -x * math.sin(yaw) - y * math.cos(yaw)            # towards the camera
    a = math.radians(HILL_RIDGE[3])
    ru, rv = u * math.cos(a) + v * math.sin(a), -u * math.sin(a) + v * math.cos(a)
    z = HILL_BIG[1] * noise.noise(Vector((x / HILL_BIG[0], y / HILL_BIG[0], 5.1)))
    z += HILL_MID[1] * noise.noise(Vector((x / HILL_MID[0], y / HILL_MID[0], 6.3)))
    z += HILL_DETAIL[1] * noise.noise(Vector((x / HILL_DETAIL[0], y / HILL_DETAIL[0], 8.7)))
    z += HILL_RIDGE[2] * noise.noise(Vector((ru / HILL_RIDGE[0], rv / HILL_RIDGE[1], 7.9)))
    # no 'back' rise here: lab's quadratic climbs ~23 m by the far corner of the 44 m ground,
    # harmless off-camera but a wall for anything walking the map
    return z * HILL_GAIN


def ground_z(x, y):
    """gentle rolling ground, rising towards the back like the video's slope
    (LAB_TERRAIN=hills: the Isometric Camera hills, flattened into a pad under the fire)"""
    if TERRAIN == 'hills':
        r = math.hypot(x, y)
        w = min(1.0, max(0.0, (FIRE_PAD[1] - r) / (FIRE_PAD[1] - FIRE_PAD[0])))
        w = w * w * (3 - 2 * w)
        return _hills_z(x, y) * (1 - w) + _hills_z(0.0, 0.0) * w
    z = 0.55 * noise.noise(Vector((x / 9.0, y / 9.0, 0.3))) + 0.25 * noise.noise(Vector((x / 4.0, y / 4.0, 1.7)))
    back = max(0.0, (x + y) / math.sqrt(2) - 6.0)
    return z + 0.12 * back * back / 4.0


# ---------------------------------------------------------------- scene

def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    coll = sc.collection
    objs = []

    # ground: 44 x 44 m (hills: HILLS_MAP, centred on the fire), 0.4 m grid
    n, size, off = (int(HILLS_MAP / 0.4), HILLS_MAP, 0.0) if TERRAIN == 'hills' else (110, 44.0, 2.0)
    verts = []
    for j in range(n + 1):
        for i in range(n + 1):
            x, y = -size / 2 + i * size / n + off, -size / 2 + j * size / n + off
            verts.append((x, y, ground_z(x, y)))
    faces = [(j * (n + 1) + i, j * (n + 1) + i + 1, (j + 1) * (n + 1) + i + 1, (j + 1) * (n + 1) + i)
             for j in range(n) for i in range(n)]
    me = bpy.data.meshes.new('GROUND')
    me.from_pydata(verts, [], faces)
    me.shade_smooth()
    ob = bpy.data.objects.new('GROUND', me)
    ob['lab_mat'] = 'grass'
    coll.objects.link(ob)
    objs.append(ob)

    def box(name, x, y, sx, sy, h, yaw, mat, sink=0.3):
        z0 = min(ground_z(x + dx, y + dy) for dx in (-sx / 2, sx / 2) for dy in (-sy / 2, sy / 2)) - sink
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.active_object
        o.name = name
        o.scale = (sx, sy, h + sink)
        o.location = (x, y, z0 + (h + sink) / 2)
        o.rotation_euler = (0, 0, math.radians(yaw))
        o['lab_mat'] = mat
        objs.append(o)
        return o

    # yaw: the blocks stand square to the camera diagonal, like the video's
    if TERRAIN == 'hills':
        for i, (u, v, sx, sy, h, yaw) in enumerate(PILLARS_UV):
            box('PILLAR_%02d' % i, *uv_to_xy(u, v), sx, sy, h, yaw, 'stone')
        rnd = __import__('random').Random(SEED)
        taken = [uv_to_xy(u, v) for u, v, *_ in PILLARS_UV]
        count, r0, r1, gap = OUTER_PILLARS
        k = 0
        while k < count:
            a, r = rnd.uniform(0, 2 * math.pi), math.sqrt(rnd.uniform(r0 * r0, r1 * r1))
            x, y = r * math.cos(a), r * math.sin(a)
            if any(math.hypot(x - px, y - py) < gap for px, py in taken):
                continue
            sx = rnd.uniform(1.0, 1.4)
            box('PILLAR_OUT_%02d' % k, x, y, sx, sx * rnd.uniform(0.85, 1.15), rnd.choice(OUTER_HEIGHTS),
                0, 'stone')
            taken.append((x, y))
            k += 1
    else:
        for i, (u, v, sx, sy, h, yaw) in enumerate(STONES_UV):
            box('STONE_%02d' % i, *uv_to_xy(u, v), sx, sy, h, yaw, 'stone')
        for i, (u, v, sx, sy, h, yaw) in enumerate(SLABS_UV):
            box('SLAB_%02d' % i, *uv_to_xy(u, v), sx, sy, h, 45 + yaw, 'stone', sink=0.15)
    for i, (a, b) in enumerate(LOGS):
        d = b - a
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.active_object
        o.name = 'LOG_%02d' % i
        o.scale = (0.22, 0.22, d.length)
        o.location = (a + b) / 2 + Vector((0, 0, ground_z(0, 0)))
        o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        o['lab_mat'] = 'wood'
        objs.append(o)

    cam_d = bpy.data.cameras.new('CAM_LAB')
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = ORTHO
    cam_d.clip_start, cam_d.clip_end = 0.1, 400
    cam = bpy.data.objects.new('CAM_LAB', cam_d)
    coll.objects.link(cam)
    yaw, el = math.radians(CAM_YAW), math.radians(CAM_ELEV)
    t = TARGET + Vector((0, 0, ground_z(TARGET.x, TARGET.y)))
    pos = t + 60 * Vector((-math.sin(yaw) * math.cos(el), -math.cos(yaw) * math.cos(el), math.sin(el)))
    cam.location = pos
    cam.rotation_euler = (t - pos).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam

    r = sc.render
    r.engine = 'BLENDER_EEVEE'
    r.resolution_x, r.resolution_y, r.resolution_percentage = W, H, 100
    r.filter_size = 0.0
    r.film_transparent = True
    sc.eevee.taa_render_samples = 1
    sc.view_settings.view_transform = 'Standard'
    sc.world = bpy.data.worlds.new('W')
    return sc, cam, objs


def emission_mat(name, kind, value=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(em.outputs[0], out.inputs['Surface'])
    if kind == 'id':
        em.inputs['Color'].default_value = (value, 0, 0, 1)
    else:
        # emission cannot go negative: position + BUF_OFFSET, normal * 0.5 + 0.5
        geo = nt.nodes.new('ShaderNodeNewGeometry')
        vm = nt.nodes.new('ShaderNodeVectorMath')
        vm.operation = 'MULTIPLY_ADD'
        if kind == 'pos':
            vm.inputs[1].default_value = (1, 1, 1)
            vm.inputs[2].default_value = (BUF_OFFSET,) * 3
        else:
            vm.inputs[1].default_value = (0.5, 0.5, 0.5)
            vm.inputs[2].default_value = (0.5, 0.5, 0.5)
        nt.links.new(geo.outputs['Position' if kind == 'pos' else 'Normal'], vm.inputs[0])
        nt.links.new(vm.outputs[0], em.inputs['Color'])
    return m


def read_exr(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1]


def buffers(sc, objs):
    mats = {'pos': emission_mat('BUF_POS', 'pos'), 'nrm': emission_mat('BUF_NRM', 'nrm')}
    ids = {k: emission_mat('BUF_ID_%s' % k, 'id', v) for k, v in MAT_IDS.items()}
    s = sc.render.image_settings
    s.file_format, s.color_depth, s.color_mode = 'OPEN_EXR', '32', 'RGBA'
    got = {}
    for kind in ('pos', 'nrm', 'id'):
        for o in objs:
            o.data.materials.clear()
            o.data.materials.append(ids[o['lab_mat']] if kind == 'id' else mats[kind])
        path = os.path.join(OUT, '_buf_%s.exr' % kind)
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        got[kind] = read_exr(path)
        if kind == 'pos':
            got[kind][..., :3] -= BUF_OFFSET
        elif kind == 'nrm':
            got[kind][..., :3] = got[kind][..., :3] * 2 - 1
        os.remove(path)
    return got


# ---------------------------------------------------------------- grass shapes

def tuft_table(n, hmax, reach, seed):
    """as render_look.py: T[p, h, k, dx + reach] - tuft p at height h fills the
    pixel k rows above its root, dx across. 2-4 blades, 1-2 px at the foot,
    each leaning and curving its own way."""
    rng = np.random.default_rng(seed)
    T = np.zeros((n, hmax + 1, hmax + 1, 2 * reach + 1), bool)
    for p in range(n):
        blades = []
        for j in range(int(rng.integers(2, 5))):
            x0 = 0 if j == 0 else int(rng.integers(-1, 2))
            blades.append((1.0 if j == 0 else rng.uniform(0.35, 0.85), x0,
                           rng.uniform(-1, 1) * BLADE_LEAN + 0.8 * x0, rng.uniform(1.3, 2.4),
                           int(rng.integers(1, 3))))
        for h in range(1, hmax + 1):
            for share, x0, lean, curve, foot in blades:
                hb = max(1, round(share * h))
                for k in range(1, hb + 1):
                    x = x0 + round(lean * (hb / hmax) * (k / hb) ** curve)
                    w = max(1, round(foot * (1 - k / (hb + 1))))
                    for xi in range(x - (w - 1) // 2, x + w // 2 + 1):
                        if abs(xi) <= reach:
                            T[p, h, k, xi + reach] = True
    return T


def shifted(a, k, dx, fill):
    """r[y, x] = a[y + k, x - dx]"""
    r = np.full_like(a, fill)
    xs_d = slice(max(dx, 0), W + min(dx, 0))
    xs_s = slice(max(-dx, 0), W + min(-dx, 0))
    r[:H - k, xs_d] = a[k:, xs_s]
    return r


def grow_blades(out, root_level, ramp, hi, tip, depth):
    """stamp a tuft of height hi (0 = none) on every pixel, z-tested at the
    root's depth; the pixel k rows up a blade of height h takes the ramp colour
    root_level + tip * k // h - the root's light, brightening towards the tip"""
    hmax = int(hi.max())
    if hmax == 0:
        return
    rng = np.random.default_rng(SEED + 1)
    pat = rng.integers(0, TUFT_SHAPES, (H, W))
    T = tuft_table(TUFT_SHAPES, hmax, BLADE_REACH, SEED)
    zb = depth.copy()
    for k in range(1, hmax + 1):
        for dx in range(-BLADE_REACH, BLADE_REACH + 1):
            fills = T[:, :, k, dx + BLADE_REACH]
            if not fills.any():
                continue
            rc = shifted(fills[pat, hi], k, dx, False)
            if not rc.any():
                continue
            rz = shifted(depth, k, dx, np.inf)
            ok = rc & (rz < zb)
            lv = shifted(root_level, k, dx, 0) + (shifted(tip, k, dx, 0) * k) // np.maximum(shifted(hi, k, dx, 1), 1)
            out[ok] = ramp[np.clip(lv[ok], 0, len(ramp) - 1)]
            zb[ok] = rz[ok]


def clump_table(classes, hmax, reach, seed, sway=0, persp=0.0):
    """Grass as the video draws it: CLUMPS of real LEAVES. A clump is 4-7 lance
    shaped leaves - narrow at the foot, widest a third of the way up, drawn to a
    point - each leaning and bending its own way (the outer ones outwards), on a
    low mass at the bottom; the union is the clump's one-colour silhouette,
    rooted at its bottom centre. classes: [(n shapes, (half width lo, hi),
    (leaf width lo, hi))]; returns T[p, h, k, dx + reach]: clump p drawn h px
    tall fills the pixel k rows up, dx across. sway: px the tips are blown
    aside (the bend grows with the square of the height up the clump). persp:
    the video's fake perspective - the clump is narrowed (> 0) or widened (< 0)
    about its axis, not at all at the foot and fully at the top."""
    rng = np.random.default_rng(seed)
    n = sum(c[0] for c in classes)
    T = np.zeros((n, hmax + 1, hmax + 1, 2 * reach + 1), bool)
    gx, gk = np.meshgrid(np.arange(-reach, reach + 1) + 0.5 * 0, np.arange(hmax + 1), indexing='xy')
    p = 0
    for count, (wlo, whi), (llo, lhi) in classes:
        for _ in range(count):
            a0 = rng.uniform(wlo, whi)
            leaves = []
            for j in range(int(rng.integers(LEAF_N[0], LEAF_N[1] + 1))):
                u = rng.uniform(-1, 1)                        # where along the clump's foot
                lean = math.radians(u * LEAF_FAN + rng.uniform(-LEAF_JITTER, LEAF_JITTER))
                leaves.append((u, lean, rng.uniform(0.55, 1.0), rng.uniform(llo, lhi),
                               rng.uniform(-LEAF_BEND, LEAF_BEND), rng.uniform(0.25, 0.4)))
            for h in range(1, hmax + 1):
                a = a0 * (0.55 + 0.45 * h / hmax)
                m = np.zeros(gx.shape, bool)
                sc = (h / hmax) ** 0.5
                for u, lean, share, wmax, bend, wide_at in leaves:
                    L = share * h
                    bx = u * a * 0.7
                    up = gk / h
                    sx = gx - sway * up ** 2
                    rx, rk = sx * (1 + persp * up) - bx, gk - 0.5
                    along = rx * math.sin(lean) + rk * math.cos(lean)
                    t = along / max(L, 1e-3)
                    across = rx * math.cos(lean) - rk * math.sin(lean) - bend * L * t * t
                    # lance: rises to wmax at wide_at, then tapers to a point
                    prof = np.where(t < wide_at, 0.5 + 0.5 * t / wide_at, np.clip((1 - t) / (1 - wide_at), 0, 1) ** 0.8)
                    half = 0.5 * max(1.0, wmax * sc) * prof
                    m |= (t >= 0) & (t <= 1) & (np.abs(across) <= np.maximum(half, 0.5 * (t < 0.92)))
                # the low mass the leaves spring from
                m |= (gk >= 1) & (gk <= max(1, round(h * CLUMP_BODY))) & (np.abs(gx) <= a * 0.5)
                m[0] = False
                T[p, h] = m
            p += 1
    return T


def grow_clumps(out, root_level, ramp, hi, pat, si, qi, T, depth, reach, zb=None):
    """stamp clump pat (height hi, 0 = none), blown by sway table si and
    perspective table qi, on every pixel, one colour - its root's - z-tested at
    the root's depth, nearer clumps over farther ones. T[s, q, p, h, k, dx + reach]."""
    hmax = int(hi.max())
    zb = depth.copy() if zb is None else zb
    for k in range(1, hmax + 1):
        for dx in range(-reach, reach + 1):
            fills = T[:, :, :, :hmax + 1, k, dx + reach]
            if not fills.any():
                continue
            rc = shifted(fills[si, qi, pat, hi], k, dx, False)
            if not rc.any():
                continue
            rz = shifted(depth, k, dx, np.inf)
            ok = rc & (rz < zb)
            lv = shifted(root_level, k, dx, 0)
            out[ok] = ramp[np.clip(lv[ok], 0, len(ramp) - 1)]
            zb[ok] = rz[ok]


# ---------------------------------------------------------------- world-anchored clumps, wind

def hash01(ix, iy, salt):
    """a number in [0, 1) per integer cell and salt, the same from any camera"""
    with np.errstate(over='ignore'):
        h = (np.asarray(ix).astype(np.int64).astype(np.uint64) * np.uint64(0x9E3779B97F4A7C15)
             ^ np.asarray(iy).astype(np.int64).astype(np.uint64) * np.uint64(0xC2B2AE3D27D4EB4F)
             ^ np.uint64((salt * 0x165667B19E3779F9 + SEED) & 0xFFFFFFFFFFFFFFFF))
        h ^= h >> np.uint64(33)
        h *= np.uint64(0xFF51AFD7ED558CCD)
        h ^= h >> np.uint64(33)
        h *= np.uint64(0xC4CEB9FE1A85EC53)
        h ^= h >> np.uint64(33)
    return (h >> np.uint64(11)).astype(np.float64) / float(1 << 53)


def vnoise(x, y, salt):
    """value noise in [0, 1], smooth - what a noise texture sampled bilinearly gives the engine"""
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = hash01(ix, iy, salt), hash01(ix + 1, iy, salt)
    c, d = hash01(ix, iy + 1, salt), hash01(ix + 1, iy + 1, salt)
    return (a + (b - a) * ux) * (1 - uy) + (c + (d - c) * ux) * uy


def world_roots(P, gm, tall):
    """one candidate clump per ROOT_CELL world cell, at a hashed point in it; it
    roots on the visible grass pixel nearest that point, or nowhere if none is
    within ROOT_TOL (hidden behind a stone, off screen). Returns root pixels
    (y, x) and each one's cell (cx, cy), which seeds everything about it."""
    gy, gx = np.nonzero(gm)
    wx, wy = P[gy, gx, 0], P[gy, gx, 1]
    cx, cy = np.floor(wx / ROOT_CELL).astype(np.int64), np.floor(wy / ROOT_CELL).astype(np.int64)
    jx = (cx + hash01(cx, cy, 1)) * ROOT_CELL
    jy = (cy + hash01(cx, cy, 2)) * ROOT_CELL
    d = np.hypot(wx - jx, wy - jy)
    o = np.lexsort((d, cy, cx))
    first = np.ones(len(o), bool)
    first[1:] = (cx[o][1:] != cx[o][:-1]) | (cy[o][1:] != cy[o][:-1])
    pick = o[first]
    pick = pick[d[pick] < ROOT_TOL]
    ry, rx, rcx, rcy = gy[pick], gx[pick], cx[pick], cy[pick]
    # keep a share of the cells so the density is the old per-pixel chance's:
    # one screen pixel covers (ORTHO / W)^2 / sin(elevation) m^2 of flat ground
    px_area = (ORTHO / W) ** 2 / math.sin(math.radians(CAM_ELEV))
    is_t = tall[ry, rx]
    p = np.where(is_t, CLUMP['tall']['p'], CLUMP['short']['p']) * ROOT_CELL ** 2 / px_area
    keep = hash01(rcx, rcy, 3) < p
    return ry[keep], rx[keep], rcx[keep], rcy[keep]


def cam_axes_xy():
    """the camera's right and towards-camera directions on the ground, unit"""
    r = np.array(uv_to_xy(1, 0))
    t = np.array(uv_to_xy(0, 1))
    return r / np.linalg.norm(r), t / np.linalg.norm(t)


def wind_gust(wx, wy, ts):
    """Dylearn's wind at world points (m) and time ts (s): 0 still .. 1 full gust"""
    right, toward = cam_axes_xy()
    d = right * WIND_DIR_UV[0] + toward * WIND_DIR_UV[1]
    d /= np.linalg.norm(d)
    a = math.radians(WIND_DIV)
    rot = lambda v, s: np.array((v[0] * math.cos(s * a) - v[1] * math.sin(s * a),
                                 v[0] * math.sin(s * a) + v[1] * math.cos(s * a)))
    d1, d2 = rot(d, 1), rot(d, -1)
    s2, v2 = WIND_SCALE / (math.pi / 2), WIND_SPEED * (math.pi / 3.7)
    n1 = vnoise((wx - d1[0] * WIND_SPEED * ts) / WIND_SCALE, (wy - d1[1] * WIND_SPEED * ts) / WIND_SCALE, 11)
    n2 = vnoise((wx - d2[0] * v2 * ts) / s2, (wy - d2[1] * v2 * ts) / s2, 12)
    return np.clip(n1 * n2 * WIND_GAIN + WIND_BIAS, 0, 1), d


def stepped(ts, fps, phase01):
    """time held at fps, each clump's frames shifted by its own phase (share of a frame)"""
    return (np.floor(ts * fps + phase01) - phase01) / fps


def walker_at(ts):
    s = (ts / LOOP_S) % 1.0
    u = WALKER_FROM_UV[0] + (WALKER_TO_UV[0] - WALKER_FROM_UV[0]) * s
    v = WALKER_FROM_UV[1] + (WALKER_TO_UV[1] - WALKER_FROM_UV[1]) * s
    x, y = uv_to_xy(u, v)
    return np.array((x, y, ground_z(x, y)))


# ---------------------------------------------------------------- shading

def flicker_at(t):
    """firelight scale over the loop, t in 0..1: whole cycles only, so it loops"""
    tau = 2 * math.pi * t
    return 1 + 0.045 * math.sin(3 * tau) + 0.03 * math.sin(7 * tau + 1.3) + 0.02 * math.sin(13 * tau + 2.1)


def draw_walker(sc, cam, out, depth, level, ramps, wp):
    """a placeholder figure standing at wp, z-tested; returns the depth buffer with
    it in, so the clumps in front of it cover it and the ones behind do not"""
    fx, fy = world_to_px(sc, cam, Vector(wp))
    cw = cam.matrix_world
    fwd = np.array(-(cw.to_3x3() @ Vector((0, 0, 1))))
    dz = float((wp - np.array(cw.translation)) @ fwd)
    zb = depth.copy()
    ramp = ramps['wood']
    lv = level[np.clip(fy, 0, H - 1), np.clip(fx, 0, W - 1)] if 0 <= fx < W and 0 <= fy < H else 3
    # ~1.3 m tall at this scale: a body 8 px wide, a head 6 px on top
    for ky in range(36):
        half = 4 if ky < 28 else (3 if ky < 35 else 2)
        for kx in range(-half, half + 1):
            py, px_ = fy - 1 - ky, fx + kx
            if 0 <= py < H and 0 <= px_ < W and depth[py, px_] > dz - 0.3:
                out[py, px_] = ramp[np.clip(lv + (1 if kx < 0 else 0), 0, len(ramp) - 1)]
                zb[py, px_] = dz
    return zb


def shade(sc, cam, bufs, t=0.0, cache=None, frame=0, walker=False):
    cache = {} if cache is None else cache
    flicker = flicker_at(t)
    P, N, I = bufs['pos'][..., :3], bufs['nrm'][..., :3], bufs['id']
    solid = I[..., 3] > 0.5
    mid = np.where(solid, np.round(I[..., 0]).astype(int), 0)
    cw = cam.matrix_world
    fwd = -(cw.to_3x3() @ Vector((0, 0, 1)))
    depth = np.where(solid, (P - np.array(cw.translation)) @ np.array(fwd), np.inf)

    # fire: inverse-square-ish falloff to FIRE_R, n.l with a little wrap, hard ray-cast shadow
    fire = np.array(FIRE) + np.array((0, 0, ground_z(0, 0)))
    L = fire - P
    d = np.linalg.norm(L, axis=-1) + 1e-6
    Ln = L / d[..., None]
    ndl = np.clip(((N * Ln).sum(-1) + 0.25) / 1.25, 0, 1)
    # grass is a mat of blades, not a surface: it takes the light from any side
    ndl = np.where(np.round(I[..., 0]) == MAT_IDS['grass'], GRASS_WRAP + (1 - GRASS_WRAP) * ndl, ndl)
    fall = np.clip(1 - d / (FIRE_R * flicker), 0, 1) ** FIRE_FALL
    names = ['grass', 'stone', 'wood']
    kind = np.full((H, W), -1)
    for nm in names:
        kind[mid == MAT_IDS[nm]] = names.index(nm)
    top = (kind == 1) & (N[..., 2] > 0.8)
    # the walls of stones and logs: light by the distance ACROSS the ground, so a
    # face turned to the fire is one flat colour top to bottom, as in the video
    wall = (kind > 0) & ~top
    dh = np.linalg.norm(L[..., :2], axis=-1) + 1e-6
    nh = np.clip((N[..., :2] * (L[..., :2] / dh[..., None])).sum(-1), 0, 1)
    fall_h = np.clip(1 - dh / (FIRE_R * flicker), 0, 1) ** FIRE_FALL
    fire_l = FIRE_GAIN * np.where(wall, nh * fall_h, ndl * fall)
    if FIRE_SHADOW:
        lit = np.ones((H, W), bool)
        logs = [o for o in sc.objects if o.name.startswith('LOG_')]
        for o in logs:
            o.hide_viewport = True
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ys, xs = np.nonzero(solid & (fire_l > FIRE_BANDS[0] * 0.8))
        fv = Vector(fire)
        for y, x in zip(ys, xs):
            p = Vector(P[y, x])
            dirv = fv - p
            dist = dirv.length
            dirv /= dist
            p = p + Vector(N[y, x]) * 0.08 + dirv * 0.25      # clear of the smooth-shaded ground's own facets
            lit[y, x] = not sc.ray_cast(dg, p, dirv, distance=max(0.0, dist - 0.5))[0]
        for o in logs:
            o.hide_viewport = False
        fire_l = fire_l * lit

    def bands(light):
        fb = np.zeros((H, W), int)
        for t in FIRE_BANDS:
            fb += light > t
        return fb

    moon = np.clip((N * np.array(MOON_DIR)).sum(-1), 0, 1)
    mb = np.zeros((H, W), int)
    for cut in MOON_BANDS:               # not `t`: that is the loop time, still needed below
        mb += moon > cut
    fb = bands(fire_l)
    level = np.where(fb > 0, 2 + fb, mb)

    # tall grass: world-space patches, a step lighter, thickening towards the fire
    gm = kind == 0
    tall = np.zeros((H, W), bool)
    gy, gx = np.nonzero(gm)
    if 'tn' not in cache:
        cache['tn'] = np.array([noise.noise(Vector((P[y, x, 0] / TALL_SCALE, P[y, x, 1] / TALL_SCALE, 4.2))) for y, x in zip(gy, gx)])
    tn = cache['tn']
    near = np.clip(1 - np.linalg.norm(P[gy, gx, :2] - fire[:2], axis=-1) / TALL_FIRE_R, 0, 1)
    tall[gy, gx] = (tn * 0.5 + 0.5) > TALL_CUT - TALL_FIRE_BOOST * near
    level = level + (gm & tall)
    # the light each BLADE takes: its root's, nudged a little per blade (blades face
    # every way), so a light edge is a band of mixed blades, not a line
    jit = np.random.default_rng(SEED + 5).normal(0, BLADE_LIGHT_JITTER, (H, W))
    fbj = bands(fire_l + jit * (fire_l > 0))
    level_blade = np.where(fbj > 0, 2 + fbj, mb) + (gm & tall)

    # vignette: banded, whole steps
    yy, xx = np.mgrid[0:H, 0:W]
    rr = np.hypot((xx - W / 2) / (W / 2), (yy - H / 2) / (H / 2)) / math.sqrt(2)
    vig = ((rr > VIGNETTE[0]).astype(int) + (rr > VIGNETTE[1]) + (rr > VIGNETTE[2])) * VIGNETTE_ON
    level = level - vig
    level_blade = level_blade - vig

    ramps = {k: np.array([hex_rgb(c) for c in v]) for k, v in RAMPS.items()}
    out = np.zeros((H, W, 3), int) + np.array(hex_rgb('#05030f'))
    for nm in names:
        m = (kind == names.index(nm)) & ~top
        r = ramps[nm]
        out[m] = r[np.clip(level[m], 0, len(r) - 1)]
    r = ramps['top']
    out[top] = r[np.clip(level[top], 0, len(r) - 1)]

    # silhouettes: a step darker where a neighbour is clearly farther
    far = depth
    edge = np.zeros((H, W), bool)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        edge |= solid & (np.roll(np.roll(far, dy, 0), dx, 1) - far > 0.6) & (kind != 0)
    for nm, k_ in (('stone', 1), ('wood', 2)):
        m = edge & (kind == k_)
        out[m] = ramps[nm][np.clip(level[m] - 1, 0, len(ramps[nm]) - 1)]

    # grass clumps: sparse roots, tall clumps in the long grass, small ones elsewhere
    nt_, ns_ = CLUMP['tall']['shapes'], CLUMP['short']['shapes']
    if 'T' not in cache:
        classes = [(ns_, CLUMP['short']['halfw'], CLUMP['short']['leafw']),
                   (nt_, CLUMP['tall']['halfw'], CLUMP['tall']['leafw'])]
        cache['T'] = np.stack([np.stack([clump_table(classes, CLUMP['tall']['h'][1], CLUMP_REACH, SEED, sw, q)
                                         for q in PERSP_Q]) for sw in SWAY_PX])
    if 'hi' not in cache:
        hi = np.zeros((H, W), int)
        pat = np.zeros((H, W), int)
        cstep = np.zeros((H, W), int)
        is_t = np.zeros((H, W), bool)
        if ROOTS == 'world':
            # everything about a clump comes from its world cell's hash, so it is
            # the same clump - shape, height, colour step - from any camera
            ry, rx, cx, cy = world_roots(P, gm, tall)
            t_ = tall[ry, rx]
            ht = CLUMP['tall']['h'][0] + (hash01(cx, cy, 4) * (CLUMP['tall']['h'][1] - CLUMP['tall']['h'][0] + 1)).astype(int)
            hs = CLUMP['short']['h'][0] + (hash01(cx, cy, 4) * (CLUMP['short']['h'][1] - CLUMP['short']['h'][0] + 1)).astype(int)
            hi[ry, rx] = np.where(t_, ht, hs)
            pat[ry, rx] = np.where(t_, ns_ + (hash01(cx, cy, 5) * nt_).astype(int), (hash01(cx, cy, 5) * ns_).astype(int))
            c = np.cumsum(CLUMP_STEP_P)
            u = hash01(cx, cy, 6)
            cstep[ry, rx] = (u >= c[0]).astype(int) + (u >= c[1]) - 1
            is_t[ry, rx] = t_
            cache['roots'] = (ry, rx, cx, cy, t_)
        else:
            rng = np.random.default_rng(SEED)
            roll = rng.random((H, W))
            h_s = rng.integers(CLUMP['short']['h'][0], CLUMP['short']['h'][1] + 1, (H, W))
            h_t = rng.integers(CLUMP['tall']['h'][0], CLUMP['tall']['h'][1] + 1, (H, W))
            is_t = gm & tall & (roll < CLUMP['tall']['p'])
            is_s = gm & ~tall & (roll < CLUMP['short']['p'])
            hi = np.where(is_t, h_t, np.where(is_s, h_s, 0))
            pat = np.where(is_t, ns_ + rng.integers(0, nt_, (H, W)), rng.integers(0, ns_, (H, W)))
            # each clump its own step up or down the ramp, for good: neighbours part
            # in colour, so the leaves show inside a lit patch too, not only at its edge
            cstep = rng.choice([-1, 0, 1], size=(H, W), p=CLUMP_STEP_P)
            ry, rx = np.nonzero(hi)
            cache['roots'] = (ry, rx, rx.astype(np.int64), ry.astype(np.int64), is_t[ry, rx])
        cache.update(hi=hi, pat=pat, cstep=cstep, is_t=is_t)
    hi, pat = cache['hi'], cache['pat']
    reach_s = max(SWAY_PX)
    sway = np.zeros((H, W))
    persp = np.zeros((H, W))
    ts = t * LOOP_S
    ry, rx, cx, cy, t_ = cache['roots']
    amp = np.where(t_, 1.0, 0.5) * WIND
    if WIND_MODE == 'waves':
        # waves running across the lawn, whole cycles per loop; tall grass bends
        # up to the widest sway, short grass half as far
        tau = 2 * math.pi * t
        wave = (0.7 * np.sin(2 * tau - (P[..., 0] * 0.55 + P[..., 1] * 0.35))
                + 0.3 * np.sin(3 * tau - (P[..., 0] * 1.3 - P[..., 1] * 0.8)))
        sway[ry, rx] = wave[ry, rx] * amp * 2
    else:
        # gusts sampled at the root, time held at WIND_FPS with each clump's frames
        # phase-shifted by its own hash so the lawn never steps all at once
        wx, wy = P[ry, rx, 0], P[ry, rx, 1]
        tq = stepped(ts, WIND_FPS, hash01(cx, cy, 7))
        gust, d = wind_gust(wx, wy, tq)
        right, toward = cam_axes_xy()
        # the gust bends a clump downwind: across the screen that is sway, along
        # the view it is the fake perspective (towards the camera: tips widen)
        sway[ry, rx] = amp * (gust * WIND_PX * float(d @ right)
                              + WIGGLE_PX * np.sin(2 * math.pi * (WIGGLE_HZ * tq + hash01(cx, cy, 8))))
        persp[ry, rx] = -amp * gust * WIND_PERSP * float(d @ toward)
    zb = None
    if walker:
        wp = walker_at(math.floor(ts * WALKER_FPS) / WALKER_FPS)
        v = P[ry, rx, :2] - wp[:2]
        dist = np.linalg.norm(v, axis=-1) + 1e-6
        m = np.clip(1 - dist / WALKER_R, 0, 1) ** WALKER_EXP
        right, toward = cam_axes_xy()
        sway[ry, rx] += m * WALKER_PX * (v @ right) / dist
        persp[ry, rx] -= m * PERSP_Q[-1] * (v @ toward) / dist
        # pushed towards or away from the camera a clump leans along the view,
        # which in pixels is mostly a shorter clump: bent over, not only aside
        hi = hi.copy()
        hi[ry, rx] = np.maximum(1, np.round(hi[ry, rx] * (1 - WALKER_FLAT * m))).astype(int) * (hi[ry, rx] > 0)
        zb = draw_walker(sc, cam, out, depth, level, ramps, wp)
    si = np.clip(np.round(sway), -reach_s, reach_s).astype(int) + reach_s   # SWAY_PX runs -reach_s .. +reach_s
    qi = np.clip(np.round(persp / PERSP_Q[-1]), -1, 1).astype(int) + 1
    if ROOTS == 'world':
        # the per-blade light spread, per clump from its hash instead of per screen pixel
        jit = np.zeros((H, W))
        u1, u2 = hash01(cx, cy, 9), hash01(cx, cy, 10)
        jit[ry, rx] = np.sqrt(-2 * np.log(np.maximum(u1, 1e-12))) * np.cos(2 * math.pi * u2) * BLADE_LIGHT_JITTER
        fbj = bands(fire_l + jit * (fire_l > 0))
        level_blade = np.where(fbj > 0, 2 + fbj, mb) + (gm & tall) - vig
    root = level_blade + np.where(fb > 0, cache['cstep'], np.minimum(cache['cstep'], 0))
    grow_clumps(out, root, ramps['grass'], hi, pat, si, qi, cache['T'], depth, CLUMP_REACH, zb)

    # pale tufts: sparse, world-anchored, three blades in a V
    tuft_spr = ['....1..',
                '1...1..',
                '1..1..1',
                '.1.1.1.',
                '.1.1.1.',
                '..111..',
                '...1...']
    cell = TUFT_SPRITE_EVERY
    cells = {}
    for y, x in zip(gy, gx):
        key = (int(math.floor(P[y, x, 0] / cell)), int(math.floor(P[y, x, 1] / cell)))
        cells.setdefault(key, (y, x))
    trng = np.random.default_rng(SEED + 7)
    for key, (y, x) in sorted(cells.items()):
        if trng.random() > 0.35:
            continue
        lv = level[y, x] + 2
        col = ramps['tuft'][np.clip(lv, 0, len(ramps['tuft']) - 1)]
        hgt = len(tuft_spr)
        for ry, row in enumerate(tuft_spr):
            for rx, ch in enumerate(row):
                if ch == '1':
                    py, px_ = y - hgt + ry, x - 3 + rx
                    if 0 <= py < H and 0 <= px_ < W and depth[py, px_] >= depth[y, x] - 0.2:
                        out[py, px_] = col

    # flame sprite, foot on the fire
    fire_px = world_to_px(sc, cam, Vector(fire) - Vector((0, 0, 0.25)))
    strip = bpy.data.images.load(os.path.join(ROOT, 'assets/flame_strip.png'))
    sw, sh = strip.size
    spx = np.array(strip.pixels[:]).reshape(sh, sw, 4)[::-1]
    bpy.data.images.remove(strip)
    fw = sw // 6
    fi = (frame // 2) % 6                            # 12 fps flame in a 24 fps loop
    cellimg = spx[:, fi * fw:(fi + 1) * fw]
    fx, fy = fire_px
    for ry in range(sh):
        for rx in range(fw):
            if cellimg[ry, rx, 3] > 0.5:
                py, px_ = fy - sh + ry, fx - fw // 2 + rx
                if 0 <= py < H and 0 <= px_ < W:
                    out[py, px_] = np.round(cellimg[ry, rx, :3] * 255)
    return out, { 'tall_px': int(tall.sum()), 'clumps': int((hi > 0).sum())}


def world_to_px(sc, cam, p):
    from bpy_extras.object_utils import world_to_camera_view
    c = world_to_camera_view(sc, cam, p)
    return int(round(c.x * W)), int(round((1 - c.y) * H))


def save_png(arr, path):
    img = bpy.data.images.new('tmp_out', arr.shape[1], arr.shape[0], alpha=False)
    px = np.concatenate([arr[::-1] / 255.0, np.ones(arr.shape[:2] + (1,))], axis=2).astype(np.float32).ravel()
    img.pixels.foreach_set(px)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)


def pan_check(sc, cam, objs, dx=7, dy=4):
    """do the clumps hold still when the camera moves? Render at the camera and at
    the camera panned (dx, dy) whole pixels, line the two frames up and count the
    pixels that differ - with the screen roll and with the world roots."""
    global ROOTS, VIGNETTE_ON
    VIGNETTE_ON = 0
    px = ORTHO / W
    bpy.context.view_layer.update()        # matrix_world is stale right after build()
    m = cam.matrix_world.to_3x3()
    home = cam.location.copy()
    bufs_a = buffers(sc, objs)
    cam.location = home + (m @ Vector((1, 0, 0))) * dx * px + (m @ Vector((0, 1, 0))) * dy * px
    bpy.context.view_layer.update()
    bufs_b = buffers(sc, objs)
    rows, res = [], {}
    for mode in ('screen', 'world'):
        ROOTS = mode
        cam.location = home
        bpy.context.view_layer.update()
        a, info = shade(sc, cam, bufs_a)
        print('CLUMPS %s: %d' % (mode, info['clumps']), flush=True)
        cam.location = home + (m @ Vector((1, 0, 0))) * dx * px + (m @ Vector((0, 1, 0))) * dy * px
        bpy.context.view_layer.update()
        b, _ = shade(sc, cam, bufs_b)
        # a world point at (x, y) in a should sit at (x - dx, y + dy) in b; search a
        # few pixels round that on the stones alone (no grass on them) to be sure
        def lined(sx, sy):
            ys_a, ys_b = slice(max(-sy, 0), H - max(sy, 0)), slice(max(sy, 0), H - max(-sy, 0))
            xs_a, xs_b = slice(max(sx, 0), W - max(-sx, 0)), slice(max(-sx, 0), W - max(sx, 0))
            return ys_a, xs_a, ys_b, xs_b
        ia, ib = bufs_a['id'][..., 0], bufs_b['id'][..., 0]
        best = min(((np.abs(ia[ya, xa] - ib[yb, xb]) > 0.5).mean(), sx, sy)
                   for sx in range(dx - 3, dx + 4) for sy in range(dy - 3, dy + 4)
                   for ya, xa, yb, xb in [lined(sx, sy)])
        print('PAN offset expected (%d, %d), found (%d, %d), id mismatch %.4f%%'
              % (dx, dy, best[1], best[2], 100 * best[0]), flush=True)
        ya, xa, yb, xb = lined(best[1], best[2])
        oa, ob = a[ya, xa], b[yb, xb]
        diff = (oa != ob).any(-1)
        res[mode] = round(100 * diff.mean(), 2)
        mark = oa.copy()
        mark[diff] = (255, 40, 200)
        rows.append(np.concatenate([oa, np.full((oa.shape[0], 6, 3), 30), mark], axis=1))
        print('PAN %s: %.2f%% of the overlap differs' % (mode, res[mode]), flush=True)
    cam.location = home
    bpy.context.view_layer.update()
    sheet = np.concatenate([rows[0], np.full((6, rows[0].shape[1], 3), 30), rows[1]], axis=0)
    save_png(np.repeat(np.repeat(sheet, 2, 0), 2, 1), os.path.join(REVIEW, 'grass_lab_pancheck.png'))
    VIGNETTE_ON = 1
    return res


def main():
    global ROOTS, WIND_MODE
    ROOTS = arg('--roots', ROOTS)
    WIND_MODE = arg('--wind', WIND_MODE)
    walker = arg('--walker', '0') == '1'
    os.makedirs(OUT, exist_ok=True)
    sc, cam, objs = build()
    if arg('--pancheck'):
        print('PANCHECK', json.dumps(pan_check(sc, cam, objs)))
        return
    bufs = buffers(sc, objs)
    out, info = shade(sc, cam, bufs)          # the stills stay free of the walker
    tag = '' if TERRAIN == 'lab' else '_' + TERRAIN
    base = os.path.join(REVIEW, 'grass_lab' + tag)
    if TERRAIN == 'hills':                    # the clip's daylight bands, to judge the relief alone
        nl = bufs['nrm'][..., :3] @ np.array(Vector((0.35, -0.55, 0.76)).normalized())
        grass = bufs['id'][..., 0].round() == MAT_IDS['grass']
        cuts = np.quantile(nl[grass], (DAY_SHARES[0], DAY_SHARES[0] + DAY_SHARES[1]))   # same shares as the clip
        band = np.digitize(nl, cuts)
        day = np.array([hex_rgb(c) for c in DAY_GREENS])[band]
        day[bufs['id'][..., 0].round() == MAT_IDS['stone']] = (150, 150, 155)
        day[bufs['id'][..., 3] < 0.5] = (40, 40, 44)
        save_png(np.repeat(np.repeat(day, 2, 0), 2, 1), base + '_relief.png')
    save_png(out, base + '_640x360.png')
    big = np.repeat(np.repeat(out, SCALE, 0), SCALE, 1)
    save_png(big, base + '_x3.png')
    if os.path.exists(VIDEO_FRAME):
        v = bpy.data.images.load(VIDEO_FRAME)
        vp = np.round(np.array(v.pixels[:]).reshape(H, W, 4)[::-1, :, :3] * 255).astype(int)
        bpy.data.images.remove(v)
        gap = np.full((H, 8, 3), 30)
        pair = np.concatenate([vp, gap, out], axis=1)
        save_png(np.repeat(np.repeat(pair, 2, 0), 2, 1), base + '_vs_video.png')
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'grass_lab%s.blend' % tag))
    print('LAB', json.dumps(info))
    nf = int(arg('--frames', 0))
    if nf:
        anim = os.path.join(OUT, 'anim' + tag)
        os.makedirs(anim, exist_ok=True)
        for f in os.listdir(anim):
            os.remove(os.path.join(anim, f))
        cache = {}
        for i in range(nf):
            fr, _ = shade(sc, cam, bufs, t=i / nf, cache=cache, frame=i, walker=walker)
            save_png(np.repeat(np.repeat(fr, SCALE, 0), SCALE, 1), os.path.join(anim, 'f_%03d.png' % i))
            print('FRAME %d/%d' % (i + 1, nf), flush=True)


main()
