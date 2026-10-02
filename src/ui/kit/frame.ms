// Hibernal UI kit: charred-wood frames built at run time.
//
// A frame starts from a whole frame of the style reference (hibernal art/ui-kit/sheets/
// styleReference.png, exported by art/ui-kit/tools/exportKitParts.py as assets/hud/kit/
// frame*.rgba) and is resized by cutting out or repeating plank spans at the darkest rim
// joints, then its interior is repainted as dark planks. A seed picks the base and the splice
// points: every panel differs, and the same seed gives the same frame. Pixels are at the
// reference's scale (REF_SCALE px per design unit); the GPU scales them on the way to the screen.
//
// This is the Python prototype kitbashFrame.py spliceFrame, line for line in its decisions.

import { readFile } from "std/fs";

export const KIT_DIR: string = "assets/hud/kit/";
export const REF_SCALE: float32 = 1.9333333;   // reference px per design unit (290 px / 150)
export const MARGIN: int32 = 4 as int32;        // ref px of room round the rim (bumps, sparks)
const BAND: int32 = 21 as int32;                 // rim depth, ref px
const CORNER: int32 = 30 as int32;               // corner piece, ref px
const BASES: int32 = 3 as int32;

export enum FrameLook { Normal, Alert, Disabled }

export interface Pixels {
	w: int32;
	h: int32;
	px: uint32[];
}

// ---- loading ------------------------------------------------------------------------------

function word(b: uint8[], at: int32): uint32 {
	return (b[at] as uint32) | ((b[at + 1] as uint32) << 8) | ((b[at + 2] as uint32) << 16) | ((b[at + 3] as uint32) << 24);
}

// A .rgba part: uint32 width, uint32 height, then the pixels. Empty (0 x 0) when unreadable.
export function loadPixels(path: string): Pixels {
	const file = readFile(path);
	const empty: Pixels = { w: 0 as int32, h: 0 as int32, px: [] };
	if (!file.ok) {
		console.log("ui kit: cannot read " + path);
		return empty;
	}
	const b: uint8[] = file.value.asBytes();
	if ((b.length as int32) < 8) { return empty; }
	const w: int32 = word(b, 0) as int32;
	const h: int32 = word(b, 4) as int32;
	if ((b.length as int32) < 8 + w * h * 4) { return empty; }
	const px: uint32[] = [];
	for (let i: int32 = 0; i < w * h; i += 1) { px.push(word(b, 8 + i * 4)); }
	return { w: w, h: h, px: px };
}

// ---- pixel helpers ------------------------------------------------------------------------

function red(c: uint32): int32 { return (c & 255) as int32; }
function green(c: uint32): int32 { return ((c >> 8) & 255) as int32; }
function blue(c: uint32): int32 { return ((c >> 16) & 255) as int32; }
function alpha(c: uint32): int32 { return ((c >> 24) & 255) as int32; }

function rgbaWord(r: int32, g: int32, b: int32, a: int32): uint32 {
	const cr: int32 = r < 0 ? 0 as int32 : (r > 255 ? 255 as int32 : r);
	const cg: int32 = g < 0 ? 0 as int32 : (g > 255 ? 255 as int32 : g);
	const cb: int32 = b < 0 ? 0 as int32 : (b > 255 ? 255 as int32 : b);
	return (cr as uint32) | ((cg as uint32) << 8) | ((cb as uint32) << 16) | ((a as uint32) << 24);
}

const LUM_R: float32 = 0.2126;
const LUM_G: float32 = 0.7152;
const LUM_B: float32 = 0.0722;
const EMBER_RATIO: float32 = 1.6;

function lum(c: uint32): float32 {
	return LUM_R * (red(c) as float32) + LUM_G * (green(c) as float32) + LUM_B * (blue(c) as float32);
}

function isEmber(c: uint32): boolean {
	return red(c) > 120 && (red(c) as float32) > EMBER_RATIO * (green(c) as float32);
}

function at(p: Pixels, x: int32, y: int32): uint32 { return p.px[y * p.w + x]; }

// ---- seeded random ------------------------------------------------------------------------

export interface Rng { state: uint32; }

export function rngFor(seed: int32): Rng {
	const s: uint32 = ((seed as uint32) * 2654435761) ^ 0x9E3779B9;
	return { state: s == 0 ? 1 as uint32 : s };
}

export function nextInt(r: Rng, n: int32): int32 {
	let x: uint32 = r.state;
	x = x ^ (x << 13);
	x = x ^ (x >> 17);
	x = x ^ (x << 5);
	r.state = x;
	if (n <= 0) { return 0 as int32; }
	return (x % (n as uint32)) as int32;
}

// ---- parts --------------------------------------------------------------------------------

export interface FrameParts {
	bases: Pixels[];
	badges: Pixels[];
	rows: uint32[];
}

export function loadFrameParts(): FrameParts {
	const bases: Pixels[] = [];
	const badges: Pixels[] = [];
	for (let i: int32 = 0; i < BASES; i += 1) {
		bases.push(loadPixels(KIT_DIR + "frame" + i.toString() + ".rgba"));
		badges.push(loadPixels(KIT_DIR + "badge" + i.toString() + ".rgba"));
	}
	const rowsImage: Pixels = loadPixels(KIT_DIR + "rows.rgba");
	return { bases: bases, badges: badges, rows: rowsImage.px };
}

// ---- splice -------------------------------------------------------------------------------

// Darkness of the rim at each column (axisX) or row: low = a plank joint, where a cut hides.
function rimScore(p: Pixels, axisX: boolean): float32[] {
	const n: int32 = axisX ? p.w : p.h;
	const out: float32[] = [];
	const deep: int32 = MARGIN + (BAND * 2) / 3;
	for (let i: int32 = 0; i < n; i += 1) {
		let sum: float32 = 0.0;
		let count: int32 = 0 as int32;
		for (let d: int32 = MARGIN; d < deep; d += 1) {
			const a: uint32 = axisX ? at(p, i, d) : at(p, d, i);
			const b: uint32 = axisX ? at(p, i, p.h - 1 - d) : at(p, p.w - 1 - d, i);
			sum += alpha(a) > 0 ? lum(a) : 0.0;
			sum += alpha(b) > 0 ? lum(b) : 0.0;
			count += 2;
		}
		out.push(sum / (count as float32));
	}
	return out;
}

// The darkest joints between the corners, darkest first (at least 4).
function joints(p: Pixels, axisX: boolean): int32[] {
	const size: int32 = axisX ? p.w : p.h;
	const score: float32[] = rimScore(p, axisX);
	const lo: int32 = CORNER + MARGIN + 4;
	const hi: int32 = size - CORNER - MARGIN - 4;
	const idx: int32[] = [];
	for (let i: int32 = lo; i < hi; i += 1) { idx.push(i); }
	// insertion sort by score
	for (let i: int32 = 1; i < idx.length; i += 1) {
		const v: int32 = idx[i];
		let j: int32 = i - 1;
		while (j >= 0 && score[idx[j]] > score[v]) {
			idx[j + 1] = idx[j];
			j -= 1;
		}
		idx[j + 1] = v;
	}
	let keep: int32 = (hi - lo) / 6;
	if (keep < 4) { keep = 4 as int32; }
	const out: int32[] = [];
	for (let i: int32 = 0; i < idx.length && i < keep; i += 1) { out.push(idx[i]); }
	if ((out.length as int32) == 0) { out.push(size / 2); }
	return out;
}

// Columns (axisX) or rows [from, to) of `src` copied to `dst` starting at `into`.
function copySpan(src: Pixels, dst: Pixels, axisX: boolean, from: int32, to: int32, into: int32): void {
	if (axisX) {
		for (let y: int32 = 0; y < src.h; y += 1) {
			for (let x: int32 = from; x < to; x += 1) { dst.px[y * dst.w + into + x - from] = at(src, x, y); }
		}
	} else {
		for (let y: int32 = from; y < to; y += 1) {
			for (let x: int32 = 0; x < src.w; x += 1) { dst.px[(into + y - from) * dst.w + x] = at(src, x, y); }
		}
	}
}

function blank(w: int32, h: int32): Pixels {
	const px: uint32[] = [];
	for (let i: int32 = 0; i < w * h; i += 1) { px.push(0 as uint32); }
	return { w: w, h: h, px: px };
}

function resizeAxis(p: Pixels, target: int32, axisX: boolean, r: Rng): Pixels {
	const size: int32 = axisX ? p.w : p.h;
	if (target == size) { return p; }
	const js: int32[] = joints(p, axisX);
	const lo: int32 = CORNER + MARGIN + 4;
	const hi: int32 = size - CORNER - MARGIN - 4;
	const out: Pixels = axisX ? blank(target, p.h) : blank(p.w, target);
	if (target < size) {
		// remove one span starting at a dark joint
		const need: int32 = size - target;
		let a: int32 = js[nextInt(r, js.length as int32)];
		if (a + need >= hi) { a = hi - need; }
		if (a < lo) { a = lo; }
		let b: int32 = a + need;
		if (b > size) { b = size; a = size - need; }
		copySpan(p, out, axisX, 0 as int32, a, 0 as int32);
		copySpan(p, out, axisX, b, size, a);
		return out;
	}
	// repeat the span between the outermost dark joints until long enough
	let a: int32 = js[0];
	let b: int32 = js[0];
	for (const j of js) {
		if (j < a) { a = j; }
		if (j > b) { b = j; }
	}
	if (b - a < 12) { a = lo; b = hi; }
	const cut: int32 = js[nextInt(r, js.length as int32)];
	copySpan(p, out, axisX, 0 as int32, cut, 0 as int32);
	let into: int32 = cut;
	let extra: int32 = target - size;
	while (extra > 0) {
		const span: int32 = extra < b - a ? extra : b - a;
		copySpan(p, out, axisX, a, a + span, into);
		into += span;
		extra -= span;
	}
	copySpan(p, out, axisX, cut, size, into);
	return out;
}

// Ref px for a design length (plus the margin on both sides).
export function refSize(design: float32): int32 {
	const half: float32 = 0.5;
	return ((design * REF_SCALE + half) as int32) + 2 * MARGIN;
}

export function spliceFrame(parts: FrameParts, wDesign: float32, hDesign: float32, seed: int32, look: FrameLook): Pixels {
	const r: Rng = rngFor(seed);
	const base: Pixels = parts.bases[nextInt(r, BASES)];
	const W: int32 = refSize(wDesign);
	const H: int32 = refSize(hDesign);
	let img: Pixels = resizeAxis(base, W, true, r);
	img = resizeAxis(img, H, false, r);
	const rows: uint32[] = parts.rows;
	const nRows: int32 = rows.length as int32;
	const inset: int32 = MARGIN + BAND - 2;
	// interior: one plank colour per row
	for (let y: int32 = inset; y < img.h - inset; y += 1) {
		const c: uint32 = rows[(y - inset) % nRows];
		for (let x: int32 = inset; x < img.w - inset; x += 1) { img.px[y * img.w + x] = c; }
	}
	// the source panel's text or widgets just inside the rim: painted over
	for (let y: int32 = MARGIN + 8; y < img.h - MARGIN - 8; y += 1) {
		for (let x: int32 = MARGIN + 8; x < img.w - MARGIN - 8; x += 1) {
			if (x >= inset && x < img.w - inset && y >= inset && y < img.h - inset) { continue; }
			const c: uint32 = at(img, x, y);
			let deep: int32 = x < y ? x : y;
			if (img.w - 1 - x < deep) { deep = img.w - 1 - x; }
			if (img.h - 1 - y < deep) { deep = img.h - 1 - y; }
			if (alpha(c) > 0 && lum(c) > 44.0 && !isEmber(c) && deep > MARGIN + 11) {
				const yi: int32 = y - inset;
				img.px[y * img.w + x] = rows[((yi % nRows) + nRows) % nRows];
			}
		}
	}
	// a little long grain across the planks
	const streaks: int32 = (W * H) / 900;
	for (let k: int32 = 0; k < streaks; k += 1) {
		const span: int32 = img.w - 2 * inset - 30;
		if (span <= 0 || img.h - 2 * inset <= 1) { break; }
		const gx: int32 = inset + nextInt(r, span);
		const gy: int32 = inset + nextInt(r, img.h - 2 * inset - 1);
		const gl: int32 = 8 + nextInt(r, 23);
		const c: uint32 = rows[(gy - inset + 3) % nRows];
		for (let i: int32 = 0; i < gl; i += 1) {
			if (gx + i < img.w - inset) { img.px[gy * img.w + gx + i] = c; }
		}
	}
	tint(img, look, inset);
	return img;
}

// Alert: a hotter rim and a faintly red interior. Disabled: grey ash.
function tint(img: Pixels, look: FrameLook, inset: int32): void {
	if (look == FrameLook.Normal) { return; }
	for (let y: int32 = 0; y < img.h; y += 1) {
		for (let x: int32 = 0; x < img.w; x += 1) {
			const c: uint32 = at(img, x, y);
			const a: int32 = alpha(c);
			if (a == 0) { continue; }
			const inside: boolean = x >= inset && x < img.w - inset && y >= inset && y < img.h - inset;
			let r: int32 = red(c);
			let g: int32 = green(c);
			let b: int32 = blue(c);
			if (look == FrameLook.Alert) {
				if (inside) {
					r = r + 10;
				} else {
					r = (r * 13) / 10 + 12;
					g = (g * 8) / 10;
					b = (b * 3) / 4;
				}
			} else {
				const l: int32 = lum(c) as int32;
				r = l + 4;
				g = l + 2;
				b = l;
			}
			img.px[y * img.w + x] = rgbaWord(r, g, b, a);
		}
	}
}

// A badge-sized frame: one of the reference badges (drawn scaled by the GPU).
export function badgeFor(parts: FrameParts, seed: int32): Pixels {
	const r: Rng = rngFor(seed);
	return parts.badges[nextInt(r, BASES)];
}
