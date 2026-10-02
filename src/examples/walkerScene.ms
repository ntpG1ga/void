// Void — hibernal's walker pet roaming its hills round the campfire.
//
// Everything drawn comes from hibernal/assets, copied into assets/hibernal/ by
// scripts/sync-hibernal-assets.py: the hills, the pillars and the campfire logs are static
// glTF scenes, and the walker is 12 rigid nodes posed every clip frame from walkerClips.bin.
// The clip played is roamHills, the wander t3ssel8r-lab/scripts/walker_roam.py baked on these
// same hills (root in scene metres, feet planted on this ground), stepped at the clip's 12 fps.
// It is 90 s long and does not loop: when it ends the walker starts again from its first frame.

import { readFile } from "std/fs";
import { gfxSetup, fbWidth, fbHeight } from "../sokol/gpu";
import { LIGHT_UNIFORM_LENGTH, TOON_UNIFORM_SLOT, TOON_UNIFORM_LENGTH, Program } from "../void3d/gpu3d";
import { RenderState, Face, Compare } from "../void3d/pass";
import { Material, Phase, UniformBlock, NO_UNIFORMS } from "../void3d/material";
import { DrawContext, DrawItem, MeshUploadError, addMeshData, addMaterial, reserveUniforms, writeUniforms } from "../void3d/draw";
import { LowResView, ViewError } from "../void3d/blit";
import {
	PixelArtRenderer,
	PixelArtSettings,
	PixelArtError,
	PixelArtLook,
	PIXEL_ART_UNIFORM_LENGTH,
	renderFrame,
} from "../void3d/pixelArtRenderer";
import { Vec3, vec3, quatBetween } from "../math/math3d";
import {
	Scene,
	NodeId,
	SceneError,
	LightError,
	LightKind,
	identityTransform,
	transformAt,
	addLightNode,
	setLocal,
	setLightPower,
	setAmbient,
	collectLights,
	refresh,
} from "../void3d/scene";
import { OrthoCamera, CameraView, CameraError, CAMERA_BLOCK_LENGTH } from "../void3d/camera";
import { loadGltf, GltfData, GltfError } from "../void3d/gltf";
import { addGltfNodes, GltfMeshBinding, GltfSceneError } from "../void3d/gltfScene";
import { float32At } from "../void3d/gltfDecode";
import { MeshData, LIT_VERTEX_STRIDE } from "../void3d/meshData";

const ASSETS: string = "assets/hibernal/";
const ROAM_CLIP: string = "roamHills";
const FLOATS_PER_NODE: int32 = 7;
const CLIPS_MAGIC: int32 = 0x504C4357;

// The lab's fire camera: 45 deg round, 30 deg down. It frames the ground the roam covers
// (x -7..8, z -2..9 round the fire at the origin), not the fire itself.
const CAMERA_YAW: float32 = 0.785398;
const CAMERA_PITCH: float32 = 0.523599;
const UNITS_ON_SHORT_SIDE: float32 = 22.0;
const CAMERA_TARGET_X: float32 = 1.5;
const CAMERA_TARGET_Y: float32 = 0.5;
const CAMERA_TARGET_Z: float32 = 1.0;

const FIRE_HEIGHT: float32 = 0.9;
const FIRE_INTENSITY: float32 = 1.5;
const FIRE_RADIUS: float32 = 12.0;
const LIGHT_LEVELS: float32 = 5.0;
const FLICKER_SECONDS: float64 = 0.12;
// A frame longer than this is a pause (the app was in the background), not time to catch up.
const LONGEST_FRAME_SECONDS: float64 = 0.25;

const RANDOM_MULTIPLIER: uint64 = 6364136223846793005;
const RANDOM_INCREMENT: uint64 = 1442695040888963407;
const RANDOM_RANGE: float32 = 16777216.0;

let context: DrawContext = DrawContext.withUniformCapacity(PIXEL_ART_UNIFORM_LENGTH + TOON_UNIFORM_LENGTH);
let renderer: PixelArtRenderer = createRenderer();
const sceneItems: Vec<DrawItem> = [];
let tree: Scene = Scene.create();
const lightParams: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
const cameraParams: Vec<float32> = new Array(CAMERA_BLOCK_LENGTH);
let fireLight: NodeId = { index: -1, generation: 0 };
let ready: boolean = false;

// walkerClips.bin, unpacked: every clip's frames in one array, a clip being a run of it.
let clipFps: float64 = 12.0;
const clipNodeNames: Vec<string> = [];
const clipNames: Vec<string> = [];
const clipFirstFloat: Vec<int32> = [];
const clipFrameCounts: Vec<int32> = [];
const clipData: Vec<float32> = [];
// The scene node each clip node poses, in the clips' node order.
const walkerNodes: Vec<NodeId> = [];

let roamClip: int32 = -1;
let roamSeconds: float64 = 0.0;
let shownFrame: int32 = -1;
let lastFrameAt: float64 = -1.0;
let flickerSeconds: float64 = 0.0;
let randomState: uint64 = 88172645463325252;

// The hills are a 60 m square and a portrait frame looks past its near and far corners, so
// the background and the fog take the colour the moonlit grass draws at: the map has no edge.
function nightLook(): PixelArtLook {
	return {
		background: { x: 0.071, y: 0.18, z: 0.082, w: 0.0 },
		outline: {
			depthThreshold: 0.006,
			normalThreshold: 0.6,
			depthShade: 0.55,
			normalShade: 1.35,
		},
		fog: {
			start: 0.62,
			end: 0.9,
			strength: 0.85,
			color: { x: 0.071, y: 0.18, z: 0.082, w: 0.0 },
		},
		saturation: 0.0,
	};
}

// The pool is sized for the renderer's blocks plus the one toon block, so create cannot fail.
function createRenderer(): PixelArtRenderer {
	const created: Result<PixelArtRenderer, PixelArtError> = PixelArtRenderer.create(
		context,
		PixelArtSettings.full(),
		nightLook(),
	);
	if (created.ok) { return created.value; }
	unreachable;
}

function nextRandom(): float32 {
	randomState = randomState * RANDOM_MULTIPLIER + RANDOM_INCREMENT;
	const high: uint64 = randomState >> 40;
	const sample: float32 = high as float32;
	return sample / RANDOM_RANGE;
}

function word(bytes: Span<uint8>, at: int32): int32 {
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

function padded(length: int32): int32 {
	return ((length + 3) / 4) * 4;
}

function displayValue(linear: float32): float32 {
	if (linear <= 0.0031308) { return (linear * 12.92) as float32; }
	return (1.055 * Math.pow(linear, 1.0 / 2.4) - 0.055) as float32;
}

// glTF's COLOR_0 is linear light, and the lit program shades the vertex colour as a display
// value: unconverted, the hills' green (0.012, 0.061, 0.009) draws as near black.
function encodeColors(ref mesh: MeshData): void {
	const count: int32 = mesh.vertexCount();
	for (let v = 0; v < count; v++) {
		const at: int32 = v * LIT_VERTEX_STRIDE + 6;
		mesh.vertices[at] = displayValue(mesh.vertices[at]);
		mesh.vertices[at + 1] = displayValue(mesh.vertices[at + 1]);
		mesh.vertices[at + 2] = displayValue(mesh.vertices[at + 2]);
	}
}

// One GLB of void's glTF subset, uploaded and hung under the root. Its nodes keep their names.
function addModel(name: string, material: int32): boolean {
	const file = readFile(ASSETS + name);
	if (!file.ok) { console.log("walker: cannot read " + name); return false; }
	const bytes: uint8[] = file.value.asBytes();
	const all: Span<uint8> = bytes;
	if ((bytes.length as int32) < 28 || word(all, 0) != 0x46546C67) {
		console.log("walker: " + name + " is not a GLB");
		return false;
	}
	const jsonLength: int32 = word(all, 12);
	const jsonBytes: uint8[] = [];
	for (let i = 20; i < 20 + jsonLength; i++) { jsonBytes.push(all[i]); }
	const json: string = jsonBytes.asString();
	const binLength: int32 = word(all, 20 + jsonLength);
	const bin: Span<uint8> = all[28 + jsonLength..28 + jsonLength + binLength];
	const loaded: Result<GltfData, GltfError> = loadGltf(json, bin);
	if (!loaded.ok) { console.log("walker: " + name + " refused " + loaded.error.toString()); return false; }
	const data: GltfData = loaded.value;
	const bindings: Vec<GltfMeshBinding> = [];
	for (let i = 0; i < (data.meshes.length as int32); i++) {
		let mesh: MeshData = data.meshes[i];
		encodeColors(mesh);
		const uploaded: Result<int32, MeshUploadError> = addMeshData(context, mesh);
		if (!uploaded.ok) { console.log("walker: " + name + " mesh upload failed"); return false; }
		bindings.push({ mesh: uploaded.value, material: material });
	}
	const added: Result<int32, GltfSceneError> = addGltfNodes(tree, tree.rootId(), data, bindings);
	if (!added.ok) { console.log("walker: " + name + " did not enter the scene"); return false; }
	return true;
}

function loadClips(): boolean {
	const file = readFile(ASSETS + "walkerClips.bin");
	if (!file.ok) { console.log("walker: cannot read walkerClips.bin"); return false; }
	const bytes: uint8[] = file.value.asBytes();
	const all: Span<uint8> = bytes;
	const size: int32 = bytes.length as int32;
	if (size < 16 || word(all, 0) != CLIPS_MAGIC) { console.log("walker: walkerClips.bin is not a clip file"); return false; }
	clipFps = word(all, 4) as float64;
	const nodeCount: int32 = word(all, 8);
	const clipCount: int32 = word(all, 12);
	let at: int32 = 16;
	for (let i = 0; i < nodeCount; i++) {
		const length: int32 = word(all, at);
		clipNodeNames.push(textAt(all, at + 4, length));
		at = at + 4 + padded(length);
	}
	for (let i = 0; i < clipCount; i++) {
		const length: int32 = word(all, at);
		clipNames.push(textAt(all, at + 4, length));
		at = at + 4 + padded(length);
		const frames: int32 = word(all, at);
		at = at + 8;
		const floats: int32 = frames * nodeCount * FLOATS_PER_NODE;
		if (at + floats * 4 > size) { console.log("walker: walkerClips.bin is cut short"); return false; }
		clipFirstFloat.push(clipData.length as int32);
		clipFrameCounts.push(frames);
		for (let k = 0; k < floats; k++) { clipData.push(float32At(all, at + k * 4)); }
		at = at + floats * 4;
	}
	return true;
}

function clipNamed(name: string): int32 {
	for (let i = 0; i < (clipNames.length as int32); i++) {
		if (clipNames[i] == name) { return i; }
	}
	return -1;
}

function bindWalker(): boolean {
	for (const name of clipNodeNames) {
		const found: Result<NodeId, SceneError> = tree.findByName(tree.rootId(), name);
		if (!found.ok) { console.log("walker: no node named " + name); return false; }
		walkerNodes.push(found.value);
	}
	return true;
}

// Every walker node takes its local transform from one frame of a clip.
function poseWalker(clip: int32, frame: int32): void {
	const nodeCount: int32 = walkerNodes.length as int32;
	const first: int32 = clipFirstFloat[clip] + frame * nodeCount * FLOATS_PER_NODE;
	for (let i = 0; i < nodeCount; i++) {
		const at: int32 = first + i * FLOATS_PER_NODE;
		const posed: Result<int32, SceneError> = setLocal(tree, walkerNodes[i], {
			...identityTransform(),
			position: vec3(clipData[at], clipData[at + 1], clipData[at + 2]),
			rotation: { x: clipData[at + 3], y: clipData[at + 4], z: clipData[at + 5], w: clipData[at + 6] },
		});
		if (!posed.ok) { return; }
	}
}

function addLights(): boolean {
	const root: NodeId = tree.rootId();
	// The moon, as in campfireScene: the node faces away from the light.
	const moonToward: Vec3 = vec3(0.35, 0.9, 0.25).normalized();
	const moon: Result<NodeId, SceneError> = addLightNode(
		tree,
		root,
		{
			...identityTransform(),
			rotation: quatBetween(vec3(0.0, 0.0, 1.0), moonToward.scaled(-1.0)),
		},
		{
			kind: LightKind.Directional,
			color: vec3(1.0, 1.0, 1.0),
			radius: 0.0,
			power: 0.3,
			priority: 100,
		},
	);
	if (!moon.ok) { return false; }
	const fire: Result<NodeId, SceneError> = addLightNode(
		tree,
		root,
		transformAt(vec3(0.0, FIRE_HEIGHT, 0.0)),
		{
			kind: LightKind.Point,
			color: vec3(1.0, 0.45, 0.16),
			radius: FIRE_RADIUS,
			power: FIRE_INTENSITY,
			priority: 0,
		},
	);
	if (!fire.ok) { return false; }
	fireLight = fire.value;
	setAmbient(tree, vec3(0.33, 0.36, 0.6));
	return true;
}

function buildScene(): boolean {
	const state: RenderState = RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(true, Compare.LessEqual);
	const litToon: Vec<float32> = [LIGHT_LEVELS, 0.0, 0.0, 0.0];
	const litBlock: UniformBlock = try reserveUniforms(
		context,
		TOON_UNIFORM_SLOT,
		TOON_UNIFORM_LENGTH,
	) catch NO_UNIFORMS;
	writeUniforms(context, litBlock, litToon);
	const lit: int32 = addMaterial(context, {
		...Material.plain(Program.Lit, state, Phase.Opaque),
		uniforms: litBlock,
	});
	if (!addModel("hillsGround.glb", lit)) { return false; }
	if (!addModel("pillars.glb", lit)) { return false; }
	if (!addModel("campfireLogs.glb", lit)) { return false; }
	if (!addModel("walker.glb", lit)) { return false; }
	if (!addLights()) { console.log("walker: the lights were refused"); return false; }
	if (!loadClips()) { return false; }
	if (!bindWalker()) { return false; }
	roamClip = clipNamed(ROAM_CLIP);
	if (roamClip < 0) { console.log("walker: no clip named " + ROAM_CLIP); return false; }
	return true;
}

function updateFlicker(dt: float64): void {
	flickerSeconds = flickerSeconds + dt;
	if (flickerSeconds < FLICKER_SECONDS) { return; }
	flickerSeconds = 0.0;
	const moved: Result<int32, SceneError> = setLocal(
		tree,
		fireLight,
		transformAt(vec3(
			(nextRandom() - 0.5) * 0.16,
			FIRE_HEIGHT + (nextRandom() - 0.5) * 0.12,
			(nextRandom() - 0.5) * 0.16,
		)),
	);
	if (!moved.ok) { return; }
	const flicker: float32 = 1.0 + (nextRandom() - 0.5) * 0.14;
	const powered: Result<int32, SceneError> = setLightPower(tree, fireLight, FIRE_INTENSITY * flicker);
	if (!powered.ok) { return; }
}

// Seconds since the last frame, from the host clock, so the walk keeps its pace at any frame rate.
function frameSeconds(): float64 {
	const now: float64 = performance.now() / 1000.0;
	const passed: float64 = lastFrameAt < 0.0 ? 0.0 : now - lastFrameAt;
	lastFrameAt = now;
	if (passed < 0.0 || passed > LONGEST_FRAME_SECONDS) { return 0.0; }
	return passed;
}

function advanceRoam(dt: float64): void {
	const frames: int32 = clipFrameCounts[roamClip];
	roamSeconds = roamSeconds + dt;
	let frame: int32 = (roamSeconds * clipFps) as int32;
	if (frame >= frames) {
		roamSeconds = 0.0;
		frame = 0;
	}
	if (frame == shownFrame) { return; }
	shownFrame = frame;
	poseWalker(roamClip, frame);
}

// For checks and previews: jump the roam to this many seconds in.
export function seekWalker(seconds: float64): void {
	roamSeconds = seconds;
}

export function initWalker(): void {
	gfxSetup();
	ready = buildScene();
	if (!ready) { console.log("walker: the scene was not built, nothing will be drawn"); }
}

export function frameWalker(): void {
	if (!ready) { return; }
	const dt: float64 = frameSeconds();
	// The view is made twice, as in campfireScene: once for the texel grid the camera snaps
	// to, once with the remainder that snap left.
	const noRemainder: float32 = 0.0;
	const sized: Result<LowResView, ViewError> = renderer.viewFor(fbWidth(), fbHeight(), noRemainder, noRemainder);
	if (!sized.ok) { return; }
	const grid: LowResView = sized.value;
	const shortSide: float32 = Math.min(grid.width, grid.height) as float32;
	const camera: OrthoCamera = {
		target: vec3(CAMERA_TARGET_X, CAMERA_TARGET_Y, CAMERA_TARGET_Z),
		yaw: CAMERA_YAW,
		pitch: CAMERA_PITCH,
		worldPerTexel: UNITS_ON_SHORT_SIDE / shortSide,
		nearPlane: -80.0,
		farPlane: 80.0,
		snap: true,
	};
	const resolved: Result<CameraView, CameraError> = camera.resolve(grid.width, grid.height);
	if (!resolved.ok) { return; }
	const cameraView: CameraView = resolved.value;
	const viewed: Result<LowResView, ViewError> = renderer.viewFor(
		fbWidth(),
		fbHeight(),
		cameraView.remainderX,
		cameraView.remainderY,
	);
	if (!viewed.ok) { return; }
	cameraView.writeCameraBlock(cameraParams);

	advanceRoam(dt);
	updateFlicker(dt);
	const drawn: int32 = refresh(tree, sceneItems);
	if (drawn == 0) { return; }
	const lit: Result<int32, LightError> = collectLights(tree, lightParams);
	if (!lit.ok) { return; }
	renderFrame(renderer, context, sceneItems, cameraParams, lightParams, viewed.value);
}
