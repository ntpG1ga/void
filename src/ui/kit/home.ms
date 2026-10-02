// Hibernal Home, built from the UI kit (hibernal docs/HUD-WIREFRAME.md §4). Replaces the baked
// hudHome.ms. Data is a stand-in PetState until the chain client exists.
//
// Tier 1: the status card (tap: the expanded card, collapses after 4 s or a tap on the scene).
// Tier 2: badges (tap: a tooltip). Feed opens the Feed sheet (portions, SignButton flow);
// Talk opens the Talk sheet (chat). The gear opens the kit gallery until Settings exists.

import { rgba } from "../../void2d/types";
import { loadNextPass } from "../../sokol/gpu";
import { Ui, createUi, beginUi, endUi, box, pressable, endOverlay } from "../ui";
import { Kit, createKit, beginKit, endKit, endKitOverlay, frame, badgeFrame, icon, say, INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED } from "./kit";
import { FrameLook } from "./frame";
import { button, ButtonStyle, textLink, signButton, SignState, chip, ChipKind, badge, heartPips, bar, bondingBar, balance } from "./components";
import { Toasts, toasts, pushToast, drawToasts, tooltip, reasonPill, walletBanner, syncChip } from "./components2";
import { sheet, sheetTop, dock, chatBubble, chatInput } from "./components3";
import { Nav, screenFrame } from "./screens";
import * as screens from "./screens";

// ---- stand-in pet state ------------------------------------------------------------------

const MAX_HEARTS: int32 = 10 as int32;
const MAX_TALKS: int32 = 5 as int32;
let hearts: int32 = 7 as int32;
let talks: int32 = 3 as int32;
let harvest: int32 = 1240 as int32;
let burrow: int32 = 5600 as int32;
let bonding: int32 = 40 as int32;

// ---- screen state --------------------------------------------------------------------------

let ui: Ui | null = null;
let kit: Kit | null = null;
let tick: int32 = 0 as int32;
const queue: Toasts = toasts();
let expandedUntil: int32 = 0 as int32;
let tipText: string = "";
let tipY: float32 = 0.0;
let tipUntil: int32 = 0 as int32;
let galleryAsked: boolean = false;
let tab: Nav = Nav.Home;
const DOCK_TABS: Nav[] = [Nav.Home, Nav.Pet, Nav.Block, Nav.Shop, Nav.Digest];

enum Sheet { None, Feed, Talk }
let openSheet: Sheet = Sheet.None;
let sheetT: float32 = 0.0;

// feed: one SignButton runs at a time
let feedRow: int32 = -1 as int32;
let feedState: SignState = SignState.Idle;
let feedSince: int32 = 0 as int32;

// talk
const said: string[] = ["DID YOU EAT TODAY?", "ATE A LITTLE. THE FIRE IS WARM."];
const byOwner: boolean[] = [true, false];
const counted: boolean[] = [true, false];
let draft: string = "";
const DRAFTS: string[] = ["STAY CLOSE TO THE FIRE.", "GOOD NIGHT.", "DON'T PICK FIGHTS TONIGHT."];
const REPLIES: string[] = ["I WILL. THE WIND IS COLD.", "NIGHT. WAKE ME AT DAWN.", "ONLY IF THEY START IT."];
let draftAt: int32 = 0 as int32;

export function takeGalleryRequest(): boolean {
	const asked: boolean = galleryAsked;
	galleryAsked = false;
	return asked;
}

export function initHudHome(): void {
	const u = createUi(rgba(0.0, 0.0, 0.0, 1.0));
	kit = createKit(u);
	ui = u;
	pushToast(queue, "MOVED 620 TO BURROW - NEXT IN 8H", false);
}

// ---- tiers ---------------------------------------------------------------------------------

function statusCard(u: Ui, k: Kit): void {
	const alert: boolean = hearts <= 2;
	const expanded: boolean = tick < expandedUntil;
	if (expanded) {
		frame(k, 10, 16.0, 32.0, 272.0, 220.0, 12, alert ? FrameLook.Alert : FrameLook.Normal);
		say(u, k, 11, "EMBER", 32.0, 48.0, 160.0, 16.0, INK, 0.0);
		say(u, k, 12, "TAP SCENE X", 180.0, 52.0, 92.0, 8.0, INK_MUTED, 1.0);
		say(u, k, 13, "LV 12 / 20", 32.0, 74.0, 120.0, 8.0, INK, 0.0);
		say(u, k, 14, "620 / 1,000 XP", 140.0, 74.0, 132.0, 8.0, INK_MUTED, 1.0);
		bar(u, 32.0, 86.0, 240.0, 6.0, 0.62, EMBER);
		heartPips(u, k, 15, 32.0, 100.0, hearts, MAX_HEARTS, 12.0);
		say(u, k, 16, hearts.toString() + "/" + MAX_HEARTS.toString(), 200.0, 102.0, 72.0, 8.0, INK, 1.0);
		balance(u, k, 17, 32.0, 122.0, 240.0, "bag", "warning", formatAmount(harvest));
		say(u, k, 18, "AT RISK - NEIGHBOURS CAN STEAL IT", 52.0, 138.0, 220.0, 8.0, INK_MUTED, 0.0);
		balance(u, k, 19, 32.0, 154.0, 240.0, "lock", "", formatAmount(burrow));
		say(u, k, 20, "BANKED - SAFE", 52.0, 170.0, 220.0, 8.0, INK_MUTED, 0.0);
		let cx: float32 = 32.0;
		cx += chip(u, k, 21, cx, 190.0, "DAY 34/90", ChipKind.Outline, INK) + 4.0;
		cx += chip(u, k, 22, cx, 190.0, "WINTER 12D", ChipKind.Outline, INK) + 4.0;
		chip(u, k, 23, cx, 190.0, "GROWTH X1.10", ChipKind.Filled, EMBER);
		chip(u, k, 24, 32.0, 210.0, "INSURED", ChipKind.Outline, INK);
		if (pressable(u, 25, 16.0, 32.0, 272.0, 220.0)) { expandedUntil = 0; }
		return;
	}
	frame(k, 10, 16.0, 32.0, 150.0, 104.0, 11, alert ? FrameLook.Alert : FrameLook.Normal);
	icon(k, 30, "heart", 34.0, 50.0, 14.0);
	say(u, k, 30, hearts.toString() + "/" + MAX_HEARTS.toString(), 62.0, 54.0, 90.0, 8.0, alert ? ALERT_RED : INK, 0.0);
	icon(k, 31, "bag", 34.0, 68.0, 14.0);
	icon(k, 31, "warning", 41.0, 74.0, 9.0);
	say(u, k, 31, formatAmount(harvest), 62.0, 72.0, 90.0, 8.0, INK, 0.0);
	icon(k, 32, "lock", 34.0, 86.0, 14.0);
	say(u, k, 32, formatAmount(burrow), 62.0, 90.0, 90.0, 8.0, INK, 0.0);
	box(u, 32.0, 105.0, 118.0, 1.0, 0.0, rgba(0.404, 0.247, 0.188, 1.0));
	say(u, k, 33, "LV12", 34.0, 113.0, 30.0, 8.0, INK, 0.0);
	bar(u, 62.0, 114.0, 56.0, 5.0, 0.62, EMBER);
	say(u, k, 34, "D34", 100.0, 113.0, 48.0, 8.0, INK, 1.0);
	if (pressable(u, 35, 16.0, 32.0, 150.0, 104.0)) { expandedUntil = tick + 120; }
	if (alert) { reasonPill(u, k, 36, 16.0, 142.0, "HEARTS LOW - FEED OR IT STARVES", true); }
}

function badges(u: Ui, k: Kit): void {
	// gear: 48 target round the 36 box
	badgeFrame(k, 40, 308.0, 34.0, 36.0, 41);
	icon(k, 40, "gear", 316.0, 42.0, 20.0);
	if (pressable(u, 40, 300.0, 28.0, 52.0, 48.0)) { tab = Nav.Settings; }
	const glyphs: string[] = ["winter", "growth", "insured"];
	const numbers: string[] = ["12", "X1.1", ""];
	const tips: string[] = ["WINTER IN 12 DAYS - EMISSION X0.75", "GROWTH X1.10 - 18H LEFT", "INSURED - REVIVES ONCE AT 3 HEARTS"];
	for (let i: int32 = 0; i < 3; i += 1) {
		const y: float32 = 84.0 + (i as float32) * 48.0;
		if (badge(u, k, 41 + i, 304.0, y, glyphs[i], numbers[i], 50 + i)) {
			tipText = tips[i];
			tipY = y + 20.0;
			tipUntil = tick + 120;
		}
	}
	syncChip(u, k, 45, 252.0, 232.0, "SYNCING...", true, tick);
	if (tick < tipUntil) { tooltip(u, k, 46, 300.0, tipY, tipText); }
}

function formatAmount(v: int32): string {
	if (v < 1000) { return v.toString(); }
	const rest: int32 = v % 1000;
	const pad: string = rest < 10 ? "00" : (rest < 100 ? "0" : "");
	return (v / 1000).toString() + "," + pad + rest.toString();
}

// ---- sheets --------------------------------------------------------------------------------

const PORTIONS: string[] = ["SMALL", "MEDIUM", "LARGE"];
const PORTION_HEARTS: int32[] = [1, 2, 3];
const PORTION_PRICE: int32[] = [5, 9, 12];

function feedSheet(u: Ui, k: Kit, top: float32): void {
	say(u, k, 100, "FEED", 32.0, top + 28.0, 200.0, 16.0, INK, 0.0);
	heartPips(u, k, 101, 32.0, top + 52.0, hearts, MAX_HEARTS, 14.0);
	say(u, k, 102, hearts.toString() + "/" + MAX_HEARTS.toString(), 230.0, top + 55.0, 98.0, 8.0, INK, 1.0);
	// the signature in flight
	if (feedState == SignState.Waiting && tick - feedSince > 75) {
		feedState = SignState.Done;
		feedSince = tick;
		const add: int32 = PORTION_HEARTS[feedRow];
		hearts = hearts + add > MAX_HEARTS ? MAX_HEARTS : hearts + add;
		bonding = bonding + 6 > 127 ? 127 as int32 : bonding + 6;
		pushToast(queue, "FED " + PORTIONS[feedRow] + " - +" + add.toString() + " HEARTS", false);
	}
	if (feedState == SignState.Done && tick - feedSince > 50) { feedState = SignState.Idle; feedRow = -1; }
	for (let i: int32 = 0; i < 3; i += 1) {
		const y: float32 = top + 84.0 + (i as float32) * 64.0;
		say(u, k, 110 + i, PORTIONS[i], 32.0, y + 10.0, 140.0, 8.0, INK, 0.0);
		say(u, k, 120 + i, "+" + PORTION_HEARTS[i].toString() + " HEARTS", 32.0, y + 26.0, 140.0, 8.0, INK_MUTED, 0.0);
		const fits: boolean = hearts + PORTION_HEARTS[i] <= MAX_HEARTS;
		let state: SignState = fits ? SignState.Idle : SignState.Disabled;
		if (feedRow == i) { state = feedState; }
		else if (feedRow >= 0) { state = SignState.Disabled; }
		if (signButton(u, k, 130 + i, 180.0, y, 148.0, 44.0, "BUY " + PORTION_PRICE[i].toString() + " SKR", state, 60 + i, tick)) {
			feedRow = i;
			feedState = SignState.Waiting;
			feedSince = tick;
		}
	}
	if (feedState == SignState.Waiting) {
		walletBanner(u, k, 140, 16.0, top + 282.0, 328.0,
			PORTIONS[feedRow] + " - +" + PORTION_HEARTS[feedRow].toString() + " HEARTS - " + PORTION_PRICE[feedRow].toString() + " SKR", 64, tick);
	} else if (hearts >= MAX_HEARTS) {
		say(u, k, 141, "HEARTS FULL - NOTHING TO FEED", 32.0, top + 296.0, 296.0, 8.0, INK_MUTED, 0.0);
	} else {
		say(u, k, 141, "FEEDING RAISES BONDING.", 32.0, top + 296.0, 296.0, 8.0, INK_MUTED, 0.0);
	}
}

function talkSheet(u: Ui, k: Kit, top: float32): void {
	say(u, k, 200, "TALK", 32.0, top + 28.0, 120.0, 16.0, INK, 0.0);
	say(u, k, 201, "EMBER - LV 12", 110.0, top + 34.0, 120.0, 8.0, INK_MUTED, 0.0);
	bondingBar(u, k, 202, 32.0, top + 60.0, 296.0, bonding);
	say(u, k, 203, talks > 0 ? "TALKS THAT COUNT TODAY: " + talks.toString() + "/" + MAX_TALKS.toString() : "NO MORE BONDING TODAY",
		32.0, top + 88.0, 296.0, 8.0, talks > 0 ? EMBER_HOT : INK_MUTED, 0.0);
	// newest messages that fit, bottom up
	const listTop: float32 = top + 108.0;
	let y: float32 = listTop;
	const first: int32 = said.length > 6 ? (said.length - 6) as int32 : 0 as int32;
	for (let i: int32 = first; i < said.length; i += 1) {
		y += chatBubble(u, k, 210 + i * 4, 24.0, 336.0, y, said[i], byOwner[i], counted[i], 70);
	}
	const inputY: float32 = 800.0 - 70.0;
	if (pressable(u, 250, 24.0, inputY, 220.0, 44.0)) {
		draft = DRAFTS[draftAt % DRAFTS.length];
	}
	if (chatInput(u, k, 251, 24.0, inputY, 312.0, draft, 71)) {
		const counts: boolean = talks > 0;
		said.push(draft); byOwner.push(true); counted.push(counts);
		said.push(REPLIES[draftAt % REPLIES.length]); byOwner.push(false); counted.push(false);
		if (counts) {
			talks -= 1;
			bonding = bonding + 4 > 127 ? 127 as int32 : bonding + 4;
		}
		draftAt += 1;
		draft = "";
	}
}

// ---- frame ---------------------------------------------------------------------------------

export function frameHudHome(): void {
	if (ui === null || kit === null) { return; }
	const u = ui as Ui;
	const k = kit as Kit;
	beginUi(u);
	beginKit(k);
	tick += 1;
	u.blockBase = openSheet != Sheet.None || (tab != Nav.Home && screens.overlayOpen);

	if (tab != Nav.Home) {
		screens.navigate = Nav.Stay;
		screenFrame(u, k, queue, tab, tick);
		drawToasts(u, k, 60, queue, 16.0, 676.0, 328.0);
		if (tab != Nav.Settings) {
			let active: int32 = 0 as int32;
			for (let i: int32 = 0; i < 5; i += 1) { if (DOCK_TABS[i] == tab) { active = i; } }
			const d: int32 = dock(u, k, 80, active, true, 31);
			if (d >= 0) { tab = DOCK_TABS[d]; }
		}
		const go: Nav = screens.navigate;
		if (go == Nav.Gallery) { galleryAsked = true; tab = Nav.Home; }
		else if (go != Nav.Stay) { tab = go; }
		endKit(k);
		loadNextPass();
		endUi(u);
		return;
	}

	// a tap on the scene collapses the expanded card
	if (tick < expandedUntil && u.released && u.releaseY > 260.0 && u.releaseY < 600.0) { expandedUntil = 0; }

	statusCard(u, k);
	badges(u, k);
	drawToasts(u, k, 60, queue, 16.0, 612.0, 328.0);

	if (button(u, k, 70, 16.0, 668.0, 156.0, 48.0, "FEED", ButtonStyle.Primary, true, 21)) { openSheet = Sheet.Feed; }
	if (button(u, k, 71, 188.0, 668.0, 156.0, 48.0, "TALK " + talks.toString() + "/" + MAX_TALKS.toString(),
		ButtonStyle.Primary, true, 22)) { openSheet = Sheet.Talk; }
	const d: int32 = dock(u, k, 80, 0 as int32, true, 31);
	if (d > 0) { tab = DOCK_TABS[d]; }

	// sheet on the overlay
	const target: float32 = openSheet != Sheet.None ? 1.0 : 0.0;
	sheetT = sheetT + (target - sheetT) * 0.25;
	if (sheetT > 0.01 || openSheet != Sheet.None) {
		const h: float32 = openSheet == Sheet.Talk ? 700.0 : 360.0;
		if (sheet(u, k, 90, h, sheetT, openSheet == Sheet.Talk ? 92 : 91) && feedState != SignState.Waiting) {
			openSheet = Sheet.None;
		}
		const top: float32 = sheetTop(h, sheetT);
		if (textLink(u, k, 95, 284.0, top + 32.0, "CLOSE", feedState != SignState.Waiting)) { openSheet = Sheet.None; }
		if (openSheet == Sheet.Feed) { feedSheet(u, k, top); }
		if (openSheet == Sheet.Talk) { talkSheet(u, k, top); }
		endOverlay(u);
		endKitOverlay(k);
	}

	endKit(k);
	loadNextPass();
	endUi(u);
}
