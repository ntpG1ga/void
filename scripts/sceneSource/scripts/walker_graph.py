"""The walker's motion graph on hibernal's hills (user, 2026-10-01): 10 stations round the fire and
10 walks leaving each, so the game can chain any walk that ends at a station with any walk that
leaves it, at random, and never play the same long loop twice.

  "$B" -b --factory-startup -P "$(wslpath -w scripts/walker_graph.py)"
      [GRAPH_PILLARS=<pillars.json>]  the pillar layout (void-touch/out/grassExport/pillars.json)
      [GRAPH_SEED=7] [GRAPH_STATIONS=10] [GRAPH_OUT=10]

Every walk starts standing at its station in that station's pose (the sim started there, facing
the station's yaw) and ends standing at its target in the target's pose (turned to the target's
yaw, feet re-planted on their home spots, the sim settled), so walk -> walk is seamless; the clip
export (walker_clips.py GRAPH=1) eases the last frames onto the shared pose. Each station has a
walk to every other (9) and one more, a second route to its nearest station round the far side of
the first (a detour). Routes are A* on a 0.25 m grid of spots the walker can stand on (clear of the
pillars and the fire by its footprint, on ground under MAX_SLOPE, inside the portrait frame), cut
down to straight legs the walker can walk.

Writes out/walker/walker_graph.blend (every walk back to back on one timeline, 24 fps) and
out/walker/walker_graph.json (stations, and per walk: from, to, first / last frame, the route).
"""
import json, math, os, random, shutil, sys
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
os.environ.setdefault("LAB_TERRAIN", "hills")
import walker_dynamics as wd
import walker_sim
from walker_sim import LEGS, WalkerSim, heading

LAB = os.path.join(HERE, "grass_lab.py")
SRC = os.path.join(ROOT, os.environ.get("RIG_SRC", "out/walker/walker_v2_legs.blend"))
V1_LEGS = os.path.basename(SRC) == "walker_dynamics.blend"
OUT = os.path.join(ROOT, "out", "walker")
FPS = 24
SECONDS = float(os.environ.get("ROAM_SECONDS", "60"))
SEED = int(os.environ.get("SEED", "4"))
RENDER = os.environ.get("RENDER", "1") == "1"
LOOP = os.environ.get("ROAM_LOOP", "0") == "1"
ROAM_OUT = os.environ.get("ROAM_OUT", "walker_roam")
HOME_WANTED = (3.6, -3.0)   # m, lab axes: in the firelit ring, in front of the fire as the fire camera sees it
HOME_SLOPE = 6.0            # deg: HOME is the clear spot nearest HOME_WANTED on ground flatter than this
RETURN_S = 25.0             # a loop turns for home this long before ROAM_SECONDS
SETTLE_TIDY = 0.02          # model units: standing at HOME again, a foot this far off its spot re-plants
WALKER_H, MODEL_H = 2.0, 3.48
S = WALKER_H / MODEL_H
ROAM_R = 11.0            # m round the fire (user: 10 m keeps it in the fire camera at up to 1.25x zoom)
WALK_SPEED = 0.32 if V1_LEGS else 0.6   # m/s: v1 legs cap a step at ~0.2 m, so they had to walk slowly
BODY_CLEAR = 1.35        # m from the walker's centre to an obstacle's edge; widened below to the rig's own
                         # reach (the v2 knees stick out past the feet)
FIRE_R = 1.4             # m: the fire and logs
MAX_SLOPE = 26.0         # deg under a waypoint / along the way
# slow-walk look, model units (walker_dynamics.PARAMS for the rest)
ROAM_PARAMS_V1 = {
    "body_f": 1.0, "body_zeta": 0.6, "body_r": -1.2,
    "turn_f": 1.2, "turn_zeta": 1.0, "head_f": 0.8, "head_zeta": 0.7,
    "max_speed": WALK_SPEED / S, "max_turn_deg_s": 70.0,
    # picked 2026-09-25 over longer strides (out/walker/roam_try/): the legs work only between 1.27
    # and 2.23 hip-sole (2.11 at rest), so on the x2 hills a longer step or a deeper crouch left no
    # root height that suits all four feet in ~1/4 of frames and soles missed by ~10 cm
    "step_threshold": 0.3, "step_lead_s": 0.22, "step_max_lead": 0.55, "crouch_m": 0.12,
    "step_time": 0.3, "step_height": 0.26,   # lower lift: the short shin flips near-flat on a high one
    "gait_pairs": 0.0,                       # one foot at a time: at a walk it reads calmer than a trot
    "step_tidy": 0.15,                       # when stopped, only re-plant a foot that is clearly off
}
# v2 legs (walker_legs_v2.py: reach 3.52, 59% extended at rest): long steps, no crouch needed, and the
# video's bounce + anticipation; picked from out/walker/roam_try_v2/ (all clean on the x2 hills)
ROAM_PARAMS_V2 = dict(ROAM_PARAMS_V1, **{
    "body_zeta": 0.5, "body_r": -2.0,
    "step_threshold": 0.8, "step_lead_s": 0.5, "step_max_lead": 0.8, "step_time": 0.38,
    "crouch_m": 0.0,
})
ROAM_PARAMS = ROAM_PARAMS_V1 if V1_LEGS else ROAM_PARAMS_V2

# ---------------------------------------------------------------- scene
lab = {"__file__": LAB, "__name__": "grass_lab"}
exec(compile(open(LAB).read().rstrip()[:-len("main()")], LAB, "exec"), lab)
GRAPH_PILLARS = os.environ.get("GRAPH_PILLARS", os.path.join(os.path.dirname(ROOT), "void-touch", "out", "grassExport", "pillars.json"))
if os.path.exists(GRAPH_PILLARS):
    lab["PILLARS_UV"] = [tuple(p) for p in json.load(open(GRAPH_PILLARS))["pillars_uv"]]
    lab["OUTER_PILLARS"] = (0, 0.0, 0.0, 0.0)
    print("PILLARS from", GRAPH_PILLARS, len(lab["PILLARS_UV"]))
sc, cam, objs = lab["build"]()
bpy.context.view_layer.update()
gz = lab["ground_z"]

with bpy.data.libraries.load(SRC) as (src, dst):
    dst.collections = [c for c in src.collections if c in ("GRP-ReferenceWalker", "GRP-Chassis", "GRP-Head", "GRP-Legs", "GRP-Controls")]
for c in dst.collections:
    sc.collection.children.link(c)
for n in ("CTRL-Target", "GEO-TargetMarker"):
    ob = bpy.data.objects.get(n)
    if ob:
        bpy.data.objects.remove(ob)
root, body, head = (bpy.data.objects[n] for n in ("ReferenceWalker", "RIG-Body", "RIG-Head"))
feet = [bpy.data.objects[f"CTRL-Foot-{L}"] for L in LEGS]
homes = {L: tuple(f["home"]) for L, f in zip(LEGS, feet)}
rest_z = body["rest_z"]
# the legs' measurements from the rig itself (root space, rest pose), so any leg design simulates right
arm = bpy.data.objects["RIG-Legs"]
for o in (root, body, head):
    o.animation_data_clear()
root.location, root.rotation_euler = (0, 0, 0), (0, 0, 0)
body.rotation_mode, body.rotation_quaternion, body.location.z = "QUATERNION", (1, 0, 0, 0), rest_z
bpy.context.view_layer.update()
to_root = root.matrix_world.inverted() @ arm.matrix_world
bones = arm.data.bones
walker_sim.configure_legs({L: to_root @ bones[f"Thigh-{L}"].head_local for L in LEGS},
                          bones["Thigh-FrontL"].length, bones["Shin-FrontL"].length)
REACH = walker_sim.REACH
leg_r = max((root.matrix_world.inverted() @ o.matrix_world @ v.co).xy.length
            for o in bpy.data.collections["GRP-Legs"].objects if o.type == "MESH" for v in o.data.vertices)
BODY_CLEAR = max(BODY_CLEAR, leg_r * S + 0.2)
print(f"footprint radius {leg_r * S:.2f} m -> obstacle clearance {BODY_CLEAR:.2f} m")
print(f"LEGS from {os.path.basename(SRC)}: thigh {bones['Thigh-FrontL'].length:.2f} shin {bones['Shin-FrontL'].length:.2f} "
      f"sole range {tuple(round(v, 2) for v in walker_sim.SOLE_RANGE)}")
scale = bpy.data.objects.new("WALKER-SCALE", None)
scale.scale = (S, S, S)
sc.collection.objects.link(scale)
for ob in [root] + feet:
    ob.animation_data_clear()
    ob.parent, ob.matrix_parent_inverse = scale, Matrix.Identity(4)
for ob in (body, head):
    ob.animation_data_clear()
root.rotation_mode, head.rotation_mode, body.rotation_mode = "XYZ", "XYZ", "QUATERNION"

# obstacles, world metres: (centre, radius of the footprint)
obstacles = [(Vector((0, 0)), FIRE_R)]
for o in objs:
    if o.name.startswith("PILLAR"):
        obstacles.append((o.location.xy.copy(), math.hypot(o.scale.x, o.scale.y) / 2))


# ROAM_HALF_WIDTH (m): keep the walker's centre this close to the fire across the fire camera's frame,
# for a game camera that stands still on a frame narrower than the roam (a portrait phone)
HALF_WIDTH = float(os.environ.get("ROAM_HALF_WIDTH", "1e9"))
CAM_RIGHT = Vector(lab["cam_axes_xy"]()[0]).normalized()


def slope_deg(p, e=0.5):
    dx = (gz(p.x + e, p.y) - gz(p.x - e, p.y)) / (2 * e)
    dy = (gz(p.x, p.y + e) - gz(p.x, p.y - e)) / (2 * e)
    return math.degrees(math.atan(math.hypot(dx, dy)))


def clear(p):
    return (p.length <= ROAM_R and slope_deg(p) < MAX_SLOPE and abs(p.dot(CAM_RIGHT)) <= HALF_WIDTH
            and all((p - c).length > r + BODY_CLEAR for c, r in obstacles))


def path_clear(a, b):
    n = max(2, int((b - a).length / 0.4))
    return all(clear(a.lerp(b, i / n)) for i in range(n + 1))


# ---------------------------------------------------------------- graph
GRAPH_SEED = int(os.environ.get("GRAPH_SEED", "7"))
STATIONS = int(os.environ.get("GRAPH_STATIONS", "10"))
OUT_PER_STATION = int(os.environ.get("GRAPH_OUT", "10"))
STATION_U, STATION_V = 5.5, 8.5     # m right / towards the camera of the fire the stations keep within
STATION_SLOPE = 8.0                 # deg: a station is flat enough to stand on still
STATION_LOOK = 60.0                 # deg: a station faces the fire give or take this
GRID = 0.25                         # m: route grid
DETOUR_PENALTY = 3.0                # A* cost per cell near the first route, for the second route
LEG_ARRIVE = 0.6                    # m: close enough to a route corner to head for the next
WALK_CAP = 90.0                     # s: a walk that has not settled by then is reported and kept

rnd = random.Random(GRAPH_SEED)
cr, ct = (Vector(v).normalized() for v in lab["cam_axes_xy"]())


def uv_of(q):
    return q.dot(cr), q.dot(ct)


def standable(q):
    u, v = uv_of(q)
    return abs(u) <= STATION_U and abs(v) <= STATION_V and clear(q) and slope_deg(q) < STATION_SLOPE


# stations: farthest-point sampling over the standable spots, starting nearest the old HOME
cands = [Vector((x * 0.5, y * 0.5)) for x in range(-30, 31) for y in range(-30, 31)]
cands = [q for q in cands if standable(q)]
assert len(cands) >= STATIONS, len(cands)
stations = [min(cands, key=lambda q: (q - Vector((3.6, -3.0))).length)]
while len(stations) < STATIONS:
    stations.append(max(cands, key=lambda q: min((q - s).length for s in stations)))
station_yaw = []
for s in stations:
    to_fire = -s
    station_yaw.append(heading(to_fire.x, to_fire.y) + math.radians(rnd.uniform(-STATION_LOOK, STATION_LOOK)))
print("STATIONS", [(round(s.x, 2), round(s.y, 2)) for s in stations])

# route grid over the stations' box (plus a margin)
xs = [s.x for s in stations]; ys = [s.y for s in stations]
gx0, gy0 = min(xs) - 4.0, min(ys) - 4.0
gw, gh = int((max(xs) + 4.0 - gx0) / GRID) + 1, int((max(ys) + 4.0 - gy0) / GRID) + 1
free = [[clear(Vector((gx0 + i * GRID, gy0 + j * GRID))) for i in range(gw)] for j in range(gh)]


def cell_of(q):
    return (min(gw - 1, max(0, int(round((q.x - gx0) / GRID)))), min(gh - 1, max(0, int(round((q.y - gy0) / GRID)))))


def point_of(c):
    return Vector((gx0 + c[0] * GRID, gy0 + c[1] * GRID))


def astar(a, b, avoid=None):
    import heapq
    s, g = cell_of(a), cell_of(b)
    openq = [(0.0, s)]
    cost, came = {s: 0.0}, {}
    while openq:
        _, c = heapq.heappop(openq)
        if c == g:
            break
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                n = (c[0] + dx, c[1] + dy)
                if not (0 <= n[0] < gw and 0 <= n[1] < gh) or not free[n[1]][n[0]]:
                    continue
                step = math.hypot(dx, dy)
                if avoid is not None and avoid.get(n):
                    step += DETOUR_PENALTY
                nc = cost[c] + step
                if nc < cost.get(n, 1e18):
                    cost[n], came[n] = nc, c
                    heapq.heappush(openq, (nc + math.hypot(n[0] - g[0], n[1] - g[1]), n))
    if g not in came and g != s:
        return None
    path, c = [g], g
    while c != s:
        c = came[c]
        path.append(c)
    return [point_of(c) for c in reversed(path)]


def simplify(points, a, b):
    """route corners: from each corner, the farthest later point still in a straight clear line"""
    pts = [a] + points[1:-1] + [b]
    out, i = [a], 0
    while i < len(pts) - 1:
        j = len(pts) - 1
        while j > i + 1 and not path_clear(pts[i], pts[j]):
            j -= 1
        out.append(pts[j])
        i = j
    return out


def near_route(route, radius=1.5):
    mark = {}
    for k in range(len(route) - 1):
        a, b = route[k], route[k + 1]
        n = max(1, int((b - a).length / GRID))
        for t in range(n + 1):
            c = cell_of(a.lerp(b, t / n))
            r = int(radius / GRID)
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    mark[(c[0] + dx, c[1] + dy)] = True
    return mark


walks = []
for i, a in enumerate(stations):
    others = sorted((j for j in range(STATIONS) if j != i), key=lambda j: (stations[j] - a).length)
    for j in others:
        raw = astar(a, stations[j])
        if raw is None:
            print(f"NO ROUTE {i}->{j}")
            continue
        walks.append({"from": i, "to": j, "route": simplify(raw, a, stations[j]), "detour": False})
    extra = OUT_PER_STATION - sum(1 for w in walks if w["from"] == i)
    for j in others[:max(0, extra)]:
        first = next(w for w in walks if w["from"] == i and w["to"] == j and not w["detour"])
        raw = astar(a, stations[j], near_route(first["route"]))
        if raw is None:
            continue
        walks.append({"from": i, "to": j, "route": simplify(raw, a, stations[j]), "detour": True})
print("WALKS", len(walks), "longest route %.1f m" % max(sum((w["route"][k + 1] - w["route"][k]).length
      for k in range(len(w["route"]) - 1)) for w in walks))

# ---------------------------------------------------------------- bake every walk back to back
p = dict(wd.PARAMS, **ROAM_PARAMS)
ground_model = lambda x, y: gz(x * S, y * S) / S
T = 1 / FPS


def settled_feet(at, yaw):
    probe = WalkerSim(dict(p), ground=ground_model, pos=at / S, yaw=yaw, homes=homes, rest_z=rest_z)
    return {L: probe.stepper.feet[L].pos.copy() for L in LEGS}


def unwrap(target, near):
    return target + round((near - target) / (2 * math.pi)) * 2 * math.pi


frame = 1
for wi, w in enumerate(walks):
    a, b = stations[w["from"]], stations[w["to"]]
    yaw_a, yaw_b = station_yaw[w["from"]], station_yaw[w["to"]]
    sim = WalkerSim(dict(p), ground=ground_model, pos=a / S, yaw=yaw_a, homes=homes, rest_z=rest_z)
    feet_b = settled_feet(b, yaw_b)
    route = w["route"][1:]
    leg = 0
    arrived, still, n = False, 0, 0
    start = frame
    worst = 0.0
    while True:
        t = n * T
        pos_w = sim.y * S
        speed_w = (sim.y - sim.y_prev).length / T * S
        if not arrived:
            wp = route[leg]
            d = wp - pos_w
            last = leg == len(route) - 1
            if not last and d.length < LEG_ARRIVE:
                leg += 1
                wp = route[leg]
                d = wp - pos_w
            if last and d.length < 0.05 and speed_w < 0.05:
                arrived = True
        if arrived:
            sim.p["step_tidy"] = SETTLE_TIDY
            fp = sim.step(T, b / S, unwrap(yaw_b, sim.byaw), None, True)
            rest = ((sim.y - b / S).length < 0.004 and abs(sim.byaw - unwrap(yaw_b, sim.byaw)) < 0.003
                    and abs(sim.hyaw - sim.byaw) < 0.005
                    and all(not sim.stepper.feet[L].stepping and (sim.stepper.feet[L].pos - feet_b[L]).length < 0.03 for L in LEGS))
            still = still + 1 if rest else 0
        else:
            yaw_t = unwrap(heading(d.x, d.y), sim.byaw)
            move = abs(yaw_t - sim.byaw) < math.radians(35)
            fp = sim.step(T, wp / S, yaw_t, None, move)
        f = frame + n
        root.location, root.rotation_euler = (sim.y.x, sim.y.y, sim.z), (0, 0, sim.byaw)
        root.keyframe_insert("location", frame=f)
        root.keyframe_insert("rotation_euler", frame=f)
        body.rotation_quaternion = sim.body_rotation()
        body.location.z = rest_z - sim.drop
        body.keyframe_insert("rotation_quaternion", frame=f)
        body.keyframe_insert("location", index=2, frame=f)
        head.rotation_euler = (0, 0, sim.hyaw - sim.byaw)
        head.keyframe_insert("rotation_euler", frame=f)
        hips = sim.hips_world(rest_z)
        worst = max(worst, max((fp[L] - hips[L]).length - REACH for L in LEGS))
        for ob, L in zip(feet, LEGS):
            ob.location = fp[L]
            ob.keyframe_insert("location", frame=f)
        n += 1
        if (arrived and still >= FPS // 2) or t > WALK_CAP:
            break
    # constant interpolation, so a walk's last key does not slide into the next walk's first
    w.update({"first": start, "last": start + n - 1, "settled": arrived and still >= FPS // 2,
              "overreach_cm": round(100 * S * max(0.0, worst), 1)})
    frame = start + n + (n % 2) + 2          # next walk starts on an odd frame two apart (clips sample every other)
    print(f"WALK {wi:3d} {w['from']}->{w['to']}{' detour' if w['detour'] else ''}: {n / FPS:5.1f} s, "
          f"{'settled' if w['settled'] else 'NOT SETTLED'}, overreach {w['overreach_cm']} cm")

for ob in (root, body, head, *feet):
    if ob.animation_data and ob.animation_data.action:
        for fc in getattr(ob.animation_data.action, "fcurves", []):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"
sc.frame_start, sc.frame_end = 1, frame
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "walker_graph.blend"))
json.dump({"fps": FPS, "scale": S, "pillars": GRAPH_PILLARS,
           "stations": [[s.x, s.y, y] for s, y in zip(stations, station_yaw)],
           "walks": [dict({k: v for k, v in w.items() if k != "route"}, route=[[q.x, q.y] for q in w["route"]]) for w in walks]},
          open(os.path.join(OUT, "walker_graph.json"), "w"))
total = sum(w["last"] - w["first"] + 1 for w in walks) / FPS
print(f"GRAPH {len(walks)} walks, {total:.0f} s in all, {sum(not w['settled'] for w in walks)} not settled; saved out/walker/walker_graph.blend")
