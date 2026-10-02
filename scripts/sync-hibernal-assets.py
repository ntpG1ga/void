#!/usr/bin/env python3
"""Copies the hibernal assets the walker scene loads into assets/hibernal/ and packs the pet's
clips into a binary the scene can read without parsing 860 kB of JSON on the phone.

  python3 scripts/sync-hibernal-assets.py [path/to/hibernal]     (default: ../hibernal)

hibernal/assets is the source; rerun after a re-bake. pets/walkerRoamLoops.json, when there, adds
its roamLoop* clips (t3ssel8r-lab walker_clips.py ROAMS=...: closed wanders that all start and end
in one pose). walkerClips.bin, little-endian:
  'WCLP', int32 fps, int32 nodes, int32 clips
  per node:  int32 length, name bytes padded to 4
  per clip:  int32 length, name bytes padded to 4, int32 frames, int32 loop,
             float32[frames * nodes * 7]: per node tx ty tz qx qy qz qw (node local)
"""
import json, os, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "hibernal"))
OUT = os.path.join(ROOT, "assets", "hibernal")
MODELS = [
    "environment/hillsGround.glb",
    "environment/pillars.glb",
    "environment/campfireLogs.glb",
    "pets/walker.glb",
]


def name_bytes(name):
    raw = name.encode("ascii")
    return struct.pack("<i", len(raw)) + raw + b"\0" * (-len(raw) % 4)


def pack_clips(path, loops_path):
    clips = json.load(open(path))
    nodes = clips["nodes"]
    found = dict(clips["clips"])
    if os.path.exists(loops_path):
        loops = json.load(open(loops_path))
        assert loops["nodes"] == nodes and loops["fps"] == clips["fps"], "the loops are of another rig"
        found.update({name: clip for name, clip in loops["clips"].items() if name.startswith("roamLoop")})
    out = [b"WCLP", struct.pack("<iii", clips["fps"], len(nodes), len(found))]
    for node in nodes:
        out.append(name_bytes(node))
    for name, clip in found.items():
        frames = clip["data"]
        assert len(frames) == clip["frames"] and all(len(f) == len(nodes) * 7 for f in frames), name
        out.append(name_bytes(name))
        out.append(struct.pack("<ii", len(frames), 1 if clip["loop"] else 0))
        for frame in frames:
            out.append(struct.pack("<%df" % len(frame), *frame))
    return b"".join(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    for model in MODELS:
        shutil.copyfile(os.path.join(SOURCE, "assets", model), os.path.join(OUT, os.path.basename(model)))
    packed = pack_clips(os.path.join(SOURCE, "assets", "pets", "walkerClips.json"),
                        os.path.join(SOURCE, "assets", "pets", "walkerRoamLoops.json"))
    with open(os.path.join(OUT, "walkerClips.bin"), "wb") as f:
        f.write(packed)
    graph = os.path.join(SOURCE, "assets", "pets", "walkerGraph.bin")
    if os.path.exists(graph):     # t3ssel8r-lab walker_clips.py GRAPH=1: the walker's motion graph
        shutil.copyfile(graph, os.path.join(OUT, "walkerGraph.bin"))
    for name in sorted(os.listdir(OUT)):
        print("%9d  assets/hibernal/%s" % (os.path.getsize(os.path.join(OUT, name)), name))


main()
