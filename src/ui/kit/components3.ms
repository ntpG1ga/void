// Hibernal UI kit, batch 3: Sheet, Modal, Dock, Pager, Chat bubble, Chat input, Lineage,
// Talent card, Skill-tree nodes and links. hibernal docs/UI-KIT.md §A #4-#5, §C.
// Same rules as components.ms.

import { Color, rgba } from "../../void2d/types";
import { Ui, box, pressable, held, beginOverlay } from "../ui";
import { Kit, beginKitOverlay, TextSize, measure, measureWrapped, frame, frameSqueezed, badgeFrame, icon, iconTinted, say,
	INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED, DISABLED_INK, WHITE } from "./kit";
import { FrameLook } from "./frame";
import { button, ButtonStyle, textLink, Rarity, rarityColor, rarityName, rarityBorder, chip, ChipKind, spinner, GROWTH_GREEN } from "./components";
import { lightFrame } from "./components2";

const SUB_BASE: int32 = 3000000 as int32;
function sub(id: int32, n: int32): int32 { return SUB_BASE + id * 16 + n; }

const HALF: float32 = 0.5;
const DIVIDER: Color = rgba(0.243, 0.149, 0.125, 1.0);
const ASH: Color = rgba(0.30, 0.28, 0.27, 1.0);
const OWNER_FILL: Color = rgba(0.200, 0.090, 0.060, 0.96);
const PET_FILL: Color = rgba(0.094, 0.071, 0.063, 0.96);

function centreY(k: Kit, s: string, size: float32, y: float32, h: float32): float32 {
	return y + (h - measure(k, s, size).h) * HALF;
}

// ---- Sheet --------------------------------------------------------------------------------

// A bottom sheet `h` tall, slid up by `open` (0 hidden .. 1 fully up); the scene behind is
// dimmed. Its bottom rim sits off-screen. Returns true when the dimmed scene is tapped
// (close). Content is the caller's, from the returned top: sheetTop(h, open).
const SCREEN_H: float32 = 800.0;
export function sheetTop(h: float32, open: float32): float32 {
	return SCREEN_H - h * open;
}

// Opens the overlay layer (ui + kit) and leaves it open, so the caller's content lands on the
// sheet; the caller calls endOverlay / endKitOverlay after it.
export function sheet(u: Ui, k: Kit, id: int32, h: float32, open: float32, seed: int32): boolean {
	beginOverlay(u);
	beginKitOverlay(k);
	if (open <= 0.0) { return false; }
	const top: float32 = sheetTop(h, open);
	box(u, 0.0, 0.0, 360.0, top, 0.0, rgba(0.02, 0.02, 0.04, 0.55 * open));
	// only once fully up: while it slides, the dim area covers the tap that opened it
	const closed: boolean = open > 0.95 && pressable(u, id, 0.0, 0.0, 360.0, top - 4.0);
	frame(k, id, 4.0, top, 352.0, h + 24.0, seed, FrameLook.Normal);
	// drag handle: a short warm wood bar
	box(u, 162.0, top + 10.0, 36.0, 3.0, 0.0, rgba(0.404, 0.247, 0.188, 1.0));
	box(u, 162.0, top + 10.0, 36.0, 1.0, 0.0, rgba(0.55, 0.36, 0.27, 1.0));
	return closed;
}

// ---- Modal --------------------------------------------------------------------------------

export enum ModalAnswer { None, Cancel, Confirm }

// A centred dialog over a dimmed screen: title, body (wraps), a frameless Cancel and a framed
// confirm (Danger when `destructive`).
// Draws on the overlay layer and leaves it open (end it with endOverlay / endKitOverlay).
export function modal(u: Ui, k: Kit, id: int32, title: string, body: string, confirm: string, destructive: boolean, seed: int32): ModalAnswer {
	beginOverlay(u);
	beginKitOverlay(k);
	box(u, 0.0, 0.0, 360.0, 800.0, 0.0, rgba(0.02, 0.02, 0.04, 0.6));
	pressable(u, sub(id, 0), 0.0, 0.0, 360.0, 800.0);   // swallow taps behind the dialog
	const w: float32 = 296.0;
	const x: float32 = (360.0 - w) * HALF;
	const bodySize: TextSize = measureWrapped(k, body, 8.0, w - 40.0);
	const h: float32 = 40.0 + 20.0 + bodySize.h + 24.0 + 44.0 + 16.0;
	const y: float32 = (800.0 - h) * HALF - 20.0;
	frame(k, id, x, y, w, h, seed, FrameLook.Normal);
	say(u, k, sub(id, 1), title, x + 20.0, y + 26.0, w - 40.0, 16.0, INK, 0.5);
	say(u, k, sub(id, 2), body, x + 20.0, y + 60.0, w - 40.0, 8.0, INK_MUTED, 0.5);
	const by: float32 = y + h - 64.0;
	let answer: ModalAnswer = ModalAnswer.None;
	const cancelW: float32 = measure(k, "CANCEL", 8.0).w;
	if (textLink(u, k, sub(id, 3), x + 30.0 + (100.0 - cancelW) * HALF, by + 18.0, "CANCEL", true)) { answer = ModalAnswer.Cancel; }
	if (button(u, k, sub(id, 4), x + w - 156.0, by, 136.0, 44.0, confirm, destructive ? ButtonStyle.Danger : ButtonStyle.Primary, true, seed + 1)) {
		answer = ModalAnswer.Confirm;
	}
	return answer;
}

// ---- Dock ---------------------------------------------------------------------------------

const DOCK_ICONS: string[] = ["home", "pet", "block", "shop", "digest"];
const DOCK_NAMES: string[] = ["HOME", "PET", "BLOCK", "SHOP", "DIGEST"];

// The floating dock, 328 x 56 at y 728: five items, the active one ember with an underline,
// an unread dot on Digest. Returns the tapped index or -1.
export function dock(u: Ui, k: Kit, id: int32, active: int32, digestUnread: boolean, seed: int32): int32 {
	const x: float32 = 16.0;
	const y: float32 = 728.0;
	frame(k, id, x, y, 328.0, 56.0, seed, FrameLook.Normal);
	const slot: float32 = (328.0 - 16.0) / 5.0;
	let tapped: int32 = -1 as int32;
	for (let i: int32 = 0; i < 5; i += 1) {
		const sx: float32 = x + 8.0 + slot * (i as float32);
		const cx: float32 = sx + slot * HALF;
		if (pressable(u, sub(id, i), sx, y, slot, 56.0)) { tapped = i; }
		const down: boolean = held(u, sub(id, i), sx, y, slot, 56.0);
		const on: boolean = i == active;
		iconTinted(k, sub(id, i), DOCK_ICONS[i], cx - 11.0, y + 9.0 + (down ? 1.0 : 0.0), 22.0, on || down ? WHITE : rgba(0.85, 0.85, 0.85, 0.9));
		say(u, k, sub(id, i), DOCK_NAMES[i], sx, y + 35.0, slot, 8.0, on ? EMBER_HOT : INK, 0.5);
		if (on) {
			box(u, cx - 18.0, y + 46.0, 36.0, 2.0, 0.0, EMBER);
			box(u, cx - 18.0, y + 46.0, 36.0, 1.0, 0.0, EMBER_HOT);
		}
		if (i == 4 && digestUnread) {
			box(u, cx + 9.0, y + 7.0, 6.0, 6.0, 0.0, ALERT_RED);
			box(u, cx + 10.0, y + 8.0, 2.0, 2.0, 0.0, rgba(1.0, 0.6, 0.5, 1.0));
		}
	}
	return tapped;
}

// ---- Pager --------------------------------------------------------------------------------

// "‹  SLOT 4 - 1 OF 9 (THREAT)  ›" with a dot per page under it. Returns the new index.
export function pager(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, label: string, index: int32, count: int32): int32 {
	let next: int32 = index;
	if (pressable(u, sub(id, 0), x, y - 8.0, 48.0, 40.0) && index > 0) { next = index - 1; }
	if (pressable(u, sub(id, 1), x + w - 48.0, y - 8.0, 48.0, 40.0) && index < count - 1) { next = index + 1; }
	say(u, k, sub(id, 2), "<", x + 12.0, y + 4.0, 16.0, 16.0, index > 0 ? EMBER_HOT : DISABLED_INK, 0.0);
	say(u, k, sub(id, 3), ">", x + w - 24.0, y + 4.0, 16.0, 16.0, index < count - 1 ? EMBER_HOT : DISABLED_INK, 0.0);
	say(u, k, sub(id, 4), label, x + 40.0, y + 8.0, w - 80.0, 8.0, INK, 0.5);
	const span: float32 = (count as float32) * 10.0 - 4.0;
	for (let i: int32 = 0; i < count; i += 1) {
		const dx: float32 = x + (w - span) * HALF + (i as float32) * 10.0;
		if (i == index) { box(u, dx - 1.0, y + 23.0, 8.0, 8.0, 0.0, EMBER_HOT); }
		else { box(u, dx, y + 24.0, 6.0, 6.0, 0.0, ASH); }
	}
	return next;
}

// ---- Chat ---------------------------------------------------------------------------------

// One message. Owner: right, ember-tinted, "COUNTED" / "DOESN'T COUNT" under it. Pet: left,
// dark, a small avatar. Returns the bubble's height so messages can be stacked.
export function chatBubble(u: Ui, k: Kit, id: int32, left: float32, right: float32, y: float32, line: string, owner: boolean,
	counted: boolean, avatarSeed: int32): float32 {
	const maxW: float32 = (right - left) - 70.0;
	const t: TextSize = measureWrapped(k, line, 8.0, maxW);
	const w: float32 = t.w + 20.0;
	const h: float32 = t.h + 16.0;
	const x: float32 = owner ? right - w : left + 46.0;
	box(u, x, y, w, h, 0.0, owner ? OWNER_FILL : PET_FILL);
	lightFrame(u, x, y, w, h, owner ? EMBER : rgba(0.404, 0.247, 0.188, 1.0));
	// tail: a 3-step wedge at the bottom corner on the speaker's side
	const tc: Color = owner ? EMBER : rgba(0.404, 0.247, 0.188, 1.0);
	for (let i: int32 = 0; i < 3; i += 1) {
		const tx: float32 = owner ? x + w - 6.0 + (i as float32) * 2.0 : x + 4.0 - (i as float32) * 2.0;
		box(u, tx, y + h + (i as float32), 2.0, 1.0, 0.0, tc);
	}
	say(u, k, id, line, x + 10.0, y + 8.0, maxW + 2.0, 8.0, INK, 0.0);
	let used: float32 = h + 4.0;
	if (!owner) {
		badgeFrame(k, sub(id, 0), left, y + h - 36.0, 36.0, avatarSeed);
		icon(k, sub(id, 0), "pet", left + 8.0, y + h - 28.0, 20.0);
	} else {
		const tag: string = counted ? "COUNTED" : "DOESN'T COUNT";
		const tw: float32 = measure(k, tag, 8.0).w;
		say(u, k, sub(id, 1), tag, right - tw - 2.0, y + h + 6.0, tw + 4.0, 8.0, counted ? EMBER : INK_MUTED, 0.0);
		used = h + 20.0;
	}
	return used;
}

// The input bar: a light-framed field (placeholder when empty) and a framed SEND, enabled
// only with text. Typing itself is a native overlay (ui.ms designToSurfaceX/Y place it).
export function chatInput(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, text: string, seed: int32): boolean {
	const fieldW: float32 = w - 92.0;
	lightFrame(u, x, y, fieldW, 44.0, rgba(0.404, 0.247, 0.188, 1.0));
	const empty: boolean = text == "";
	const shown: string = empty ? "SAY SOMETHING..." : text;
	say(u, k, id, shown, x + 12.0, centreY(k, shown, 8.0, y, 44.0), fieldW - 24.0, 8.0, empty ? INK_MUTED : INK, 0.0);
	return button(u, k, sub(id, 0), x + w - 84.0, y, 84.0, 44.0, "SEND", ButtonStyle.Primary, !empty, seed);
}

// ---- Lineage ------------------------------------------------------------------------------

export enum LineageState { Lived, Died, Now }

// One generation on a vertical timeline: a node (ember diamond now, ash skull when it died,
// a dim diamond when it lived its span), the line to the next entry, and the text.
export function lineageEntry(u: Ui, k: Kit, id: int32, x: float32, y: float32, w: float32, line: string,
	state: LineageState, last: boolean): void {
	const cx: float32 = x + 8.0;
	if (!last) { box(u, cx - 1.0, y + 14.0, 2.0, 30.0, 0.0, DIVIDER); }
	if (state == LineageState.Died) {
		iconTinted(k, id, "skull", cx - 7.0, y - 1.0, 14.0, rgba(0.6, 0.58, 0.56, 1.0));
	} else {
		const c: Color = state == LineageState.Now ? EMBER_HOT : ASH;
		for (let i: int32 = 0; i < 6; i += 1) {
			const half: float32 = (i < 3 ? i + 1 : 6 - i) as float32;
			box(u, cx - half, y + 2.0 + (i as float32) * 1.5, half * 2.0, 1.5, 0.0, c);
		}
		if (state == LineageState.Now) {
			box(u, cx - 6.0, y - 1.0, 12.0, 1.0, 0.0, rgba(0.969, 0.549, 0.227, 0.35));
			box(u, cx - 6.0, y + 12.0, 12.0, 1.0, 0.0, rgba(0.969, 0.549, 0.227, 0.35));
		}
	}
	say(u, k, id, line, x + 24.0, y + 2.0, w - 24.0, 8.0, state == LineageState.Now ? INK : INK_MUTED, 0.0);
}

// ---- Talent card --------------------------------------------------------------------------

const CARD_W: float32 = 120.0;
const CARD_H: float32 = 160.0;

// The talent card at (x, y): `flip` 0 shows the back ("?"), 1 the face; between, the card
// squeezes shut on its back and opens on its face. Face: kind, rarity plate colour, multiplier.
export function talentCard(u: Ui, k: Kit, id: int32, x: float32, y: float32, flip: float32, kind: string, rarity: Rarity,
	multiplier: string, seed: int32): void {
	const f: float32 = flip < 0.0 ? 0.0 : (flip > 1.0 ? 1.0 : flip);
	const faceUp: boolean = f >= 0.5;
	const open: float32 = faceUp ? (f - 0.5) * 2.0 : 1.0 - f * 2.0;
	const squeeze: float32 = open < 0.04 ? 0.04 : open;
	if (!faceUp) {
		frameSqueezed(k, id, x, y, CARD_W, CARD_H, seed, FrameLook.Normal, squeeze);
		if (open >= 0.6) { say(u, k, id, "?", x, y + CARD_H * HALF - 16.0, CARD_W, 32.0, EMBER_HOT, 0.5); }
		return;
	}
	// face: the rarity border, squeezed about the card's centre while it turns
	const w: float32 = CARD_W * squeeze;
	const fx: float32 = x + (CARD_W - w) * HALF;
	rarityBorder(u, fx, y, w, CARD_H, rarity);
	if (open < 0.6) { return; }
	const c: Color = rarityColor(rarity);
	say(u, k, id, kind, x, y + 26.0, CARD_W, 8.0, INK_MUTED, 0.5);
	icon(k, id, "fightWon", x + CARD_W * HALF - 14.0, y + 42.0, 28.0);
	say(u, k, sub(id, 0), rarityName(rarity), x, y + 82.0, CARD_W, 16.0, c, 0.5);
	box(u, x + 24.0, y + 104.0, CARD_W - 48.0, 1.0, 0.0, rgba(c.r, c.g, c.b, 0.5));
	say(u, k, sub(id, 1), multiplier, x, y + 112.0, CARD_W, 16.0, INK, 0.5);
	say(u, k, sub(id, 2), "TO FIGHT STATS", x, y + 134.0, CARD_W, 8.0, INK_MUTED, 0.5);
}

// The grade ladder: every grade a chip, lit up to and including `reached`, dashed above it.
export function gradeLadder(u: Ui, k: Kit, id: int32, x: float32, y: float32, reached: Rarity): void {
	let cx: float32 = x;
	const grades: Rarity[] = [Rarity.Common, Rarity.Rare, Rarity.Epic, Rarity.Legendary, Rarity.Mythic];
	for (let i: int32 = 0; i < 5; i += 1) {
		const lit: boolean = (grades[i] as int32) <= (reached as int32);
		cx += chip(u, k, sub(id, i), cx, y, rarityName(grades[i]), lit ? ChipKind.Outline : ChipKind.Dashed,
			lit ? rarityColor(grades[i]) : DISABLED_INK) + 4.0;
	}
}

// ---- Skill tree ---------------------------------------------------------------------------

export enum NodeShape { Small, Notable, Keystone }
export enum NodeState { Allocated, Reachable, Locked }

// A tree node, the sheet-6 sprites: small, notable, keystone; allocated, reachable, locked.
// Sizes in design units follow the sheet (40 / 56 / 72 px at its 2.84 px per unit, so 14 / 20 / 26).
const NODE_SIZE: float32[] = [15.0, 21.0, 26.0];
const NODE_SHAPE: string[] = ["Small", "Notable", "Keystone"];
const NODE_STATE: string[] = ["Allocated", "Reachable", "Locked"];

export function treeNode(u: Ui, k: Kit, id: int32, cx: float32, cy: float32, shape: NodeShape, state: NodeState): boolean {
	return treeNodeScaled(u, k, id, cx, cy, shape, state, 1.0);
}

// The same at `scale` (the tree's zoom): the sprite and its touch target grow with it.
export function treeNodeScaled(u: Ui, k: Kit, id: int32, cx: float32, cy: float32, shape: NodeShape, state: NodeState,
	scale: float32): boolean {
	const t: float32 = 48.0 * (scale > 1.0 ? scale : 1.0);
	const tapped: boolean = pressable(u, id, cx - t * HALF, cy - t * HALF, t, t);
	const size: float32 = NODE_SIZE[shape as int32] * scale;
	icon(k, id, "node" + NODE_SHAPE[shape as int32] + NODE_STATE[state as int32], cx - size * HALF, cy - size * HALF, size);
	return tapped;
}

// A link between two nodes: thin ash, or thick ember when both ends are allocated.
export function treeLink(u: Ui, x0: float32, y0: float32, x1: float32, y1: float32, allocated: boolean): void {
	treeLinkIn(u, x0, y0, x1, y1, allocated, 0.0, 0.0, 360.0, 800.0);
}

// The same, drawn only where it lies inside the clip rectangle (the tree's frame).
export function treeLinkIn(u: Ui, x0: float32, y0: float32, x1: float32, y1: float32, allocated: boolean,
	clipX: float32, clipY: float32, clipW: float32, clipH: float32): void {
	const dx: float32 = x1 - x0;
	const dy: float32 = y1 - y0;
	const adx: float32 = dx < 0.0 ? -dx : dx;
	const ady: float32 = dy < 0.0 ? -dy : dy;
	const longest: float32 = adx > ady ? adx : ady;
	const steps: int32 = longest as int32;
	for (let i: int32 = 0; i <= steps; i += 1) {
		const f: float32 = steps == 0 ? 0.0 : (i as float32) / (steps as float32);
		const px: float32 = x0 + dx * f;
		const py: float32 = y0 + dy * f;
		if (px < clipX + 2.0 || py < clipY + 2.0 || px > clipX + clipW - 2.0 || py > clipY + clipH - 2.0) { continue; }
		if (allocated) {
			box(u, px - 2.0, py - 2.0, 4.0, 4.0, 0.0, rgba(0.969, 0.549, 0.227, 0.18));
			box(u, px - 1.0, py - 1.0, 2.0, 2.0, 0.0, EMBER_HOT);
		} else {
			box(u, px - 1.0, py - 1.0, 2.0, 2.0, 0.0, rgba(0.42, 0.40, 0.39, 0.85));
		}
	}
}

// ---- Odds block ---------------------------------------------------------------------------

export enum OddsState { Ready, Computing, NotAttackable }

// "IF YOUR PET ATTACKS" in a panel 328 x 168: win chance, expected and max loot, a bar per
// fight length (1..6 rounds, `rounds` are shares 0..1), the read-only line. Computing shows a
// spinner; NotAttackable replaces it all with the reason.
export function oddsBlock(u: Ui, k: Kit, id: int32, x: float32, y: float32, state: OddsState, winPercent: int32,
	expectedLoot: int32, maxLoot: int32, rounds: float32[], reason: string, seed: int32, tick: int32): void {
	const w: float32 = 328.0;
	const h: float32 = 168.0;
	frame(k, id, x, y, w, h, seed, FrameLook.Normal);
	say(u, k, id, "IF YOUR PET ATTACKS", x + 18.0, y + 18.0, w - 36.0, 8.0, EMBER_HOT, 0.0);
	box(u, x + 18.0, y + 32.0, w - 36.0, 1.0, 0.0, DIVIDER);
	if (state == OddsState.Computing) {
		spinner(u, x + w * HALF - 8.0, y + 68.0, 16.0, tick);
		say(u, k, sub(id, 0), "SIMULATING 2,000 FIGHTS...", x, y + 94.0, w, 8.0, INK_MUTED, 0.5);
		return;
	}
	if (state == OddsState.NotAttackable) {
		iconTinted(k, sub(id, 0), "shield", x + w * HALF - 10.0, y + 58.0, 20.0, rgba(0.7, 0.68, 0.66, 1.0));
		say(u, k, sub(id, 1), "NOT ATTACKABLE", x, y + 88.0, w, 8.0, INK, 0.5);
		say(u, k, sub(id, 2), reason, x + 18.0, y + 104.0, w - 36.0, 8.0, INK_MUTED, 0.5);
		return;
	}
	// numbers, left column
	say(u, k, sub(id, 0), "WIN CHANCE", x + 18.0, y + 44.0, 120.0, 8.0, INK_MUTED, 0.0);
	say(u, k, sub(id, 1), winPercent.toString() + "%", x + 18.0, y + 56.0, 120.0, 16.0,
		winPercent >= 50 ? GROWTH_GREEN : ALERT_RED, 0.0);
	say(u, k, sub(id, 2), "EXP. LOOT", x + 18.0, y + 84.0, 70.0, 8.0, INK_MUTED, 0.0);
	say(u, k, sub(id, 3), expectedLoot.toString(), x + 18.0, y + 96.0, 70.0, 8.0, INK, 0.0);
	say(u, k, sub(id, 4), "MAX LOOT", x + 88.0, y + 84.0, 70.0, 8.0, INK_MUTED, 0.0);
	say(u, k, sub(id, 5), maxLoot.toString(), x + 88.0, y + 96.0, 70.0, 8.0, INK, 0.0);
	// rounds chart, right column
	const cx: float32 = x + 176.0;
	const base: float32 = y + 108.0;
	say(u, k, sub(id, 6), "ROUNDS", cx, y + 44.0, 130.0, 8.0, INK_MUTED, 0.0);
	let top: float32 = 0.0;
	for (const r of rounds) { if (r > top) { top = r; } }
	for (let i: int32 = 0; i < rounds.length; i += 1) {
		const bh: float32 = top > 0.0 ? 44.0 * rounds[i] / top : 0.0;
		const bx: float32 = cx + (i as float32) * 22.0;
		box(u, bx, base - bh, 14.0, bh, 0.0, rounds[i] == top ? EMBER_HOT : EMBER);
		box(u, bx, base - bh, 14.0, 1.0, 0.0, rgba(1.0, 0.75, 0.45, 0.6));
		say(u, k, sub(id, 7) + i * 16, (i + 1).toString(), bx, base + 4.0, 14.0, 8.0, INK_MUTED, 0.5);
	}
	box(u, cx - 2.0, base, 134.0, 1.0, 0.0, DIVIDER);
	box(u, x + 18.0, y + h - 36.0, w - 36.0, 1.0, 0.0, DIVIDER);
	say(u, k, sub(id, 8), "YOUR PET DECIDES ON ITS OWN.", x, y + h - 26.0, w, 8.0, INK_MUTED, 0.5);
}
