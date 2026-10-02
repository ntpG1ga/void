// Hibernal UI kit, batch 1: Panel, Button, Text link, SignButton, Spinner, Chip, Badge,
// HeartPips, Bar, Bonding bar, Balance. hibernal docs/UI-KIT.md §A #1-#3, #10-#14.
//
// Immediate mode on ui.ms + kit.ms: call each frame between beginUi/beginKit and endKit/endUi.
// A component takes the caller's id; when it needs more than one label it derives sub-ids
// from it (sub()), so ids below SUB_BASE are free for the caller.

import { Color, rgba } from "../../void2d/types";
import { Ui, box, pressable, held } from "../ui";
import { Kit, TextSize, measure, frame, badgeFrame, icon, iconTinted, say, DIMMED, WHITE, INK, INK_MUTED, EMBER, EMBER_HOT, EMBER_PRESSED, ALERT_RED, DISABLED_INK, ASH_DEEP } from "./kit";
import { FrameLook } from "./frame";

const SUB_BASE: int32 = 1000000 as int32;
function sub(id: int32, n: int32): int32 { return SUB_BASE + id * 8 + n; }

export const GROWTH_GREEN: Color = rgba(0.478, 0.663, 0.294, 1.0);
export const RARE_BLUE: Color = rgba(0.478, 0.675, 0.843, 1.0);
export const EPIC_PURPLE: Color = rgba(0.745, 0.439, 0.894, 1.0);
export const LEGENDARY_GOLD: Color = rgba(0.910, 0.678, 0.318, 1.0);
export const MYTHIC_CYAN: Color = rgba(0.439, 0.765, 0.788, 1.0);
export const COMMON_ASH: Color = rgba(0.576, 0.549, 0.522, 1.0);
const TRACK: Color = rgba(0.11, 0.09, 0.09, 1.0);
const TRACK_RIM: Color = rgba(0.275, 0.251, 0.243, 1.0);
const HATCH: Color = rgba(0.20, 0.15, 0.14, 1.0);

// ---- Panel --------------------------------------------------------------------------------

export function panel(k: Kit, id: int32, x: float32, y: float32, w: float32, h: float32, seed: int32, look: FrameLook): void {
	frame(k, id, x, y, w, h, seed, look);
}

// ---- Buttons ------------------------------------------------------------------------------

export enum ButtonStyle { Primary, Danger }

// Framed button: charred frame, centred label. Pressed = label 1 unit down and hotter.
export function button(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, h: float32, label: string,
	style: ButtonStyle, enabled: boolean, seed: int32): boolean {
	const clicked: boolean = pressable(u, id, x, y, w, h) && enabled;
	const down: boolean = enabled && held(u, id, x, y, w, h);
	const look: FrameLook = !enabled ? FrameLook.Disabled : (style == ButtonStyle.Danger ? FrameLook.Alert : FrameLook.Normal);
	frame(k, id, x, y, w, h, seed, look);
	let ink: Color = style == ButtonStyle.Danger ? ALERT_RED : EMBER_HOT;
	if (down) { ink = EMBER_PRESSED; }
	if (!enabled) { ink = DISABLED_INK; }
	const t: TextSize = measure(k, label, 8.0);
	say(u, k, id, label, x, y + (h - t.h) * 0.5 + (down ? 1.0 : 0.0), w, 8.0, ink, 0.5);
	return clicked;
}

// Frameless text button with an even ember underline (no hot spot at its ends).
export function textLink(u: Ui, k: Kit, id: int32, x: float32, y: float32, label: string, enabled: boolean): boolean {
	const w: float32 = measure(k, label, 8.0).w;
	const clicked: boolean = pressable(u, id, x - 6.0, y - 14.0, w + 12.0, 36.0) && enabled;
	const down: boolean = enabled && held(u, id, x - 6.0, y - 14.0, w + 12.0, 36.0);
	const ink: Color = !enabled ? DISABLED_INK : (down ? EMBER_PRESSED : EMBER_HOT);
	say(u, k, id, label, x, y + (down ? 1.0 : 0.0), w + 8.0, 8.0, ink, 0.0);
	box(u, x, y + 11.0, w, 1.0, 0.0, !enabled ? DISABLED_INK : (down ? EMBER_PRESSED : EMBER));
	return clicked;
}

// ---- Spinner ------------------------------------------------------------------------------

const RING_X: float32[] = [0.0, 0.707, 1.0, 0.707, 0.0, -0.707, -1.0, -0.707];
const RING_Y: float32[] = [-1.0, -0.707, 0.0, 0.707, 1.0, 0.707, 0.0, -0.707];

// Eight ember dots in a ring, the bright one walking round; `tick` = frames since start.
export function spinner(u: Ui, x: float32, y: float32, size: float32, tick: int32): void {
	const head: int32 = (tick / 3) % 8;
	const r: float32 = size * 0.5 - 1.5;
	for (let i: int32 = 0; i < 8; i += 1) {
		const age: int32 = (head - i + 8) % 8;
		const c: Color = age == 0 ? EMBER_PRESSED : (age < 3 ? EMBER_HOT : EMBER);
		const a: float32 = age < 4 ? 1.0 : 0.45;
		box(u, x + size * 0.5 + RING_X[i] * r - 1.0, y + size * 0.5 + RING_Y[i] * r - 1.0, 2.0, 2.0, 0.0,
			rgba(c.r, c.g, c.b, a));
	}
}

// ---- SignButton ---------------------------------------------------------------------------

export enum SignState { Idle, Waiting, Done, Failed, Disabled }

// The button that hands off to the wallet. Clickable while Idle or Failed.
export function signButton(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, h: float32, label: string,
	state: SignState, seed: int32, tick: int32): boolean {
	const live: boolean = state == SignState.Idle || state == SignState.Failed;
	const clicked: boolean = pressable(u, id, x, y, w, h) && live;
	const down: boolean = live && held(u, id, x, y, w, h);
	let look: FrameLook = FrameLook.Normal;
	if (state == SignState.Failed) { look = FrameLook.Alert; }
	if (state == SignState.Disabled || state == SignState.Waiting) { look = FrameLook.Disabled; }
	frame(k, id, x, y, w, h, seed, look);
	let caption: string = label;
	let ink: Color = down ? EMBER_PRESSED : EMBER_HOT;
	let glyph: string = "wallet";
	if (state == SignState.Waiting) { caption = "WALLET..."; ink = INK_MUTED; glyph = ""; }
	if (state == SignState.Done) { caption = "DONE"; ink = GROWTH_GREEN; glyph = ""; }
	if (state == SignState.Failed) { caption = "RETRY"; ink = ALERT_RED; glyph = "warning"; }
	if (state == SignState.Disabled) { ink = DISABLED_INK; }
	const t: TextSize = measure(k, caption, 8.0);
	const tw: float32 = t.w;
	const lead: float32 = glyph != "" || state == SignState.Waiting ? 22.0 : 0.0;
	const left: float32 = x + (w - tw - lead) * 0.5;
	const ty: float32 = y + (h - t.h) * 0.5 + (down ? 1.0 : 0.0);
	const iy: float32 = y + (h - 16.0) * 0.5 + (down ? 1.0 : 0.0);
	if (state == SignState.Waiting) { spinner(u, left, iy, 16.0, tick); }
	else if (glyph != "") { iconTinted(k, id, glyph, left, iy, 16.0, state == SignState.Disabled ? DIMMED : WHITE); }
	say(u, k, id, caption, left + lead, ty, tw + 8.0, 8.0, ink, 0.0);
	return clicked;
}

// ---- Chip ---------------------------------------------------------------------------------

export enum ChipKind { Outline, Filled, Dashed }

// Small status pill with a 1-unit rim; returns its width so chips can be laid in a row.
export function chip(u: Ui, k: Kit, id: int32, x: float32, y: float32, label: string, kind: ChipKind, color: Color): float32 {
	const t: TextSize = measure(k, label, 8.0);
	const pad: float32 = 5.0;
	const w: float32 = t.w + 2.0 * pad;
	const h: float32 = 16.0;
	if (kind == ChipKind.Filled) {
		box(u, x, y, w, h, 0.0, color);
	} else if (kind == ChipKind.Outline) {
		box(u, x, y, w, h, 0.0, rgba(0.06, 0.05, 0.05, 0.85));
		box(u, x, y, w, 1.0, 0.0, color);
		box(u, x, y + h - 1.0, w, 1.0, 0.0, color);
		box(u, x, y, 1.0, h, 0.0, color);
		box(u, x + w - 1.0, y, 1.0, h, 0.0, color);
	} else {
		box(u, x, y, w, h, 0.0, rgba(0.06, 0.05, 0.05, 0.85));
		let d: float32 = 0.0;
		while (d < w) {
			const seg: float32 = d + 3.0 < w ? 3.0 : w - d;
			box(u, x + d, y, seg, 1.0, 0.0, color);
			box(u, x + d, y + h - 1.0, seg, 1.0, 0.0, color);
			d += 5.0;
		}
		d = 0.0;
		while (d < h) {
			const seg: float32 = d + 3.0 < h ? 3.0 : h - d;
			box(u, x, y + d, 1.0, seg, 0.0, color);
			box(u, x + w - 1.0, y + d, 1.0, seg, 0.0, color);
			d += 5.0;
		}
	}
	say(u, k, id, label, x + pad, y + (h - t.h) * 0.5, t.w + 2.0, 8.0, kind == ChipKind.Filled ? ASH_DEEP : color, 0.0);
	return w;
}

// ---- Badge --------------------------------------------------------------------------------

// 40 x 40 charred badge: icon, and a short number under it when given. True when tapped.
export function badge(u: Ui, k: Kit, id: int32, x: float32, y: float32, glyph: string, number: string, seed: int32): boolean {
	const tapped: boolean = pressable(u, id, x - 4.0, y - 4.0, 48.0, 48.0);
	badgeFrame(k, id, x, y, 40.0, seed);
	if (number == "") {
		icon(k, id, glyph, x + 10.0, y + 10.0, 20.0);
	} else {
		// icon 14 + gap 2 + number line, centred in the 40-unit badge
		const t: TextSize = measure(k, number, 8.0);
		const top: float32 = y + (40.0 - (14.0 + 2.0 + t.h)) * 0.5;
		icon(k, id, glyph, x + 13.0, top, 14.0);
		say(u, k, id, number, x, top + 16.0, 40.0, 8.0, INK, 0.5);
	}
	return tapped;
}

// ---- HeartPips ----------------------------------------------------------------------------

// Full and cracked hearts; up to 10 per row, two rows up to 20, past that "♥ n/max".
export function heartPips(u: Ui, k: Kit, id: int32, x: float32, y: float32, hearts: int32, max: int32, size: float32): void {
	if (max > 20) {
		icon(k, id, "heart", x, y, size);
		say(u, k, id, hearts.toString() + "/" + max.toString(), x + size + 4.0, y + (size - 8.0) * 0.5, 80.0, 8.0, INK, 0.0);
		return;
	}
	const step: float32 = size + 2.0;
	for (let i: int32 = 0; i < max; i += 1) {
		const col: int32 = i % 10;
		const row: int32 = i / 10;
		icon(k, sub(id, 0) + i * 10, i < hearts ? "heart" : "crackedHeart", x + (col as float32) * step, y + (row as float32) * step, size);
	}
}

// ---- Bars ---------------------------------------------------------------------------------

// Plain progress bar, value 0..1: dark track, 1-unit rim, flat fill, no end spark.
export function bar(u: Ui, x: float32, y: float32, w: float32, h: float32, value: float32, fill: Color): void {
	const v: float32 = value < 0.0 ? 0.0 : (value > 1.0 ? 1.0 : value);
	box(u, x, y, w, h, 0.0, TRACK_RIM);
	box(u, x + 1.0, y + 1.0, w - 2.0, h - 2.0, 0.0, TRACK);
	if (v > 0.0) { box(u, x + 1.0, y + 1.0, (w - 2.0) * v, h - 2.0, 0.0, fill); }
}

// Bonding, -127..127: centre tick, hatched ends (refuses food / gives gifts), fill from the
// centre to the value, a marker on the value.
export function bondingBar(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, value: int32): void {
	const h: float32 = 8.0;
	bar(u, x, y, w, h, 0.0, TRACK);
	const zone: float32 = w * 0.18;
	let d: float32 = 2.0;
	while (d < zone - 2.0) {
		box(u, x + d, y + 2.0, 1.0, h - 4.0, 0.0, HATCH);
		box(u, x + w - d - 1.0, y + 2.0, 1.0, h - 4.0, 0.0, HATCH);
		d += 3.0;
	}
	const mid: float32 = x + w * 0.5;
	const at: float32 = mid + (w * 0.5 - 2.0) * ((value as float32) / 127.0);
	const fill: Color = value >= 0 ? RARE_BLUE : ALERT_RED;
	if (at > mid) { box(u, mid, y + 2.0, at - mid, h - 4.0, 0.0, fill); }
	else { box(u, at, y + 2.0, mid - at, h - 4.0, 0.0, fill); }
	box(u, mid - 0.5, y - 2.0, 1.0, h + 4.0, 0.0, INK_MUTED);
	box(u, at - 1.0, y - 3.0, 2.0, h + 6.0, 0.0, INK);
	say(u, k, sub(id, 0), "REFUSES", x, y + h + 4.0, w * 0.5, 8.0, INK_MUTED, 0.0);
	say(u, k, sub(id, 1), "GIFTS", x + w * 0.5, y + h + 4.0, w * 0.5, 8.0, INK_MUTED, 1.0);
}

// ---- Balance ------------------------------------------------------------------------------

// Icon + right-aligned amount. `overlay` (e.g. "warning" on the harvest bag) sits small on
// the icon's corner.
export function balance(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, glyph: string, overlay: string, amount: string): void {
	icon(k, id, glyph, x, y, 14.0);
	if (overlay != "") { icon(k, id, overlay, x + 7.0, y + 6.0, 9.0); }
	say(u, k, id, amount, x + 20.0, y + 3.0, w - 20.0, 8.0, INK, 1.0);
}

// A signed change, coloured by its sign: "+280" green, "-310" red.
export function delta(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, value: int32, align: float32): void {
	const s: string = value > 0 ? "+" + value.toString() : value.toString();
	const c: Color = value > 0 ? GROWTH_GREEN : (value < 0 ? ALERT_RED : INK_MUTED);
	say(u, k, id, s, x, y, w, 8.0, c, align);
}

// ---- Rarity -------------------------------------------------------------------------------

export enum Rarity { Common, Rare, Epic, Legendary, Mythic }

// Common is the warm bone of the reference's plate, not grey: grey reads as disabled.
export const COMMON_BONE: Color = rgba(0.851, 0.663, 0.510, 1.0);

export function rarityColor(r: Rarity): Color {
	return match (r) {
		Rarity.Common => COMMON_BONE,
		Rarity.Rare => RARE_BLUE,
		Rarity.Epic => EPIC_PURPLE,
		Rarity.Legendary => LEGENDARY_GOLD,
		Rarity.Mythic => MYTHIC_CYAN,
	};
}

export function rarityName(r: Rarity): string {
	return match (r) {
		Rarity.Common => "COMMON",
		Rarity.Rare => "RARE",
		Rarity.Epic => "EPIC",
		Rarity.Legendary => "LEGENDARY",
		Rarity.Mythic => "MYTHIC",
	};
}

// The simple form: a rarity chip (outline, the rarity's colour).
export function rarityChip(u: Ui, k: Kit, id: int32, x: float32, y: float32, r: Rarity): float32 {
	return chip(u, k, id, x, y, rarityName(r), ChipKind.Outline, rarityColor(r));
}

function faded(c: Color, a: float32): Color { return rgba(c.r, c.g, c.b, a); }

// Rectangle outline, `t` thick.
function outline(u: Ui, x: float32, y: float32, w: float32, h: float32, t: float32, c: Color): void {
	box(u, x, y, w, t, 0.0, c);
	box(u, x, y + h - t, w, t, 0.0, c);
	box(u, x, y + t, t, h - 2.0 * t, 0.0, c);
	box(u, x + w - t, y + t, t, h - 2.0 * t, 0.0, c);
}

// One unit pixel at (dx, dy) from a corner, mirrored by (sx, sy) = (+-1, +-1).
function dot(u: Ui, cx: float32, cy: float32, sx: float32, sy: float32, dx: float32, dy: float32, c: Color): void {
	const px: float32 = sx > 0.0 ? cx + dx : cx - dx - 1.0;
	const py: float32 = sy > 0.0 ? cy + dy : cy - dy - 1.0;
	box(u, px, py, 1.0, 1.0, 0.0, c);
}

// The plate's corner: a chamfered rim tip, a two-step bracket (bright outside, dim inside),
// a small diamond with a light core where the bracket turns, and a bead at each bracket end.
function cornerOrnament(u: Ui, cx: float32, cy: float32, sx: float32, sy: float32, c: Color, plate: Color): void {
	const dim: Color = faded(c, 0.5);
	const light: Color = rgba(c.r * 0.5 + 0.5, c.g * 0.5 + 0.5, c.b * 0.5 + 0.5, 1.0);
	// chamfer: the outer tip cut away, the cut edge drawn one step in
	dot(u, cx, cy, sx, sy, 0.0, 0.0, plate);
	dot(u, cx, cy, sx, sy, 1.0, 0.0, faded(c, 0.45));
	dot(u, cx, cy, sx, sy, 0.0, 1.0, faded(c, 0.45));
	dot(u, cx, cy, sx, sy, 1.0, 1.0, c);
	// bracket: outer L (6 long) and a shorter dim L inside it
	for (let i: int32 = 0; i < 6; i += 1) {
		const d: float32 = 3.0 + (i as float32);
		dot(u, cx, cy, sx, sy, d, 3.0, c);
		dot(u, cx, cy, sx, sy, 3.0, d, c);
	}
	for (let i: int32 = 0; i < 3; i += 1) {
		const d: float32 = 4.0 + (i as float32);
		dot(u, cx, cy, sx, sy, d, 4.0, dim);
		dot(u, cx, cy, sx, sy, 4.0, d, dim);
	}
	// diamond where the bracket turns, light core
	dot(u, cx, cy, sx, sy, 6.0, 5.0, c);
	dot(u, cx, cy, sx, sy, 5.0, 6.0, c);
	dot(u, cx, cy, sx, sy, 7.0, 6.0, c);
	dot(u, cx, cy, sx, sy, 6.0, 7.0, c);
	dot(u, cx, cy, sx, sy, 6.0, 6.0, light);
	// beads past the bracket ends
	dot(u, cx, cy, sx, sy, 10.0, 3.0, c);
	dot(u, cx, cy, sx, sy, 3.0, 10.0, c);
	dot(u, cx, cy, sx, sy, 12.0, 3.0, dim);
	dot(u, cx, cy, sx, sy, 3.0, 12.0, dim);
}

// The rarity border alone (glow, dark plank plate, double rim, corner ornaments), for plates,
// the talent card face, item reveals.
export function rarityBorder(u: Ui, x: float32, y: float32, w: float32, h: float32, r: Rarity): void {
	const c: Color = rarityColor(r);
	outline(u, x - 2.0, y - 2.0, w + 4.0, h + 4.0, 1.0, faded(c, 0.12));
	outline(u, x - 1.0, y - 1.0, w + 2.0, h + 2.0, 1.0, faded(c, 0.25));
	box(u, x, y, w, h, 0.0, rgba(0.094, 0.071, 0.063, 0.96));
	let s: float32 = y + 6.0;
	while (s < y + h - 3.0) {
		box(u, x + 3.0, s, w - 6.0, 1.0, 0.0, rgba(0.055, 0.043, 0.039, 0.9));
		s += 6.0;
	}
	outline(u, x, y, w, h, 1.0, c);
	outline(u, x + 1.0, y + 1.0, w - 2.0, h - 2.0, 1.0, faded(c, 0.45));
	if (w < 30.0 || h < 30.0) { return; }
	const plate: Color = rgba(0.094, 0.071, 0.063, 1.0);
	cornerOrnament(u, x, y, 1.0, 1.0, c, plate);
	cornerOrnament(u, x + w, y, -1.0, 1.0, c, plate);
	cornerOrnament(u, x, y + h, 1.0, -1.0, c, plate);
	cornerOrnament(u, x + w, y + h, -1.0, -1.0, c, plate);
}

// The detailed form, for the moment an item is received: the rarity border and its name at 16.
export function rarityPlate(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, h: float32, r: Rarity): void {
	const c: Color = rarityColor(r);
	rarityBorder(u, x, y, w, h, r);
	// name, measured and centred
	const label: string = rarityName(r);
	let size: float32 = 16.0;
	let t: TextSize = measure(k, label, size);
	if (t.w > w - 16.0) {
		size = 8.0;
		t = measure(k, label, size);
	}
	say(u, k, id, label, x + (w - t.w) * 0.5, y + (h - t.h) * 0.5, t.w + 2.0, size, c, 0.0);
}
