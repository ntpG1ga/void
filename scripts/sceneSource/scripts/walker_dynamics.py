"""Step 1 of the procedural walker: body + head follow a target through t3ssel8r's f/zeta/r filter.

  "$B" -b -P "$(wslpath -w scripts/walker_dynamics.py)"

Reads out/walker/walker_dynamics.blend if it exists (so edited CTRL-Target keys / params survive),
otherwise builds it from referenceWalker.blend (never written to).
  - CTRL-Target  : the input x. Keyframe its location (XY) and rotation Z by hand, then re-run.
                   Its custom props hold the f/zeta/r params (edit in N panel > Item > Properties).
  - ReferenceWalker (root) : baked filtered position + body yaw
  - RIG-Body     : baked tilt toward the target (chassis + head pivot hang off it)
  - RIG-Head     : baked head yaw, lower f than the body so it lags (secondary motion)
  - CTRL-Foot-*  : once walker_rig.py has run, baked world-space foot plants/steps (walker_steps.py)
x (and its heading) is first speed-limited to max_speed / max_turn_deg_s (like a character controller walking to a clicked point),
then filtered; the raw pass uses that same speed-limited x with no filter.

PARAMS=out/walker/params.json (a JSON object, e.g. copied from the playground) overrides the
CTRL-Target props and is written onto them, so later runs keep it.

CANDIDATE=<tag> (with PARAMS) bakes and renders only the filtered pass into out/walker/frames_<tag>/
without saving the .blend - used to preview sweep candidates.

RENDER=1 also renders a raw (y = speed-limited x) pass and the filtered pass into out/walker/frames_{raw,filtered}/
and writes out/walker/trace.json for scripts/walker_compare.py.
"""
import bpy, json, math, os, shutil, sys
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "referenceWalker.blend")
OUT_DIR = os.path.join(ROOT, "out", "walker")
OUT = os.path.join(OUT_DIR, "walker_dynamics.blend")
RENDER = os.environ.get("RENDER") == "1"
CANDIDATE = os.environ.get("CANDIDATE", "")
LEGS = ["FrontL", "FrontR", "RearL", "RearR"]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# name -> default; stored as custom props on CTRL-Target so they can be tuned without code
PARAMS = {
    "body_f": 1.2, "body_zeta": 0.5, "body_r": -2.0,    # underdamped + anticipation (video)
    "turn_f": 1.0, "turn_zeta": 1.0, "turn_r": 0.0,     # smooth turning (video)
    "head_f": 0.6, "head_zeta": 1.0, "head_r": 0.0,     # same as turn but slower -> head lags
    "tilt_f": 2.5, "tilt_zeta": 0.8, "tilt_r": 0.0,     # smooths the lean so it can't pop
    "tilt_deg_per_m": 7.0, "tilt_max_deg": 16.0,
    "crouch_m": 0.38, "crouch_f": 1.5, "crouch_zeta": 0.6,  # body drops at full speed: legs reach further
    "max_speed": 2.5,                                   # m/s the input may travel; 0 = teleport
    "max_turn_deg_s": 150.0,                            # deg/s the input heading may turn; 0 = instant
    "step_threshold": 0.3, "step_panic": 0.7,           # m of drift before a foot steps / must step
    "step_time": 0.2, "step_height": 0.35,              # s per swing, m of lift
    "step_lead_s": 0.22, "step_max_lead": 0.55,         # land ahead of home by velocity * lead
    "gait_pairs": 1.0,                                  # 1 = diagonal pairs swing together (trot), 0 = each foot alone
}

# (frame, x, y, interpolation of the segment that starts here). CONSTANT = the target teleports,
# like a mouse click; LINEAR = it glides at constant speed.
TARGET_KEYS = [
    (1, 0.0, 0.0, "CONSTANT"),
    (30, 3.0, 0.5, "CONSTANT"),
    (70, 3.0, -3.0, "CONSTANT"),
    (105, -2.5, -2.0, "CONSTANT"),
    (140, -3.0, 1.5, "LINEAR"),
    (185, 1.5, 3.0, "CONSTANT"),
    (215, 0.0, 0.0, "CONSTANT"),
]


class SecondOrderDynamics:
    """y + k1*y' + k2*y'' = x + k3*x'  (semi-implicit Euler, k2 clamped so big steps can't explode)."""

    def __init__(self, f, zeta, r, x0):
        self.k1 = zeta / (math.pi * f)
        self.k2 = 1 / ((2 * math.pi * f) ** 2)
        self.k3 = r * zeta / (2 * math.pi * f)
        self.xp = x0
        self.y = x0
        self.yd = x0 * 0

    def update(self, T, x, xd=None):
        if xd is None:
            xd = (x - self.xp) / T
            self.xp = x
        # T < sqrt(4*k2 + k1^2) - k1 for stability; the T*k1 term also stops frame-to-frame jitter
        k2 = max(self.k2, T * T / 2 + T * self.k1 / 2, T * self.k1)
        self.y = self.y + T * self.yd
        self.yd = self.yd + T * (x + self.k3 * xd - self.y - self.k1 * self.yd) / k2
        return self.y


def fcurves(obj):
    ad = obj.animation_data
    try:
        from bpy_extras import anim_utils
        return anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot).fcurves
    except (ImportError, AttributeError):
        return ad.action.fcurves


def new_empty(name, coll, loc, display="PLAIN_AXES", size=0.4):
    o = bpy.data.objects.new(name, None)
    o.empty_display_type, o.empty_display_size = display, size
    o.location = loc
    coll.objects.link(o)
    return o


def reparent(obj, parent):
    mw = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_world = mw


def bbox_world(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return (Vector([min(p[i] for p in pts) for i in range(3)]),
            Vector([max(p[i] for p in pts) for i in range(3)]))


def heading(dx, dy):
    """Yaw that turns the walker's front (-Y, where the eye is) toward (dx, dy)."""
    return math.atan2(dx, -dy)


def build():
    sc = bpy.context.scene
    root = bpy.data.objects["ReferenceWalker"]
    chassis = list(bpy.data.collections["GRP-Chassis"].objects)
    head = list(bpy.data.collections["GRP-Head"].objects)
    rig_coll = bpy.data.collections["GRP-ReferenceWalker"]
    ctrl_coll = bpy.data.collections.new("GRP-Controls")
    sc.collection.children.link(ctrl_coll)
    bpy.context.view_layer.update()

    lo, hi = bbox_world(chassis)
    body_pivot = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2))
    neck = bpy.data.objects["GEO-Chassis-Neck"]
    nlo, nhi = bbox_world([neck])
    head_pivot = Vector(((nlo.x + nhi.x) / 2, (nlo.y + nhi.y) / 2, nhi.z))
    print(f"body pivot {tuple(round(v, 3) for v in body_pivot)}  head pivot {tuple(round(v, 3) for v in head_pivot)}")

    body = new_empty("RIG-Body", rig_coll, body_pivot, "CUBE", 0.25)
    body.parent = root
    body.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    body.matrix_world = Matrix.Translation(body_pivot)
    hd = new_empty("RIG-Head", rig_coll, head_pivot, "SINGLE_ARROW", 0.8)
    reparent(hd, body)
    for o in chassis:
        reparent(o, body)
    for o in head:
        reparent(o, hd)

    tgt = new_empty("CTRL-Target", ctrl_coll, (0, 0, 0), "CIRCLE", 0.6)
    tgt.rotation_euler = (0, 0, 0)
    for k, v in PARAMS.items():
        tgt[k] = v
    # a flat red marker so the target shows up in renders, with a notch pointing at its front
    me = bpy.data.meshes.new("GEO-TargetMarker")
    s, n = 0.35, 0.6
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0), (0, -n, 0)], [],
                   [(0, 1, 2, 3), (0, 4, 1)])
    mat = bpy.data.materials.new("MAT-TargetMarker")
    mat.diffuse_color = (0.9, 0.12, 0.08, 1)
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.12, 0.08, 1)
    me.materials.append(mat)
    mk = bpy.data.objects.new("GEO-TargetMarker", me)
    mk.location = (0, 0, 0.01)
    mk.parent = tgt
    ctrl_coll.objects.link(mk)

    yaw, prev = 0.0, (0.0, 0.0)
    for i, (f, x, y, interp) in enumerate(TARGET_KEYS):
        if (x, y) != prev:
            h = heading(x - prev[0], y - prev[1])
            yaw = h + round((yaw - h) / (2 * math.pi)) * 2 * math.pi  # nearest turn, no 350deg spins
        tgt.location = (x, y, 0)
        tgt.rotation_euler.z = yaw
        tgt.keyframe_insert("location", frame=f)
        tgt.keyframe_insert("rotation_euler", index=2, frame=f)
        if interp == "LINEAR" and i + 1 < len(TARGET_KEYS):
            # face the glide direction shortly after landing at its start
            nx, ny = TARGET_KEYS[i + 1][1:3]
            h = heading(nx - x, ny - y)
            yaw = h + round((yaw - h) / (2 * math.pi)) * 2 * math.pi
            tgt.rotation_euler.z = yaw
            tgt.keyframe_insert("rotation_euler", index=2, frame=f + 10)
        prev = (x, y)
    interp_at = {f: it for f, _, _, it in TARGET_KEYS}
    for fc in fcurves(tgt):
        for kp in fc.keyframe_points:
            kp.interpolation = "CONSTANT" if fc.data_path == "rotation_euler" else interp_at[int(kp.co.x)]

    # a wider camera than the 3/4 hero shot so the whole run stays in frame
    cd = bpy.data.cameras.new("CAM-Walker-Clip")
    cd.type, cd.ortho_scale = "ORTHO", 13.5
    cam = bpy.data.objects.new("CAM-Walker-Clip", cd)
    d = Vector((6.0, -9.0, 6.9)).normalized()
    cam.location = d * 30
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    bpy.data.collections["GRP-Presentation"].objects.link(cam)


def bake(raw=False):
    sc = bpy.context.scene
    fps = sc.render.fps / sc.render.fps_base
    T = 1 / fps
    root = bpy.data.objects["ReferenceWalker"]
    body = bpy.data.objects["RIG-Body"]
    hd = bpy.data.objects["RIG-Head"]
    tgt = bpy.data.objects["CTRL-Target"]
    p = {k: float(tgt.get(k, v)) for k, v in PARAMS.items()}
    if os.environ.get("PARAMS"):
        with open(os.path.join(ROOT, os.environ["PARAMS"])) as fh:
            given = json.load(fh)
        p.update({k: float(v) for k, v in given.items() if k in PARAMS})
        print("params from", os.environ["PARAMS"], sorted(k for k in given if k in PARAMS))
    for k, v in PARAMS.items():
        tgt[k] = p[k]
    for o in (root, body, hd):
        o.animation_data_clear()
    root.rotation_mode, hd.rotation_mode = "XYZ", "XYZ"

    f0, f1 = sc.frame_start, sc.frame_end
    samples = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        m = tgt.matrix_world
        samples.append((Vector((m.translation.x, m.translation.y)), tgt.rotation_euler.z))

    feet = [bpy.data.objects.get(f"CTRL-Foot-{L}") for L in LEGS]
    stepper = None
    if all(feet):
        import walker_steps
        homes = {}
        for L, ft in zip(LEGS, feet):
            if "home" not in ft:   # first run after walker_rig: foot is still parented at rest on frame f0
                sc.frame_set(f0)
                ft["home"] = list(root.matrix_world.inverted() @ ft.matrix_world.translation)
            homes[L] = Vector(ft["home"])
            ft.animation_data_clear()
            ft.parent = None
            ft.matrix_parent_inverse = Matrix.Identity(4)

    x0, a0 = samples[0]
    xc, ac = x0.copy(), a0
    pos = SecondOrderDynamics(p["body_f"], p["body_zeta"], p["body_r"], x0.copy())
    turn = SecondOrderDynamics(p["turn_f"], p["turn_zeta"], p["turn_r"], a0)
    look = SecondOrderDynamics(p["head_f"], p["head_zeta"], p["head_r"], a0)
    lean = SecondOrderDynamics(p["tilt_f"], p["tilt_zeta"], p["tilt_r"], Vector((0, 0)))
    crouch = SecondOrderDynamics(p["crouch_f"], p["crouch_zeta"], 0.0, 0.0)
    if "rest_z" not in body:
        body["rest_z"] = body.location.z
    rest_z = body["rest_z"]
    trace = []
    y_prev = x0.copy()
    for i, (x, a) in enumerate(samples):
        f = f0 + i
        step = x - xc
        vmax = p["max_speed"] * T
        xc = x.copy() if p["max_speed"] <= 0 or step.length <= vmax else xc + step * (vmax / step.length)
        # turning is speed-limited too: a snap turn swings the foot homes (2 m out) faster than any gait
        amax = math.radians(p["max_turn_deg_s"]) * T
        ac = a if p["max_turn_deg_s"] <= 0 or abs(a - ac) <= amax else ac + math.copysign(amax, a - ac)
        if raw or i == 0:
            y, byaw, hyaw, off = xc.copy(), ac, ac, Vector((0, 0))
        if not raw and i > 0:
            y = pos.update(T, xc).copy()
            byaw = turn.update(T, ac)
            hyaw = look.update(T, ac)
            off = lean.update(T, xc - y).copy()
        # soft limit: ~tilt_deg_per_m for small offsets, eases into tilt_max_deg instead of a hard clamp
        tmax = math.radians(p["tilt_max_deg"])
        tilt = 0.0 if raw else tmax * math.tanh(math.radians(p["tilt_deg_per_m"]) * off.length / tmax)

        root.location = (y.x, y.y, 0)
        root.rotation_euler = (0, 0, byaw)
        root.keyframe_insert("location", frame=f)
        root.keyframe_insert("rotation_euler", frame=f)
        q_yaw = Quaternion((0, 0, 1), byaw)
        if off.length > 1e-6:
            q_tilt = Quaternion(Vector((0, 0, 1)).cross(Vector((off.x, off.y, 0))).normalized(), tilt)
        else:
            q_tilt = Quaternion()
        body.rotation_quaternion = q_yaw.inverted() @ q_tilt @ q_yaw
        body.keyframe_insert("rotation_quaternion", frame=f)
        speed = (y - y_prev).length / T
        drop = 0.0 if raw or p["max_speed"] <= 0 else crouch.update(T, p["crouch_m"] * min(1.0, speed / p["max_speed"]))
        body.location.z = rest_z - drop
        body.keyframe_insert("location", index=2, frame=f)
        hd.rotation_euler = (0, 0, hyaw - byaw)
        hd.keyframe_insert("rotation_euler", frame=f)
        foot_z = []
        if all(feet):
            rm = Matrix.Translation((y.x, y.y, 0)) @ Matrix.Rotation(byaw, 4, "Z")
            if stepper is None:
                stepper = walker_steps.Stepper(homes, rm, p)
            vel = Vector(((y - y_prev).x, (y - y_prev).y, 0)) / T
            for ft, (L, fp) in zip(feet, stepper.update(T, rm, vel).items()):
                ft.location = fp
                ft.keyframe_insert("location", frame=f)
                foot_z.append(fp.z)
        y_prev = y.copy()
        trace.append({"f": f, "x": [x.x, x.y], "xc": [xc.x, xc.y], "yaw_in": a, "y": [y.x, y.y],
                      "yaw_body": byaw, "yaw_head": hyaw, "tilt_deg": math.degrees(tilt), "drop": drop,
                      "foot_z": foot_z})
    sc.frame_set(f0)
    return trace, p


def render(tag, res=540):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.eevee.taa_render_samples = 8
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.camera = bpy.data.objects["CAM-Walker-Clip"]
    d = os.path.join(OUT_DIR, f"frames_{tag}")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    sc.render.filepath = os.path.join(d, "")
    bpy.ops.render.render(animation=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    src = OUT if os.path.exists(OUT) else SRC
    bpy.ops.wm.open_mainfile(filepath=src)
    print("opened", bpy.data.filepath)
    if "RIG-Body" not in bpy.data.objects:
        build()
    sc = bpy.context.scene
    if not sc.get("walker_frames_set"):   # speed-limited input needs longer to finish the route
        sc.frame_end, sc["walker_frames_set"] = 300, 1
    if CANDIDATE:   # preview only: never touches the saved file
        bake()
        render(CANDIDATE, res=400)
        return
    if RENDER:
        raw_trace, _ = bake(raw=True)
        render("raw")
    trace, p = bake()
    bpy.context.scene.camera = bpy.data.objects["CAM-Walker-Clip"]
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
    print("saved", OUT)
    if RENDER:
        render("filtered")
        with open(os.path.join(OUT_DIR, "trace.json"), "w") as fh:
            json.dump({"fps": bpy.context.scene.render.fps, "params": p, "raw": raw_trace, "filtered": trace}, fh)
    print("params", p)


if __name__ == "__main__":   # walker_sweep.py imports this module for SecondOrderDynamics / PARAMS
    main()
