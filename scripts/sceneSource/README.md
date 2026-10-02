# Grass lab scene sources

A copy of what the grass lab's generated data is built from, so the scene can be rebuilt without
`~/projects/t3ssel8r-lab` (4 GB, not under git). The layout mirrors t3ssel8r-lab (`scripts/`,
`assets/`, `out/walker/`), so the scripts' `ROOT = parent of scripts/` paths still resolve here.
Copied 2026-10-02; the originals in t3ssel8r-lab stay the working copies.

| Output | Built by | Inputs |
|---|---|---|
| `assets/grassLab/*` (terrain, clumps, pillars, fire, walker path) | `grassExport/export_wide.py` in Blender | `scripts/grass_lab.py`, `assets/flame_strip.png`; writes `grassExport/pillars.json` |
| `scene_pillars.blend` | `grassExport/save_scene_blend.py` | same scene |
| walker motion graph (`walker_graph.json` + `.blend`) | `scripts/walker_graph.py` (Blender) | `grass_lab.py`, `walker_dynamics.py`, `walker_sim.py`, `walker_steps.py`, `out/walker/walker_v2_legs.blend`, `pillars.json` |
| `walkerGraph.bin`, `walker.glb`, clips | `scripts/walker_clips.py` with `GRAPH=1` (Blender) | the graph above, `walker_dynamics.py`, `scripts/hibernal/hillsScene.py`, hibernal `assets/environment/hillsGround.glb` |
| `plants.gltf/.bin`, `plant_leaves.f32` | `../make-plants.py` | `assets/trees/broadleaf/parts/*.glb` (Tripo) |
| grass atlases, `ramps.rgba` | `../make-grass-atlas.py` | the exported `assets/grassLab` data; re-run after every export |

Not copied: `out/walker/walker_graph.blend` (11.7 MB, `walker_graph.py` writes it again).

Path caveats:
- `export_wide.py` sets `ROOT` and `DATA` to hard-coded `\\wsl.localhost\...` paths, because Blender
  runs as the Windows build:
  `LAB_TERRAIN=hills WSLENV=LAB_TERRAIN "<blender.exe>" -b --factory-startup -P "$(wslpath -w export_wide.py)"`.
  Point `ROOT` at this folder to build from the copy, then copy `DATA` into `assets/grassLab/`.
- `make-plants.py` reads the tree models from t3ssel8r-lab (`LAB`); the same files are under `assets/trees/` here.
- `walker_graph.py` reads `pillars.json` from `void-touch/out/grassExport` unless `GRAPH_PILLARS` is set.

Changing the terrain or pillars inside the walker's area means re-baking the graph: the walks are baked
paths with no avoidance.
