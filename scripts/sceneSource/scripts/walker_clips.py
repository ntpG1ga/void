"""The walker pet's 9 clips for hibernal, baked as per-part transforms at 12 fps (user, 2026-09-28).

  "$B" -b --factory-startup -P "$(wslpath -w scripts/walker_clips.py)"      [ONLY=idle,walk]
      [ROAMS=walker_loop11,walker_loop23]   closed loops from walker_roam.py ROAM_LOOP=1 (out/walker/<name>.blend)
                                            -> clips roamLoop0, roamLoop1, ...: all start in one pose and end in
                                            it, so the game can play them one after another in any order
      [CLIPS_OUT=out/walker_clips_loops]    write there instead of out/walker_clips (ONLY=idle,roamLoops: just the loops)
      [GRAPH=1]                             walker_graph.py's walks (out/walker/walker_graph.blend + .json)
                                            -> <CLIPS_OUT>/walkerGraph.bin (run with ONLY=idle,graph and a CLIPS_OUT
                                            of its own: the walker.glb it writes is culled for fewer poses)
Reads out/walker/walker_v2_legs.blend (the rig, never written) and out/walker/walker_roam.blend
(walker_roam.py's bake, for roamHills). Writes out/walker_clips/:
  walker.glb          the rest pose as 12 rigid nodes (no skin, no animation: void's glTF subset),
                      position + normal + vertex colour, 2 m tall, front +Z
  walkerClips.json    per clip, per frame, every node's local translation + rotation (glTF axes)
  printed checks      tris vs the 500 budget, sole-to-IK-target, lowest point vs the ground, turn end state
Check it loads in void: msc run out/walker_clips/voidLoadCheck.ms. Preview: scripts/walker_clips_preview.py.
Hibernal's renderer has no skinning (docs/BRIEF.md §5.6 item 6: "animations are vertex-baked keyframes
stepped at 12 fps"). The walker is rigid boxes, so a frame is 12 node transforms, not 12 vertex arrays:
the same pixels, a few hundred KB instead of MB. The legs' IK, the stepping and the filters stay here.

Nodes (parent first): walker (root motion, no mesh) > body > head > lens; body > thigh<L> > shin<L>.
Clips (brainstormed with the user 2026-09-28: a box camera on spider legs, so moves are snappy
mechanical steps with overshoot through walker_dynamics' f/zeta/r filter; the eye is the face, and
pulling the red lens back into its black recess reads as blink, glitch and power-off):
  idle        loop 6 s: breathing bob, a snapped glance, one front foot taps twice, one blink
  lookAround  4.5 s: security-camera head snaps left, right, a curious tilt; the body shifts its weight
  walk        loop 1 s (one trot cycle): diagonal pairs, body bobs, the head held level like a gimbal
  turnLeft    3 s, 90 deg on the spot: the head snaps round first, the body follows through walker_sim
              and its stepper re-plants the diagonal pairs as it turns (as roamHills turns)
  turnRight   mirror of turnLeft
  react       2.6 s: startled (tap): eye shut, drops and splays its feet, shivers, rises, tilts its head
  hit         1.3 s: shoved back, head rattles, the eye glitches, a front foot slips and re-steps
  die         2.8 s, hold the last frame: eye flickers off, legs give way one by one, body drops, twitch
  roamHills   walker_roam.py's wander round the fire, on hibernal's hills, root in scene metres
"""
import json, math, os, sys
import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from walker_dynamics import SecondOrderDynamics as SOD

RIG = os.path.join(ROOT, "out", "walker", "walker_v2_legs.blend")
ROAM = os.path.join(ROOT, "out", "walker", "walker_roam.blend")
OUT = os.path.join(ROOT, os.environ.get("CLIPS_OUT", os.path.join("out", "walker_clips")))
ROAMS = [r for r in os.environ.get("ROAMS", "").split(",") if r]
GRAPH = os.environ.get("GRAPH", "0") == "1"
CLOSE_FRAMES = 6                 # a roam loop's last frames ease onto the loops' shared first frame
LEGS = ["FrontL", "FrontR", "RearL", "RearR"]
PAIRS = (("FrontL", "RearR"), ("FrontR", "RearL"))
FPS, SUB = 12, 4                 # clips at 12 fps, filters stepped 4x finer
PET_H, MODEL_H = 2.0, 3.48       # walker_roam.WALKER_H: 2 m in the hills scene
S = PET_H / MODEL_H
NECK = Vector((0, 0, 2.2))       # head pivot, model units: yaw about the vertical through the origin
                                 # (as RIG-Head turns in walker_roam), pitch/roll at the neck's top
LENS_BACK = 0.16                 # lens pulled this far into the recess = eye off (model units)
PET_BUDGET = 500
REST_M = {}                      # part name -> world matrix at rest (bone-parented parts move with every pose)
SHIN_V = {}                      # leg -> its shin's vertices in the Shin bone's rest frame (model units)
KEEP_WHOLE = ("GEO-Head-NotchedHousing", "GEO-Eye-Recess", "GEO-Eye-RedLens")
ONLY = [c for c in os.environ.get("ONLY", "").split(",") if c]


# ---------------------------------------------------------------- authoring helpers (model units)
class Track:
    """keys [(t, value)]: the target holds each value from its time on ("step") or glides between
    keys ("linear"), then goes through f/zeta/r (None = raw). Step + a low zeta is the mechanical snap."""

    def __init__(self, keys, f=None, zeta=1.0, r=0.0, mode="step"):
        self.keys, self.mode = sorted(keys, key=lambda k: k[0]), mode
        v0 = self.keys[0][1]
        self.sod = SOD(f, zeta, r, v0.copy() if isinstance(v0, Vector) else v0) if f else None

    def target(self, t):
        ks = self.keys
        if t <= ks[0][0]:
            return ks[0][1]
        for (t0, a), (t1, b) in zip(ks, ks[1:]):
            if t < t1:
                if self.mode == "step":
                    return a
                s = (t - t0) / (t1 - t0)
                return a + (b - a) * s
        return ks[-1][1]

    def update(self, T, t):
        x = self.target(t)
        if self.sod is None:
            return x
        y = self.sod.update(T, x.copy() if isinstance(x, Vector) else x)
        return y.copy() if isinstance(y, Vector) else y


def smooth(s):
    s = max(0.0, min(1.0, s))
    return s * s * (3 - 2 * s)


class Feet:
    """feet in root-local model space. Each leg rests on its planted spot; moves are (t0, t1, to, lift):
    lift > 0 swings in an arc, lift == 0 slides along the ground (a slip, a splay)"""

    def __init__(self, homes):
        self.homes = {L: Vector(h) for L, h in homes.items()}
        self.moves = {L: [] for L in LEGS}

    def move(self, L, t0, t1, to, lift=0.3):
        self.moves[L].append((t0, t1, Vector(to), lift))

    def out(self, L, d):
        """L's home pushed d outward along its diagonal"""
        h = self.homes[L]
        return h + Vector((h.x, h.y, 0)).normalized() * d

    def at(self, t):
        pos = {}
        for L in LEGS:
            p = self.homes[L].copy()
            for t0, t1, to, lift in sorted(self.moves[L], key=lambda m: m[0]):
                if t >= t1:
                    p = to.copy()
                elif t > t0:
                    s = smooth((t - t0) / (t1 - t0))
                    q = p.lerp(to, s)
                    q.z += lift * math.sin(math.pi * (t - t0) / (t1 - t0))
                    p = q
                    break
                else:
                    break
            pos[L] = p
        return pos


class Pose:
    """one frame, model units: root (xy, yaw), body offset/rotation in root space, head yaw/pitch/roll
    relative to the body (+ an offset), lens depth, feet in root space (or world, with feet_world)"""

    def __init__(self, **kw):
        self.root = Vector((0, 0, 0))
        self.yaw = 0.0
        self.body_off = Vector((0, 0, 0))
        self.body_rot = Vector((0, 0, 0))      # euler XYZ, radians: +x tips the front (-Y) down
        self.body_quat = None                  # or a quaternion straight from walker_sim
        self.head = Vector((0, 0, 0))          # (pitch +down, roll +toward +x, yaw +left)
        self.head_off = Vector((0, 0, 0))
        self.lens = 0.0
        self.feet = None
        self.feet_world = False
        self.__dict__.update(kw)


def run(dur, frame_fn):
    """step frame_fn(T, t) at FPS*SUB and keep every SUB-th pose: frames at t = 0, 1/12, ..."""
    n = int(round(dur * FPS))
    T = 1.0 / (FPS * SUB)
    poses = []
    for i in range(n * SUB):
        p = frame_fn(T, i * T)
        if i % SUB == 0:
            poses.append(p)
    return poses


D = math.radians


def clip_idle(homes):
    dur = 6.0
    glance = Track([(0, Vector((0, 0, 0))), (1.5, Vector((0, 0, D(20)))), (2.3, Vector((0, 0, 0))),
                    (4.3, Vector((D(-8), D(5), 0))), (5.0, Vector((0, 0, 0)))], f=2.4, zeta=0.45)
    shift = Track([(0, Vector((0, 0, 0))), (2.7, Vector((-0.1, 0.04, 0))), (3.95, Vector((0, 0, 0)))], f=1.6, zeta=0.6)
    feet = Feet(homes)
    tap = feet.homes["FrontR"]
    feet.move("FrontR", 2.95, 3.2, tap, lift=0.3)       # lift, tap
    feet.move("FrontR", 3.25, 3.5, tap, lift=0.24)      # and tap again
    lens = Track([(0, 0.0), (5.25, LENS_BACK), (5.42, 0.0)])

    def f(T, t):
        breath = -0.035 * (1 - math.cos(2 * math.pi * t / 3.0)) / 2
        return Pose(body_off=shift.update(T, t) + Vector((0, 0, breath)), head=glance.update(T, t),
                    lens=lens.update(T, t), feet=feet.at(t))
    return {"loop": True}, run(dur, f)


def clip_look(homes):
    dur = 4.5
    # (pitch, roll, yaw): snap left, hold, snap right, hold, back with a curious tilt, level
    head = Track([(0, Vector((0, 0, 0))), (0.25, Vector((0, 0, D(60)))), (1.45, Vector((0, 0, D(-60)))),
                  (2.65, Vector((D(-6), D(16), D(8)))), (3.55, Vector((0, 0, 0)))], f=2.6, zeta=0.4)
    weight = Track([(0, 0.0), (0.3, 1.0), (1.5, -1.0), (2.7, 0.0)], f=1.4, zeta=0.65)
    lens = Track([(0, 0.0), (2.2, LENS_BACK), (2.37, 0.0)])

    def f(T, t):
        w = weight.update(T, t)
        # lean toward where the head looks (+yaw looks toward +x): the legs on that side fold by IK
        return Pose(body_off=Vector((0.14 * w, 0, -0.03 * abs(w))), body_rot=Vector((0, D(4) * w, 0)),
                    head=head.update(T, t), lens=lens.update(T, t), feet={L: Vector(h) for L, h in homes.items()})
    return {"loop": False}, run(dur, f)


TURN_PARAMS = {"body_f": 1.0, "body_zeta": 0.5, "body_r": -2.0, "turn_f": 1.2, "turn_zeta": 0.7,
               "max_turn_deg_s": 70.0, "step_threshold": 0.3, "step_lead_s": 0.5, "step_max_lead": 0.8,
               "step_time": 0.25, "step_height": 0.3, "crouch_m": 0.0, "gait_pairs": 1.0, "step_tidy": 0.03}
REST_Z = 1.75                    # RIG-Body rest height, set from the rig in main()
WALK_P, WALK_V = 1.0, 1.0        # s per trot cycle, model units/s (0.57 m/s in the scene; roam walks 0.6)


def clip_walk(homes):
    """one exact trot cycle (loops by construction): pair A swings in the first half, pair B in the second"""
    swing = WALK_P / 2
    stride = WALK_V * WALK_P

    def foot(L, t):
        h = Vector(homes[L])
        ph = (t / WALK_P + (0.0 if L in PAIRS[0] else 0.5)) % 1.0
        # planted: slides back under the body from 1/4 stride ahead to 1/4 behind; swinging: comes forward
        if ph < 0.5:
            s = smooth(ph / 0.5)
            y = stride / 4 - s * stride / 2          # +y is behind (front is -y)
            z = 0.36 * math.sin(math.pi * ph / 0.5)
        else:
            y = -stride / 4 + (ph - 0.5) / 0.5 * stride / 2
            z = 0.0
        return Vector((h.x, h.y + y, h.z + z))

    def f(T, t):
        dip = -0.045 * (1 + math.cos(4 * math.pi * t / WALK_P)) / 2       # dips as each pair lands
        sway = D(2.0) * math.sin(2 * math.pi * t / WALK_P)
        lean = D(4.0)
        return Pose(root=Vector((0, -WALK_V * t, 0)), body_off=Vector((0, -0.06, dip)),
                    body_rot=Vector((lean, sway, 0)),
                    head=Vector((-lean, -sway, 0)), head_off=Vector((0, 0, -0.7 * dip)),     # gimbal: held level
                    feet={L: foot(L, t) for L in LEGS})
    return {"loop": True, "loopDelta": "root per cycle"}, run(WALK_P, f)


def clip_turn(homes, sign):
    """walker_sim turning on the spot, as roamHills turns (its stepper re-plants the pairs while the body
    turns: stepping only after each notch crossed the legs). The head leads, the body follows."""
    import walker_dynamics as wd
    from walker_sim import WalkerSim
    dur = 3.0
    p = dict(wd.PARAMS, **TURN_PARAMS)
    sim = WalkerSim(p, pos=(0.0, 0.0), yaw=0.0, homes=homes, rest_z=REST_Z)
    goal = sign * D(90)
    look = Track([(0, 0.0), (0.05, goal)], f=3.0, zeta=0.5)

    def f(T, t):
        yaw_t = goal if t > 0.25 else 0.0              # the head snaps first, the body sets off after
        feet = sim.step(T, Vector((0, 0)), yaw_t, None, move=False)
        hy = max(-D(70), min(D(70), look.update(T, t) - sim.byaw))
        return Pose(root=Vector((sim.y.x, sim.y.y, sim.z)), yaw=sim.byaw, body_quat=sim.body_rotation(),
                    body_off=Vector((0, 0, -sim.drop)), head=Vector((0, 0, hy)), feet=feet, feet_world=True)
    poses = run(dur, f)
    last = poses[-1]
    R = Matrix.Rotation(last.yaw, 3, "Z")
    off = max((last.feet[L] - (last.root + R @ Vector(homes[L]))).xy.length for L in LEGS)
    print(f"TURN {sign:+d}: ends at yaw {math.degrees(last.yaw):.2f} deg, root {tuple(round(v, 3) for v in last.root)}, "
          f"feet off home {100 * off * S:.1f} cm (scene)")
    return {"loop": False, "rootYawDeg": sign * 90}, poses


def clip_react(homes):
    dur = 2.6
    feet = Feet(homes)
    for L in LEGS:                                     # a startled hop outward, all four at once
        feet.move(L, 0.02, 0.2, feet.out(L, 0.55), lift=0.16)
    for k, pair in enumerate(PAIRS):                   # then back home, a pair at a time
        for L in pair:
            feet.move(L, 1.45 + 0.25 * k, 1.68 + 0.25 * k, homes[L], lift=0.26)
    drop = Track([(0, 0.0), (0.0, -0.3), (1.0, 0.0)], f=3.2, zeta=0.35)
    # recoil: the head jerks back (tipping it down swung its front rails into the front thighs)
    head = Track([(0, Vector((0, 0, 0))), (0.0, Vector((D(-6), 0, 0))),
                  (1.05, Vector((D(-4), D(-9), D(-6)))), (2.05, Vector((0, 0, 0)))], f=2.6, zeta=0.45)
    lens = Track([(0, 0.0), (0.01, LENS_BACK), (0.9, LENS_BACK * 0.5), (1.0, 0.0)])

    def f(T, t):
        shiver = 0.018 * (1 if int(t * 12) % 2 else -1) if 0.25 < t < 0.9 else 0.0
        return Pose(body_off=Vector((shiver, 0, drop.update(T, t))), head=head.update(T, t),
                    lens=lens.update(T, t), feet=feet.at(t))
    return {"loop": False}, run(dur, f)


def clip_hit(homes):
    dur = 1.3
    shove = Track([(0, Vector((0, 0, 0))), (0.0, Vector((0, 0.4, -0.1))), (0.12, Vector((0, 0, 0)))], f=3.4, zeta=0.3)
    tip = Track([(0, 0.0), (0.0, D(-8)), (0.12, 0.0)], f=3.4, zeta=0.4)
    head = Track([(0, Vector((0, 0, 0))), (0.0, Vector((D(-12), D(6), D(-8)))), (0.1, Vector((0, 0, 0)))],
                 f=3.6, zeta=0.35)
    lens = Track([(0, 0.0), (0.04, LENS_BACK), (0.13, 0.0), (0.25, LENS_BACK * 0.6), (0.34, 0.0)])
    feet = Feet(homes)
    slip = feet.homes["FrontL"] + Vector((-0.12, 0.42, 0))
    feet.move("FrontL", 0.03, 0.2, slip, lift=0.0)                 # the front foot skids back and out
    feet.move("FrontL", 0.55, 0.8, homes["FrontL"], lift=0.3)       # and steps back in
    feet.move("RearR", 0.62, 0.85, homes["RearR"], lift=0.18)       # its partner settles

    def f(T, t):
        return Pose(body_off=shove.update(T, t), body_rot=Vector((tip.update(T, t), 0, 0)),
                    head=head.update(T, t), lens=lens.update(T, t), feet=feet.at(t))
    return {"loop": False}, run(dur, f)


DIE_SPLAY, DIE_PITCH, DIE_ROLL = float(os.environ.get("DIE_SPLAY", 1.8)), float(os.environ.get("DIE_PITCH", 8)), \
    float(os.environ.get("DIE_ROLL", 0))     # swept 2026-09-28: a side slump or a deeper droop puts the head
                                             # on the thighs (the head sits right over the hips)
DIE_FLOOR = -0.88                # body drop that sets the tilted belly on the ground (LOW die ~ 0)


def clip_die(homes):
    dur = 2.8
    feet = Feet(homes)
    feet.move("FrontR", 0.45, 0.7, feet.out("FrontR", DIE_SPLAY), lift=0.0)      # legs give way one at a time
    feet.move("RearL", 0.95, 1.15, feet.out("RearL", DIE_SPLAY * 0.85), lift=0.0)
    feet.move("FrontL", 1.3, 1.48, feet.out("FrontL", DIE_SPLAY), lift=0.0)
    feet.move("RearR", 1.0, 1.16, feet.out("RearR", DIE_SPLAY * 0.85), lift=0.0)  # out before the body sinks onto it
    tw = feet.out("RearR", DIE_SPLAY * 0.85)
    feet.move("RearR", 2.2, 2.32, tw + Vector((0, 0, 0.0)), lift=0.14)       # one last twitch
    # body: sags toward the first leg to go, drops, lands on its belly tilted toward FrontR
    body = Track([(0, Vector((0, 0, 0))), (0.45, Vector((0.12, -0.1, -0.3))), (0.95, Vector((0.08, -0.05, -0.55))),
                  (1.38, Vector((0.1, -0.12, -0.95)))], f=3.0, zeta=0.35)
    rot = Track([(0, Vector((0, 0, 0))), (0.45, Vector((D(4), D(6), 0))), (0.95, Vector((D(2), D(3), 0))),
                 (1.3, Vector((D(5), D(7), 0)))], f=3.0, zeta=0.35)
    head = Track([(0, Vector((0, 0, 0))), (0.05, Vector((D(-12), D(-6), D(8)))), (0.3, Vector((0, 0, 0))),
                  (1.35, Vector((D(DIE_PITCH), D(DIE_ROLL), D(-14))))], f=2.4, zeta=0.3)
    lens = Track([(0, 0.0), (0.1, LENS_BACK), (0.2, 0.0), (0.35, LENS_BACK), (0.5, 0.0),
                  (1.0, LENS_BACK * 0.5), (1.1, 0.0), (1.45, LENS_BACK)])
    jerk = Track([(0, 0.0), (2.2, D(-3)), (2.3, 0.0)], f=4.0, zeta=0.4)

    def f(T, t):
        r = rot.update(T, t)
        r.x += jerk.update(T, t)
        b = body.update(T, t)
        b.z = max(b.z, DIE_FLOOR)     # the belly lands: the filter's bounce stops on the ground
        return Pose(body_off=b, body_rot=r, head=head.update(T, t),
                    lens=lens.update(T, t), feet=feet.at(t))
    return {"loop": False, "holdLast": True}, run(dur, f)


# ---------------------------------------------------------------- rig
class Rig:
    def __init__(self, to_model=None):
        o = bpy.data.objects
        self.root, self.body, self.head = o["ReferenceWalker"], o["RIG-Body"], o["RIG-Head"]
        self.arm = o["RIG-Legs"]
        self.feet = {L: o[f"CTRL-Foot-{L}"] for L in LEGS}
        self.to_model = to_model or Matrix.Identity(4)

    def w(self, ob):
        return self.to_model @ ob.matrix_world

    def bone_w(self, name):
        return self.to_model @ self.arm.matrix_world @ self.arm.pose.bones[name].matrix

    def rest(self):
        """model-space rest matrices of everything a node rides on (call in the rest pose)"""
        self.R = {"root": self.w(self.root), "body": self.w(self.body), "head": self.w(self.head)}
        for L in LEGS:
            for b in ("Thigh", "Shin"):
                self.R[f"{b}-{L}"] = self.bone_w(f"{b}-{L}")

    def apply(self, p):
        root, body, head = self.root, self.body, self.head
        root.location = p.root
        root.rotation_mode = "XYZ"
        root.rotation_euler = (0, 0, p.yaw)
        body.rotation_mode = "QUATERNION"
        body.location = self.body_rest_loc + p.body_off
        body.rotation_quaternion = p.body_quat if p.body_quat is not None else (Matrix.Rotation(p.body_rot.z, 3, "Z") @ Matrix.Rotation(p.body_rot.y, 3, "Y")
                                    @ Matrix.Rotation(p.body_rot.x, 3, "X")).to_quaternion()
        rootm = Matrix.Translation(p.root) @ Matrix.Rotation(p.yaw, 4, "Z")
        for L in LEGS:
            f = p.feet[L]
            self.feet[L].matrix_world = Matrix.Translation(f if p.feet_world else rootm @ f)
        bpy.context.view_layer.update()
        head.matrix_world = self.head_world(p)
        bpy.context.view_layer.update()
        self.seat_feet(lambda x, y: 0.0)          # the authored clips stand on flat ground (model z 0)

    def seat_feet(self, ground, planted=()):
        """the foot is part of the rigid shin (no ankle), so when the leg changes angle its outer edge
        tips into the ground: lift the IK target by however deep the shin's lowest point went, re-solve.
        Legs in `planted` are also lowered onto `ground` when they hover over it (roam: the game's
        coarse ground mesh sits up to ~15 cm off the true hills the sim planted them on)"""
        for _ in range(3):
            moved = False
            for L in LEGS:
                bw = self.bone_w(f"Shin-{L}")
                pen = max(ground(w.x, w.y) - w.z for w in (bw @ v for v in SHIN_V[L]))
                # sunk: lift it; planted and hovering: bring it down to touch
                if pen > 1e-4 or (L in planted and -0.4 < pen < -1e-4):
                    t =(self.to_model @ self.feet[L].matrix_world).translation + Vector((0, 0, pen))
                    self.feet[L].matrix_world = self.to_model.inverted() @ Matrix.Translation(t)
                    moved = True
            if not moved:
                return
            bpy.context.view_layer.update()

    def head_world(self, p):
        """the head turned about NECK in the body's rest frame, riding the body"""
        pitch, roll, yaw = p.head
        R = (Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(roll, 4, "Y") @ Matrix.Rotation(pitch, 4, "X"))
        piv = Matrix.Translation(NECK)
        local = Matrix.Translation(p.head_off) @ piv @ R @ piv.inverted()
        return self.body.matrix_world @ self.body_rest_w.inverted() @ local @ self.head_rest_w


# node -> (parent, pivot in model space at rest, what it rides on)
def node_table(rig):
    b = rig.arm.data.bones
    armw = rig.to_model @ rig.arm.matrix_world
    T = {"walker": (None, Vector((0, 0, 0)), "root"),
         "body": ("walker", rig.R["body"].translation.copy(), "body"),
         "head": ("body", NECK.copy(), "head")}
    lens = bpy.data.objects["GEO-Eye-RedLens"]
    T["lens"] = ("head", centre(lens), "lens")
    for L in LEGS:
        T[f"thigh{L}"] = ("body", armw @ b[f"Thigh-{L}"].head_local, f"Thigh-{L}")
        T[f"shin{L}"] = (f"thigh{L}", armw @ b[f"Shin-{L}"].head_local, f"Shin-{L}")
    return T


def centre(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return sum(vs, Vector()) / len(vs)


def node_worlds(rig, table, lens_depth):
    """model-space world matrix of every node for the current evaluated pose"""
    W = {}
    for n, (par, piv, ride) in table.items():
        if ride == "root":
            W[n] = rig.w(rig.root)
        elif ride == "lens":
            continue
        elif ride in ("body", "head"):
            ob = rig.body if ride == "body" else rig.head
            W[n] = rig.w(ob) @ rig.R[ride].inverted() @ Matrix.Translation(piv)
        else:
            W[n] = rig.bone_w(ride) @ rig.R[ride].inverted() @ Matrix.Translation(piv)
    W["lens"] = W["head"] @ Matrix.Translation(Vector((0, lens_depth, 0)) + table["lens"][1] - NECK)
    return W


def gltf_trs(m):
    """model-space local matrix -> glTF (Y up, scaled to the scene): [tx, ty, tz, qx, qy, qz, qw]"""
    t, q, s = m.decompose()
    assert abs(s.x - 1) < 1e-3 and abs(s.y - 1) < 1e-3 and abs(s.z - 1) < 1e-3, s
    t = t * S
    return [t.x, t.z, -t.y, q.x, q.z, -q.y, q.w]


# ---------------------------------------------------------------- mesh
def parts_by_node(table):
    out = {n: [] for n in table}
    for o in bpy.data.objects:
        if o.type != "MESH" or not o.name.startswith("GEO-") or not o.visible_get():
            continue
        if o.name in ("GEO-CheckerGround", "GEO-TargetMarker"):
            continue
        if o.name == "GEO-Eye-RedLens":
            out["lens"].append(o)
        elif o.parent_type == "BONE":
            kind, L = o.parent_bone.split("-")
            out[f"{kind.lower()}{L}"].append(o)
        elif o.name.startswith(("GEO-Head-", "GEO-Eye-")):
            out["head"].append(o)
        elif o.name.startswith("GEO-Chassis-"):
            out["body"].append(o)
        else:
            raise RuntimeError(f"no node for {o.name}")
    return out


def base_colour(mat):
    if mat is None:
        return (0.8, 0.8, 0.8, 1.0)
    if mat.use_nodes and mat.node_tree:
        for nd in mat.node_tree.nodes:
            if nd.type == "BSDF_PRINCIPLED":
                return tuple(nd.inputs["Base Color"].default_value)
            if nd.type == "EMISSION":
                return tuple(nd.inputs["Color"].default_value)
    return tuple(mat.diffuse_color)


def inside(tree, p):
    """odd crossings along three skewed axes (hibernal_stage.inside)"""
    for d in (Vector((1, 0.0137, 0.0071)), Vector((0.0093, 1, 0.0121)), Vector((0.0111, 0.0079, 1))):
        d, n, q = d.normalized(), 0, p.copy()
        for _ in range(32):
            hit = tree.ray_cast(q, d)
            if hit[0] is None:
                break
            n += 1
            q = hit[0] + d * 1e-4
        if n % 2 == 0:
            return False
    return True


def cull(parts, table, samples):
    """faces hidden inside another part in EVERY sampled pose (so never seen in any clip).
    parts: {node: [objects]} at rest; samples: [{node: model world}]. -> set of (object name, poly index)"""
    rest = {n: Matrix.Translation(table[n][1]) for n in table}
    local = {}   # part -> (node, BVH in the node's rest-local frame, bbox)
    for n, obs in parts.items():
        for o in obs:
            m = rest[n].inverted() @ REST_M[o.name]
            vs = [m @ v.co for v in o.data.vertices]
            local[o.name] = (n, BVHTree.FromPolygons(vs, [tuple(p.vertices) for p in o.data.polygons]),
                             (Vector([min(v[i] for v in vs) for i in range(3)]), Vector([max(v[i] for v in vs) for i in range(3)])))
    hidden = set()
    for n, obs in parts.items():
        for o in obs:
            if o.name in KEEP_WHOLE:
                continue
            m = rest[n].inverted() @ REST_M[o.name]
            nm = m.to_3x3().inverted().transposed()
            for poly in o.data.polygons:
                probe = m @ poly.center + (nm @ poly.normal).normalized() * 0.004
                always = True
                for W in samples:
                    covered = False
                    for other, (on, tree, (lo, hi)) in local.items():
                        if other == o.name:
                            continue
                        q = W[on].inverted() @ W[n] @ probe if on != n else probe
                        if not all(lo[i] - 1e-3 <= q[i] <= hi[i] + 1e-3 for i in range(3)):
                            continue
                        if inside(tree, q):
                            covered = True
                            break
                    if not covered:
                        always = False
                        break
                if always:
                    hidden.add((o.name, poly.index))
    return hidden


def build_export(parts, table, hidden):
    """new objects, one per node, in export form: scaled, pivot at the origin, rest rotation identity"""
    coll = bpy.data.collections.new("EXPORT")
    bpy.context.scene.collection.children.link(coll)
    made, tris = {}, {}
    for n, (par, piv, _) in table.items():
        if not parts[n]:
            ob = bpy.data.objects.new(n, None)
        else:
            bm = bmesh.new()
            col = bm.loops.layers.color.new("Col")
            for o in parts[n]:
                mw = REST_M[o.name]
                for poly in o.data.polygons:
                    if (o.name, poly.index) in hidden:
                        continue
                    rgba = base_colour(o.data.materials[poly.material_index] if o.data.materials else None)
                    vs = [bm.verts.new((mw @ o.data.vertices[i].co - piv) * S) for i in poly.vertices]
                    f = bm.faces.new(vs)
                    for lp in f.loops:
                        lp[col] = rgba
            bmesh.ops.triangulate(bm, faces=bm.faces)
            me = bpy.data.meshes.new(n)
            bm.to_mesh(me)
            bm.free()
            for p in me.polygons:
                p.use_smooth = False
            me.color_attributes.active_color_index = me.color_attributes.render_color_index = 0
            tris[n] = len(me.polygons)
            ob = bpy.data.objects.new(n, me)
        coll.objects.link(ob)
        ob.name = n
        assert ob.name == n, f"name {n} taken in the rig file"
        made[n] = ob
    for n, (par, piv, _) in table.items():
        ob = made[n]
        if par:
            ob.parent = made[par]
            ob.location = (piv - table[par][1]) * S
        else:
            ob.location = piv * S
    return made, tris


def export(made, path):
    import importlib.util
    spec = importlib.util.spec_from_file_location("hills", os.path.join(HERE, "hibernal", "hillsScene.py"))
    src = open(spec.origin).read()
    ns = {"__name__": "hills_helpers", "__file__": spec.origin}
    exec(compile(src.split("\ndef main():")[0], spec.origin, "exec"), ns)     # voidSubset without running main
    for o in bpy.context.scene.objects:
        o.select_set(o in made.values())
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="NONE",
                              export_texcoords=False, export_normals=True, export_vertex_color="ACTIVE",
                              export_animations=False, export_yup=True, export_extras=False)
    ns["voidSubset"](path)


# ---------------------------------------------------------------- bake
def bake_authored(rig, table, clips):
    out, samples, checks = {}, [], {}
    for name, (meta, poses) in clips.items():
        frames, worst = [], (0.0, 0.0)
        for p in poses:
            rig.apply(p)
            W = node_worlds(rig, table, p.lens)
            frames.append(W)
            # soles: shin tail vs its target (IK reach), and the lowest point of the body vs the ground
            err = max((rig.bone_w(f"Shin-{L}") @ Vector((0, rig.arm.data.bones[f"Shin-{L}"].length, 0))
                       - rig.w(rig.feet[L]).translation).length for L in LEGS)
            worst = (max(worst[0], err), worst[1])
        checks[name] = worst[0]
        out[name] = (meta, frames)
        samples += frames
    return out, samples, checks


def bake_roam(table_rest_pivots, path=ROAM):
    """walker_roam.blend's baked wander -> node worlds in model space, every other 24 fps frame"""
    bpy.ops.wm.open_mainfile(filepath=path)
    sc = bpy.context.scene
    scale = bpy.data.objects["WALKER-SCALE"]
    rig = Rig(scale.matrix_world.inverted())
    rig.R = table_rest_pivots["R"]
    rig.body_rest_w = rig.R["body"]
    src = os.path.join(HERE, "hibernal", "hillsScene.py")
    ns = {"__name__": "hills_helpers", "__file__": src}
    exec(compile(open(src).read().split("\ndef main():")[0], src, "exec"), ns)
    gh = ns["groundHeight"]
    # the ground the game draws: hibernal's hillsGround.glb (1 m grid), world metres
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(os.path.dirname(ROOT), "hibernal", "assets", "environment", "hillsGround.glb"))
    bpy.context.view_layer.update()
    vs, fs = [], []
    for o in set(bpy.data.objects) - before:
        if o.type == "MESH":
            b = len(vs)
            vs += [o.matrix_world @ v.co for v in o.data.vertices]
            fs += [tuple(b + i for i in p.vertices) for p in o.data.polygons]
    mesh = BVHTree.FromPolygons(vs, fs)

    def mesh_z(x, y):       # model units in, model units out
        hit = mesh.ray_cast(Vector((x * S, y * S, 100.0)), Vector((0, 0, -1)))
        return (hit[0].z if hit[0] is not None else gh(x * S, y * S)) / S

    frames = []
    for f in range(sc.frame_start, sc.frame_end + 1, 24 // FPS):
        sc.frame_set(f)
        planted = []
        for L in LEGS:      # the sim planted this foot: its target sits at the true ground (+ home 0.02)
            t = (rig.to_model @ rig.feet[L].matrix_world).translation
            if t.z - gh(t.x * S, t.y * S) / S < 0.06:
                planted.append(L)
        rig.seat_feet(mesh_z, planted)
        frames.append(node_worlds(rig, table_rest_pivots["table"], 0.0))
    return frames


def close_loop(name, rows, first):
    """a roam loop ends standing where every loop starts, to within the sim's settling (printed); its first
    frame becomes `first` and its last CLOSE_FRAMES ease onto it, so loop -> loop is the same pose twice"""
    def gap(a, b):
        move = max(math.dist(a[k:k + 3], b[k:k + 3]) for k in range(0, len(a), 7))
        turn = max(2 * math.degrees(math.acos(min(1.0, abs(sum(x * y for x, y in zip(a[k + 3:k + 7], b[k + 3:k + 7]))))))
                   for k in range(0, len(a), 7))
        return move, turn
    print(f"SEAM {name}: first frame off the shared one by {100 * gap(rows[0], first)[0]:.2f} cm / {gap(rows[0], first)[1]:.2f} deg; "
          f"last frame by {100 * gap(rows[-1], first)[0]:.2f} cm / {gap(rows[-1], first)[1]:.2f} deg before easing")
    rows = [list(first)] + [list(r) for r in rows[1:]]
    n = len(rows)
    for j in range(CLOSE_FRAMES):
        w = smooth((j + 1) / CLOSE_FRAMES)
        row = rows[n - CLOSE_FRAMES + j]
        for k in range(0, len(row), 7):
            for a in range(3):
                row[k + a] = round(row[k + a] * (1 - w) + first[k + a] * w, 5)
            q, q0 = row[k + 3:k + 7], first[k + 3:k + 7]
            sign = 1.0 if sum(x * y for x, y in zip(q, q0)) >= 0 else -1.0
            mixed = [x * (1 - w) + sign * y * w for x, y in zip(q, q0)]
            length = math.sqrt(sum(x * x for x in mixed))
            row[k + 3:k + 7] = [round(x / length, 5) for x in mixed]
    return rows


def rows_of(frames, order, table):
    rows = []
    for W in frames:
        row = []
        for n in order:
            par = table[n][0]
            m = W[n] if par is None else W[par].inverted() @ W[n]
            row += [round(v, 5) for v in gltf_trs(m)]
        rows.append(row)
    return rows


def ease_onto(rows, target):
    """the last CLOSE_FRAMES rows eased onto `target` (positions lerped, rotations nlerped)"""
    n = len(rows)
    for j in range(min(CLOSE_FRAMES, n)):
        w = smooth((j + 1) / CLOSE_FRAMES)
        row = rows[n - CLOSE_FRAMES + j] if n >= CLOSE_FRAMES else rows[j]
        for k in range(0, len(row), 7):
            for a in range(3):
                row[k + a] = row[k + a] * (1 - w) + target[k + a] * w
            q, q0 = row[k + 3:k + 7], target[k + 3:k + 7]
            sign = 1.0 if sum(x * y for x, y in zip(q, q0)) >= 0 else -1.0
            mixed = [x * (1 - w) + sign * y * w for x, y in zip(q, q0)]
            length = math.sqrt(sum(x * x for x in mixed))
            row[k + 3:k + 7] = [x / length for x in mixed]


def export_graph(rest_pivots, order, table):
    """walker_graph.py's walks -> walkerGraph.bin, little-endian:
      'WGRF', int32 version 1, fps, nodes, stations, walks
      per node: int32 length, name padded to 4
      per station: float32 x, z (glTF axes: where its walks start)
      per walk: int32 from, to, frames, detour; int16[frames * nodes * 7]: translation in mm,
                rotation times 32767, per node tx ty tz qx qy qz qw (node local)
    Every walk's first row is its station's pose and its last rows ease onto its target's."""
    import struct
    meta = json.load(open(os.path.join(ROOT, "out", "walker", "walker_graph.json")))
    frames = bake_roam(rest_pivots, os.path.join(ROOT, "out", "walker", "walker_graph.blend"))
    walks, pose = [], {}
    for w in meta["walks"]:
        k0, count = (w["first"] - 1) // 2, (w["last"] - w["first"]) // 2 + 1
        rows = rows_of(frames[k0:k0 + count], order, table)
        pose.setdefault(w["from"], rows[0])
        walks.append((w, rows))
    worst_start = worst_end = 0.0
    for w, rows in walks:
        start = pose[w["from"]]
        worst_start = max(worst_start, max(abs(a - b) for a, b in zip(rows[0], start)))
        rows[0] = list(start)
        end = pose[w["to"]]
        worst_end = max(worst_end, max(math.dist(rows[-1][k:k + 3], end[k:k + 3]) for k in range(0, len(end), 7)))
        ease_onto(rows, end)
        rows[-1] = list(end)
    print(f"GRAPH SEAMS: first rows off their station pose by at most {worst_start:.5f}; "
          f"last rows by at most {100 * worst_end:.2f} cm before easing")
    out = [b"WGRF", struct.pack("<iiiii", 1, FPS, len(order), len(meta["stations"]), len(walks))]
    for n in order:
        raw = n.encode("ascii")
        out.append(struct.pack("<i", len(raw)) + raw + b"\0" * (-len(raw) % 4))
    for i in range(len(meta["stations"])):
        out.append(struct.pack("<ff", pose[i][0], pose[i][2]))
    total = 0
    for w, rows in walks:
        out.append(struct.pack("<iiii", w["from"], w["to"], len(rows), 1 if w["detour"] else 0))
        q = []
        for row in rows:
            for k in range(0, len(row), 7):
                q += [max(-32767, min(32767, int(round(v * 1000.0)))) for v in row[k:k + 3]]
                q += [max(-32767, min(32767, int(round(v * 32767.0)))) for v in row[k + 3:k + 7]]
        out.append(struct.pack("<%dh" % len(q), *q))
        total += len(rows)
    path = os.path.join(OUT, "walkerGraph.bin")
    with open(path, "wb") as fh:
        fh.write(b"".join(out))
    print(f"wrote {path}: {len(walks)} walks, {total} frames ({total / FPS:.0f} s), {os.path.getsize(path) // 1024} KB")


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=RIG)
    sc = bpy.context.scene
    sc.frame_set(1)
    rig = Rig()
    for ob in (rig.root, rig.body, rig.head, *rig.feet.values()):
        ob.animation_data_clear()
    bpy.context.view_layer.update()
    rig.rest()
    rig.body_rest_loc = rig.body.location.copy()
    rig.body_rest_w, rig.head_rest_w = rig.R["body"].copy(), rig.R["head"].copy()
    homes = {L: tuple(rig.feet[L]["home"]) for L in LEGS}
    import walker_sim
    global REST_Z
    REST_Z = rig.body["rest_z"]
    bones = rig.arm.data.bones
    to_root = rig.root.matrix_world.inverted() @ rig.arm.matrix_world
    walker_sim.configure_legs({L: to_root @ bones[f"Thigh-{L}"].head_local for L in LEGS},
                              bones["Thigh-FrontL"].length, bones["Shin-FrontL"].length)
    table = node_table(rig)
    parts = parts_by_node(table)
    REST_M.update({o.name: o.matrix_world.copy() for obs in parts.values() for o in obs})
    for L in LEGS:
        inv = rig.R[f"Shin-{L}"].inverted()
        SHIN_V[L] = [inv @ REST_M[o.name] @ v.co for o in parts[f"shin{L}"] for v in o.data.vertices]
    print("NODES", {n: len(v) for n, v in parts.items()})

    makers = {"idle": clip_idle, "lookAround": clip_look, "walk": clip_walk,
              "turnLeft": lambda h: clip_turn(h, 1), "turnRight": lambda h: clip_turn(h, -1),
              "react": clip_react, "hit": clip_hit, "die": clip_die}
    clips = {n: fn(homes) for n, fn in makers.items() if not ONLY or n in ONLY}
    baked, samples, checks = bake_authored(rig, table, clips)
    for n, e in checks.items():
        print(f"CLIP {n}: {len(baked[n][1])} frames, worst sole-to-target {100 * e * S:.1f} cm (scene)")

    # lowest point of every part per frame (ground at z 0 for the authored clips)
    for n, (meta, frames) in baked.items():
        low = 1e9
        for W in frames:
            for node, obs in parts.items():
                m = W[node] @ Matrix.Translation(-table[node][1])
                for o in obs:
                    if node.startswith("shin"):
                        continue          # the feet stand on the ground by design
                    low = min(low, min((m @ REST_M[o.name] @ v.co).z for v in o.data.vertices))
        print(f"LOW {n}: lowest non-foot point {100 * low * S:.1f} cm above ground")

    # self collision: no leg part may pass through the head (user, 2026-09-25) - checked on the real meshes
    head_parts = parts["head"] + parts["lens"]
    leg_nodes = [n for n in table if n.startswith(("thigh", "shin"))]
    for n, (meta, frames) in baked.items():
        bad = {}
        for f, W in enumerate(frames):
            def tree(node, o):
                m = W[node] @ Matrix.Translation(-table[node][1]) @ REST_M[o.name]
                return BVHTree.FromPolygons([m @ v.co for v in o.data.vertices], [tuple(p.vertices) for p in o.data.polygons])
            heads = [tree("head" if o in parts["head"] else "lens", o) for o in head_parts]
            for ln in leg_nodes:
                for o in parts[ln]:
                    t = tree(ln, o)
                    for ho, ht in zip(head_parts, heads):
                        if t.overlap(ht):
                            bad.setdefault(f, set()).add(f"{o.name[8:]}~{ho.name[4:]}")
        print(f"SELF {n}: legs through the head in {len(bad)}/{len(frames)} frames" +
              "".join(f"\n    f{f}: {sorted(v)}" for f, v in list(bad.items())[:6]))

    hidden = cull(parts, table, samples[::2])
    made, tris = build_export(parts, table, hidden)
    total = sum(tris.values())
    print(f"TRIS {total} (budget {PET_BUDGET}); {len(hidden)} faces hidden in every sampled pose; per node {tris}")

    rest_pivots = {"R": {k: v.copy() for k, v in rig.R.items()}, "table": table}
    export(made, os.path.join(OUT, "walker.glb"))

    if not ONLY or "roamHills" in ONLY:
        baked["roamHills"] = ({"loop": False, "sceneSpace": True}, bake_roam(rest_pivots))

    if not ONLY or "roamLoops" in ONLY:
        for i, name in enumerate(ROAMS):
            baked[f"roamLoop{i}"] = ({"loop": True, "sceneSpace": True, "source": name},
                                     bake_roam(rest_pivots, os.path.join(ROOT, "out", "walker", name + ".blend")))

    if GRAPH:
        export_graph(rest_pivots, list(table), table)
        return

    order = list(table)
    first_row = None             # the roam loops' shared first frame
    doc = {"fps": FPS, "units": "metres, glTF axes (Y up), front +Z", "heightM": PET_H,
           "nodes": order, "parents": [table[n][0] for n in order],
           "layout": "frames[f] = per node in `nodes` order: tx ty tz qx qy qz qw (node local)",
           "clips": {}}
    for name, (meta, frames) in baked.items():
        rows = []
        for W in frames:
            row = []
            for n in order:
                par = table[n][0]
                m = W[n] if par is None else W[par].inverted() @ W[n]
                row += [round(v, 5) for v in gltf_trs(m)]
            rows.append(row)
        if name.startswith("roamLoop"):
            rows = close_loop(name, rows, first_row or rows[0])
            first_row = first_row or rows[0]
        c = dict(meta, frames=len(rows), data=rows)
        if name == "walk":
            c["loopDelta"] = [0.0, 0.0, round(WALK_V * WALK_P * S, 5)]
        doc["clips"][name] = c
        print(f"JSON {name}: {len(rows)} frames ({len(rows) / FPS:.2f} s)")
    path = os.path.join(OUT, "walkerClips.json")
    with open(path, "w") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    print(f"wrote {path} ({os.path.getsize(path) // 1024} KB) and walker.glb")


main()
