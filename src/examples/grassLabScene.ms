// The grass lab (scripts/grass_lab.py, t3ssel8r's night campfire) running live on void's
// pixel-art preset: the scene is out/grass_lab/void/data, written by export_void.py.
//
// What void does here is the whole David Holland / t3ssel8r pipeline: a 640x360 low-res
// target, toon light (a moon cut at one threshold, the fire cut into LIGHT_LEVELS bands), the
// outline pass from depth + normal edges, the lab's ramps as a palette LUT, and the camera
// snapped to the texel grid with the remainder handed to the upscale blit, so the frame pans
// smoothly while every texel stays on its patch of world. The grass is the lab's world-rooted
// clumps as camera-facing billboards, each one colour: the light at its root.
//
// This is t3ssel8r-lab/out/grass_lab/void/grassLab.ms moved into void-touch: the entries are
// mainGrassLab.ms (desktop, portrait) and androidGrassLabEntry.ms, the data is assets/grassLab/
// (the lab's data_hills/), the clock is the host's, the walker is on by default, the camera
// stands still zoomed out to the walker's whole roam, and the vignette is off. It needs the lab's void.patch, applied here.
//
// Three looks: the default colours by the lab's ramps (void's LitRamp / BillboardRamp programs,
// the grass lab's shade() on the GPU); LAB_RAMP 0 lights with void's toon programs and the lab's
// parameters on them; LAB_SHADER 0 is the toon programs with those parameters off.
//
// Env: LAB_RAMP 0 / LAB_SHADER 0 as above, LAB_WALKER 0 removes the lab's walker across the
// lawn, LAB_SNOW 1 turns the snow on, LAB_PARTICLES 0 turns off it and the embers (the campfire example's), LAB_WALLS 0 lights walls per texel (the lab's stripes) instead of one colour a face, LAB_ZOOM 125 zooms out 1.25x, LAB_WIND 0 stills the grass,
// LAB_PAN texels per 100 frames the camera slides (default 0, still; 40 shows every sub-texel offset), LAB_SNAP 0 turns the snap off,
// LAB_PALETTE 0/1 (default: off for the ramp look, on for the toon looks), LAB_OUTLINE 0, LAB_CAPTURE N saves frames N, N+30 and N+60
// to shots/ as PPM (ppm2png.py) and exits.

import { gfxSetup, fbWidth, fbHeight } from "../sokol/gpu";
import {
	LIGHT_UNIFORM_LENGTH,
	TOON_UNIFORM_SLOT,
	TOON_UNIFORM_LENGTH,
	RAMP_UNIFORM_SLOT,
	RAMP_UNIFORM_LENGTH,
	SPRITE_RAMP_UNIFORM_LENGTH,
	SPRITE_UNIFORM_SLOT,
	SPRITE_UNIFORM_LENGTH,
	Program,
	VertexLayout,
	Filter,
	Wrap,
	makeVertexBuffer,
	makeImage,
	makeTextureView,
	originTopLeft,
} from "../void3d/gpu3d";
import { RenderState, Face, Compare } from "../void3d/pass";
import { Material, Phase, UniformBlock, NO_UNIFORMS } from "../void3d/material";
import { Sampler } from "../void3d/target";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshUploadError,
	addMesh,
	addMeshData,
	addMaterial,
	StreamError,
	addStreamMesh,
	writeStream,
	reserveUniforms,
	writeUniforms,
} from "../void3d/draw";
import { LowResView, ViewError } from "../void3d/blit";
import { PaletteError } from "../void3d/palette";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtError,
	PixelArtLook,
	PIXEL_ART_UNIFORM_LENGTH,
	GLOW_LENGTH,
	setGlow,
	setPalette,
	setSettings,
	renderFrame,
} from "../void3d/pixelArtRenderer";
import { Vec3, vec3, Vec4, vec4, Mat4, Quat, quatBetween } from "../math/math3d";
import { sinf, cosf } from "../math/mat4";
import { MeshData, MeshError, Box, addBox, LIT_VERTEX_STRIDE } from "../void3d/meshData";
import { float32At } from "../void3d/gltfDecode";
import {
	Scene,
	NodeId,
	SceneError,
	LightError,
	LightKind,
	identityTransform,
	transformAt,
	addMeshNode,
	addLightNode,
	setLocal,
	setMeshOf,
	setVisible,
	setLightPower,
	setAmbient,
	collectLights,
	refresh,
	syncWorld,
} from "../void3d/scene";
import { OrthoCamera, CameraView, CameraError, CAMERA_BLOCK_LENGTH } from "../void3d/camera";
import { GltfData, GltfError, loadGltf } from "../void3d/gltf";
import { GltfMeshBinding, GltfSceneError, addGltfNodes } from "../void3d/gltfScene";
import {
	EmitterState,
	ParticleEmitter,
	ParticleError,
	ShapeKind,
	ValueKind,
	Converge,
	PARTICLE_INSTANCE_STRIDE,
	constant,
	updateEmitter,
	writeInstances,
} from "../void3d/particles";
import { readFile } from "std/fs";
import {
	labFileSize,
	labEnvInt,
	labCapture,
	labExit,
} from "./labio.h";
import { initHudHome, frameHudHome } from "./hudHome";
import { skipNextCommit } from "../sokol/gpu";

@include("../sokol/bridge.h");
// Declared here rather than imported: a Span parameter is what msc lowers to C's pointer + length.
extern function labReadFloats(out: Span<float32>, path: cstring): int64;
extern function labReadWords(out: Span<uint32>, path: cstring): int64;

// Relative to the asset root: the repo on the desktop, the extracted APK assets on Android.
const DATA: string = "assets/grassLab/";

// The lab's frame: 20 m across 640 px, so 11.25 m on the 360 px short side; the camera 45 deg
// round (from the south-east) and 30 deg down.
const UNITS_ON_SHORT_SIDE: float32 = 11.25;
const CAMERA_YAW: float32 = 0.785398;
const CAMERA_PITCH: float32 = 0.523599;
const TARGET_HEIGHT: float32 = 1.2;
// The camera stands still on the fire. The walker's roam reaches 6 m to either side of it on
// screen, so the portrait frame is zoomed out to 15.5 m across (LAB_ZOOM, percent of the lab's).
const DEFAULT_ZOOM: int32 = 138;

// Heights above the ground under the fire (data/fire.f32: 0 on the lab's lawn, 0.5 m down in the hills).
const FIRE_HEIGHT: float32 = 1.0;
const FIRE_POWER: float32 = 1.7;
const FIRE_RADIUS: float32 = 9.0;
const LIGHT_LEVELS: float32 = 7.0;
const FLICKER_EVERY: int32 = 5;          // frames per flicker step (12 fps at 60)
const FLAME_EVERY: int32 = 5;
const FLAME_FRAMES: int32 = 6;           // flame_strip.png: frames 0-3 in one atlas, 4-5 in another
// The flame rises from inside the kindling: its foot at FLAME_ROOT, below the logs' tops
// (~0.8 m), and its card slid FLAME_TOWARD_CAMERA along the view, which leaves it where it is on
// screen (the camera is orthographic) but puts it in front of the pile's middle. Depth-tested,
// so the logs that reach further out in front hide its foot, and a walker or stone in front of
// the fire hides it.
const FLAME_ROOT: float32 = 0.6;
const FLAME_TOWARD_CAMERA: float32 = 0.3;

const SHORT_CELL_W: int32 = 22;          // scripts/make-grass-atlas.py: broad-leaf rosettes
const SHORT_CELL_H: int32 = 22;
const TALL_CELL_W: int32 = 28;
const TALL_CELL_H: int32 = 28;
const FLAME_CELL_W: int32 = 20;
const FLAME_CELL_H: int32 = 28;
const INSTANCE_STRIDE: int32 = 8;

// The toon shader lights grass as base * (ambient + moon) + fire; the clumps are
// grassColor * tint + fire, so grassColor is the ground's base times the same ambient + moon.
const AMBIENT_R: float32 = 0.26;
const AMBIENT_G: float32 = 0.30;
const AMBIENT_B: float32 = 0.52;
const MOON_POWER: float32 = 0.18;
const GRASS_R: float32 = 0.22;
const GRASS_G: float32 = 0.30;
const GRASS_B: float32 = 0.52;
// The lab's GRASS_WRAP: the lawn takes this share of the firelight whatever its normal, and
// the clumps the same (as a surface facing up, weighted by the rest, sampled at the root).
const GRASS_WRAP: float32 = 0.75;
const WIND_SWAY: float32 = 0.09;         // m at a clump's top in a full gust, ~3 texels

// The ramp look: scripts/grass_lab.py's numbers. Rows of data/ramps.rgba (export_void.py
// RAMP_ROWS); 3 night steps, then 16 fire bands from 0.05 in steps of 0.058; the fire's falloff
// to FIRE_R raised to FIRE_FALL; moon bands at n.l 0.35 and 0.75; the banded vignette.
const ROW_GRASS: float32 = 0.0;
const ROW_STONE: float32 = 1.0;
const ROW_TOP: float32 = 2.0;
const ROW_WOOD: float32 = 3.0;
const RAMP_WIDTH: int32 = 19;
const RAMP_ROWS: int32 = 8;
const ROW_LEAF: float32 = 7.0;          // make-grass-atlas.py: the crowns' teal night to autumn red
const ROW_FLOWER: float32 = 6.0;        // scripts/make-grass-atlas.py flower_ramp: pale blue to cream
const ROW_LENS: float32 = 5.0;          // export_void.py LENS_ROW: the walker's lens, one red
const NIGHT_STEPS: float32 = 3.0;
const FIRE_BANDS: float32 = 16.0;
const FIRST_BAND: float32 = 0.05;
const BAND_STEP: float32 = 0.058;
// Wider than the lab's 7.5 m: in the video the firelit grass reaches about as far again as the
// pillars round the fire.
// 16 (user, 2026-10-02, was 11 then 13): with the log falloff, a longer faint tail.
const LAB_FIRE_R: float32 = 16.0;
// Negative: the eye's falloff, full within this many metres and linear in log distance out to
// LAB_FIRE_R (shader3d.glsl fallShape; user, 2026-10-02: a small fire lit too much ground evenly
// with the linear 1.0). LAB_FALL in centimetres overrides it.
let LAB_FIRE_FALL: float32 = -0.7;
// 1.1: flat grass sits a moon step down (slopeSteps), which took a band off the firelight too
// (1.0 with GRASS_PATCHES, whose CLUMP_LIFT gives that step back).
const LAB_FIRE_GAIN: float32 = 1.1;
const MOON_CUT_1: float32 = 0.35;
const MOON_CUT_2: float32 = 0.75;
const VIGNETTE_1: float32 = 0.55;
const VIGNETTE_2: float32 = 0.72;
const VIGNETTE_3: float32 = 0.9;
// The firelight's faint tail, times its radius: 2.0 spread its first warm steps in spots over
// the dark; 1.5 keeps them a rim round the lit ground.
const TAIL_REACH: float32 = 2.0;
// The tall grass's own steps over the lawn (was 1; 0: one colour).
const TALL_STEPS: float32 = 0.0;
const TAIL_ENERGY: float32 = 0.4;
// The lawn and its short grass take a fainter tail: their light fades a step at a time instead of
// stopping where the core does (the long grass round them kept glowing and the edge read as a cliff).
const LAWN_TAIL_ENERGY: float32 = 0.25;
const WALL_GAIN: float32 = 2.5;
// 0 (user, 2026-10-02): the clumps carry their slope's moon steps (slopeSteps), which the quiet
// dark would have reset to 0.
const QUIET_SHORT_GRASS: float32 = 0.0;
// The tall grass too: out of the firelight it drops its step over the lawn, one tone in the dark.
const QUIET_TALL_GRASS: float32 = 0.0;
const UNIFORM_CLUMPS: boolean = true;
// The lab's frame, 20 m over 640 px: a sprite texel is this many metres before the zoom.
const LAB_METRES_PER_TEXEL: float32 = 0.03125;
const FIRE_GRASS_CLEAR: float32 = 1.4;
const SHORT_KEEP: float32 = 0.18;
const TALL_KEEP: float32 = 0.22;

function fractOf(v: float32): float32 {
	return v - (Math.floor(v) as float32);
}
// The ground between the blades: level with the short grass, so no ground shows anywhere (user,
// 2026-10-01). The blades read through their lighter tips (TIP_SHARE) instead of darker gaps.
// -1 with GRASS_PATCHES (also the fog and fire gain above, see out/tools/grassLabScene.with_patches.ms): the bare ground between the patches a step under the grass, so a
// patch's edge shows (0 when the grass covered everything).
const LAWN_STEPS: float32 = 0.0;
// Off: each vignette ring takes a ramp step off, and away from the fire the grass has only its
// three night steps, so under the rings the lawn and its clumps all land on the darkest one and
// the grass reads as bare ground. 1.0 is the lab's look.
const VIGNETTE_ON: float32 = 0.0;

// Past the video (VEP4INri_1U), per material (shader3d.glsl rampFar): x the far tail's reach in
// light radii, y its energy at the fire, z a wall's gain on the firelight, w > 0.5 a clump shows
// its own steps only in firelight.
// - Stones: the video's pillars facing the fire are lit near the top of the ramp; at their
//   origin, 4.5-5.5 m out, the lab's falloff leaves 0.15-0.25 of the light, two or three bands.
// - Long grass and stones take the dim magenta tail (the lab measured ~2.6x the core radius): in
//   the video the far long-grass patches glow pink while the lawn round them stays blue.
// - Short grass: in the video the dark lawn is flat, its clumps a fringe at the light's edge.
// After Dylearn's grass (youtube OxsuWDtjuGw), the four after the far values (shader3d.glsl
// rampPatch): colour patches from world-space noise, PATCH_CELL metres, a step down below
// PATCH_LOW and up above PATCH_HIGH, on the lawn and its grass alike so a clump is the colour of
// the patch it stands in and a patch's edge is ragged with blades; and his hybrid toon shading,
// HYBRID of a band blending into the next at every cut. Sprites take four more (spriteAccent):
// a share of the short grass stands ACCENT_HEIGHT taller and ACCENT_STEPS lighter.
// One colour for every leaf (user, 2026-10-02): only the light changes it, so no patches (cell
// 0), no lighter accents, no step for the tall grass or the lawn's long-grass marks.
const PATCH_CELL: float32 = 0.0;
const PATCH_LOW: float32 = 0.36;
const PATCH_HIGH: float32 = 0.66;
const HYBRID: float32 = 0.5;
// The clumps take no blend and no per-clump light jitter: each rosette is one colour, and with
// the in-between colours of the blend and the jitter neighbouring rosettes all differed a little,
// so where leaves overlap (and through the gaps between a rosette's leaves) the grass broke up
// into a mosaic (user, 2026-10-01). Clumps in one band now share one colour and merge.
const SPRITE_HYBRID: float32 = 0.0;
// and the clumps take the fire's 16 bands two at a time, so a band is wider than a rosette.
// (user, 2026-10-02: every band, finer light steps, now that all clumps are one colour)
const CLUMP_BAND_MERGE: float32 = 1.0;
// Each clump turned up to this many radians either way and half of them mirrored (shader3d.glsl).
const CLUMP_SPIN: float32 = 0.1047;   // 6 degrees (user: clumps stand straighter; was 15)
const ACCENT_SHARE: float32 = 0.05;
const ACCENT_HEIGHT: float32 = 1.6;
const ACCENT_STEPS: float32 = 0.0;
const TIP_SHARE: float32 = 0.0;
const NO_FAR: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, HYBRID, 0.0, 0.0, 0.0, 0.0];
// The lawn shows through the gaps between leaves, so it is drawn exactly as the short grass is
// (same merged bands, no blend): a region of grass is one colour, with leaves only at its edges,
// as in Dylearn's grass (user, 2026-10-01).
const LAWN_FAR: Vec<float32> = [TAIL_REACH, LAWN_TAIL_ENERGY, 0.0, 1.0, PATCH_CELL, PATCH_LOW, PATCH_HIGH, SPRITE_HYBRID];
const STONE_FAR: Vec<float32> = [TAIL_REACH, TAIL_ENERGY, WALL_GAIN, 1.0, 0.0, 0.0, 0.0, HYBRID];
const TALL_FAR: Vec<float32> = [TAIL_REACH, TAIL_ENERGY, 0.0, QUIET_TALL_GRASS, PATCH_CELL, PATCH_LOW, PATCH_HIGH, SPRITE_HYBRID, 0.0, 0.0, 0.0, TIP_SHARE];
const SHORT_FAR: Vec<float32> = [TAIL_REACH, LAWN_TAIL_ENERGY, 0.0, QUIET_SHORT_GRASS, PATCH_CELL, PATCH_LOW, PATCH_HIGH, SPRITE_HYBRID,
	ACCENT_SHARE, ACCENT_HEIGHT, ACCENT_STEPS, TIP_SHARE];
// A firelit wall takes the light at its object's origin: one colour per face (LAB_WALLS 0: per
// texel, the lab's stripes).
let WALLS_AT_ORIGIN: float32 = 1.0;
const TALL_MARK: float32 = 0.0;    // off (one colour); export_void.py: ground vertex red above 0.24 is long grass
const TALL_MARK_UNUSED: float32 = 0.24;         // export_void.py: ground vertex red above this is long grass
const BLADE_JITTER: float32 = 0.0;       // the lab's BLADE_LIGHT_JITTER (0.012, a sigma) as a range
const TINT_PER_STEP: float32 = 0.11;     // toon looks: a clump's ramp steps as a tint
const ROW_TUFT: float32 = 4.0;
const TUFT_STEPS: float32 = 2.0;         // the lab's pale tufts: two steps up the tuft ramp
const TUFT_CELL_W: int32 = 8;
const TUFT_CELL_H: int32 = 7;
// Pale sprigs (user, 2026-10-02), hibernal's broadleafSprig: five pointed leaves fanned up
// (atlas_flower, 15x12 cells), standing alone and spaced, the grass cleared round each so it
// shows. One at most a FLOWER_CELL metre cell, in a FLOWER_SHARE of the cells, on the short
// grass root of that cell with the lowest hash; no clump within FLOWER_CLEAR of one.
// Off (user, 2026-10-02: not these); kept for a later look.
const SPRIGS_WANTED: boolean = false;
const FLOWER_CELL_W: int32 = 15;
const FLOWER_CELL_H: int32 = 12;
const FLOWER_CELL: float32 = 1.6;
const FLOWER_SHARE: float32 = 0.28;
const FLOWER_CLEAR: float32 = 0.75;
const FLOWER_STEPS: float32 = 0.0;
const FLOWER_SWAY: float32 = 0.4;
// The sprig grid over the 60 m map: per cell the chosen root (x, y, z) and its hash (2: none).
const FLOWER_GRID: int32 = 40;
const FLOWER_ORIGIN: float32 = -32.0;
const sprigAt: Vec<float32> = new Array(FLOWER_GRID * FLOWER_GRID * 4);

// The lab's wind (Dylearn's): blowing to screen right and away, two noises +-20 deg apart,
// 3.2 m cells at 2.4 m/s, gust = clamp(n1 * n2 * 3.2 - 0.25); 3 texels at a full gust, 0.55 of
// idle wiggle at 0.7 Hz, 8 poses a second, 0.3 of fake perspective; long grass sways fully,
// short grass half. The walker: 1.2 m reach, pushes 4 texels, flattens 55%, 12 positions a
// second over a 4 s loop. The fire: its reach breathes with flicker_at over the same loop.
const WIND_RIGHT: float32 = 0.85;
const WIND_AWAY: float32 = 0.5;
const WIND_SPREAD: float32 = 0.349066;
const WIND_CELL: float32 = 3.2;
const WIND_SPEED: float32 = 2.4;
const WIND_GAIN: float32 = 3.2;
const WIND_BIAS: float32 = -0.25;
const WIND_TEXELS: float32 = 3.0;
const WIGGLE_TEXELS: float32 = 0.55;
const WIGGLE_HZ: float32 = 0.7;
const WIND_POSES: float32 = 8.0;
const WIND_PERSP: float32 = 0.3;
const TALL_SWAY: float32 = 1.0;
const SHORT_SWAY: float32 = 0.5;
const WALKER_REACH: float32 = 1.2;
const WALKER_EXP: float32 = 1.0;
const WALKER_TEXELS: float32 = 4.0;
const WALKER_FLAT: float32 = 0.55;
const WALKER_FPS: float32 = 12.0;
const LOOP_SECONDS: float32 = 4.0;
// The fire's breathing runs over twice the lab's loop: the user found 4 s too quick (2026-10-01).
// The stones do not breathe at all (walls take LAB_FIRE_R, shader3d.glsl rampFire).
const FLICKER_LOOP_SECONDS: float32 = 8.0;
const FRAMES_PER_SECOND: float32 = 60.0;

const RANDOM_MULTIPLIER: uint64 = 6364136223846793005;
const RANDOM_INCREMENT: uint64 = 1442695040888963407;
const RANDOM_RANGE: float32 = 16777216.0;

const CORNERS: Vec<float32> = [
	-0.5, 0.0, 0.5, 0.0, 0.5, 1.0,
	-0.5, 0.0, 0.5, 1.0, -0.5, 1.0,
];

const MATERIAL_UNIFORM_LENGTH: int32 =
	3 * TOON_UNIFORM_LENGTH + 4 * SPRITE_UNIFORM_LENGTH + 6 * RAMP_UNIFORM_LENGTH + 5 * SPRITE_RAMP_UNIFORM_LENGTH;
let context: DrawContext = DrawContext.withUniformCapacity(
	PIXEL_ART_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH,
);
let renderer: PixelArtRenderer = makeRenderer();
let tree: Scene = Scene.create();
const sceneItems: Vec<DrawItem> = [];
const lightParams: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
const cameraParams: Vec<float32> = new Array(CAMERA_BLOCK_LENGTH);
let fireLight: NodeId = { index: -1, generation: 0 };
// The flame: two nodes, one per atlas (frames 0-3, 4-5), one shown at a time.
let flameNode: NodeId = { index: -1, generation: 0 };
let flameNode2: NodeId = { index: -1, generation: 0 };
let firstFlameMesh: int32 = 0;
// The lab counts frames of a 60 fps clock. Here the count follows the host clock, so the scene
// keeps its pace on a phone drawing 30 fps; a capture run (LAB_CAPTURE) still counts frames.
let frameIndex: int32 = 0;
let previousIndex: int32 = -1;
let labSeconds: float64 = 0.0;
let lastFrameAt: float64 = -1.0;
const LONGEST_FRAME_SECONDS: float64 = 0.25;

let randomState: uint64 = 88172645463325252;
let ready: boolean = false;
let fireGround: float32 = 0.0;

let panPer100: int32 = 0;
let snapWanted: boolean = true;
let captureAt: int32 = -1;
// LAB_ZOOM: percent of the lab's view (125: out to 1.25x, the widest the game camera goes).
let zoomOut: float32 = 1.0;
let windWanted: boolean = true;
// LAB_SHADER 0: the lab's shader parameters all at 0 (plain toon light, sprites lit a quarter
// unit up from every side, no wind) - the look before void's shader gained them.
let labShader: float32 = 1.0;
let rampLook: boolean = true;
let walkerWanted: boolean = false;
// The sprite blocks rewritten every frame (the walker moves, the texel size can change).
const spriteBlocks: Vec<UniformBlock> = [];
const spriteSettings: Vec<Vec<float32>> = [];
let walkerPath: Vec<float32> = [];
let walkerNode: NodeId = { index: -1, generation: 0 };
let windDirX: float32 = 0.0;
let windDirZ: float32 = 0.0;
let walkerX: float32 = 1000.0;
let walkerZ: float32 = 1000.0;
// The walker is hibernal's pet (assets/hibernal/walker.glb, 12 rigid nodes) playing baked wanders:
// per WALKER_FPS frame every node's local position and rotation (WALKER_POSE floats a node), baked
// on these hills. The roamLoop clips are closed wanders played one after another in random order;
// a file without them plays roamHills, which jumps when it restarts. Without the glb, the lab's box.
const WALKER_POSE: int32 = 7;
const WALKER_LENS: string = "lens";
const WALKER_DIR: string = "assets/hibernal/";
const WALKER_CLIP: string = "roamHills";
const WALKER_LOOPS: string = "roamLoop";
// The roam clips in walkerAnim: where each starts and how many frames it has; the one playing
// and the scene time it started at.
const loopFirst: Vec<int32> = [];
// With a motion graph, each walk's station of departure and arrival (walkerGraph.bin).
const walkFrom: Vec<int32> = [];
const walkTo: Vec<int32> = [];
const loopFrames: Vec<int32> = [];
let loopNow: int32 = 0;
let loopStartedAt: float32 = 0.0;
const walkerParts: Vec<NodeId> = [];
const walkerAnim: Vec<float32> = [];

// The snow and embers of void's campfire (src/examples/campfireScene.ms, M11),
// its emitters unchanged. Stepped at 1/30 s every other frame, as its 30 fps clock, and run for
// fourteen seconds at setup so snow is already falling in the first frame. The embers rise from
// the flame's foot. The snow's disc is the campfire's widened and slid towards the camera: seen
// 30 deg down, flakes at SNOW_HEIGHT land on the upper part of the frame, and the campfire's
// 13 m disc round the fire left the foreground bare. Its rate grows with its area, so the
// density is the campfire's.
const PARTICLE_STEP: float64 = 1.0 / 30.0;
const PARTICLE_EVERY: int32 = 2;
const PARTICLE_WARMUP_STEPS: int32 = 420;
const SNOW_SEED: uint32 = 12345;
const EMBER_SEED: uint32 = 777;
const SNOW_HEIGHT: float32 = 10.0;
const SNOW_RADIUS: float32 = 18.0;
// From 10 m, not the campfire's 6, at its fall (gravity 0.15-0.3, so 0.5 g t^2): the slowest
// flake needs ~11.5 s to land and fades out at 90% of its life, hence 13 s, and room for the
// ~1120 flakes that makes (86/s). The warm-up covers one whole life.
const SNOW_LIFE: float32 = 13.0;
const SNOW_TOWARD_CAMERA: float32 = 6.0;
const EMBER_HEIGHT: float32 = FLAME_ROOT;
let particlesWanted: boolean = false;
// Off unless LAB_SNOW 1: the embers alone are the default.
let snowWanted: boolean = false;
let snow: ParticleEmitter = emitterOf(snowState(), SNOW_SEED);
let embers: ParticleEmitter = emitterOf(emberState(), EMBER_SEED);
let snowNode: NodeId = { index: -1, generation: 0 };
let emberNode: NodeId = { index: -1, generation: 0 };
let snowMesh: int32 = 0;
let emberMesh: int32 = 0;
const snowInstances: Vec<float32> = new Array(snowState().maxParts * PARTICLE_INSTANCE_STRIDE);
const emberInstances: Vec<float32> = new Array(emberState().maxParts * PARTICLE_INSTANCE_STRIDE);

function snowState(): EmitterState {
	return {
		...EmitterState.defaults(),
		emitRate: constant(86.0),
		maxParts: 1200,
		shape: { kind: ShapeKind.Disc, radius: constant(SNOW_RADIUS) },
		life: constant(SNOW_LIFE),
		size: constant(0.07),
		speed: constant(0.0),
		gravity: { kind: ValueKind.Random, start: 0.15, length: 0.15, converge: Converge.No },
		force: { x: constant(0.08), y: constant(0.0), z: constant(0.0) },
		colors: [{ time: 0.0, color: 0xE6ECFF }],
		alpha: { kind: ValueKind.Linear, start: 1.4, length: -1.0 },
	};
}

function emberState(): EmitterState {
	return {
		...EmitterState.defaults(),
		emitRate: constant(10.0),
		maxParts: 48,
		shape: { kind: ShapeKind.Cone, radius: constant(0.12), angle: constant(0.5) },
		life: { kind: ValueKind.Random, start: 1.0, length: 1.0, converge: Converge.No },
		size: constant(0.08),
		speed: { kind: ValueKind.Random, start: 0.5, length: 0.5, converge: Converge.No },
		gravity: constant(-0.4),
		force: { x: constant(0.1), y: constant(0.0), z: constant(0.0) },
		colors: [
			{ time: 0.0, color: 0xFFE070 },
			{ time: 0.4, color: 0xFF7A20 },
			{ time: 1.0, color: 0x9A2A10 },
		],
		alpha: { kind: ValueKind.Linear, start: 1.5, length: -1.2 },
	};
}

function emitterOf(state: EmitterState, seed: uint32): ParticleEmitter {
	const made: Result<ParticleEmitter, ParticleError> = ParticleEmitter.create(state, seed);
	if (made.ok) { return made.value; }
	unreachable;
}

// Far darkening; the patches trial used 0.47 / 0.66 / 0.65 (user preferred this one).
const FOG_START: float32 = 0.5;
const FOG_END: float32 = 0.75;
const FOG_STRENGTH: float32 = 0.45;

// The firelight in a thin fog (shader3d.glsl fireGlow): the fog the fire lights between the
// camera and whatever a pixel shows, so the light hangs in the air round the flame and a pillar
// in front of it stands out against it. Centred FOG_GLOW_HEIGHT over the fire's ground (the
// flame's middle); LAB_FOG sets the strength in hundredths (0: off).
// The logs lie in the fire: lit by n.l toward the flame's light over them, wrapped by WOOD_WRAP,
// so their tops and inner sides glow and only what faces the ground stays charred. (As walls,
// lit across the ground only, a top faced nothing and the pile read black under the flame.)
const WOOD_WRAP: float32 = 0.35;
const FOG_GLOW_PERCENT: int32 = 0;
const CAMERA_NEAR: float32 = -60.0;
const CAMERA_FAR: float32 = 60.0;
const FOG_GLOW_HEIGHT: float32 = 0.9;
const FOG_GLOW_SOFT: float32 = 0.6;
const FOG_GLOW_REACH: float32 = 12.0;
const FOG_GLOW_BANDS: float32 = 6.0;
const FOG_GLOW_COLOR: Vec3 = vec3(1.0, 0.5, 0.22);
// Patches in the fog, drifting with the wind (screen right): the halo thins and thickens by up to
// FOG_MIST_AMOUNT over FOG_MIST_CELL metres. Off (cell 0): the user wants the mist even over the
// whole scene, and the fire's own glow off (LAB_FOG 0 by default).
const FOG_MIST_CELL: float32 = 0.0;
const FOG_MIST_AMOUNT: float32 = 0.7;
const FOG_MIST_DRIFT: float32 = 0.25;
// The mist over the whole scene, moonlit and even: FOG_VEIL_PERCENT of the way to a pale night blue (LAB_VEIL in hundredths, 0: off). The fire's glow is added over it.
const FOG_VEIL_PERCENT: int32 = 12;
const FOG_VEIL_COLOR: Vec3 = vec3(0.30, 0.33, 0.50);
let fogVeil: float32 = 0.0;
// At night in fog the unlit ground is low contrast: its colours pulled NIGHT_FLAT_PERCENT of the
// way toward the grass's middle night step (LAB_FLAT in hundredths, 0: off).
const NIGHT_FLAT_PERCENT: int32 = 25;
const NIGHT_FLAT_COLOR: Vec3 = vec3(0.09, 0.13, 0.24);
let nightFlat: float32 = 0.0;
let fogGlow: float32 = 0.0;
const glowValues: Vec<float32> = new Array(GLOW_LENGTH);

function labLook(): PixelArtLook {
	return {
		// The grass ramp's middle night step (0x15213D): zoomed out, a portrait frame's corners
		// look past the 60 m map, and this keeps them from showing as black notches.
		background: { x: 0.082, y: 0.129, z: 0.239, w: 0.0 },
		outline: {
			depthThreshold: 0.004,
			normalThreshold: 0.6,
			depthShade: 0.6,
			normalShade: 1.3,
		},
		// Distance, as the video shows it: the far ground sinks into a dark violet (the vignette,
		// which darkens by screen radius instead, is off). Depth runs along the view, so it is
		// the top of the portrait frame that goes.
		fog: { start: FOG_START, end: FOG_END, strength: FOG_STRENGTH, color: { x: 0.03, y: 0.025, z: 0.07, w: 0.0 } },
		saturation: 0.0,
	};
}

function makeRenderer(): PixelArtRenderer {
	let pool: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH + MATERIAL_UNIFORM_LENGTH);
	// Variables, not calls: the bun dev compiler checks a `this typeof` call's ref parameter
	// against the argument one to its right and refuses an expression there (msc 0.2.54 does not).
	const settings: PixelArtSettings = PixelArtSettings.full();
	const look: PixelArtLook = labLook();
	const created: Result<PixelArtRenderer, PixelArtError> = PixelArtRenderer.create(pool, settings, look);
	context = pool;
	if (created.ok) { return created.value; }
	unreachable;
}

function nextRandom(): float32 {
	randomState = randomState * RANDOM_MULTIPLIER + RANDOM_INCREMENT;
	const high: uint64 = randomState >> 40;
	const sample: float32 = high as float32;
	return sample / RANDOM_RANGE;
}

// ---- data files -------------------------------------------------------------------------

function floatsInto(path: string, out: Span<float32>): int64 { return labReadFloats(out, path); }
function wordsInto(path: string, out: Span<uint32>): int64 { return labReadWords(out, path); }

function readFloats(name: string): Vec<float32> {
	const path: string = DATA + name;
	const size: int64 = labFileSize(path);
	if (size <= 0) { console.log("grass lab: missing " + path); return []; }
	const values: Vec<float32> = new Array((size / 4) as int32);
	const _read: int64 = floatsInto(path, values);
	return values;
}

function readWords(name: string): Vec<uint32> {
	const path: string = DATA + name;
	const size: int64 = labFileSize(path);
	if (size <= 0) { console.log("grass lab: missing " + path); return []; }
	const values: Vec<uint32> = new Array((size / 4) as int32);
	const _read: int64 = wordsInto(path, values);
	return values;
}

// The glTF buffer, read as words (the exporter pads it to 4 bytes) and unpacked little-endian.
function readBytes(name: string): Vec<uint8> {
	const words: Vec<uint32> = readWords(name);
	const count: int32 = words.length as int32;
	const values: Vec<uint8> = new Array(count * 4);
	for (let i = 0; i < count; i++) {
		const word: uint32 = words[i];
		values[i * 4] = (word & 255) as uint8;
		values[i * 4 + 1] = ((word >> 8) & 255) as uint8;
		values[i * 4 + 2] = ((word >> 16) & 255) as uint8;
		values[i * 4 + 3] = ((word >> 24) & 255) as uint8;
	}
	return values;
}

// Raw RGBA8 rows (the exporter's .rgba) are already the byte order makeImage wants.
function atlasImage(name: string, width: int32, height: int32): uint32 {
	const pixels: Vec<uint32> = readWords(name);
	if ((pixels.length as int32) < width * height) { console.log("grass lab: short atlas " + name); }
	return makeTextureView(makeImage(pixels, width, height));
}

// ---- scene ------------------------------------------------------------------------------

function spriteBlock(red: float32, green: float32, blue: float32, normalWeight: float32, atRoot: float32): UniformBlock {
	const block: UniformBlock = try reserveUniforms(context, SPRITE_UNIFORM_SLOT, SPRITE_UNIFORM_LENGTH)
		catch NO_UNIFORMS;
	const values: Vec<float32> = [red, green, blue, 0.0, LIGHT_LEVELS, normalWeight, atRoot, 0.0];
	writeUniforms(context, block, values);
	return block;
}

// A LitRamp / BillboardRamp block (shader3d.glsl rampParams): row, top row + 1, level offset,
// mark or jitter; then the lab's bands, falloff, walls and wrap, moon cuts and vignette.
// The walker's shadow and its marks in the grass (shader3d.glsl rampWalker / walkerFeet /
// walkerTrail), refreshed every frame from its pose:
// - it stands in the fire's light as a cylinder WALKER_SHADOW_RADIUS wide up to WALKER_SHADOW_TOP
//   above its root, so the grass behind it, away from the fire, is dark; the ground round it is a
//   step darker (contact shadow);
// - each foot (the end of a shin, SHIN_LENGTH below the shin's node) parts the grass within
//   FOOT_REACH; every TRAIL_EVERY seconds of walking its place is kept, TRAIL_POINTS of them, and
//   the grass there stays pressed (within TRAIL_REACH) and springs back over TRAIL_LIFE seconds.
const WALKER_SHADOW_RADIUS: float32 = 0.55;
const WALKER_SHADOW_TOP: float32 = 1.6;
const SHIN_LENGTH: float32 = 0.95;
const SHIN_NODES: Vec<int32> = [5, 7, 9, 11];
const FOOT_REACH: float32 = 0.45;
const TRAIL_REACH: float32 = 0.8;
const TRAIL_POINTS: int32 = 6;
const TRAIL_EVERY: float32 = 0.3;
const TRAIL_LIFE: float32 = 1.8;
const TRAIL_MOVE: float32 = 0.08;
let walkerShadowX: float32 = 0.0;
let walkerShadowZ: float32 = 0.0;
let walkerShadowTop: float32 = 0.0;
const feet: Vec<float32> = [1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0];
const trail: Vec<float32> = [1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0, 1000.0];
const trailBorn: Vec<float32> = [-100.0, -100.0, -100.0, -100.0, -100.0, -100.0];
const trailWeight: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
let trailNext: int32 = 0;
let trailLastAt: float32 = -100.0;
const litBlocks: Vec<UniformBlock> = [];
const litValues: Vec<Vec<float32>> = [];

// LAB_WALKER_FX 0 turns the shadow, the feet and the trail off (for side-by-side checks).
let walkerFx: boolean = true;

function walkerShadowRadius(): float32 {
	return walkerFx && walkerWanted && (walkerParts.length as int32) > 0 ? WALKER_SHADOW_RADIUS : 0.0;
}

// The walker's feet, shadow and trail for this frame, from the pose the last refresh placed.
function trackWalker(): void {
	if ((walkerParts.length as int32) == 0) { return; }
	const rootWorld: Result<Mat4, SceneError> = tree.worldOf(walkerParts[0]);
	if (!rootWorld.ok) { return; }
	const rootAt: Vec3 = vec3(0.0, 0.0, 0.0) * rootWorld.value;
	walkerShadowX = rootAt.x;
	walkerShadowZ = rootAt.z;
	walkerShadowTop = rootAt.y + WALKER_SHADOW_TOP;
	for (let i = 0; i < 4; i++) {
		const shin: Result<Mat4, SceneError> = tree.worldOf(walkerParts[SHIN_NODES[i]]);
		if (!shin.ok) { continue; }
		const foot: Vec3 = vec3(0.0, -SHIN_LENGTH, 0.0) * shin.value;
		feet[i * 2] = foot.x;
		feet[i * 2 + 1] = foot.z;
	}
	const now: float32 = seconds();
	const last: int32 = (trailNext + TRAIL_POINTS - 1) % TRAIL_POINTS;
	const dx: float32 = rootAt.x - trail[last * 2];
	const dz: float32 = rootAt.z - trail[last * 2 + 1];
	if (now - trailLastAt >= TRAIL_EVERY && dx * dx + dz * dz > TRAIL_MOVE * TRAIL_MOVE) {
		trail[trailNext * 2] = rootAt.x;
		trail[trailNext * 2 + 1] = rootAt.z;
		trailBorn[trailNext] = now;
		trailNext = (trailNext + 1) % TRAIL_POINTS;
		trailLastAt = now;
	}
	for (let i = 0; i < TRAIL_POINTS; i++) {
		const age: float32 = now - trailBorn[i];
		trailWeight[i] = age < 0.0 ? 0.0 : Math.max(0.0, 1.0 - age / TRAIL_LIFE) as float32;
	}
}

function rampBlock(row: float32, topRow: float32, offset: float32, markOrJitter: float32, flatWalls: float32, wrap: float32, far: Vec<float32>): UniformBlock {
	// The lawn's moon steps are cut round flat ground, as the clumps' (slopeSteps): flat ground the
	// middle step, slopes to or from the moon the top or the bottom one.
	const isLawn: boolean = row == ROW_GRASS && flatWalls < 0.5 && SLOPE_SHADING && GRASS_PATCHES;
	const block: UniformBlock = try reserveUniforms(context, RAMP_UNIFORM_SLOT, RAMP_UNIFORM_LENGTH)
		catch NO_UNIFORMS;
	const values: Vec<float32> = [
		row, topRow, offset, markOrJitter,
		NIGHT_STEPS, FIRE_BANDS, FIRST_BAND, BAND_STEP,
		LAB_FIRE_FALL, flatWalls, wrap, flatWalls > 0.5 && flatWalls < 1.5 ? LAB_FIRE_R : 0.0,
		// Only stones (flatWalls 1) take the light at their origin. A log's origin sits a few
		// centimetres off the fire, so its direction to the fire is arbitrary and its falloff full:
		// logs (flatWalls 2) are lit per texel, as the lab lights wood.
		isLawn ? MOON_Y - SLOPE_AWAY : MOON_CUT_1, isLawn ? MOON_Y + SLOPE_TOWARD : MOON_CUT_2, flatWalls > 0.5 && flatWalls < 1.5 ? WALLS_AT_ORIGIN : (row == ROW_GRASS ? CLUMP_BAND_MERGE : 0.0), far[3] > 0.5 ? SHADOW_HALF : 0.0,
		VIGNETTE_1, VIGNETTE_2, VIGNETTE_3, VIGNETTE_ON,
		far[0], far[1], far[2], far[3],
		far[4], far[5], far[6], far[7],
		walkerShadowX, walkerShadowZ, walkerShadowRadius(), walkerShadowTop,
	];
	writeUniforms(context, block, values);
	litBlocks.push(block);
	litValues.push(values);
	return block;
}

// A BillboardRamp block: the five ramp vectors, then the wind and the walker (shader3d.glsl
// spriteRampParams). `sway` is the share of the full sway (0: none); `stepsUpInFire` keeps a
// sprite's own steps up to the firelight, as the lab's clumps.
function spriteRampValues(row: float32, offset: float32, sway: float32, stepsUpInFire: float32, metresPerTexel: float32, far: Span<float32>): Vec<float32> {
	const windOn: float32 = (windWanted && sway > 0.0) ? metresPerTexel : 0.0;
	const reach: float32 = walkerWanted ? WALKER_REACH : 0.0;
	return [
		row, (row == ROW_GRASS || row == ROW_LEAF) ? CLUMP_SPIN : 0.0, offset, BLADE_JITTER,
		NIGHT_STEPS, FIRE_BANDS, FIRST_BAND, BAND_STEP,
		LAB_FIRE_FALL, 0.0, GRASS_WRAP, stepsUpInFire,
		MOON_CUT_1, MOON_CUT_2, row == ROW_GRASS ? CLUMP_BAND_MERGE : 1.0, SHADOW_HALF,
		VIGNETTE_1, VIGNETTE_2, VIGNETTE_3, VIGNETTE_ON,
		windDirX, windDirZ, WIND_SPREAD, sway,
		WIND_CELL, WIND_SPEED, WIND_GAIN, WIND_BIAS,
		WIND_TEXELS, WIGGLE_TEXELS, WIGGLE_HZ, WIND_POSES,
		WIND_PERSP, windOn, reach, WALKER_EXP,
		walkerX, walkerZ, WALKER_TEXELS, WALKER_FLAT,
		far[0], far[1], far[2], far[3],
		far[4], far[5], far[6], far[7],
		far[8], far[9], far[10], far[11],
		feet[0], feet[1], feet[2], feet[3],
		feet[4], feet[5], feet[6], feet[7],
		trail[0], trail[1], trail[2], trail[3],
		trail[4], trail[5], trail[6], trail[7],
		trail[8], trail[9], trail[10], trail[11],
		trailWeight[0], trailWeight[1], trailWeight[2], trailWeight[3],
		trailWeight[4], trailWeight[5], walkerWanted && walkerFx ? FOOT_REACH : 0.0, walkerWanted && walkerFx ? TRAIL_REACH : 0.0,
		walkerShadowX, walkerShadowZ, walkerShadowRadius(), walkerShadowTop,
	];
}

function spriteRampBlock(row: float32, offset: float32, sway: float32, stepsUpInFire: float32, far: Vec<float32>): UniformBlock {
	const block: UniformBlock = try reserveUniforms(context, RAMP_UNIFORM_SLOT, SPRITE_RAMP_UNIFORM_LENGTH)
		catch NO_UNIFORMS;
	spriteBlocks.push(block);
	const kept: Vec<float32> = [row, offset, sway, stepsUpInFire];
	for (const value of far) { kept.push(value); }
	spriteSettings.push(kept);
	writeUniforms(context, block, spriteRampValues(row, offset, sway, stepsUpInFire, 0.0, far));
	return block;
}

// Every frame: the wind's texel size and the walker's place into each sprite block.
function updateSprites(metresPerTexel: float32): void {
	for (let i = 0; i < (litBlocks.length as int32); i++) {
		const at: int32 = RAMP_UNIFORM_LENGTH - 4;
		litValues[i][at] = walkerShadowX;
		litValues[i][at + 1] = walkerShadowZ;
		litValues[i][at + 2] = walkerShadowRadius();
		litValues[i][at + 3] = walkerShadowTop;
		writeUniforms(context, litBlocks[i], litValues[i]);
	}
	for (let i = 0; i < (spriteBlocks.length as int32); i++) {
		const k: Vec<float32> = spriteSettings[i];
		writeUniforms(context, spriteBlocks[i], spriteRampValues(k[0], k[1], k[2], k[3], metresPerTexel, k[4..16]));
	}
}

function rampLit(state: RenderState, ramps: uint32, sampler: uint32, block: UniformBlock): int32 {
	return addMaterial(context, {
		...Material.plain(Program.LitRamp, state, Phase.Opaque),
		texture0: ramps,
		texture2: shadowView,
		sampler0: sampler,
		sampler1: shadowSampler,
		uniforms: block,
	});
}

function hashOf(x: float32, z: float32, salt: float32): float32 {
	return fractOf(sinf(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.547);
}

function flowerCellOf(v: float32): int32 {
	return Math.floor((v - FLOWER_ORIGIN) / FLOWER_CELL) as int32;
}

// Picks the sprigs' roots, before the clumps so they can keep clear of them.
function placeSprigs(): void {
	for (let c = 0; c < FLOWER_GRID * FLOWER_GRID; c++) { sprigAt[c * 4 + 3] = 2.0; }
	if (!rampLook || !SPRIGS_WANTED) { return; }
	const read: Vec<float32> = readFloats("clumps_short.f32");
	for (let i = 0; i < (read.length as int32) / INSTANCE_STRIDE; i++) {
		const at: int32 = i * INSTANCE_STRIDE;
		const x: float32 = read[at];
		const z: float32 = read[at + 2];
		if (x * x + z * z < FIRE_GRASS_CLEAR * FIRE_GRASS_CLEAR * 2.0) { continue; }
		const cx: int32 = flowerCellOf(x);
		const cz: int32 = flowerCellOf(z);
		if (cx < 0 || cz < 0 || cx >= FLOWER_GRID || cz >= FLOWER_GRID) { continue; }
		if (hashOf(cx as float32, cz as float32, 3.0) >= FLOWER_SHARE) { continue; }
		const h: float32 = hashOf(x, z, 7.0);
		const c: int32 = (cz * FLOWER_GRID + cx) * 4;
		if (h < sprigAt[c + 3]) {
			sprigAt[c] = x;
			sprigAt[c + 1] = read[at + 1];
			sprigAt[c + 2] = z;
			sprigAt[c + 3] = h;
		}
	}
}

function nearSprig(x: float32, z: float32): boolean {
	const cx: int32 = flowerCellOf(x);
	const cz: int32 = flowerCellOf(z);
	for (let dz = -1; dz <= 1; dz++) {
		for (let dx = -1; dx <= 1; dx++) {
			const gx: int32 = cx + dx;
			const gz: int32 = cz + dz;
			if (gx < 0 || gz < 0 || gx >= FLOWER_GRID || gz >= FLOWER_GRID) { continue; }
			const c: int32 = (gz * FLOWER_GRID + gx) * 4;
			if (sprigAt[c + 3] > 1.5) { continue; }
			const ox: float32 = sprigAt[c] - x;
			const oz: float32 = sprigAt[c + 2] - z;
			if (ox * ox + oz * oz < FLOWER_CLEAR * FLOWER_CLEAR) { return true; }
		}
	}
	return false;
}

function addFlowers(root: NodeId, corners: uint32, ramps: uint32, sampler: uint32, state: RenderState): boolean {
	const instances: Vec<float32> = [];
	for (let c = 0; c < FLOWER_GRID * FLOWER_GRID; c++) {
		if (sprigAt[c * 4 + 3] > 1.5) { continue; }
		instances.push(sprigAt[c * 4]);
		instances.push(sprigAt[c * 4 + 1]);
		instances.push(sprigAt[c * 4 + 2]);
		instances.push(Math.floor(sprigAt[c * 4 + 3] * 4.0) as float32);
		instances.push((FLOWER_CELL_W as float32) * LAB_METRES_PER_TEXEL * zoomOut);
		instances.push((FLOWER_CELL_H as float32) * LAB_METRES_PER_TEXEL * zoomOut);
		instances.push(0.0);
		instances.push(0.0);
	}
	const count: int32 = (instances.length as int32) / INSTANCE_STRIDE;
	console.log("grass lab: " + count.toString() + " sprigs");
	if (count == 0) { return true; }
	const material: int32 = addMaterial(context, {
		...Material.plain(Program.BillboardRamp, state, Phase.Opaque),
		texture0: atlasImage("atlas_flower.rgba", FLOWER_CELL_W * 4, FLOWER_CELL_H),
		texture1: ramps,
		texture2: shadowView,
		sampler0: sampler,
		sampler1: shadowSampler,
		uniforms: spriteRampBlock(ROW_FLOWER, FLOWER_STEPS, FLOWER_SWAY, 0.0, NO_FAR),
	});
	const mesh: int32 = addMesh(
		context,
		GpuMesh.external(VertexLayout.Billboard, corners, makeVertexBuffer(instances), 6, count),
	);
	const node: Result<NodeId, SceneError> = addMeshNode(tree, root, identityTransform(), mesh, material);
	return node.ok;
}

// Grass in patches over bare ground (user, 2026-10-02, after the reference video: its ground is
// mostly smooth lawn, shaded by its slopes, and the grass grows in patches whose blade-topped edges
// follow the ground like contour lines; grass over everything hid the hills). Two octaves of value
// noise, PATCH_NOISE_CELL metres, grass where they pass PATCH_NOISE_CUT (about PATCH share of the
// ground). false: grass everywhere (user, 2026-10-02: the full cover looked better on the phone).
const GRASS_PATCHES: boolean = false;
// The patches a step over flat grass's (slopeSteps puts it a step under the moon's top): two over
// the bare ground, and on slopes facing the moon past the top into the first, violet, warm step,
// as the reference's patches stand lighter and pinker than its blue ground.
const CLUMP_LIFT: float32 = 1.0;
const PATCH_NOISE_CELL: float32 = 4.5;
const PATCH_NOISE_CUT: float32 = 0.52;

function valueNoise2(x: float32, z: float32, salt: float32): float32 {
	const ix: float32 = Math.floor(x) as float32;
	const iz: float32 = Math.floor(z) as float32;
	const fx: float32 = x - ix;
	const fz: float32 = z - iz;
	const ux: float32 = fx * fx * (3.0 - 2.0 * fx);
	const uz: float32 = fz * fz * (3.0 - 2.0 * fz);
	const a: float32 = hashOf(ix, iz, salt);
	const b: float32 = hashOf(ix + 1.0, iz, salt);
	const c: float32 = hashOf(ix, iz + 1.0, salt);
	const d: float32 = hashOf(ix + 1.0, iz + 1.0, salt);
	return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uz;
}

function inGrassPatch(x: float32, z: float32): boolean {
	const n: float32 = valueNoise2(x / PATCH_NOISE_CELL, z / PATCH_NOISE_CELL, 11.0) * 0.7
		+ valueNoise2(x / (PATCH_NOISE_CELL * 0.4), z / (PATCH_NOISE_CELL * 0.4), 12.0) * 0.3;
	return n > PATCH_NOISE_CUT;
}

// The hills read through their slopes (user, 2026-10-02: the terrain did not show): a clump is lit
// as facing up (shader3d.glsl billboardRampFs), which is the moon's top step everywhere, so each
// carries steps from its ground's slope, 0 facing the moon, -1 flat, -2 turned away, from
// the height grid (groundAt) over SLOPE_SPAN metres. One colour still: only the light differs.
const SLOPE_SHADING: boolean = true;
const SLOPE_SPAN: float32 = 0.5;
const SLOPE_TOWARD: float32 = 0.06;
const SLOPE_AWAY: float32 = 0.12;
const MOON_X: float32 = -0.4553;
const MOON_Y: float32 = 0.8701;
const MOON_Z: float32 = -0.2529;

function slopeSteps(x: float32, z: float32): float32 {
	const dx: float32 = (groundAt(x + SLOPE_SPAN, z) - groundAt(x - SLOPE_SPAN, z)) / (2.0 * SLOPE_SPAN);
	const dz: float32 = (groundAt(x, z + SLOPE_SPAN) - groundAt(x, z - SLOPE_SPAN)) / (2.0 * SLOPE_SPAN);
	const length: float32 = Math.sqrt(dx * dx + 1.0 + dz * dz) as float32;
	const facing: float32 = (-dx * MOON_X + MOON_Y - dz * MOON_Z) / length;
	// Relative to flat ground (facing = MOON_Y): flat ground sits a step under the top, a slope
	// turned SLOPE_TOWARD to the moon takes the top and one turned SLOPE_AWAY from it the bottom
	// (~15 deg either way at this moon), so the usual slopes, not only the steepest, show.
	if (facing > MOON_Y + SLOPE_TOWARD) { return 0.0; }
	if (facing < MOON_Y - SLOPE_AWAY) { return -2.0; }
	return -1.0;
}

// `steps`: the material's own ramp steps (long grass one up); `sway`: its share of the wind.
function addClumps(root: NodeId, corners: uint32, file: string, texture: uint32, ramps: uint32, sampler: uint32, state: RenderState, steps: float32, sway: float32, cellW: int32, cellH: int32, keep: float32): boolean {
	const read: Vec<float32> = readFloats(file);
	// The rosettes are several times the lab's blades, so a share `keep` of the clumps (hashed on
	// their root, so it is the same every run) still covers the ground, and the rest are dropped.
	const instances: Vec<float32> = [];
	for (let i = 0; i < (read.length as int32) / INSTANCE_STRIDE; i++) {
		const at: int32 = i * INSTANCE_STRIDE;
		const h: float32 = fractOf(sinf(read[at] * 12.9898 + read[at + 2] * 78.233) * 43758.547);
		if (h >= keep) { continue; }
		// The rosettes reach about a metre past their root: keep them off the logs.
		if (read[at] * read[at] + read[at + 2] * read[at + 2] < FIRE_GRASS_CLEAR * FIRE_GRASS_CLEAR) { continue; }
		// and off the sprigs, which stand in a little clearing of their own
		if (rampLook && nearSprig(read[at], read[at + 2])) { continue; }
		if (rampLook && GRASS_PATCHES && !inGrassPatch(read[at], read[at + 2])) { continue; }
		for (let k = 0; k < INSTANCE_STRIDE; k++) { instances.push(read[at + k]); }
	}
	const count: int32 = (instances.length as int32) / INSTANCE_STRIDE;
	if (count == 0) { return false; }
	// Closer to the video (VEP4INri_1U), whose grass reads as patches, smooth inside, with blades
	// only as a fringe where the light or the patch changes:
	// - every clump of a kind takes the same step (the lab's -1 / 0 / +1 per clump speckled the
	//   whole lawn), so short grass is the lawn's colour and long grass one step up from it;
	// - the sprites keep their size in texels when the camera zooms out (their width and height
	//   are world metres, so at 1.38x they drew 0.72 as big and the blades turned to noise).
	if (rampLook) {
		for (let i = 0; i < count; i++) {
			const at: int32 = i * INSTANCE_STRIDE;
			if (UNIFORM_CLUMPS) { instances[at + 6] = SLOPE_SHADING ? slopeSteps(instances[at], instances[at + 2]) : 0.0; }
			instances[at + 4] = (cellW as float32) * LAB_METRES_PER_TEXEL * zoomOut;
			instances[at + 5] = (cellH as float32) * LAB_METRES_PER_TEXEL * zoomOut;
		}
	}
	// shape.z holds the clump's ramp step; the toon programs take it, and the material's, as a tint.
	if (!rampLook) {
		for (let i = 0; i < count; i++) {
			const at: int32 = i * INSTANCE_STRIDE + 6;
			instances[at] = 1.0 + (instances[at] + steps) * TINT_PER_STEP;
		}
	}
	const light: float32 = AMBIENT_R + MOON_POWER;
	let material: int32 = 0;
	if (rampLook) {
		material = addMaterial(context, {
			...Material.plain(Program.BillboardRamp, state, Phase.Opaque),
			texture0: texture,
			texture1: ramps,
			texture2: shadowView,
			sampler0: sampler,
			sampler1: shadowSampler,
			uniforms: spriteRampBlock(ROW_GRASS, steps + (GRASS_PATCHES ? CLUMP_LIFT : 0.0), sway, 1.0, steps > 0.5 ? TALL_FAR : SHORT_FAR),
		});
	} else {
		const block: UniformBlock = spriteBlock(
			GRASS_R * (AMBIENT_R + MOON_POWER),
			GRASS_G * (AMBIENT_G + MOON_POWER),
			GRASS_B * (AMBIENT_B + MOON_POWER),
			(1.0 - GRASS_WRAP) * labShader,
			labShader,
		);
		material = addMaterial(context, {
			...Material.plain(Program.Billboard, state, Phase.Opaque),
			texture0: texture,
			sampler0: sampler,
			uniforms: block,
		});
	}
	const mesh: int32 = addMesh(
		context,
		GpuMesh.external(VertexLayout.Billboard, corners, makeVertexBuffer(instances), 6, count),
	);
	const placed: Result<NodeId, SceneError> = addMeshNode(tree, root, identityTransform(), mesh, material);
	console.log("grass lab: " + file + " clumps " + count.toString());
	return placed.ok && light > 0.0;
}

function flameInstance(frame: int32): Vec<float32> {
	const width: float32 = (FLAME_CELL_W as float32) * UNITS_ON_SHORT_SIDE / 360.0;
	const height: float32 = (FLAME_CELL_H as float32) * UNITS_ON_SHORT_SIDE / 360.0;
	// Towards the camera: -forward of camera.ms basisOf.
	const pitchCos: float32 = cosf(CAMERA_PITCH);
	const x: float32 = sinf(CAMERA_YAW) * pitchCos * FLAME_TOWARD_CAMERA;
	const y: float32 = sinf(CAMERA_PITCH) * FLAME_TOWARD_CAMERA;
	const z: float32 = cosf(CAMERA_YAW) * pitchCos * FLAME_TOWARD_CAMERA;
	return [x, fireGround + FLAME_ROOT + y, z, frame as float32, width, height, 1.0, 1.0];
}

function litMaterial(state: RenderState, flatWalls: float32, wrap: float32): int32 {
	const toon: UniformBlock = try reserveUniforms(context, TOON_UNIFORM_SLOT, TOON_UNIFORM_LENGTH)
		catch NO_UNIFORMS;
	const values: Vec<float32> = [LIGHT_LEVELS, flatWalls, wrap, 0.0];
	writeUniforms(context, toon, values);
	return addMaterial(context, { ...Material.plain(Program.Lit, state, Phase.Opaque), uniforms: toon });
}

function cosOf(angle: float32): float32 { return sinf(angle + 1.5707963); }

// The ramp look takes the lab's fire; the toon looks keep the one tuned for them.
function firePower(): float32 { return rampLook ? LAB_FIRE_GAIN : FIRE_POWER; }
function fireRadius(): float32 { return rampLook ? LAB_FIRE_R : FIRE_RADIUS; }

// The camera looks along -(sin yaw, cos yaw) on the ground (camera.ms basisOf).
function snowCentre(): Vec3 {
	return vec3(sinf(CAMERA_YAW) * SNOW_TOWARD_CAMERA, fireGround + SNOW_HEIGHT, cosf(CAMERA_YAW) * SNOW_TOWARD_CAMERA);
}

// Each emitter draws from a stream mesh under its own node, depth-tested with the scene; added
// before the flame, which is drawn last over everything.
function setupParticles(root: NodeId, state: RenderState): boolean {
	const material: int32 = addMaterial(context, Material.plain(Program.Particle, state, Phase.Opaque));
	const snowStream: Result<int32, StreamError> = addStreamMesh(context, snow.capacity);
	const emberStream: Result<int32, StreamError> = addStreamMesh(context, embers.capacity);
	if (!snowStream.ok || !emberStream.ok) { console.log("grass lab: particle streams refused"); return false; }
	snowMesh = snowStream.value;
	emberMesh = emberStream.value;
	const snowPlaced: Result<NodeId, SceneError> =
		addMeshNode(tree, root, transformAt(snowCentre()), snowMesh, material);
	const emberPlaced: Result<NodeId, SceneError> =
		addMeshNode(tree, root, transformAt(vec3(0.0, fireGround + EMBER_HEIGHT, 0.0)), emberMesh, material);
	if (!snowPlaced.ok || !emberPlaced.ok) { console.log("grass lab: particle nodes refused"); return false; }
	snowNode = snowPlaced.value;
	const _shown: Result<int32, SceneError> = setVisible(tree, snowNode, snowWanted);
	emberNode = emberPlaced.value;
	const _synced: int32 = syncWorld(tree);
	for (let i = 0; i < PARTICLE_WARMUP_STEPS; i++) {
		if ((snowWanted && !advanceEmitter(snow, snowNode)) || !advanceEmitter(embers, emberNode)) {
			console.log("grass lab: particle warm-up refused at step " + i.toString());
			return false;
		}
	}
	return true;
}

function advanceEmitter(ref emitter: ParticleEmitter, node: NodeId): boolean {
	const world: Result<Mat4, SceneError> = tree.worldOf(node);
	if (!world.ok) { return false; }
	return updateEmitter(emitter, PARTICLE_STEP, world.value).ok;
}

function drawEmitter(ref emitter: ParticleEmitter, node: NodeId, mesh: int32, instances: Span<float32>): boolean {
	const world: Result<Mat4, SceneError> = tree.worldOf(node);
	if (!world.ok) { return false; }
	const written: Result<int32, ParticleError> = writeInstances(emitter, world.value, instances);
	if (!written.ok) { return false; }
	return writeStream(context, mesh, instances, written.value).ok;
}

// The walker's nodes keep their glTF hierarchy and are posed each frame from walkerAnim. The body
// is lit by its own vertex colours (the toon program); the lens takes its ramp row, one red at
// every level: it glows.
function setupFourLegs(root: NodeId, state: RenderState, body: int32, lens: int32): boolean {
	const file = readFile(WALKER_DIR + "walker.glb");
	if (!file.ok) { return false; }
	const glb: uint8[] = file.value.asBytes();
	const all: Span<uint8> = glb;
	if ((glb.length as int32) < 28 || wordAt(all, 0) != 0x46546C67) { console.log("grass lab: walker.glb is not a GLB"); return false; }
	const jsonLength: int32 = wordAt(all, 12);
	const jsonBytes: uint8[] = [];
	for (let i = 20; i < 20 + jsonLength; i++) { jsonBytes.push(all[i]); }
	const binLength: int32 = wordAt(all, 20 + jsonLength);
	const loaded: Result<GltfData, GltfError> =
		loadGltf(jsonBytes.asString(), all[28 + jsonLength..28 + jsonLength + binLength]);
	if (!loaded.ok) { console.log("grass lab: walker.glb refused: " + loaded.error.toString()); return false; }
	const parts: GltfData = loaded.value;
	// A mesh takes the material of the node that draws it: the lens its glowing red.
	const bindings: Vec<GltfMeshBinding> = [];
	for (let i = 0; i < (parts.meshes.length as int32); i++) {
		let mesh: MeshData = parts.meshes[i];
		encodeColors(mesh);
		const uploaded: Result<int32, MeshUploadError> = addMeshData(context, mesh);
		if (!uploaded.ok) { return false; }
		bindings.push({ mesh: uploaded.value, material: body });
	}
	for (const node of parts.nodes) {
		if (node.name == WALKER_LENS && node.mesh >= 0) { bindings[node.mesh].material = lens; }
	}
	const added: Result<int32, GltfSceneError> = addGltfNodes(tree, root, parts, bindings);
	if (!added.ok) { console.log("grass lab: walker.glb did not enter the scene"); return false; }
	if (!loadRoamClip(root)) { return false; }
	console.log("grass lab: walker " + (walkerParts.length as int32).toString() + " parts");
	return true;
}

// walkerClips.bin (scripts/sync-hibernal-assets.py): the node names, then each clip. Keeps the
// scene node of every clip node in walkerParts and the roam clips' frames in walkerAnim: every
// WALKER_LOOPS clip when the file has any, else the one WALKER_CLIP.
// walkerGraph.bin (t3ssel8r-lab walker_clips.py GRAPH=1): the walker's motion graph, walks between
// stations that all start and end in their station's pose. When it is there the walker plays it:
// every walk is a clip, and at the end of one the next is drawn from those leaving the station it
// reached (not straight back where it came from, when there is another).
function loadGraph(root: NodeId): boolean {
	const file = readFile(WALKER_DIR + "walkerGraph.bin");
	if (!file.ok) { return false; }
	const bytes: uint8[] = file.value.asBytes();
	const all: Span<uint8> = bytes;
	const size: int32 = bytes.length as int32;
	if (size < 24 || wordAt(all, 0) != 0x46524757) { console.log("grass lab: walkerGraph.bin is not a graph"); return false; }
	const nodeCount: int32 = wordAt(all, 12);
	const stationCount: int32 = wordAt(all, 16);
	const walkCount: int32 = wordAt(all, 20);
	let at: int32 = 24;
	for (let i = 0; i < nodeCount; i++) {
		const length: int32 = wordAt(all, at);
		const name: string = textAt(all, at + 4, length);
		at = at + 4 + ((length + 3) / 4) * 4;
		const found: Result<NodeId, SceneError> = tree.findByName(root, name);
		if (!found.ok) { console.log("grass lab: walker.glb has no node " + name); return false; }
		walkerParts.push(found.value);
	}
	at = at + stationCount * 8;
	for (let w = 0; w < walkCount; w++) {
		if (at + 16 > size) { console.log("grass lab: walkerGraph.bin is cut short"); return false; }
		walkFrom.push(wordAt(all, at));
		walkTo.push(wordAt(all, at + 4));
		const frames: int32 = wordAt(all, at + 8);
		at = at + 16;
		const values: int32 = frames * nodeCount * WALKER_POSE;
		if (at + values * 2 > size) { console.log("grass lab: walkerGraph.bin is cut short"); return false; }
		loopFirst.push(walkerAnim.length as int32);
		loopFrames.push(frames);
		for (let k = 0; k < values; k++) {
			const raw: int32 = (all[at + k * 2] as int32) | ((all[at + k * 2 + 1] as int32) << 8);
			const signed: int32 = raw >= 32768 ? raw - 65536 : raw;
			const isTranslation: boolean = k % WALKER_POSE < 3;
			walkerAnim.push((signed as float32) / (isTranslation ? 1000.0 : 32767.0));
		}
		at = at + values * 2;
	}
	console.log("grass lab: walker graph, " + stationCount.toString() + " stations, " + walkCount.toString() + " walks");
	return true;
}

function loadRoamClip(root: NodeId): boolean {
	if (loadGraph(root)) { return true; }
	walkerParts.length = 0;
	loopFirst.length = 0;
	loopFrames.length = 0;
	walkFrom.length = 0;
	walkTo.length = 0;
	walkerAnim.length = 0;
	const file = readFile(WALKER_DIR + "walkerClips.bin");
	if (!file.ok) { console.log("grass lab: no walkerClips.bin"); return false; }
	const bytes: uint8[] = file.value.asBytes();
	const all: Span<uint8> = bytes;
	const size: int32 = bytes.length as int32;
	if (size < 16 || wordAt(all, 0) != 0x504C4357) { console.log("grass lab: walkerClips.bin is not a clip file"); return false; }
	const nodeCount: int32 = wordAt(all, 8);
	const clipCount: int32 = wordAt(all, 12);
	let at: int32 = 16;
	for (let i = 0; i < nodeCount; i++) {
		const length: int32 = wordAt(all, at);
		const name: string = textAt(all, at + 4, length);
		at = at + 4 + ((length + 3) / 4) * 4;
		const found: Result<NodeId, SceneError> = tree.findByName(root, name);
		if (!found.ok) { console.log("grass lab: walker.glb has no node " + name); return false; }
		walkerParts.push(found.value);
	}
	// Two passes over the clips: the loops, and only if there were none, the single wander.
	const clipsAt: int32 = at;
	for (let pass = 0; pass < 2 && (loopFrames.length as int32) == 0; pass++) {
		at = clipsAt;
		for (let i = 0; i < clipCount; i++) {
			const length: int32 = wordAt(all, at);
			const name: string = textAt(all, at + 4, length);
			at = at + 4 + ((length + 3) / 4) * 4;
			const frames: int32 = wordAt(all, at);
			const floats: int32 = frames * nodeCount * WALKER_POSE;
			at = at + 8;
			if (at + floats * 4 > size) { console.log("grass lab: walkerClips.bin is cut short"); return false; }
			const wanted: boolean = pass == 0 ? name.startsWith(WALKER_LOOPS) : name == WALKER_CLIP;
			if (wanted && frames > 0) {
				loopFirst.push(walkerAnim.length as int32);
				loopFrames.push(frames);
				for (let k = 0; k < floats; k++) { walkerAnim.push(float32At(all, at + k * 4)); }
			}
			at = at + floats * 4;
		}
	}
	if ((loopFrames.length as int32) == 0) { console.log("grass lab: walkerClips.bin has no roam clip"); return false; }
	console.log("grass lab: " + (loopFrames.length as int32).toString() + " roam clips");
	return true;
}

function wordAt(bytes: Span<uint8>, at: int32): int32 {
	return (bytes[at] as int32)
		| ((bytes[at + 1] as int32) << 8)
		| ((bytes[at + 2] as int32) << 16)
		| ((bytes[at + 3] as int32) << 24);
}

function textAt(bytes: Span<uint8>, at: int32, length: int32): string {
	const text: uint8[] = [];
	for (let i = 0; i < length; i++) { text.push(bytes[at + i]); }
	return text.asString();
}

function displayValue(linear: float32): float32 {
	if (linear <= 0.0031308) { return (linear * 12.92) as float32; }
	return (1.055 * Math.pow(linear, 1.0 / 2.4) - 0.055) as float32;
}

// glTF's COLOR_0 is linear light; the lit program shades the vertex colour as a display value.
function encodeColors(ref mesh: MeshData): void {
	const count: int32 = mesh.vertexCount();
	for (let v = 0; v < count; v++) {
		const at: int32 = v * LIT_VERTEX_STRIDE + 6;
		mesh.vertices[at] = displayValue(mesh.vertices[at]);
		mesh.vertices[at + 1] = displayValue(mesh.vertices[at + 1]);
		mesh.vertices[at + 2] = displayValue(mesh.vertices[at + 2]);
	}
}

// The clip frame for now. A clip that ran out hands over to another one, never the same twice
// in a row when there is a choice: the loops all start and end in one pose, so nothing jumps.
// A walk leaving the station `done` reached, at random; not one straight back to where `done`
// started unless that is all there is.
function nextWalk(done: int32): int32 {
	const at: int32 = walkTo[done];
	const back: int32 = walkFrom[done];
	let options: int32 = 0;
	let others: int32 = 0;
	for (let w = 0; w < (walkFrom.length as int32); w++) {
		if (walkFrom[w] != at) { continue; }
		options = options + 1;
		if (walkTo[w] != back) { others = others + 1; }
	}
	if (options == 0) { return done; }
	const avoidBack: boolean = others > 0;
	let pick: int32 = (nextRandom() * ((avoidBack ? others : options) as float32)) as int32;
	for (let w = 0; w < (walkFrom.length as int32); w++) {
		if (walkFrom[w] != at || (avoidBack && walkTo[w] == back)) { continue; }
		if (pick == 0) { return w; }
		pick = pick - 1;
	}
	return done;
}

function roamFrame(): int32 {
	let frame: int32 = ((seconds() - loopStartedAt) * WALKER_FPS) as int32;
	while (frame >= loopFrames[loopNow]) {
		loopStartedAt = loopStartedAt + (loopFrames[loopNow] as float32) / WALKER_FPS;
		const count: int32 = loopFrames.length as int32;
		if ((walkFrom.length as int32) == count && count > 0) {
			loopNow = nextWalk(loopNow);
		} else if (count > 1) {
			const skip: int32 = 1 + ((nextRandom() * ((count - 1) as float32)) as int32);
			loopNow = (loopNow + Math.min(skip, count - 1) as int32) % count;
		}
		frame = ((seconds() - loopStartedAt) * WALKER_FPS) as int32;
	}
	return frame < 0 ? 0 : frame;
}

function poseFourLegs(): boolean {
	const count: int32 = walkerParts.length as int32;
	// roamFrame first: it is what moves on to the next walk, and the walk's start read before it
	// showed the frame of a switch from the walk just finished, a flash back to where it began.
	const frame: int32 = roamFrame();
	const first: int32 = loopFirst[loopNow] + frame * count * WALKER_POSE;
	for (let i = 0; i < count; i++) {
		const k: int32 = first + i * WALKER_POSE;
		const rotation: Quat = { x: walkerAnim[k + 3], y: walkerAnim[k + 4], z: walkerAnim[k + 5], w: walkerAnim[k + 6] };
		const posed: Result<int32, SceneError> = setLocal(tree, walkerParts[i], {
			...identityTransform(),
			position: vec3(walkerAnim[k], walkerAnim[k + 1], walkerAnim[k + 2]),
			rotation: rotation,
		});
		if (!posed.ok) { return false; }
	}
	// The first clip node is the walker's root: where it stands, which is what pushes the grass.
	walkerX = walkerAnim[first];
	walkerZ = walkerAnim[first + 2];
	return true;
}

// The fire's shadows, seen from above: SHADOW_SIZE texels square over 2 * SHADOW_HALF metres
// round the fire (the world origin). A texel says whether the fire reaches it along a straight
// line from the light to a point SHADOW_AIM above the ground there (grass height):
// - pillars: a pillar blocks the line where the line passes it lower than its top, so a tall
//   pillar's shadow runs off the map and a stone lower than the fire casts a short one; four
//   sample points a texel soften the edge. The pillars are turned boxes (pillarBox); a point
//   inside one is lit, so a pillar lit at its own origin (flat walls) is never in its own shadow.
// - terrain: the line is marched over the ground (a height grid rasterized from the GROUND mesh,
//   the same texels), every TERRAIN_STEP metres; ground higher than the line hides what is behind.
//   One sample a texel: the march is the costly part.
// Not modelled: the logs and the walker cast nothing, and the fire is one fixed point.
const SHADOW_SIZE: int32 = 512;
const SHADOW_HALF: float32 = 32.0;
const SHADOW_AIM: float32 = 0.3;
const TERRAIN_STEP: float32 = 0.25;
// The march starts this far from the fire (the logs' pad) and stops this far short of the point,
// so the slope a point stands on does not shade the point itself.
const TERRAIN_SKIP_START: float32 = 0.8;
const TERRAIN_SKIP_END: float32 = 0.4;
const TERRAIN_EPSILON: float32 = 0.03;
let shadowView: uint32 = 0;
let shadowSampler: uint32 = 0;
const groundHeights: Vec<float32> = [];

// box: centre x, z, the footprint's axes (cos, sin of its turn), half sizes along them, top, foot
function blocksLine(px: float32, pz: float32, light: float32, aim: float32, box: Vec<float32>): boolean {
	const cx: float32 = box[0];
	const cz: float32 = box[1];
	const c: float32 = box[2];
	const sn: float32 = box[3];
	// the line from the fire (world origin) to the point, in the pillar's own axes
	const ax: float32 = (0.0 - cx) * c + (0.0 - cz) * sn;
	const az: float32 = -(0.0 - cx) * sn + (0.0 - cz) * c;
	const bx: float32 = (px - cx) * c + (pz - cz) * sn;
	const bz: float32 = -(px - cx) * sn + (pz - cz) * c;
	if (bx > -box[4] && bx < box[4] && bz > -box[5] && bz < box[5]) { return false; }
	let enter: float32 = 0.0;
	let leave: float32 = 1.0;
	for (let axis = 0; axis < 2; axis++) {
		const start: float32 = axis == 0 ? ax : az;
		const d: float32 = axis == 0 ? bx - ax : bz - az;
		const half: float32 = box[4 + axis];
		if (d > -0.000001 && d < 0.000001) {
			if (start < -half || start > half) { return false; }
		} else {
			const t0: float32 = (-half - start) / d;
			const t1: float32 = (half - start) / d;
			enter = Math.max(enter, Math.min(t0, t1)) as float32;
			leave = Math.min(leave, Math.max(t0, t1)) as float32;
		}
	}
	if (enter > leave) { return false; }
	const height: float32 = light + (aim - light) * enter;
	return height < box[6];
}

// A pillar's footprint as a turned box: the turn that gives its vertices' smallest bounding
// rectangle (the exporter bakes the turn into the vertices, so the node only carries the centre).
function pillarBox(at: Vec3, mesh: MeshData): Vec<float32> {
	const v: Vec<float32> = mesh.vertices;
	const count: int32 = mesh.vertexCount();
	let best: Vec<float32> = [];
	let bestArea: float32 = 1.0e9;
	for (let step = 0; step < 180; step++) {
		const a: float32 = (step as float32) * 0.0087266;   // half a degree
		const c: float32 = cosf(a);
		const sn: float32 = sinf(a);
		let lo0: float32 = 1.0e9; let hi0: float32 = -1.0e9; let lo1: float32 = 1.0e9; let hi1: float32 = -1.0e9;
		for (let k = 0; k < count; k++) {
			const x: float32 = v[k * LIT_VERTEX_STRIDE];
			const z: float32 = v[k * LIT_VERTEX_STRIDE + 2];
			const u0: float32 = x * c + z * sn;
			const u1: float32 = -x * sn + z * c;
			lo0 = Math.min(lo0, u0) as float32; hi0 = Math.max(hi0, u0) as float32;
			lo1 = Math.min(lo1, u1) as float32; hi1 = Math.max(hi1, u1) as float32;
		}
		const area: float32 = (hi0 - lo0) * (hi1 - lo1);
		if (area < bestArea) {
			bestArea = area;
			const mid0: float32 = (lo0 + hi0) * 0.5;
			const mid1: float32 = (lo1 + hi1) * 0.5;
			best = [at.x + mid0 * c - mid1 * sn, at.z + mid0 * sn + mid1 * c, c, sn,
				(hi0 - lo0) * 0.5, (hi1 - lo1) * 0.5, at.y + mesh.bounds.max.y, at.y + mesh.bounds.min.y];
		}
	}
	return best;
}

function cellOf(metres: float32): int32 {
	const step: float32 = 2.0 * SHADOW_HALF / (SHADOW_SIZE as float32);
	const cell: int32 = Math.floor((metres + SHADOW_HALF) / step) as int32;
	return cell < 0 ? 0 : (cell >= SHADOW_SIZE ? SHADOW_SIZE - 1 : cell);
}

function groundAt(x: float32, z: float32): float32 {
	return groundHeights[cellOf(z) * SHADOW_SIZE + cellOf(x)];
}

// The GROUND mesh's triangles, top view, written into the height grid at every texel centre they
// cover (barycentric height). Texels no triangle covers keep the fire's ground.
function rasterizeGround(data: GltfData): void {
	for (let i = 0; i < SHADOW_SIZE * SHADOW_SIZE; i++) { groundHeights.push(fireGround); }
	const step: float32 = 2.0 * SHADOW_HALF / (SHADOW_SIZE as float32);
	for (const node of data.nodes) {
		if (node.name != "GROUND" || node.mesh < 0) { continue; }
		const at: Vec3 = node.local.position;
		const v: Vec<float32> = data.meshes[node.mesh].vertices;
		const index: Vec<uint16> = data.meshes[node.mesh].indices;
		for (let t = 0; t + 2 < (index.length as int32); t += 3) {
			const a: int32 = (index[t] as int32) * LIT_VERTEX_STRIDE;
			const b: int32 = (index[t + 1] as int32) * LIT_VERTEX_STRIDE;
			const c: int32 = (index[t + 2] as int32) * LIT_VERTEX_STRIDE;
			const ax: float32 = v[a] + at.x; const ay: float32 = v[a + 1] + at.y; const az: float32 = v[a + 2] + at.z;
			const bx: float32 = v[b] + at.x; const by: float32 = v[b + 1] + at.y; const bz: float32 = v[b + 2] + at.z;
			const cx: float32 = v[c] + at.x; const cy: float32 = v[c + 1] + at.y; const cz: float32 = v[c + 2] + at.z;
			const area: float32 = (bx - ax) * (cz - az) - (cx - ax) * (bz - az);
			if (area > -0.000001 && area < 0.000001) { continue; }
			const x0: int32 = cellOf(Math.min(ax, Math.min(bx, cx)) as float32);
			const x1: int32 = cellOf(Math.max(ax, Math.max(bx, cx)) as float32);
			const z0: int32 = cellOf(Math.min(az, Math.min(bz, cz)) as float32);
			const z1: int32 = cellOf(Math.max(az, Math.max(bz, cz)) as float32);
			for (let row = z0; row <= z1; row++) {
				const pz: float32 = ((row as float32) + 0.5) * step - SHADOW_HALF;
				for (let column = x0; column <= x1; column++) {
					const px: float32 = ((column as float32) + 0.5) * step - SHADOW_HALF;
					const wa: float32 = ((bx - px) * (cz - pz) - (cx - px) * (bz - pz)) / area;
					const wb: float32 = ((cx - px) * (az - pz) - (ax - px) * (cz - pz)) / area;
					const wc: float32 = 1.0 - wa - wb;
					if (wa < -0.0001 || wb < -0.0001 || wc < -0.0001) { continue; }
					groundHeights[row * SHADOW_SIZE + column] = wa * ay + wb * by + wc * cy;
				}
			}
		}
	}
}

// Whether the ground rises above the line from the light to (px, aim, pz) anywhere between.
function terrainBlocks(px: float32, pz: float32, light: float32, aim: float32): boolean {
	const length: float32 = Math.sqrt(px * px + pz * pz) as float32;
	if (length < TERRAIN_SKIP_START + TERRAIN_SKIP_END) { return false; }
	let along: float32 = TERRAIN_SKIP_START;
	while (along < length - TERRAIN_SKIP_END) {
		const t: float32 = along / length;
		const height: float32 = light + (aim - light) * t;
		if (groundAt(px * t, pz * t) > height + TERRAIN_EPSILON) { return true; }
		along = along + TERRAIN_STEP;
	}
	return false;
}

function buildShadowMap(data: GltfData): void {
	const started: float64 = performance.now();
	rasterizeGround(data);
	// per pillar: blocksLine's box, world metres
	const boxes: Vec<Vec<float32>> = [];
	for (const node of data.nodes) {
		if (!node.name.startsWith("PILLAR") || node.mesh < 0) { continue; }
		boxes.push(pillarBox(node.local.position, data.meshes[node.mesh]));
	}
	const light: float32 = fireGround + FIRE_HEIGHT;
	const texels: Vec<uint32> = new Array(SHADOW_SIZE * SHADOW_SIZE);
	const step: float32 = 2.0 * SHADOW_HALF / (SHADOW_SIZE as float32);
	let hidden: int32 = 0;
	for (let row = 0; row < SHADOW_SIZE; row++) {
		for (let column = 0; column < SHADOW_SIZE; column++) {
			const cx: float32 = ((column as float32) + 0.5) * step - SHADOW_HALF;
			const cz: float32 = ((row as float32) + 0.5) * step - SHADOW_HALF;
			let reached: int32 = 0;
			if (!terrainBlocks(cx, cz, light, groundAt(cx, cz) + SHADOW_AIM)) {
				for (let k = 0; k < 4; k++) {
					const px: float32 = ((column as float32) + 0.25 + 0.5 * ((k % 2) as float32)) * step - SHADOW_HALF;
					const pz: float32 = ((row as float32) + 0.25 + 0.5 * ((k / 2) as float32)) * step - SHADOW_HALF;
					const aim: float32 = groundAt(px, pz) + SHADOW_AIM;
					let lit: boolean = true;
					for (const box of boxes) {
						if (blocksLine(px, pz, light, aim, box)) { lit = false; break; }
					}
					if (lit) { reached = reached + 1; }
				}
			} else {
				hidden = hidden + 1;
			}
			const value: uint32 = ((reached * 255) / 4) as uint32;
			texels[row * SHADOW_SIZE + column] = (0xFF000000 as uint32) | (value << 16) | (value << 8) | value;
		}
	}
	shadowView = makeTextureView(makeImage(texels, SHADOW_SIZE, SHADOW_SIZE));
	shadowSampler = Sampler.create(Filter.Linear, Wrap.Clamp).handle;
	console.log("grass lab: fire shadows from " + (boxes.length as int32).toString() + " pillars, "
		+ hidden.toString() + " texels behind the terrain, "
		+ ((performance.now() - started) as int32).toString() + " ms");
}

// A few round-crowned trees and bushes (scripts/make-plants.py, from t3ssel8r-lab's broadleaf
// sheet; user, 2026-10-02): LEAF_ meshes on their own ramp row, lit round like the clumps (wrap)
// (LEAF_MARK), TRUNK_ ones as the logs.
// No file, no plants. They cast no fire shadow.
const LEAF_WRAP: float32 = 0.45;
// Leaf cards over the crowns and bushes (make-plants.py plant_leaves.f32): the short grass's
// rosettes on the leaf ramp, swaying a little; each card carries its face's moon steps (shape.z).
const LEAF_CARD_SWAY: float32 = 0.35;
// No band blending on the cards (one colour a band, as the grass clumps).
const LEAF_CARD_FAR: Vec<float32> = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
// Above 1: the texture's light clumps (vertex red) are not drawn a step up; they speckled the
// crowns, which read better from the moon's steps alone (0.5 turns them on).
const LEAF_MARK: float32 = 2.0;

function addPlants(root: NodeId, state: RenderState, ramps: uint32, sampler: uint32, wood: int32): boolean {
	if (labFileSize(DATA + "plants.gltf") <= 0) { return true; }
	const json = readFile(DATA + "plants.gltf");
	if (!json.ok) { return true; }
	const buffer: Vec<uint8> = readBytes("plants.bin");
	const loaded: Result<GltfData, GltfError> = loadGltf(json.value, buffer);
	if (!loaded.ok) { console.log("grass lab: plants.gltf was refused: " + loaded.error.toString()); return false; }
	const data: GltfData = loaded.value;
	const leaf: int32 = rampLit(state, ramps, sampler, rampBlock(ROW_LEAF, 0.0, 0.0, LEAF_MARK, 0.0, LEAF_WRAP, NO_FAR));
	const bindings: Vec<GltfMeshBinding> = [];
	for (let i = 0; i < (data.meshes.length as int32); i++) {
		const uploaded: Result<int32, MeshUploadError> = addMeshData(context, data.meshes[i]);
		if (!uploaded.ok) { console.log("grass lab: a plant mesh did not upload"); return false; }
		let material: int32 = leaf;
		for (const node of data.nodes) {
			if (node.mesh == i && node.name.startsWith("TRUNK_")) { material = wood; }
		}
		bindings.push({ mesh: uploaded.value, material: material });
	}
	const added: Result<int32, GltfSceneError> = addGltfNodes(tree, root, data, bindings);
	if (!added.ok) { console.log("grass lab: the plants were refused"); return false; }
	const cards: Vec<float32> = readFloats("plant_leaves.f32");
	const cardCount: int32 = (cards.length as int32) / INSTANCE_STRIDE;
	if (cardCount > 0) {
		for (let i = 0; i < cardCount; i++) {
			cards[i * INSTANCE_STRIDE + 4] = (SHORT_CELL_W as float32) * LAB_METRES_PER_TEXEL * zoomOut;
			cards[i * INSTANCE_STRIDE + 5] = (SHORT_CELL_H as float32) * LAB_METRES_PER_TEXEL * zoomOut;
		}
		const cardMaterial: int32 = addMaterial(context, {
			...Material.plain(Program.BillboardRamp, state, Phase.Opaque),
			texture0: atlasImage("atlas_short.rgba", SHORT_CELL_W * 4, SHORT_CELL_H),
			texture1: ramps,
			texture2: shadowView,
			sampler0: sampler,
			sampler1: shadowSampler,
			uniforms: spriteRampBlock(ROW_LEAF, 0.0, LEAF_CARD_SWAY, 0.0, LEAF_CARD_FAR),
		});
		const cardMesh: int32 = addMesh(
			context,
			GpuMesh.external(VertexLayout.Billboard, makeVertexBuffer(CORNERS), makeVertexBuffer(cards), 6, cardCount),
		);
		const cardNode: Result<NodeId, SceneError> = addMeshNode(tree, root, identityTransform(), cardMesh, cardMaterial);
		if (!cardNode.ok) { return false; }
		console.log("grass lab: " + cardCount.toString() + " leaf cards");
	}
	console.log("grass lab: " + (data.nodes.length as int32).toString() + " plant nodes");
	return true;
}

function setup(): boolean {
	const json = readFile(DATA + "grass_lab.gltf");
	if (!json.ok) { console.log("grass lab: no grass_lab.gltf in " + DATA); return false; }
	const buffer: Vec<uint8> = readBytes("grass_lab.bin");
	const loaded: Result<GltfData, GltfError> = loadGltf(json.value, buffer);
	if (!loaded.ok) { console.log("grass lab: the glTF was refused"); return false; }
	const data: GltfData = loaded.value;
	const fireAt: Vec<float32> = readFloats("fire.f32");
	if ((fireAt.length as int32) >= 3) { fireGround = fireAt[1]; }
	buildShadowMap(data);

	const state: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(true, Compare.LessEqual);
	const sampler: Sampler = Sampler.create(Filter.Nearest, Wrap.Clamp);
	const ramps: uint32 = atlasImage("ramps.rgba", RAMP_WIDTH, RAMP_ROWS);
	// Stones and logs: firelit walls are flat faces. The lawn: wrapped light, as the clumps.
	let lit: int32 = 0;
	let lawn: int32 = 0;
	let wood: int32 = 0;
	if (rampLook) {
		lawn = rampLit(state, ramps, sampler.handle, rampBlock(ROW_GRASS, 0.0, LAWN_STEPS, TALL_MARK, 0.0, GRASS_WRAP, LAWN_FAR));
		lit = rampLit(state, ramps, sampler.handle, rampBlock(ROW_STONE, ROW_TOP + 1.0, 0.0, 0.0, 1.0, 0.0, STONE_FAR));
		wood = rampLit(state, ramps, sampler.handle, rampBlock(ROW_WOOD, 0.0, 0.0, 0.0, 0.0, WOOD_WRAP, NO_FAR));
	} else {
		lit = litMaterial(state, labShader, 0.0);
		lawn = litMaterial(state, 0.0, GRASS_WRAP * labShader);
		wood = lit;
	}

	// The exporter writes one node per mesh, in the same order.
	const bindings: Vec<GltfMeshBinding> = [];
	for (let i = 0; i < (data.meshes.length as int32); i++) {
		const uploaded: Result<int32, MeshUploadError> = addMeshData(context, data.meshes[i]);
		if (!uploaded.ok) { console.log("grass lab: a mesh did not upload"); return false; }
		const name: string = data.nodes[i].name;
		let material: int32 = lit;
		if (name == "GROUND") { material = lawn; }
		if (name.startsWith("LOG_")) { material = wood; }
		bindings.push({ mesh: uploaded.value, material: material });
	}
	const root: NodeId = tree.rootId();
	const added: Result<int32, GltfSceneError> = addGltfNodes(tree, root, data, bindings);
	if (!added.ok) { console.log("grass lab: the glTF nodes were refused"); return false; }
	if (rampLook && !addPlants(root, state, ramps, sampler.handle, wood)) { return false; }

	// The lab's moon, (-0.45, 0.25, 0.86) toward it in Blender's Z up, is (-0.45, 0.86, -0.25) here.
	const moonToward: Vec3 = vec3(-0.45, 0.86, -0.25).normalized();
	const moon: Result<NodeId, SceneError> = addLightNode(
		tree,
		root,
		{ ...identityTransform(), rotation: quatBetween(vec3(0.0, 0.0, 1.0), moonToward.scaled(-1.0)) },
		{ kind: LightKind.Directional, color: vec3(1.0, 1.0, 1.0), radius: 0.0, power: MOON_POWER, priority: 100 },
	);
	if (!moon.ok) { return false; }
	const fire: Result<NodeId, SceneError> = addLightNode(
		tree,
		root,
		transformAt(vec3(0.0, fireGround + FIRE_HEIGHT, 0.0)),
		{ kind: LightKind.Point, color: vec3(1.0, 0.42, 0.16), radius: fireRadius(), power: firePower(), priority: 0 },
	);
	if (!fire.ok) { return false; }
	fireLight = fire.value;
	setAmbient(tree, vec3(AMBIENT_R, AMBIENT_G, AMBIENT_B));

	const corners: uint32 = makeVertexBuffer(CORNERS);
	// The wind blows to screen right and away from the camera, in world x, z.
	const rightX: float32 = cosOf(CAMERA_YAW);
	const rightZ: float32 = -sinf(CAMERA_YAW);
	const dirX: float32 = rightX * WIND_RIGHT - (-rightZ) * WIND_AWAY;
	const dirZ: float32 = rightZ * WIND_RIGHT - rightX * WIND_AWAY;
	const dirLength: float32 = Math.sqrt(dirX * dirX + dirZ * dirZ) as float32;
	windDirX = dirX / dirLength;
	windDirZ = dirZ / dirLength;
	const shortAtlas: uint32 = atlasImage("atlas_short.rgba", SHORT_CELL_W * 4, SHORT_CELL_H);
	const tallAtlas: uint32 = atlasImage("atlas_tall.rgba", TALL_CELL_W * 4, TALL_CELL_H);
	const flameAtlas: uint32 = atlasImage("atlas_flame.rgba", FLAME_CELL_W * 4, FLAME_CELL_H);
	const flameAtlas2: uint32 = atlasImage("atlas_flame2.rgba", FLAME_CELL_W * 4, FLAME_CELL_H);
	placeSprigs();
	if (!addClumps(root, corners, "clumps_short.f32", shortAtlas, ramps, sampler.handle, state, 0.0, SHORT_SWAY, SHORT_CELL_W, SHORT_CELL_H, SHORT_KEEP)) { return false; }
	if (!addClumps(root, corners, "clumps_tall.f32", tallAtlas, ramps, sampler.handle, state, TALL_STEPS, TALL_SWAY, TALL_CELL_W, TALL_CELL_H, TALL_KEEP)) { return false; }
	if (rampLook && SPRIGS_WANTED && !addFlowers(root, corners, ramps, sampler.handle, state)) { return false; }
	if (rampLook) {
		// The lab's pale tufts: still, two steps up the tuft ramp.
		const tufts: Vec<float32> = readFloats("tufts.f32");
		const tuftCount: int32 = (tufts.length as int32) / INSTANCE_STRIDE;
		const tuftMaterial: int32 = addMaterial(context, {
			...Material.plain(Program.BillboardRamp, state, Phase.Opaque),
			texture0: atlasImage("atlas_tuft.rgba", TUFT_CELL_W * 4, TUFT_CELL_H),
			texture1: ramps,
			texture2: shadowView,
			sampler0: sampler.handle,
			sampler1: shadowSampler,
			uniforms: spriteRampBlock(ROW_TUFT, TUFT_STEPS, 0.0, 0.0, NO_FAR),
		});
		const tuftMesh: int32 = addMesh(
			context,
			GpuMesh.external(VertexLayout.Billboard, corners, makeVertexBuffer(tufts), 6, tuftCount),
		);
		const tuftNode: Result<NodeId, SceneError> = addMeshNode(tree, root, identityTransform(), tuftMesh, tuftMaterial);
		if (!tuftNode.ok) { return false; }
	}
	if (walkerWanted && labFileSize(WALKER_DIR + "walker.glb") > 0) {
		const lens: int32 = rampLook
			? rampLit(state, ramps, sampler.handle, rampBlock(ROW_LENS, 0.0, 0.0, 0.0, 0.0, 0.0, NO_FAR))
			: litMaterial(state, 0.0, 0.0);
		if (!setupFourLegs(root, state, litMaterial(state, 0.0, 0.0), lens)) { console.log("grass lab: the four-legged walker was refused"); return false; }
	} else if (walkerWanted) {
		// A placeholder figure as the lab's (8 x 36 texels: 0.25 m across, 1.3 m tall), lit as wood.
		walkerPath = readFloats("walker.f32");
		let figure: MeshData = MeshData.empty();
		const body: Box = {
			base: vec3(0.0, 0.0, 0.0),
			size: vec3(0.25, 1.3, 0.25),
			yaw: CAMERA_YAW,
			tilt: 0.0,
			color: { red: 0.16, green: 0.12, blue: 0.2, alpha: 1.0 },
		};
		const built: Result<int32, MeshError> = addBox(figure, body);
		const uploaded: Result<int32, MeshUploadError> = addMeshData(context, figure);
		if (!built.ok || !uploaded.ok) { return false; }
		const walker: Result<NodeId, SceneError> = addMeshNode(tree, root, identityTransform(), uploaded.value, wood);
		if (!walker.ok) { return false; }
		walkerNode = walker.value;
	}
	if (particlesWanted && !setupParticles(root, state)) {
		console.log("grass lab: the particles were refused");
		return false;
	}

	// Mesh i draws atlas cell i % 4; frame f is mesh f of the first node (f < 4) or mesh f - 4
	// of the second. Tested against the scene's depth but not written: drawn last (it is added
	// last), it goes over the snow behind it and under what stands in front (FLAME_ROOT).
	const overlay: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(false, Compare.LessEqual);
	firstFlameMesh = context.meshes.length as int32;
	for (let i = 0; i < 4; i++) {
		addMesh(context, GpuMesh.external(VertexLayout.Billboard, corners, makeVertexBuffer(flameInstance(i)), 6, 1));
	}
	const flame: Result<NodeId, SceneError> = addMeshNode(tree, root, identityTransform(), firstFlameMesh,
		addMaterial(context, {
			...Material.plain(Program.Billboard, overlay, Phase.Opaque),
			texture0: flameAtlas,
			sampler0: sampler.handle,
			uniforms: spriteBlock(0.0, 0.0, 0.0, 0.0, 0.0),
		}));
	const flame2: Result<NodeId, SceneError> = addMeshNode(tree, root, identityTransform(), firstFlameMesh,
		addMaterial(context, {
			...Material.plain(Program.Billboard, overlay, Phase.Opaque),
			texture0: flameAtlas2,
			sampler0: sampler.handle,
			uniforms: spriteBlock(0.0, 0.0, 0.0, 0.0, 0.0),
		}));
	if (!flame.ok || !flame2.ok) { return false; }
	flameNode = flame.value;
	flameNode2 = flame2.value;

	const palette: Vec<uint32> = readWords(rampLook ? "palette.u32" : "palette_toon.u32");
	let settings: PixelArtSettings = { ...PixelArtSettings.full(), margin: 1 };
	if (labEnvInt("LAB_OUTLINE", 1) == 0) { settings = { ...settings, outline: false }; }
	setSettings(renderer, settings);
	// The ramp look's colours are ramp colours already; the LUT would only pull what the outline
	// darkens onto whatever palette colour is nearest (the pale tufts' among them), so it is off
	// there unless asked for.
	if (labEnvInt("LAB_PALETTE", rampLook ? 0 : 1) != 0 && (palette.length as int32) > 0) {
		const filled: Result<int32, PaletteError> = setPalette(renderer, palette);
		if (filled.ok) { setSettings(renderer, { ...renderer.settings, palette: true }); }
	}
	console.log("grass lab: " + (data.meshes.length as int32).toString() + " meshes, palette "
		+ (palette.length as int32).toString());
	return true;
}

// The Hibernal Home HUD (hudHome.ms) drawn over the scene; LAB_HUD=0 turns it off.
let hudWanted: boolean = true;

export function initLab(): void {
	gfxSetup();
	panPer100 = labEnvInt("LAB_PAN", 0);
	snapWanted = labEnvInt("LAB_SNAP", 1) != 0;
	captureAt = labEnvInt("LAB_CAPTURE", -1);
	windWanted = labEnvInt("LAB_WIND", 1) != 0;
	rampLook = labEnvInt("LAB_RAMP", 1) != 0;
	walkerWanted = labEnvInt("LAB_WALKER", 1) != 0;
	particlesWanted = labEnvInt("LAB_PARTICLES", 1) != 0;
	hudWanted = labEnvInt("LAB_HUD", 1) != 0;
	snowWanted = labEnvInt("LAB_SNOW", 0) != 0;
	walkerFx = labEnvInt("LAB_WALKER_FX", 1) != 0;
	zoomOut = (labEnvInt("LAB_ZOOM", DEFAULT_ZOOM) as float32) / 100.0;
	fogGlow = (labEnvInt("LAB_FOG", FOG_GLOW_PERCENT) as float32) / 100.0;
	fogVeil = (labEnvInt("LAB_VEIL", FOG_VEIL_PERCENT) as float32) / 100.0;
	nightFlat = (labEnvInt("LAB_FLAT", NIGHT_FLAT_PERCENT) as float32) / 100.0;
	LAB_FIRE_FALL = -(labEnvInt("LAB_FALL", 70) as float32) / 100.0;
	WALLS_AT_ORIGIN = labEnvInt("LAB_WALLS", 1) != 0 ? 1.0 : 0.0;
	if (labEnvInt("LAB_SHADER", 1) == 0) {
		labShader = 0.0;
		windWanted = false;
		rampLook = false;
	}
	ready = setup();
	// after the scene: its gfxSetup is done and the HUD's assets load inside the asset root
	if (ready && hudWanted) { initHudHome(); }
}

// The fire: a new light position and power every FLICKER_EVERY frames, the flame sprite a new
// cell every FLAME_EVERY frames - both stepped, as the lab's 12 fps.
// The lab's flicker_at: the fire's reach over the loop, whole cycles only so it loops.
function labFlicker(loop: float32): float32 {
	const tau: float32 = 6.2831853 * loop;
	const a: float32 = 0.045;
	const b: float32 = 0.03;
	const c: float32 = 0.02;
	const one: float32 = 1.0;
	return one + a * sinf(3.0 * tau) + b * sinf(7.0 * tau + 1.3) + c * sinf(13.0 * tau + 2.1);
}

// Whether a step that happens every `every` frames fell between the last frame and this one.
function due(every: int32): boolean {
	return previousIndex < 0 || frameIndex / every != previousIndex / every;
}

// Seconds since the last frame; a gap longer than LONGEST_FRAME_SECONDS is a pause, not time.
function advanceClock(): float32 {
	if (captureAt >= 0) {
		frameIndex = previousIndex + 1;
		return (1.0 / FRAMES_PER_SECOND) as float32;
	}
	const now: float64 = performance.now() / 1000.0;
	let passed: float64 = lastFrameAt < 0.0 ? 0.0 : now - lastFrameAt;
	lastFrameAt = now;
	if (passed < 0.0 || passed > LONGEST_FRAME_SECONDS) { passed = 0.0; }
	labSeconds = labSeconds + passed;
	frameIndex = (labSeconds * (FRAMES_PER_SECOND as float64)) as int32;
	return passed as float32;
}

function seconds(): float32 { return (frameIndex as float32) / FRAMES_PER_SECOND; }

function flicker(): void {
	if (rampLook && due(FLICKER_EVERY)) {
		// The lab keeps the fire still and breathes its reach.
		const held: float32 = ((frameIndex - frameIndex % FLICKER_EVERY) as float32) / FRAMES_PER_SECOND;
		const loop: float32 = held / FLICKER_LOOP_SECONDS - ((held / FLICKER_LOOP_SECONDS) as int32 as float32);
		const light: int32 = tree.nodes[fireLight.index].payload;
		tree.lights[light].radius = LAB_FIRE_R * labFlicker(loop);
	} else if (!rampLook && due(FLICKER_EVERY)) {
		const dx: float32 = (nextRandom() - 0.5) * 0.14;
		const dz: float32 = (nextRandom() - 0.5) * 0.14;
		const moved: Result<int32, SceneError> = setLocal(tree, fireLight, transformAt(vec3(dx, fireGround + FIRE_HEIGHT, dz)));
		const powered: Result<int32, SceneError> =
			setLightPower(tree, fireLight, firePower() * (0.93 + nextRandom() * 0.14));
		if (!moved.ok || !powered.ok) { return; }
	}
	const cell: int32 = (frameIndex / FLAME_EVERY) % FLAME_FRAMES;
	const first: boolean = cell < 4;
	const shown: NodeId = first ? flameNode : flameNode2;
	const _swapped: Result<int32, SceneError> = setMeshOf(tree, shown, firstFlameMesh + (first ? cell : cell - 4));
	const _one: Result<int32, SceneError> = setVisible(tree, flameNode, first);
	const _two: Result<int32, SceneError> = setVisible(tree, flameNode2, !first);
}

// The fire's place in the low-res target (texelOf in camera.ms, the target's row order) and
// depth, for the post pass's fog glow.
function placeGlow(view: CameraView): void {
	const fire: Vec4 = vec4(0.0, fireGround + FOG_GLOW_HEIGHT, 0.0, 1.0) * view.viewProj;
	const width: float32 = view.texelWidth as float32;
	const height: float32 = view.texelHeight as float32;
	glowValues[0] = (fire.x + 1.0) * 0.5 * width;
	glowValues[1] = (originTopLeft() ? 1.0 - fire.y : fire.y + 1.0) * 0.5 * height;
	glowValues[2] = fire.z;
	glowValues[3] = fogGlow;
	glowValues[4] = view.worldPerTexel;
	glowValues[5] = CAMERA_FAR - CAMERA_NEAR;
	glowValues[6] = FOG_GLOW_SOFT;
	glowValues[7] = FOG_GLOW_BANDS;
	glowValues[8] = FOG_GLOW_COLOR.x;
	glowValues[9] = FOG_GLOW_COLOR.y;
	glowValues[10] = FOG_GLOW_COLOR.z;
	glowValues[11] = FOG_GLOW_REACH;
	glowValues[12] = FOG_MIST_CELL;
	glowValues[13] = FOG_MIST_AMOUNT;
	glowValues[14] = -seconds() * FOG_MIST_DRIFT;
	glowValues[15] = -seconds() * FOG_MIST_DRIFT * 0.3;
	glowValues[16] = FOG_VEIL_COLOR.x;
	glowValues[17] = FOG_VEIL_COLOR.y;
	glowValues[18] = FOG_VEIL_COLOR.z;
	glowValues[19] = fogVeil;
	glowValues[20] = NIGHT_FLAT_COLOR.x;
	glowValues[21] = NIGHT_FLAT_COLOR.y;
	glowValues[22] = NIGHT_FLAT_COLOR.z;
	glowValues[23] = nightFlat;
	setGlow(renderer, glowValues);
}

export function frameLab(): void {
	if (!ready) { return; }
	const _passed: float32 = advanceClock();
	const none: float32 = 0.0;
	const sized: Result<LowResView, ViewError> = renderer.viewFor(fbWidth(), fbHeight(), none, none);
	if (!sized.ok) { return; }
	const grid: LowResView = sized.value;
	const shortSide: float32 = Math.min(grid.width, grid.height) as float32;
	const worldPerTexel: float32 = UNITS_ON_SHORT_SIDE * zoomOut / shortSide;
	const centred: OrthoCamera = {
		target: vec3(0.0, TARGET_HEIGHT, 0.0),
		yaw: CAMERA_YAW,
		pitch: CAMERA_PITCH,
		worldPerTexel: worldPerTexel,
		nearPlane: CAMERA_NEAR,
		farPlane: CAMERA_FAR,
		snap: snapWanted,
	};
	// A slow slide to the right and a little up the screen, so every sub-texel offset shows.
	const texels: float32 = ((panPer100 * frameIndex) as float32) / 100.0;
	const basis = centred.basisOf();
	const target: Vec3 = centred.target + basis.right.scaled(texels * worldPerTexel)
		+ basis.up.scaled(texels * 0.37 * worldPerTexel);
	const camera: OrthoCamera = { ...centred, target: target };
	const resolved: Result<CameraView, CameraError> = camera.resolve(grid.width, grid.height);
	if (!resolved.ok) { return; }
	const view: CameraView = resolved.value;
	const shifted: Result<LowResView, ViewError> =
		renderer.viewFor(fbWidth(), fbHeight(), view.remainderX, view.remainderY);
	if (!shifted.ok) { return; }
	view.writeCameraBlock(cameraParams);
	placeGlow(view);
	// The billboard program reads the wind from the camera block's spare lanes: the sway in
	// cameraRight.w, the time (s, at 60 fps) in cameraUp.w.
	if (windWanted) {
		cameraParams[19] = WIND_SWAY;
		cameraParams[23] = (frameIndex as float32) / 60.0;
	}

	flicker();
	if (walkerWanted && (walkerParts.length as int32) > 0) {
		if (!poseFourLegs()) { return; }
	} else if (walkerWanted && (walkerPath.length as int32) >= 3) {
		const steps: int32 = (walkerPath.length as int32) / 3;
		const at: int32 = ((seconds() * WALKER_FPS) as int32) % steps;
		walkerX = walkerPath[at * 3];
		walkerZ = walkerPath[at * 3 + 2];
		const placed: Result<int32, SceneError> =
			setLocal(tree, walkerNode, transformAt(vec3(walkerX, walkerPath[at * 3 + 1], walkerZ)));
		if (!placed.ok) { return; }
	}
	if (walkerWanted) { trackWalker(); }
	if (rampLook) { updateSprites(worldPerTexel); }
	const drawn: int32 = refresh(tree, sceneItems);
	if (drawn == 0) { return; }
	const lit: Result<int32, LightError> = collectLights(tree, lightParams);
	if (!lit.ok) { return; }
	if (particlesWanted && due(PARTICLE_EVERY)) {
		const snowed: boolean = !snowWanted
			|| (advanceEmitter(snow, snowNode) && drawEmitter(snow, snowNode, snowMesh, snowInstances));
		if (!snowed || !advanceEmitter(embers, emberNode)
			|| !drawEmitter(embers, emberNode, emberMesh, emberInstances)) {
			console.log("grass lab: a particle emitter failed to step or draw");
			return;
		}
	}
	if (hudWanted) { skipNextCommit(); }
	renderFrame(renderer, context, sceneItems, cameraParams, lightParams, shifted.value);
	if (hudWanted) { frameHudHome(); }

	if (captureAt >= 0) {
		const out: string = "out/shots/";
		if (frameIndex == captureAt || frameIndex == captureAt + 30 || frameIndex == captureAt + 60) {
			const saved: int32 = labCapture(out + "frame_" + frameIndex.toString() + ".ppm");
			console.log("grass lab: captured frame " + frameIndex.toString() + " ok=" + saved.toString());
		}
		if (frameIndex >= captureAt + 60) { labExit(0); }
	}
	previousIndex = frameIndex;
}

