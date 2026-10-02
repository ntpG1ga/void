// Hibernal UI kit, batch 2: Toggle, Segmented, Tabs, Radio row, List row, Section header,
// Divider, Toast queue, Tooltip, Reason pill, Banner, Skeleton, Sync chip, Empty state.
// hibernal docs/UI-KIT.md §A #6-#9, #15-#21. Same rules as components.ms.

import { Color, rgba } from "../../void2d/types";
import { Ui, box, pressable, held } from "../ui";
import { Kit, TextSize, measure, frame, iconTinted, say, INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED,
	DISABLED_INK, ASH_DEEP, DIMMED, WHITE } from "./kit";
import { FrameLook } from "./frame";
import { spinner } from "./components";

const SUB_BASE: int32 = 2000000 as int32;
function sub(id: int32, n: int32): int32 { return SUB_BASE + id * 8 + n; }

// light charred rim (no ember), for the light frame weight
const RIM_OUT: Color = rgba(0.161, 0.110, 0.102, 1.0);    // charDeep
const RIM_IN: Color = rgba(0.404, 0.247, 0.188, 1.0);     // charLight
const FILL: Color = rgba(0.094, 0.071, 0.063, 0.96);      // plank dark
const FILL_LIGHT: Color = rgba(0.733, 0.682, 0.675, 1.0); // chipFill, the inverted row
const DIVIDER: Color = rgba(0.243, 0.149, 0.125, 1.0);    // charMid
const STRIP: Color = rgba(0.047, 0.051, 0.063, 0.86);

function outline(u: Ui, x: float32, y: float32, w: float32, h: float32, t: float32, c: Color): void {
	box(u, x, y, w, t, 0.0, c);
	box(u, x, y + h - t, w, t, 0.0, c);
	box(u, x, y + t, t, h - 2.0 * t, 0.0, c);
	box(u, x + w - t, y + t, t, h - 2.0 * t, 0.0, c);
}

// The light frame: plank fill, a 2-unit charred rim (dark outside, warm inside), corners cut.
export function lightFrame(u: Ui, x: float32, y: float32, w: float32, h: float32, rim: Color): void {
	box(u, x + 1.0, y + 1.0, w - 2.0, h - 2.0, 0.0, FILL);
	box(u, x + 1.0, y, w - 2.0, 1.0, 0.0, RIM_OUT);
	box(u, x + 1.0, y + h - 1.0, w - 2.0, 1.0, 0.0, RIM_OUT);
	box(u, x, y + 1.0, 1.0, h - 2.0, 0.0, RIM_OUT);
	box(u, x + w - 1.0, y + 1.0, 1.0, h - 2.0, 0.0, RIM_OUT);
	outline(u, x + 1.0, y + 1.0, w - 2.0, h - 2.0, 1.0, rim);
}

const HALF: float32 = 0.5;
function centreY(k: Kit, s: string, size: float32, y: float32, h: float32): float32 {
	return y + (h - measure(k, s, size).h) * HALF;
}

// ---- Toggle -------------------------------------------------------------------------------

export enum ToggleState { Off, On, Pending, Disabled }

// 48 x 48 touch target, a 40 x 20 charred slot; the knob glows ember when on. Returns true
// on a tap (the caller flips the state, or makes it Pending while a signature is out).
export function toggle(u: Ui, k: Kit, id: int32, x: float32, y: float32, state: ToggleState, tick: int32): boolean {
	const live: boolean = state == ToggleState.Off || state == ToggleState.On;
	const tapped: boolean = pressable(u, id, x, y, 48.0, 48.0) && live;
	const sx: float32 = x + 4.0;
	const sy: float32 = y + 14.0;
	if (state == ToggleState.Disabled) {
		// the off shape, faded: a sunken slot, a dashed ash rim, a dark knob
		box(u, sx, sy, 40.0, 20.0, 0.0, rgba(0.035, 0.031, 0.031, 0.95));
		let d: float32 = 0.0;
		const ash: Color = rgba(0.30, 0.28, 0.27, 1.0);
		while (d < 40.0) {
			box(u, sx + d, sy, 2.0, 1.0, 0.0, ash);
			box(u, sx + d, sy + 19.0, 2.0, 1.0, 0.0, ash);
			d += 4.0;
		}
		d = 0.0;
		while (d < 20.0) {
			box(u, sx, sy + d, 1.0, 2.0, 0.0, ash);
			box(u, sx + 39.0, sy + d, 1.0, 2.0, 0.0, ash);
			d += 4.0;
		}
		// the off knob, solid but sunk into ash
		box(u, sx + 3.0, sy + 3.0, 15.0, 14.0, 0.0, rgba(0.24, 0.22, 0.21, 1.0));
		return tapped;
	}
	lightFrame(u, sx, sy, 40.0, 20.0, state == ToggleState.On ? EMBER : RIM_IN);
	const on: boolean = state == ToggleState.On;
	const kx: float32 = on ? sx + 22.0 : sx + 3.0;
	const knob: Color = state == ToggleState.Disabled ? DISABLED_INK : (on ? EMBER_HOT : INK_MUTED);
	if (state == ToggleState.Pending) {
		spinner(u, sx + 12.0, sy + 2.0, 16.0, tick);
	} else {
		box(u, kx, sy + 3.0, 15.0, 14.0, 0.0, knob);
		box(u, kx + 1.0, sy + 4.0, 13.0, 2.0, 0.0, rgba(1.0, 1.0, 1.0, on ? 0.35 : 0.15));
		if (on) { outline(u, kx - 1.0, sy + 2.0, 17.0, 16.0, 1.0, rgba(0.969, 0.549, 0.227, 0.35)); }
	}
	return tapped;
}

// ---- Segmented control and tabs -------------------------------------------------------------

// One active segment, ember-filled, in a heavy frame. Returns the (maybe new) active index.
export function segmented(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, labels: string[], active: int32, seed: int32): int32 {
	const h: float32 = 36.0;
	frame(k, id, x, y, w, h, seed, FrameLook.Normal);
	const n: int32 = labels.length as int32;
	const pad: float32 = 7.0;
	const segW: float32 = (w - 2.0 * pad) / (n as float32);
	let picked: int32 = active;
	for (let i: int32 = 0; i < n; i += 1) {
		const sx: float32 = x + pad + segW * (i as float32);
		if (pressable(u, sub(id, i), sx, y, segW, h)) { picked = i; }
		if (i == active) {
			box(u, sx + 1.0, y + 7.0, segW - 2.0, h - 14.0, 0.0, EMBER);
			box(u, sx + 1.0, y + 7.0, segW - 2.0, 1.0, 0.0, EMBER_HOT);
		} else if (i > 0 && i - 1 != active) {
			box(u, sx, y + 10.0, 1.0, h - 20.0, 0.0, DIVIDER);
		}
		say(u, k, sub(id, i), labels[i], sx, centreY(k, labels[i], 8.0, y, h), segW, 8.0, i == active ? ASH_DEEP : INK, 0.5);
	}
	return picked;
}

// Text tabs with an ember underline on the active one; `counts[i]` > 0 shows a small filled
// pill after the label (points unspent on Tree). Returns the active index.
export function tabs(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, labels: string[], counts: int32[], active: int32): int32 {
	const n: int32 = labels.length as int32;
	const tabW: float32 = w / (n as float32);
	let picked: int32 = active;
	box(u, x, y + 30.0, w, 1.0, 0.0, DIVIDER);
	for (let i: int32 = 0; i < n; i += 1) {
		const tx: float32 = x + tabW * (i as float32);
		if (pressable(u, sub(id, i), tx, y - 8.0, tabW, 48.0)) { picked = i; }
		const t: TextSize = measure(k, labels[i], 8.0);
		const count: string = counts[i] > 0 ? counts[i].toString() : "";
		const cw: float32 = count == "" ? 0.0 : measure(k, count, 8.0).w + 8.0;
		const left: float32 = tx + (tabW - t.w - (cw > 0.0 ? cw + 4.0 : 0.0)) * 0.5;
		say(u, k, sub(id, i), labels[i], left, y + 10.0, t.w + 2.0, 8.0, i == active ? EMBER_HOT : INK_MUTED, 0.0);
		if (cw > 0.0) {
			box(u, left + t.w + 4.0, y + 8.0, cw, 12.0, 0.0, EMBER);
			say(u, k, sub(id, i) + 4, count, left + t.w + 4.0, y + 10.0, cw, 8.0, ASH_DEEP, 0.5);
		}
		if (i == active) {
			box(u, tx + 8.0, y + 28.0, tabW - 16.0, 2.0, 0.0, EMBER);
			box(u, tx + 8.0, y + 28.0, tabW - 16.0, 1.0, 0.0, EMBER_HOT);
		}
	}
	return picked;
}

// ---- Radio row ----------------------------------------------------------------------------

// A 48-unit row: pixel ring, title, one-line description; "CURRENT" tag on the current one.
export function radioRow(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, title: string, detail: string,
	selected: boolean, current: boolean): boolean {
	const tapped: boolean = pressable(u, id, x, y, w, 48.0);
	const rx: float32 = x + 4.0;
	const ry: float32 = y + 16.0;
	const ring: Color = selected ? EMBER_HOT : INK_MUTED;
	box(u, rx + 3.0, ry, 6.0, 1.0, 0.0, ring);
	box(u, rx + 3.0, ry + 11.0, 6.0, 1.0, 0.0, ring);
	box(u, rx, ry + 3.0, 1.0, 6.0, 0.0, ring);
	box(u, rx + 11.0, ry + 3.0, 1.0, 6.0, 0.0, ring);
	box(u, rx + 1.0, ry + 1.0, 2.0, 2.0, 0.0, ring);
	box(u, rx + 9.0, ry + 1.0, 2.0, 2.0, 0.0, ring);
	box(u, rx + 1.0, ry + 9.0, 2.0, 2.0, 0.0, ring);
	box(u, rx + 9.0, ry + 9.0, 2.0, 2.0, 0.0, ring);
	if (selected) { box(u, rx + 3.0, ry + 3.0, 6.0, 6.0, 0.0, EMBER_HOT); }
	say(u, k, id, title, x + 26.0, y + 10.0, w - 100.0, 8.0, selected ? INK : INK_MUTED, 0.0);
	say(u, k, sub(id, 0), detail, x + 26.0, y + 26.0, w - 30.0, 8.0, INK_MUTED, 0.0);
	if (current) {
		const t: TextSize = measure(k, "CURRENT", 8.0);
		box(u, x + w - t.w - 12.0, y + 8.0, t.w + 10.0, 14.0, 0.0, EMBER);
		say(u, k, sub(id, 1), "CURRENT", x + w - t.w - 12.0, y + 11.0, t.w + 10.0, 8.0, ASH_DEEP, 0.5);
	}
	box(u, x, y + 47.0, w, 1.0, 0.0, DIVIDER);
	return tapped;
}

// ---- List row -----------------------------------------------------------------------------

export enum RowKind { Plain, Selected, Destructive, Locked }

// Frameless row: icon, text, right-aligned value, chevron; a thin divider under it.
// `tall` = 56 units (Settings), else 48. Selected = inverted. Returns true on a tap.
export function listRow(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, glyph: string, label: string,
	value: string, valueColor: Color, kind: RowKind, chevron: boolean, tall: boolean): boolean {
	const h: float32 = tall ? 56.0 : 48.0;
	const live: boolean = kind != RowKind.Locked;
	const tapped: boolean = pressable(u, id, x, y, w, h) && live;
	const down: boolean = live && held(u, id, x, y, w, h);
	const selected: boolean = kind == RowKind.Selected;
	if (selected) { box(u, x, y, w, h - 1.0, 0.0, FILL_LIGHT); }
	else if (down) { box(u, x, y, w, h - 1.0, 0.0, rgba(1.0, 0.6, 0.3, 0.08)); }
	let ink: Color = INK;
	if (selected) { ink = ASH_DEEP; }
	if (kind == RowKind.Destructive) { ink = ALERT_RED; }
	if (kind == RowKind.Locked) { ink = DISABLED_INK; }
	let tx: float32 = x + 8.0;
	if (glyph != "") {
		iconTinted(k, id, glyph, x + 8.0, y + (h - 16.0) * 0.5, 16.0, kind == RowKind.Locked ? DIMMED : WHITE);
		tx = x + 32.0;
	}
	const ty: float32 = centreY(k, label, 8.0, y, h);
	say(u, k, id, label, tx, ty, w * 0.6, 8.0, ink, 0.0);
	const right: float32 = x + w - (chevron || kind == RowKind.Locked ? 22.0 : 8.0);
	if (value != "") {
		say(u, k, sub(id, 0), value, x + w * 0.4, ty, right - x - w * 0.4, 8.0, selected ? ASH_DEEP : valueColor, 1.0);
	}
	if (kind == RowKind.Locked) {
		iconTinted(k, sub(id, 1), "lock", x + w - 18.0, y + (h - 12.0) * 0.5, 12.0, DIMMED);
	} else if (chevron) {
		say(u, k, sub(id, 2), ">", x + w - 16.0, ty, 12.0, 8.0, selected ? ASH_DEEP : INK_MUTED, 0.0);
	}
	box(u, x, y + h - 1.0, w, 1.0, 0.0, DIVIDER);
	return tapped;
}

// ---- Section header and dividers ----------------------------------------------------------

// "THIS MORNING" left, a date right, a thin divider under them.
export function sectionHeader(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, title: string, right: string): void {
	say(u, k, id, title, x, y, w * 0.6, 8.0, EMBER_HOT, 0.0);
	if (right != "") { say(u, k, sub(id, 0), right, x + w * 0.4, y, w * 0.6, 8.0, INK_MUTED, 1.0); }
	box(u, x, y + 14.0, w, 1.0, 0.0, DIVIDER);
}

// A divider with a label in its middle ("NEW SINCE 23:10", "SEEN", "YESTERDAY").
export function labelDivider(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, label: string, color: Color): void {
	const t: TextSize = measure(k, label, 8.0);
	const lx: float32 = x + (w - t.w) * 0.5;
	box(u, x, y + 4.0, lx - x - 6.0, 1.0, 0.0, color);
	box(u, lx + t.w + 6.0, y + 4.0, x + w - lx - t.w - 6.0, 1.0, 0.0, color);
	say(u, k, id, label, lx, y, t.w + 2.0, 8.0, color, 0.0);
}

// ---- Toast queue --------------------------------------------------------------------------

const TOAST_FRAMES: int32 = 120 as int32;

export interface Toasts {
	lines: string[];
	alerts: boolean[];
	left: int32;
}

export function toasts(): Toasts { return { lines: [], alerts: [], left: 0 as int32 }; }

// Queue a line; toasts show one at a time and never stack.
export function pushToast(q: Toasts, line: string, alert: boolean): void {
	q.lines.push(line);
	q.alerts.push(alert);
	if ((q.lines.length as int32) == 1) { q.left = TOAST_FRAMES; }
}

// The frameless dark strip for the head of the queue; fades in and out.
export function drawToasts(u: Ui, k: Kit, id: int32, q: Toasts, x: float32, y: float32, w: float32): void {
	if ((q.lines.length as int32) == 0) { return; }
	const age: int32 = TOAST_FRAMES - q.left;
	let a: float32 = 1.0;
	if (age < 8) { a = (age as float32) / 8.0; }
	if (q.left < 12) { a = (q.left as float32) / 12.0; }
	box(u, x, y, w, 36.0, 0.0, rgba(STRIP.r, STRIP.g, STRIP.b, STRIP.a * a));
	if (q.alerts[0]) { box(u, x, y, 2.0, 36.0, 0.0, rgba(ALERT_RED.r, ALERT_RED.g, ALERT_RED.b, a)); }
	const ink: Color = q.alerts[0] ? ALERT_RED : INK;
	say(u, k, id, q.lines[0], x + 8.0, centreY(k, q.lines[0], 8.0, y, 36.0), w - 16.0, 8.0, rgba(ink.r, ink.g, ink.b, a), 0.5);
	q.left -= 1;
	if (q.left <= 0) {
		const lines: string[] = [];
		const alerts: boolean[] = [];
		for (let i: int32 = 1; i < q.lines.length; i += 1) {
			lines.push(q.lines[i]);
			alerts.push(q.alerts[i]);
		}
		q.lines = lines;
		q.alerts = alerts;
		q.left = (lines.length as int32) > 0 ? TOAST_FRAMES : 0 as int32;
	}
}

// ---- Tooltip, reason pill, banner ---------------------------------------------------------

// One line in a light frame to the LEFT of an anchor at (ax, ay) (its vertical middle), with
// a small tail pointing at it.
export function tooltip(u: Ui, k: Kit, id: int32, ax: float32, ay: float32, line: string): void {
	const t: TextSize = measure(k, line, 8.0);
	const w: float32 = t.w + 16.0;
	const h: float32 = 24.0;
	const x: float32 = ax - w - 6.0;
	const y: float32 = ay - h * 0.5;
	lightFrame(u, x, y, w, h, RIM_IN);
	for (let i: int32 = 0; i < 4; i += 1) {
		box(u, x + w + (i as float32), ay - 3.0 + (i as float32), 1.0, 6.0 - 2.0 * (i as float32), 0.0, RIM_IN);
	}
	say(u, k, id, line, x + 8.0, centreY(k, line, 8.0, y, h), t.w + 2.0, 8.0, INK, 0.0);
}

// The one-line reason under a card: a warning glyph and the reason; alert = red rim and ink.
export function reasonPill(u: Ui, k: Kit, id: int32, x: float32, y: float32, line: string, alert: boolean): float32 {
	const t: TextSize = measure(k, line, 8.0);
	const w: float32 = t.w + 30.0;
	lightFrame(u, x, y, w, 20.0, alert ? ALERT_RED : RIM_IN);
	iconTinted(k, id, "warning", x + 6.0, y + 4.0, 12.0, alert ? WHITE : DIMMED);
	say(u, k, id, line, x + 22.0, centreY(k, line, 8.0, y, 20.0), t.w + 2.0, 8.0, alert ? ALERT_RED : INK, 0.0);
	return w;
}

// "Confirm in your wallet": a heavy frame, a spinner, the line and what is being signed.
export function walletBanner(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, detail: string, seed: int32, tick: int32): void {
	frame(k, id, x, y, w, 52.0, seed, FrameLook.Normal);
	spinner(u, x + 14.0, y + 18.0, 16.0, tick);
	say(u, k, id, "CONFIRM IN YOUR WALLET", x + 40.0, y + 15.0, w - 50.0, 8.0, EMBER_HOT, 0.0);
	say(u, k, sub(id, 0), detail, x + 40.0, y + 29.0, w - 50.0, 8.0, INK_MUTED, 0.0);
}

// ---- Loading and empty --------------------------------------------------------------------

// A skeleton bar: a dim bar whose light sweeps left to right.
export function skeleton(u: Ui, x: float32, y: float32, w: float32, h: float32, tick: int32): void {
	box(u, x, y, w, h, 0.0, rgba(0.16, 0.12, 0.11, 0.9));
	const sweep: float32 = ((tick % 60) as float32) / 60.0;
	const bw: float32 = w * 0.3;
	let bx: float32 = x - bw + (w + bw) * sweep;
	let bwc: float32 = bw;
	if (bx < x) { bwc = bw - (x - bx); bx = x; }
	if (bx + bwc > x + w) { bwc = x + w - bx; }
	if (bwc > 0.0) { box(u, bx, y, bwc, h, 0.0, rgba(0.30, 0.22, 0.19, 0.9)); }
}

// "SYNCING..." (spinner) or "OFFLINE - 3 MIN AGO" (dim dot) in a dashed chip.
export function syncChip(u: Ui, k: Kit, id: int32, x: float32, y: float32, line: string, syncing: boolean, tick: int32): float32 {
	const t: TextSize = measure(k, line, 8.0);
	const w: float32 = t.w + 30.0;
	box(u, x, y, w, 20.0, 0.0, FILL);
	let d: float32 = 0.0;
	while (d < w) {
		box(u, x + d, y, d + 3.0 < w ? 3.0 : w - d, 1.0, 0.0, RIM_IN);
		box(u, x + d, y + 19.0, d + 3.0 < w ? 3.0 : w - d, 1.0, 0.0, RIM_IN);
		d += 5.0;
	}
	box(u, x, y, 1.0, 20.0, 0.0, RIM_IN);
	box(u, x + w - 1.0, y, 1.0, 20.0, 0.0, RIM_IN);
	if (syncing) { spinner(u, x + 5.0, y + 2.0, 16.0, tick); }
	else { box(u, x + 10.0, y + 8.0, 4.0, 4.0, 0.0, DISABLED_INK); }
	say(u, k, id, line, x + 24.0, centreY(k, line, 8.0, y, 20.0), t.w + 2.0, 8.0, syncing ? INK : INK_MUTED, 0.0);
	return w;
}

// A dashed box with an icon and one line: nothing yet, hidden, not attackable, dead slot.
export function emptyState(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, h: float32, glyph: string, line: string): void {
	box(u, x, y, w, h, 0.0, rgba(0.06, 0.05, 0.05, 0.7));
	let d: float32 = 0.0;
	while (d < w) {
		box(u, x + d, y, d + 4.0 < w ? 4.0 : w - d, 1.0, 0.0, RIM_IN);
		box(u, x + d, y + h - 1.0, d + 4.0 < w ? 4.0 : w - d, 1.0, 0.0, RIM_IN);
		d += 7.0;
	}
	d = 0.0;
	while (d < h) {
		box(u, x, y + d, 1.0, d + 4.0 < h ? 4.0 : h - d, 0.0, RIM_IN);
		box(u, x + w - 1.0, y + d, 1.0, d + 4.0 < h ? 4.0 : h - d, 0.0, RIM_IN);
		d += 7.0;
	}
	if (glyph == "") {
		say(u, k, id, line, x + 8.0, centreY(k, line, 8.0, y, h), w - 16.0, 8.0, INK_MUTED, 0.5);
		return;
	}
	iconTinted(k, id, glyph, x + (w - 20.0) * 0.5, y + h * 0.5 - 18.0, 20.0, DIMMED);
	say(u, k, id, line, x + 8.0, y + h * 0.5 + 8.0, w - 16.0, 8.0, INK_MUTED, 0.5);
}
