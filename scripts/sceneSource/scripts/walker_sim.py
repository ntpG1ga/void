"""The walker's motion as a pure simulation (no scene): one step() per frame -> the pose to key.

Everything is in MODEL units - the rig as modelled (3.48 m tall, front = -Y); a scene that shows it
smaller scales the terrain up to match (ground(x, y) in model units) and parents the baked result
under a scaled empty. Time is unchanged, so f / zeta / r keep their meaning.

Per frame: the input point x and heading are speed / turn limited, then filtered (walker_dynamics'
f/zeta/r); the body leans toward the input and crouches with speed; on terrain the root rides the
mean ground height under the four home spots and the body tilts part way to their slope, both
filtered too. The legs are nearly straight at rest (hip-sole 2.11 of 2.23) and can't fold much
either (thigh 1.75, shin 0.48: never closer than 1.27), so the root follows the rest height over the
mean ground but is then clamped, from where the soles actually are and with the crouch counted, so
every hip stays SOLE_RANGE from its sole: a far foot must still reach and a tucked-in or uphill one
must not jam into the hip. walker_steps plants and swings the feet on the ground.
"""
import math
from mathutils import Matrix, Quaternion, Vector

import walker_steps
from walker_dynamics import SecondOrderDynamics as SOD

LEGS = ["FrontL", "FrontR", "RearL", "RearR"]
HOME = {"FrontL": (-1.4, -1.4, 0.02), "FrontR": (1.4, -1.4, 0.02), "RearL": (-1.4, 1.4, 0.02), "RearR": (1.4, 1.4, 0.02)}
HIP = {"FrontL": (-0.52, -0.52, 1.72), "FrontR": (0.52, -0.52, 1.72), "RearL": (-0.52, 0.52, 1.72), "RearR": (0.52, 0.52, 1.72)}
BODY_PIVOT = Vector((0, 0.1, 1.75))
REACH = 1.75 + 0.48                       # v1 legs; configure_legs() replaces these from a rig
SOLE_RANGE = (1.36, 2.14)                 # hip-sole distance kept inside the legs' 1.27..2.23, with margin


def configure_legs(hips, thigh, shin, margin=(0.1, 0.09)):
    """use another rig's legs: hips = {leg: root-space hip joint at rest}, bone lengths in model units"""
    global REACH, SOLE_RANGE
    HIP.update({n: tuple(v) for n, v in hips.items()})
    REACH = thigh + shin
    SOLE_RANGE = (abs(thigh - shin) + margin[0], thigh + shin - margin[1])
TERRAIN_DEFAULTS = {
    "height_f": 1.6, "height_zeta": 0.8,     # root riding the ground: a little lag, no bounce
    "slope_follow": 0.6,                     # share of the ground's slope the body tilts to
    "slope_f": 1.4, "slope_zeta": 0.9,
}


def heading(dx, dy):
    """yaw that turns the front (-Y) toward (dx, dy)"""
    return math.atan2(dx, -dy)


class WalkerSim:
    def __init__(self, p, ground=None, pos=(0.0, 0.0), yaw=0.0, homes=None, rest_z=1.75):
        self.p = dict(TERRAIN_DEFAULTS, **p)
        self.rest_z = rest_z
        self.ground = ground
        g = ground or (lambda x, y: 0.0)
        self.g = g
        x0 = Vector(pos)
        self.xc, self.ac = x0.copy(), yaw
        self.pos = SOD(p["body_f"], p["body_zeta"], p["body_r"], x0.copy())
        self.turn = SOD(p["turn_f"], p["turn_zeta"], p["turn_r"], yaw)
        self.look = SOD(p["head_f"], p["head_zeta"], p["head_r"], yaw)
        self.lean = SOD(p["tilt_f"], p["tilt_zeta"], p["tilt_r"], Vector((0, 0)))
        self.crouch = SOD(p["crouch_f"], p["crouch_zeta"], 0.0, 0.0)
        self.homes = {n: Vector(h) for n, h in (homes or HOME).items()}
        z0, n0 = self._ground_frame(x0, yaw)
        self.height = SOD(self.p["height_f"], self.p["height_zeta"], 0.0, z0)
        self.slope = SOD(self.p["slope_f"], self.p["slope_zeta"], 0.0, n0.copy())
        self.y, self.y_prev, self.byaw, self.hyaw, self.z = x0.copy(), x0.copy(), yaw, yaw, z0
        self.stepper = walker_steps.Stepper(self.homes, self.root_matrix(), self.p, ground)
        self.drop, self.tilt, self.off, self.n = 0.0, 0.0, Vector((0, 0)), n0

    def _ground_frame(self, y, yaw):
        """root height for the ground under the home spots, and the slope as root-local (dz/dx, dz/dy)"""
        r = Matrix.Rotation(yaw, 3, "Z")
        h = {n: self.g(*(Vector((y.x, y.y, 0)) + r @ Vector((hm.x, hm.y, 0))).xy) for n, hm in self.homes.items()}
        span = 2 * abs(self.homes["FrontR"].x)
        dx = ((h["FrontR"] + h["RearR"]) - (h["FrontL"] + h["RearL"])) / 2 / span
        dy = ((h["RearL"] + h["RearR"]) - (h["FrontL"] + h["FrontR"])) / 2 / span
        return sum(h.values()) / 4, Vector((dx, dy))

    def _height_window(self, y, yaw):
        """root heights that keep every hip SOLE_RANGE from its actual sole, crouch included"""
        r = Matrix.Rotation(yaw, 3, "Z")
        lo, hi = -1e9, 1e9
        for n, f in self.stepper.feet.items():
            hip = Vector((y.x, y.y, 0)) + r @ Vector((HIP[n][0], HIP[n][1], 0))
            flat = (f.pos.xy - hip.xy).length
            vmin = math.sqrt(max(0.0, SOLE_RANGE[0] ** 2 - flat * flat))
            vmax = math.sqrt(max(0.0, SOLE_RANGE[1] ** 2 - flat * flat))
            base = f.pos.z - HIP[n][2] + self.drop    # root z that puts this hip level with its sole
            lo, hi = max(lo, base + vmin), min(hi, base + vmax)
        return lo, hi

    def root_matrix(self):
        return Matrix.Translation((self.y.x, self.y.y, self.z)) @ Matrix.Rotation(self.byaw, 4, "Z")

    def body_rotation(self):
        """RIG-Body's local rotation: the slope tilt, then the lean toward the input (root-local)"""
        s = self.n * self.p["slope_follow"]
        q_slope = Vector((0, 0, 1)).rotation_difference(Vector((-s.x, -s.y, 1)).normalized())
        q_yaw = Quaternion((0, 0, 1), self.byaw)
        if self.off.length > 1e-6:
            q_tilt = Quaternion(Vector((0, 0, 1)).cross(Vector((self.off.x, self.off.y, 0))).normalized(), self.tilt)
        else:
            q_tilt = Quaternion()
        return q_slope @ (q_yaw.inverted() @ q_tilt @ q_yaw)

    def step(self, T, target, yaw_target, look_yaw=None, move=True):
        p = self.p
        x = Vector(target)
        if move:
            d = x - self.xc
            vmax = p["max_speed"] * T
            self.xc = x.copy() if d.length <= vmax else self.xc + d * (vmax / d.length)
        amax = math.radians(p["max_turn_deg_s"]) * T
        da = yaw_target - self.ac
        self.ac = yaw_target if abs(da) <= amax else self.ac + math.copysign(amax, da)
        self.y = self.pos.update(T, self.xc).copy()
        self.byaw = self.turn.update(T, self.ac)
        self.hyaw = self.look.update(T, self.ac if look_yaw is None else look_yaw)
        self.off = self.lean.update(T, self.xc - self.y).copy()
        tmax = math.radians(p["tilt_max_deg"])
        self.tilt = tmax * math.tanh(math.radians(p["tilt_deg_per_m"]) * self.off.length / tmax) if tmax > 0 else 0.0
        vel = self.y - self.y_prev
        speed = vel.length / T
        self.drop = self.crouch.update(T, p["crouch_m"] * min(1.0, speed / max(p["max_speed"], 1e-6)))
        zg, ng = self._ground_frame(self.y, self.byaw)
        z = self.height.update(T, zg)
        lo, hi = self._height_window(self.y, self.byaw)
        self.window = (lo, hi, z)
        z = (lo + hi) / 2 if lo > hi else max(lo, min(hi, z))   # lo > hi: can't satisfy all four; split it
        self.z = self.height.y = z
        self.n = self.slope.update(T, ng).copy()
        feet = self.stepper.update(T, self.root_matrix(), Vector((vel.x, vel.y, 0)) / T)
        # a swinging foot can't lift higher than the folded leg allows (uphill it would jam the hip)
        hips = self.hips_world(self.rest_z)
        for n, fp in feet.items():
            d = fp - hips[n]
            if d.length < SOLE_RANGE[0] and d.z < 0:
                flat = d.xy.length
                if flat < SOLE_RANGE[0]:
                    low = hips[n].z - math.sqrt(SOLE_RANGE[0] ** 2 - flat * flat)
                    fp.z = max(self.g(fp.x, fp.y) + self.homes[n].z, min(fp.z, low))
                    self.stepper.feet[n].pos.z = fp.z
        self.y_prev = self.y.copy()
        return feet

    def hips_world(self, rest_z):
        """hip joints in model space, riding the leaning, crouching, slope-tilted body (for reach checks)"""
        body = (self.root_matrix() @ Matrix.Translation((BODY_PIVOT.x, BODY_PIVOT.y, rest_z - self.drop))
                @ self.body_rotation().to_matrix().to_4x4())
        return {n: body @ (Vector(HIP[n]) - Vector((BODY_PIVOT.x, BODY_PIVOT.y, rest_z))) for n in LEGS}
