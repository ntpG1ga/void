// Hibernal UI kit: the drawing layer every component is built on.
//
// src/ui/ui.ms draws boxes and labels and answers touches; the kit adds what the charred-wood
// look needs: run-time frames (frame.ms), icons cut from the style reference, Silkscreen text.
// Like ui.ms it is immediate mode: call beginKit after beginUi, the components, then endKit
// before endUi. Sprites are kept by widget id and hidden in a frame that does not draw them.
//
// Layers, bottom to top: frames, ui boxes, icons, ui labels.
// Ids: the caller's, one per drawn thing, never 0; frames and icons may reuse a label's id.

import { makeImage as makeImageBytes, makeView } from "../../sokol/gpu";
import { makeImage, makeTextureView } from "../../void3d/gpu3d";
import { Node2D, group, sprite, addChildAt, addChild } from "../../void2d/node";
import { Color, rgba, tile } from "../../void2d/types";
import { addFont, faceFor } from "../../void2d/labelText";
import { TextLayout, TextStyle } from "../../void2d/textLayout";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../../assets/image";
import { Ui, text } from "../ui";
import { KIT_DIR, REF_SCALE, MARGIN, FrameLook, FrameParts, Pixels, loadFrameParts, spliceFrame, badgeFor } from "./frame";

// ---- palette (hibernal assets/ui/hudPalette.json) ----------------------------------------

export const INK: Color = rgba(0.824, 0.831, 0.824, 1.0);          // textLight
export const INK_MUTED: Color = rgba(0.608, 0.588, 0.592, 1.0);    // textMuted
export const EMBER: Color = rgba(0.784, 0.365, 0.157, 1.0);
export const EMBER_HOT: Color = rgba(0.969, 0.549, 0.227, 1.0);
export const EMBER_PRESSED: Color = rgba(1.0, 0.75, 0.45, 1.0);
export const ASH_DEEP: Color = rgba(0.047, 0.051, 0.063, 1.0);
export const ALERT_RED: Color = rgba(0.784, 0.239, 0.184, 1.0);
export const DISABLED_INK: Color = rgba(0.45, 0.43, 0.42, 1.0);
export const WHITE: Color = rgba(1.0, 1.0, 1.0, 1.0);
export const DIMMED: Color = rgba(0.45, 0.45, 0.45, 0.8);

export interface Kit {
	frames: Node2D;
	icons: Node2D;
	framesTop: Node2D;
	iconsTop: Node2D;
	font: int32;
	parts: FrameParts;
	// sprites kept by (layer, id)
	spriteKeys: string[];
	spriteNodes: Node2D[];
	spriteUsed: boolean[];
	// frame textures by look key
	frameKeys: string[];
	frameViews: uint32[];
	frameW: int32[];
	frameH: int32[];
	// icon textures by name
	iconNames: string[];
	iconViews: uint32[];
	iconW: int32[];
	iconH: int32[];
	badgeViews: uint32[];
	badgeW: int32[];
	overlay: boolean;
}

// Kit drawing between these goes on the overlay layers (with ui.beginOverlay).
export function beginKitOverlay(k: Kit): void { k.overlay = true; }
export function endKitOverlay(k: Kit): void { k.overlay = false; }

// Every icon in assets/hud/kit/icons, loaded by createKit: on Android files only open during
// init, while the asset root is the working directory.
export const ICON_NAMES: string[] = ["heart", "bag", "lock", "warning", "winter", "growth", "insured", "gear",
	"home", "pet", "block", "shop", "digest", "crackedHeart", "shield", "fading", "rage", "skull", "wallet",
	"copy", "back", "send", "worked", "ate", "levelUp", "gearBought", "gearSold", "fightWon", "fightLost", "gift",
	"nodeSmallAllocated", "nodeSmallReachable", "nodeSmallLocked", "nodeNotableAllocated", "nodeNotableReachable",
	"nodeNotableLocked", "nodeKeystoneAllocated", "nodeKeystoneReachable", "nodeKeystoneLocked", "recenter"];

// Textures shared by every Kit (Home, the gallery...): built once per process.
const shared: Kit[] = [];

export function createKit(u: Ui): Kit {
	const frames = group();
	const icons = group();
	const framesTop = group();
	const iconsTop = group();
	// ui.sc.root is [boxes, texts, boxesTop, textsTop]; the kit's layers interleave so that
	// each layer is frames, boxes, icons, texts, base below overlay
	u.sc.root.addChildAt(frames, 0);
	u.sc.root.addChildAt(icons, 2);
	u.sc.root.addChildAt(framesTop, 4);
	u.sc.root.addChildAt(iconsTop, 6);
	const k: Kit = {
		frames: frames, icons: icons, framesTop: framesTop, iconsTop: iconsTop, overlay: false,
		font: (shared.length as int32) > 0 ? shared[0].font : addFont(KIT_DIR + "Silkscreen-Regular.ttf"),
		parts: (shared.length as int32) > 0 ? shared[0].parts : loadFrameParts(),
		spriteKeys: [], spriteNodes: [], spriteUsed: [],
		frameKeys: [], frameViews: [], frameW: [], frameH: [],
		iconNames: [], iconViews: [], iconW: [], iconH: [],
		badgeViews: [], badgeW: [],
	};
	if ((shared.length as int32) > 0) {
		// reuse the first kit's parts and textures; only the layers (scene nodes) are per kit
		const first: Kit = shared[0];
		k.frameKeys = first.frameKeys; k.frameViews = first.frameViews; k.frameW = first.frameW; k.frameH = first.frameH;
		k.iconNames = first.iconNames; k.iconViews = first.iconViews; k.iconW = first.iconW; k.iconH = first.iconH;
		k.badgeViews = first.badgeViews; k.badgeW = first.badgeW;
		return k;
	}
	for (const name of ICON_NAMES) { iconIndex(k, name); }
	shared.push(k);
	return k;
}

export function beginKit(k: Kit): void {
	for (let i: int32 = 0; i < k.spriteUsed.length; i += 1) { k.spriteUsed[i] = false; }
}

export function endKit(k: Kit): void {
	for (let i: int32 = 0; i < k.spriteNodes.length; i += 1) { k.spriteNodes[i].visible = k.spriteUsed[i]; }
}

function viewOf(p: Pixels): uint32 {
	return makeTextureView(makeImage(p.px, p.w, p.h));
}

// A sprite node for (layer, id), created on first use, placed and shown this frame.
function place(k: Kit, layer: Node2D, key: string, view: uint32, x: float32, y: float32, w: float32, h: float32, tint: Color): void {
	let at: int32 = -1 as int32;
	for (let i: int32 = 0; i < k.spriteKeys.length; i += 1) {
		if (k.spriteKeys[i] == key) { at = i; }
	}
	if (at < 0) {
		const n = sprite(tile(view, w, h));
		if (k.overlay) {
			if (layer === k.frames) { k.framesTop.addChild(n); } else { k.iconsTop.addChild(n); }
		} else {
			layer.addChild(n);
		}
		k.spriteKeys.push(key);
		k.spriteNodes.push(n);
		k.spriteUsed.push(true);
		at = (k.spriteNodes.length - 1) as int32;
	}
	const n = k.spriteNodes[at];
	n.sheet = tile(view, w, h);
	n.w = w;
	n.h = h;
	n.x = x;
	n.y = y;
	n.color = tint;
	k.spriteUsed[at] = true;
}

// ---- frames -------------------------------------------------------------------------------

function lookName(look: FrameLook): string {
	return look == FrameLook.Alert ? "a" : (look == FrameLook.Disabled ? "d" : "n");
}

// A heavy charred frame round the design rectangle (x, y, w, h). Built once per
// (size, seed, look) and cached; the rim reaches a little outside the rectangle.
export function frame(k: Kit, id: int32, x: float32, y: float32, w: float32, h: float32, seed: int32, look: FrameLook): void {
	const key: string = (w as int32).toString() + "x" + (h as int32).toString() + ":" + seed.toString() + lookName(look);
	let at: int32 = -1 as int32;
	for (let i: int32 = 0; i < k.frameKeys.length; i += 1) {
		if (k.frameKeys[i] == key) { at = i; }
	}
	if (at < 0) {
		const img: Pixels = spliceFrame(k.parts, w, h, seed, look);
		k.frameKeys.push(key);
		k.frameViews.push(viewOf(img));
		k.frameW.push(img.w);
		k.frameH.push(img.h);
		at = (k.frameKeys.length - 1) as int32;
	}
	const m: float32 = (MARGIN as float32) / REF_SCALE;
	const dw: float32 = (k.frameW[at] as float32) / REF_SCALE;
	const dh: float32 = (k.frameH[at] as float32) / REF_SCALE;
	place(k, k.frames, "f" + id.toString(), k.frameViews[at], x - m, y - m, dw, dh, WHITE);
}

// A heavy frame built for (w, h) but drawn `squeeze` (0..1) as wide, centred: a card flip.
// The texture is the one frame() caches for (w, h, seed, look), so a flip builds nothing.
export function frameSqueezed(k: Kit, id: int32, x: float32, y: float32, w: float32, h: float32, seed: int32, look: FrameLook, squeeze: float32): void {
	frame(k, id, x, y, w, h, seed, look);
	const key: string = "f" + id.toString();
	for (let i: int32 = 0; i < k.spriteKeys.length; i += 1) {
		if (k.spriteKeys[i] == key) {
			const n = k.spriteNodes[i];
			const full: float32 = n.w;
			n.w = full * squeeze;
			n.x = n.x + (full - n.w) * 0.5;
		}
	}
}

// A badge-weight frame (the reference's own badge frames) round a square of `size`.
export function badgeFrame(k: Kit, id: int32, x: float32, y: float32, size: float32, seed: int32): void {
	if ((k.badgeViews.length as int32) == 0) {
		for (const p of k.parts.badges) {
			k.badgeViews.push(viewOf(p));
			k.badgeW.push(p.w);
		}
	}
	const pick: Pixels = badgeFor(k.parts, seed);
	let at: int32 = 0 as int32;
	for (let i: int32 = 0; i < k.parts.badges.length; i += 1) {
		if (k.parts.badges[i].w == pick.w && k.parts.badges[i].h == pick.h) { at = i; }
	}
	// the badge art is drawn for a 40-unit square; it scales with `size`
	const scale: float32 = size / ((k.badgeW[at] - 2 * MARGIN) as float32);
	const m: float32 = (MARGIN as float32) * scale;
	const side: float32 = (k.badgeW[at] as float32) * scale;
	place(k, k.frames, "f" + id.toString(), k.badgeViews[at], x - m, y - m, side, side, WHITE);
}

// ---- icons --------------------------------------------------------------------------------

function iconIndex(k: Kit, name: string): int32 {
	for (let i: int32 = 0; i < k.iconNames.length; i += 1) {
		if (k.iconNames[i] == name) { return i; }
	}
	const pixels = loadImageSync(KIT_DIR + "icons/" + name + ".png", 4);
	const w: int32 = imageWidth();
	const h: int32 = imageHeight();
	const view: uint32 = makeView(makeImageBytes(pixels, w, h));
	freeImage(pixels);
	k.iconNames.push(name);
	k.iconViews.push(view);
	k.iconW.push(w);
	k.iconH.push(h);
	return (k.iconNames.length - 1) as int32;
}

// An icon fitted (aspect kept) and centred in a size x size square at (x, y).
export function icon(k: Kit, id: int32, name: string, x: float32, y: float32, size: float32): void {
	iconTinted(k, id, name, x, y, size, WHITE);
}

// The same, multiplied by `tint` (DIMMED for a disabled control).
export function iconTinted(k: Kit, id: int32, name: string, x: float32, y: float32, size: float32, tint: Color): void {
	const i: int32 = iconIndex(k, name);
	const iw: float32 = k.iconW[i] as float32;
	const ih: float32 = k.iconH[i] as float32;
	const s: float32 = size / (iw > ih ? iw : ih);
	const w: float32 = iw * s;
	const h: float32 = ih * s;
	place(k, k.icons, "i" + id.toString() + name, k.iconViews[i], x + (size - w) * 0.5, y + (size - h) * 0.5, w, h, tint);
}

// ---- text ---------------------------------------------------------------------------------

// The real laid-out size of `s` in Silkscreen at `size` (design units): width and line height.
export interface TextSize { w: float32; h: float32; }
export function measure(k: Kit, s: string, size: float32): TextSize {
	const style: TextStyle = { face: faceFor(k.font), size: size, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: 0.0 };
	const laid: TextLayout = TextLayout.layout(s, style);
	return { w: laid.width, h: laid.lineHeight };
}

// The same, wrapped at `maxWidth`: width of the widest line and total height.
export function measureWrapped(k: Kit, s: string, size: float32, maxWidth: float32): TextSize {
	const style: TextStyle = { face: faceFor(k.font), size: size, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: maxWidth, align: 0.0 };
	const laid: TextLayout = TextLayout.layout(s, style);
	return { w: laid.width, h: laid.height };
}

// ui.text in Silkscreen. Sizes 8 and 16 stay crisp.
export function say(u: Ui, k: Kit, id: int32, s: string, x: float32, y: float32, w: float32, size: float32, color: Color, align: float32): void {
	text(u, id, s, x, y, w, size, color, align);
	for (let i: int32 = 0; i < u.labelIds.length; i += 1) {
		if (u.labelIds[i] === id) { u.labelNodes[i].fontId = k.font; }
	}
}
