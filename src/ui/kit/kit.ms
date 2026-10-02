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
import { addFont } from "../../void2d/labelText";
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

export interface Kit {
	frames: Node2D;
	icons: Node2D;
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
}

// Every icon in assets/hud/kit/icons, loaded by createKit: on Android files only open during
// init, while the asset root is the working directory.
export const ICON_NAMES: string[] = ["heart", "bag", "lock", "warning", "winter", "growth", "insured", "gear",
	"home", "pet", "block", "shop", "digest"];

export function createKit(u: Ui): Kit {
	const frames = group();
	const icons = group();
	// ui.sc.root is [boxes, texts]: frames go under the boxes, icons between boxes and texts
	u.sc.root.addChildAt(frames, 0);
	u.sc.root.addChildAt(icons, 2);
	const k: Kit = {
		frames: frames, icons: icons,
		font: addFont(KIT_DIR + "Silkscreen-Regular.ttf"),
		parts: loadFrameParts(),
		spriteKeys: [], spriteNodes: [], spriteUsed: [],
		frameKeys: [], frameViews: [], frameW: [], frameH: [],
		iconNames: [], iconViews: [], iconW: [], iconH: [],
		badgeViews: [], badgeW: [],
	};
	for (const name of ICON_NAMES) { iconIndex(k, name); }
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
function place(k: Kit, layer: Node2D, key: string, view: uint32, x: float32, y: float32, w: float32, h: float32): void {
	let at: int32 = -1 as int32;
	for (let i: int32 = 0; i < k.spriteKeys.length; i += 1) {
		if (k.spriteKeys[i] == key) { at = i; }
	}
	if (at < 0) {
		const n = sprite(tile(view, w, h));
		layer.addChild(n);
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
	place(k, k.frames, "f" + id.toString(), k.frameViews[at], x - m, y - m, dw, dh);
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
	place(k, k.frames, "f" + id.toString(), k.badgeViews[at], x - m, y - m, side, side);
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
	const i: int32 = iconIndex(k, name);
	const iw: float32 = k.iconW[i] as float32;
	const ih: float32 = k.iconH[i] as float32;
	const s: float32 = size / (iw > ih ? iw : ih);
	const w: float32 = iw * s;
	const h: float32 = ih * s;
	place(k, k.icons, "i" + id.toString() + name, k.iconViews[i], x + (size - w) * 0.5, y + (size - h) * 0.5, w, h);
}

// ---- text ---------------------------------------------------------------------------------

// ui.text in Silkscreen. Sizes 8 and 16 stay crisp.
export function say(u: Ui, k: Kit, id: int32, s: string, x: float32, y: float32, w: float32, size: float32, color: Color, align: float32): void {
	text(u, id, s, x, y, w, size, color, align);
	for (let i: int32 = 0; i < u.labelIds.length; i += 1) {
		if (u.labelIds[i] === id) { u.labelNodes[i].fontId = k.font; }
	}
}
