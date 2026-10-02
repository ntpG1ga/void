"""Foot placement for the walker (step 3). Imported by walker_dynamics.py; not run on its own.

Each foot stays planted in world space and steps when it drifts more than step_threshold from its
home spot (the rest pose, carried along by the root). It lands ahead of home by the body velocity
times step_lead_s, so while moving a foot that is still ahead of home does not count as drifted -
otherwise a fast foot would lift again the moment it landed. (Measuring from the landing spot instead
follows every wobble of the velocity and made the robot tap-dance on a twitchy target.)
A foot also stays down at least 0.75 * step_time, so the other pair gets its turn.
ground(x, y) (optional) gives the terrain height: soles land on it and swing between the heights.

gait_pairs = 1 (default): diagonal pairs (FrontL+RearR, FrontR+RearL) swing together and a pair only
lifts while the other pair is planted - a trot. Letting each foot decide alone (gait_pairs = 0) jams at
speed: neighbours block each other until the step_panic rule fires, which walker_sweep.py measured
as broken rhythm in 7-19% of frames for every parameter set it tried.
A foot/pair past step_panic ignores the wait; once the body is still, feet more than step_tidy
(default 0.04) off their spot tidy up.
"""
import math
from mathutils import Vector

NEIGHBOURS = {"FrontL": ("FrontR", "RearL"), "FrontR": ("FrontL", "RearR"),
              "RearL": ("FrontL", "RearR"), "RearR": ("FrontR", "RearL")}
PAIRS = (("FrontL", "RearR"), ("FrontR", "RearL"))


class Foot:
    def __init__(self, name, home_local, pos):
        self.name, self.home, self.pos = name, home_local.copy(), pos.copy()
        self.stepping, self.t, self.start = False, 0.0, pos.copy()
        self.landed = -1e9


class Stepper:
    def __init__(self, homes, root_matrix, p, ground=None):
        self.p, self.ground = p, ground
        self.feet = {n: Foot(n, h, self._on_ground(root_matrix @ h, h)) for n, h in homes.items()}
        self.vel = Vector((0, 0, 0))
        self.still = 0.0
        self.time = 0.0

    def _on_ground(self, p, home_local):
        if self.ground is not None:
            p.z = self.ground(p.x, p.y) + home_local.z
        return p

    def _landing(self, foot, root_matrix):
        home = self._on_ground(root_matrix @ foot.home, foot.home)
        lead = self.vel * self.p["step_lead_s"]
        lead.z = 0
        if lead.length > self.p["step_max_lead"]:
            lead *= self.p["step_max_lead"] / lead.length
        return home, self._on_ground(home + lead, foot.home)

    def _lift(self, names):
        for n in names:
            f = self.feet[n]
            f.stepping, f.t, f.start = True, 0.0, f.pos.copy()

    def update(self, T, root_matrix, vel):
        p = self.p
        self.time += T
        self.vel = self.vel.lerp(vel, min(1.0, T * 12))  # light smoothing so one spiky frame can't fling a foot
        self.still = self.still + T if self.vel.length < 0.15 else 0.0
        swinging = {n for n, f in self.feet.items() if f.stepping}

        drift = {}
        for n, f in self.feet.items():
            home, _ = self._landing(f, root_matrix)
            d = f.pos - home
            d.z = 0
            ahead = self.vel.length > 0.15 and d.dot(self.vel.normalized()) > 0
            drift[n] = 0.0 if ahead and d.length < p["step_panic"] else d.length

        if p.get("gait_pairs", 1) >= 0.5:
            for pair in sorted(PAIRS, key=lambda pr: -max(drift[n] for n in pr)):
                if any(n in swinging for n in pair):
                    continue
                worst = max(drift[n] for n in pair)
                panic = worst > p["step_panic"]
                tidy = self.still > 0.2 and worst > p.get("step_tidy", 0.04)
                other_down = not swinging
                rested = all(self.time - self.feet[n].landed >= 0.75 * p["step_time"] for n in pair)
                if (worst > p["step_threshold"] or tidy or panic) and ((other_down and rested) or panic):
                    self._lift(pair)
                    swinging.update(pair)
        else:
            for n in sorted(self.feet, key=lambda n: -drift[n]):
                f = self.feet[n]
                if f.stepping:
                    continue
                panic = drift[n] > p["step_panic"]
                tidy = self.still > 0.2 and drift[n] > p.get("step_tidy", 0.04)
                if (drift[n] > p["step_threshold"] or tidy or panic) and \
                        (panic or not any(m in swinging for m in NEIGHBOURS[n])) and \
                        (not tidy or not swinging or drift[n] > p["step_threshold"]):
                    self._lift([n])
                    swinging.add(n)

        for f in self.feet.values():
            if not f.stepping:
                continue
            _, land = self._landing(f, root_matrix)   # re-aim every frame so the foot tracks the body
            f.t = min(1.0, f.t + T / p["step_time"])
            s = f.t * f.t * (3 - 2 * f.t)
            reach = (land - f.start).length
            h = p["step_height"] * min(1.0, 0.4 + reach)
            f.pos = f.start.lerp(land, s)
            f.pos.z = f.start.z + (land.z - f.start.z) * s + h * math.sin(math.pi * f.t)
            if self.ground is not None:   # never dip into a hump between the two spots
                f.pos.z = max(f.pos.z, self.ground(f.pos.x, f.pos.y) + f.home.z)
            if f.t >= 1.0:
                f.pos, f.stepping, f.landed = land.copy(), False, self.time
        return {n: f.pos.copy() for n, f in self.feet.items()}
