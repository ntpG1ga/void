// Hibernal UI kit gallery: every kit piece on one screen, to review on the phone.
// Run the grass lab with LAB_HUD=2. Grows with each batch of components.

import { rgba } from "../../void2d/types";
import { loadNextPass } from "../../sokol/gpu";
import { Ui, createUi, beginUi, endUi, pressable, held, endOverlay } from "../ui";
import { Kit, createKit, beginKit, endKit, frame, badgeFrame, icon, say, INK, INK_MUTED, EMBER_HOT, EMBER_PRESSED } from "./kit";
import { FrameLook } from "./frame";
import { button, ButtonStyle, textLink, signButton, SignState, chip, ChipKind, badge, heartPips, bar, bondingBar,
	balance, delta, rarityPlate, rarityChip, Rarity, GROWTH_GREEN, RARE_BLUE, EPIC_PURPLE, LEGENDARY_GOLD, MYTHIC_CYAN, COMMON_ASH } from "./components";
import { EMBER, ALERT_RED, endKitOverlay } from "./kit";
import { toggle, ToggleState, segmented, tabs, radioRow, listRow, RowKind, sectionHeader, labelDivider, Toasts, toasts,
	pushToast, drawToasts, tooltip, reasonPill, walletBanner, skeleton, syncChip, emptyState } from "./components2";
import { sheet, sheetTop, modal, ModalAnswer, dock, pager, chatBubble, chatInput, lineageEntry, LineageState, talentCard,
	gradeLadder, treeNode, treeLink, NodeShape, NodeState, oddsBlock, OddsState } from "./components3";

const ICONS: string[] = ["heart", "bag", "lock", "warning", "winter", "growth", "insured", "gear",
	"home", "pet", "block", "shop", "digest"];

let ui: Ui | null = null;
let kit: Kit | null = null;
let seedShift: int32 = 0 as int32;
let page: int32 = 0 as int32;
let tick: int32 = 0 as int32;
let hearts: int32 = 7 as int32;
let signState: SignState = SignState.Idle;
let signSince: int32 = 0 as int32;
let bonding: int32 = 35 as int32;
const PAGES: int32 = 6 as int32;
let oddsMode: int32 = 0 as int32;
let dockActive: int32 = 0 as int32;
let pagerAt: int32 = 0 as int32;
let sheetOpen: boolean = false;
let sheetT: float32 = 0.0;
let modalOpen: boolean = false;
let chatText: string = "";
let cardFlip: float32 = 0.0;
let cardTarget: float32 = 0.0;
let picked: int32 = -1 as int32;
let toggleOn: boolean = true;
let segActive: int32 = 0 as int32;
let tabActive: int32 = 0 as int32;
let radioPick: int32 = 1 as int32;
let rowPick: int32 = 1 as int32;
const toastQueue: Toasts = toasts();
let toastCount: int32 = 0 as int32;

// The title is the way back to Home; the caller polls this.
let homeAsked: boolean = false;
export function takeHomeRequest(): boolean {
	const asked: boolean = homeAsked;
	homeAsked = false;
	return asked;
}

// setup2d is the caller's (once, before any HUD screen).
export function initGallery(): void {
	const u = createUi(rgba(0.0, 0.0, 0.0, 1.0));
	kit = createKit(u);
	ui = u;
}

export function frameGallery(): void {
	if (ui === null || kit === null) { return; }
	const u = ui as Ui;
	const k = kit as Kit;
	beginUi(u);
	beginKit(k);
	tick += 1;
	// an open sheet or modal takes every touch
	u.blockBase = page == 3 && (sheetOpen || modalOpen);

	const titles: string[] = ["UI KIT - FRAMES", "UI KIT - BATCH 1", "UI KIT - BATCH 2", "UI KIT - BATCH 3A", "UI KIT - BATCH 3B", "UI KIT - ODDS"];
	say(u, k, 1, titles[page], 16.0, 30.0, 260.0, 16.0, INK, 0.0);
	say(u, k, 2, "TAP THE TITLE FOR HOME", 16.0, 52.0, 260.0, 8.0, INK_MUTED, 0.0);
	if (pressable(u, 3, 0.0, 20.0, 250.0, 44.0)) { homeAsked = true; }
	if (textLink(u, k, 4, 284.0, 34.0, "NEXT " + (page + 1).toString() + "/" + PAGES.toString(), true)) {
		page = (page + 1) % PAGES;
	}
	if (page == 1) { batchOne(u, k); }
	else if (page == 2) { batchTwo(u, k); }
	else if (page == 3) { batchThreeA(u, k); }
	else if (page == 4) { batchThreeB(u, k); }
	else if (page == 5) { oddsPage(u, k); }
	else { framesPage(u, k); }

	endKit(k);
	loadNextPass();
	endUi(u);
}

function framesPage(u: Ui, k: Kit): void {
	// three panels, same size, different seeds
	for (let i: int32 = 0; i < 2; i += 1) {
		const x: float32 = 16.0 + (i as float32) * 172.0;
		frame(k, 10 + i, x, 76.0, 156.0, 96.0, 1 + i + seedShift, FrameLook.Normal);
		say(u, k, 10 + i, "SEED " + (1 + i + seedShift).toString(), x + 14.0, 88.0, 128.0, 8.0, INK, 0.0);
		if (pressable(u, 10 + i, x, 76.0, 156.0, 96.0)) { seedShift = seedShift + 2; }
	}
	// alert and disabled looks
	frame(k, 12, 16.0, 190.0, 156.0, 70.0, 3 + seedShift, FrameLook.Alert);
	say(u, k, 12, "ALERT", 30.0, 202.0, 128.0, 8.0, INK, 0.0);
	frame(k, 13, 188.0, 190.0, 156.0, 70.0, 4 + seedShift, FrameLook.Disabled);
	say(u, k, 13, "DISABLED", 202.0, 202.0, 128.0, 8.0, INK_MUTED, 0.0);

	// wide (dock-sized) and tall
	frame(k, 14, 16.0, 278.0, 328.0, 56.0, 5 + seedShift, FrameLook.Normal);
	say(u, k, 14, "WIDE 328 X 56", 30.0, 300.0, 300.0, 8.0, INK, 0.0);
	frame(k, 15, 16.0, 352.0, 100.0, 170.0, 6 + seedShift, FrameLook.Normal);
	say(u, k, 15, "TALL", 30.0, 364.0, 80.0, 8.0, INK, 0.0);

	// buttons: frame + label + touch
	for (let i: int32 = 0; i < 2; i += 1) {
		const x: float32 = 132.0 + (i as float32) * 108.0;
		const id: int32 = 20 + i;
		const down: boolean = held(u, id, x, 352.0, 100.0, 48.0);
		pressable(u, id, x, 352.0, 100.0, 48.0);
		frame(k, id, x, 352.0, 100.0, 48.0, 20 + i + seedShift, i == 0 ? FrameLook.Normal : FrameLook.Disabled);
		say(u, k, id, i == 0 ? "PRESS" : "OFF", x, 370.0 + (down ? 1.0 : 0.0), 100.0, 8.0,
			i == 1 ? INK_MUTED : (down ? EMBER_PRESSED : EMBER_HOT), 0.5);
	}

	// badges with icons
	const badgeIcons: string[] = ["gear", "winter", "growth", "insured"];
	for (let i: int32 = 0; i < 4; i += 1) {
		const x: float32 = 132.0 + (i as float32) * 54.0;
		badgeFrame(k, 30 + i, x, 420.0, 40.0, 30 + i);
		icon(k, 30 + i, badgeIcons[i], x + 10.0, 430.0, 20.0);
	}

	// rarity plates (the detailed form) and chips (the simple one)
	say(u, k, 50, "RARITY - PLATE AND CHIP", 16.0, 628.0, 300.0, 8.0, INK_MUTED, 0.0);
	rarityPlate(u, k, 51, 16.0, 644.0, 104.0, 40.0, Rarity.Common);
	rarityPlate(u, k, 52, 128.0, 644.0, 104.0, 40.0, Rarity.Rare);
	rarityPlate(u, k, 53, 240.0, 644.0, 104.0, 40.0, Rarity.Epic);
	rarityPlate(u, k, 54, 16.0, 694.0, 160.0, 40.0, Rarity.Legendary);
	rarityPlate(u, k, 55, 184.0, 694.0, 160.0, 40.0, Rarity.Mythic);
	let rx: float32 = 16.0;
	rx += rarityChip(u, k, 56, rx, 748.0, Rarity.Common) + 6.0;
	rx += rarityChip(u, k, 57, rx, 748.0, Rarity.Rare) + 6.0;
	rx += rarityChip(u, k, 58, rx, 748.0, Rarity.Epic) + 6.0;
	rx += rarityChip(u, k, 59, rx, 748.0, Rarity.Legendary) + 6.0;
	rarityChip(u, k, 60, rx, 748.0, Rarity.Mythic);

	// every icon at 24
	say(u, k, 40, "ICONS", 16.0, 540.0, 200.0, 8.0, INK_MUTED, 0.0);
	for (let i: int32 = 0; i < ICONS.length; i += 1) {
		const col: int32 = i % 7;
		const row: int32 = i / 7;
		icon(k, 41 + i, ICONS[i], 16.0 + (col as float32) * 48.0, 556.0 + (row as float32) * 40.0, 24.0);
	}

}

function batchOne(u: Ui, k: Kit): void {
	// buttons
	if (button(u, k, 100, 16.0, 76.0, 156.0, 48.0, "FEED", ButtonStyle.Primary, hearts < 10, 101)) { hearts += 1; }
	button(u, k, 102, 188.0, 76.0, 156.0, 48.0, "DISCONNECT", ButtonStyle.Danger, true, 103);
	if (textLink(u, k, 104, 28.0, 142.0, "RESET HEARTS", true)) { hearts = 3 as int32; }
	button(u, k, 105, 188.0, 132.0, 156.0, 40.0, "FEED", ButtonStyle.Primary, false, 106);

	// sign buttons: the first one runs idle -> waiting -> done -> idle on a tap
	if (signState == SignState.Waiting && tick - signSince > 75) { signState = SignState.Done; signSince = tick; }
	if (signState == SignState.Done && tick - signSince > 60) { signState = SignState.Idle; }
	if (signButton(u, k, 110, 16.0, 188.0, 156.0, 44.0, "BUY 9 SKR", signState, 111, tick)) {
		signState = SignState.Waiting;
		signSince = tick;
	}
	signButton(u, k, 112, 188.0, 188.0, 156.0, 44.0, "BUY", SignState.Waiting, 113, tick);
	signButton(u, k, 114, 16.0, 244.0, 156.0, 44.0, "BUY", SignState.Done, 115, tick);
	signButton(u, k, 116, 188.0, 244.0, 156.0, 44.0, "BUY", SignState.Failed, 117, tick);
	signButton(u, k, 118, 16.0, 300.0, 156.0, 44.0, "BUY 9 SKR", SignState.Disabled, 119, tick);
	say(u, k, 120, "TAP THE FIRST ONE", 188.0, 318.0, 156.0, 8.0, INK_MUTED, 0.0);

	// chips
	let cx: float32 = 16.0;
	cx += chip(u, k, 130, cx, 362.0, "SHIELD 2D", ChipKind.Outline, INK) + 6.0;
	cx += chip(u, k, 131, cx, 362.0, "GROWTH X1.1", ChipKind.Filled, EMBER) + 6.0;
	cx += chip(u, k, 132, cx, 362.0, "FADING", ChipKind.Dashed, INK_MUTED) + 6.0;
	cx = 16.0;
	cx += chip(u, k, 133, cx, 384.0, "COMMON", ChipKind.Outline, COMMON_ASH) + 6.0;
	cx += chip(u, k, 134, cx, 384.0, "RARE", ChipKind.Outline, RARE_BLUE) + 6.0;
	cx += chip(u, k, 135, cx, 384.0, "EPIC", ChipKind.Outline, EPIC_PURPLE) + 6.0;
	cx += chip(u, k, 136, cx, 384.0, "LEGEND", ChipKind.Outline, LEGENDARY_GOLD) + 6.0;
	cx += chip(u, k, 137, cx, 384.0, "MYTHIC", ChipKind.Outline, MYTHIC_CYAN) + 6.0;
	chip(u, k, 138, 16.0, 406.0, "RAGE 2", ChipKind.Filled, ALERT_RED);

	// badges
	badge(u, k, 140, 16.0, 436.0, "winter", "12", 1);
	badge(u, k, 141, 70.0, 436.0, "growth", "X1.1", 2);
	badge(u, k, 142, 124.0, 436.0, "insured", "", 3);
	badge(u, k, 143, 178.0, 436.0, "shield", "2", 4);
	badge(u, k, 144, 232.0, 436.0, "fading", "", 5);

	// hearts: one row, two rows, collapsed
	heartPips(u, k, 150, 16.0, 496.0, hearts, 10, 14.0);
	heartPips(u, k, 151, 190.0, 494.0, 13, 20, 7.0);
	heartPips(u, k, 152, 16.0, 520.0, 17, 25, 14.0);

	// bars
	say(u, k, 160, "LV12", 16.0, 552.0, 40.0, 8.0, INK, 0.0);
	bar(u, 56.0, 552.0, 120.0, 8.0, 0.62, EMBER);
	say(u, k, 161, "D34", 180.0, 552.0, 40.0, 8.0, INK, 0.0);
	bar(u, 230.0, 552.0, 114.0, 6.0, 0.4, GROWTH_GREEN);
	if (pressable(u, 162, 16.0, 572.0, 328.0, 36.0)) { bonding = bonding > 100 ? -110 as int32 : bonding + 40; }
	bondingBar(u, k, 163, 16.0, 580.0, 328.0, bonding);
	say(u, k, 164, "BONDING " + bonding.toString() + " - TAP TO MOVE", 16.0, 610.0, 328.0, 8.0, INK_MUTED, 0.0);

	// balances and deltas, in a panel like the status card
	frame(k, 170, 16.0, 636.0, 156.0, 80.0, 7, FrameLook.Normal);
	balance(u, k, 171, 30.0, 652.0, 128.0, "bag", "warning", "1,240");
	balance(u, k, 172, 30.0, 672.0, 128.0, "lock", "", "5,600");
	balance(u, k, 173, 30.0, 692.0, 128.0, "heart", "", hearts.toString() + "/10");
	delta(u, k, 174, 188.0, 652.0, 156.0, 280, 0.0);
	delta(u, k, 175, 188.0, 672.0, 156.0, -310, 0.0);
	delta(u, k, 176, 188.0, 692.0, 156.0, 0, 0.0);
}

function batchTwo(u: Ui, k: Kit): void {
	// toggles: off, on (tap), pending, disabled
	if (toggle(u, k, 200, 16.0, 70.0, toggleOn ? ToggleState.On : ToggleState.Off, tick)) { toggleOn = !toggleOn; }
	toggle(u, k, 201, 70.0, 70.0, ToggleState.Off, tick);
	toggle(u, k, 202, 124.0, 70.0, ToggleState.Pending, tick);
	toggle(u, k, 203, 178.0, 70.0, ToggleState.Disabled, tick);
	if (textLink(u, k, 204, 260.0, 88.0, "TOAST", true)) {
		toastCount += 1;
		pushToast(toastQueue, toastCount % 3 == 0 ? "FAILED: NOT ENOUGH SKR" : "MOVED 620 TO BURROW - " + toastCount.toString(), toastCount % 3 == 0);
	}

	segActive = segmented(u, k, 210, 16.0, 124.0, 328.0, ["THREAT", "LOOT", "WEAK"], segActive, 21);
	tabActive = tabs(u, k, 211, 16.0, 172.0, 200.0, ["PET", "TREE"], [0, 2], tabActive);

	// rows live inside a panel or a sheet in the game; here a panel holds them
	frame(k, 219, 16.0, 210.0, 328.0, 292.0, 22, FrameLook.Normal);
	if (radioRow(u, k, 220, 30.0, 220.0, 300.0, "CAUTIOUS", "AVOIDS FIGHTS IT MIGHT LOSE", radioPick == 0, true)) { radioPick = 0; }
	if (radioRow(u, k, 221, 30.0, 268.0, 300.0, "GREEDY", "GOES FOR THE FATTEST HARVEST", radioPick == 1, false)) { radioPick = 1; }
	if (listRow(u, k, 230, 30.0, 316.0, 300.0, "ate", "ATE A MEDIUM PORTION", "-315", ALERT_RED,
		rowPick == 0 ? RowKind.Selected : RowKind.Plain, true, false)) { rowPick = 0; }
	if (listRow(u, k, 231, 30.0, 364.0, 300.0, "fightLost", "ROBBED BY SLOT 4", "-310", ALERT_RED,
		rowPick == 1 ? RowKind.Selected : RowKind.Plain, true, false)) { rowPick = 1; }
	listRow(u, k, 232, 30.0, 412.0, 300.0, "", "DISCONNECT", "", INK, RowKind.Destructive, false, false);
	listRow(u, k, 233, 30.0, 446.0, 300.0, "", "NETWORK", "DEVNET", INK_MUTED, RowKind.Locked, false, false);

	sectionHeader(u, k, 240, 16.0, 516.0, 328.0, "THIS MORNING", "OCT 2");
	labelDivider(u, k, 241, 16.0, 540.0, 328.0, "NEW SINCE 23:10", EMBER);

	reasonPill(u, k, 250, 16.0, 560.0, "BONDING LOW", false);
	reasonPill(u, k, 251, 140.0, 560.0, "ROBBED BY SLOT 4: -310", true);
	tooltip(u, k, 252, 344.0, 598.0, "INSURED - REVIVES ONCE AT 3");

	walletBanner(u, k, 260, 16.0, 618.0, 328.0, "MEDIUM - +2 HEARTS - 9 SKR", 26, tick);

	skeleton(u, 16.0, 680.0, 150.0, 8.0, tick);
	skeleton(u, 16.0, 694.0, 100.0, 8.0, tick);
	syncChip(u, k, 270, 180.0, 676.0, "SYNCING...", true, tick);
	syncChip(u, k, 271, 180.0, 698.0, "OFFLINE - 3 MIN AGO", false, tick);

	emptyState(u, k, 280, 16.0, 724.0, 328.0, 32.0, "", "NOTHING YET. FIRST DAY UNDER WAY.");
	drawToasts(u, k, 290, toastQueue, 16.0, 760.0, 328.0);
}

const PAGER_LABELS: string[] = ["SLOT 4 - THREAT", "SLOT 7 - THREAT", "SLOT 10 - THREAT", "SLOT 2 - THREAT"];

function batchThreeA(u: Ui, k: Kit): void {
	pagerAt = pager(u, k, 300, 16.0, 76.0, 328.0, PAGER_LABELS[pagerAt] + " - " + (pagerAt + 1).toString() + " OF 4", pagerAt, 4);

	// chat
	frame(k, 309, 16.0, 120.0, 328.0, 300.0, 31, FrameLook.Normal);
	let cy: float32 = 136.0;
	cy += chatBubble(u, k, 310, 30.0, 330.0, cy, "DID YOU EAT TODAY?", true, true, 0);
	cy += chatBubble(u, k, 311, 30.0, 330.0, cy, "ATE A LITTLE. THE FIRE IS WARM AND THE NIGHT IS LONG.", false, false, 33);
	cy += chatBubble(u, k, 312, 30.0, 330.0, cy, "STAY CLOSE TO IT.", true, false, 0);
	if (chatInput(u, k, 313, 30.0, 360.0, 300.0, chatText, 34)) { chatText = ""; }
	if (textLink(u, k, 314, 30.0, 432.0, chatText == "" ? "TYPE (DEMO)" : "CLEAR", true)) {
		chatText = chatText == "" ? "GOOD NIGHT" : "";
	}

	if (button(u, k, 320, 16.0, 470.0, 156.0, 48.0, "OPEN SHEET", ButtonStyle.Primary, true, 35)) { sheetOpen = true; }
	if (button(u, k, 321, 188.0, 470.0, 156.0, 48.0, "OPEN MODAL", ButtonStyle.Primary, true, 36)) { modalOpen = true; }

	const d: int32 = dock(u, k, 330, dockActive, true, 37);
	if (d >= 0) { dockActive = d; }

	// overlays last, on top
	const target: float32 = sheetOpen ? 1.0 : 0.0;
	sheetT = sheetT + (target - sheetT) * 0.25;
	if (sheetT > 0.01) {
		if (sheet(u, k, 340, 360.0, sheetT, 38)) { sheetOpen = false; }
		const top: float32 = sheetTop(360.0, sheetT);
		say(u, k, 341, "FEED", 32.0, top + 28.0, 200.0, 16.0, INK, 0.0);
		say(u, k, 342, "SWIPE DOWN OR TAP THE SCENE TO CLOSE", 32.0, top + 52.0, 296.0, 8.0, INK_MUTED, 0.0);
		if (button(u, k, 343, 32.0, top + 80.0, 296.0, 44.0, "CLOSE", ButtonStyle.Primary, true, 39)) { sheetOpen = false; }
		endOverlay(u);
		endKitOverlay(k);
	}
	if (modalOpen) {
		const a: ModalAnswer = modal(u, k, 350, "DISCONNECT WALLET?", "YOUR PET KEEPS PLAYING ON ITS OWN.", "DISCONNECT", true, 40);
		if (a != ModalAnswer.None) { modalOpen = false; }
		endOverlay(u);
		endKitOverlay(k);
	}
}

// skill-tree demo: a gate, a fork, a notable and a keystone
const NODE_X: float32[] = [180.0, 120.0, 240.0, 80.0, 150.0, 210.0, 280.0, 180.0];
const NODE_Y: float32[] = [700.0, 650.0, 650.0, 600.0, 600.0, 600.0, 600.0, 556.0];
const LINKS: int32[] = [0, 1, 0, 2, 1, 3, 1, 4, 2, 5, 2, 6, 4, 7, 5, 7];

function batchThreeB(u: Ui, k: Kit): void {
	frame(k, 400, 16.0, 76.0, 328.0, 136.0, 41, FrameLook.Normal);
	say(u, k, 401, "LINEAGE", 30.0, 88.0, 200.0, 8.0, EMBER_HOT, 0.0);
	lineageEntry(u, k, 402, 30.0, 108.0, 300.0, "GEN 1 - FIGHTER - LIVED 90 DAYS", LineageState.Lived, false);
	lineageEntry(u, k, 403, 30.0, 140.0, 300.0, "GEN 2 - WORKER - DIED DAY 61", LineageState.Died, false);
	lineageEntry(u, k, 404, 30.0, 172.0, 300.0, "GEN 3 - FIGHTER - NOW - DAY 34", LineageState.Now, true);

	// talent: tap the card to flip it
	cardFlip = cardFlip + (cardTarget - cardFlip) * 0.12;
	if (pressable(u, 410, 30.0, 232.0, 120.0, 160.0)) { cardTarget = cardTarget > 0.5 ? 0.0 : 1.0; }
	talentCard(u, k, 411, 30.0, 232.0, cardFlip, "FIGHT", Rarity.Epic, "X1.35", 42);
	say(u, k, 412, "TAP THE CARD", 166.0, 240.0, 170.0, 8.0, INK_MUTED, 0.0);
	say(u, k, 413, "TALENT REVEALED", 166.0, 262.0, 170.0, 8.0, INK, 0.0);
	gradeLadder(u, k, 414, 16.0, 410.0, Rarity.Epic);

	// tree
	say(u, k, 420, "TREE - TAP A NODE", 16.0, 450.0, 200.0, 8.0, INK_MUTED, 0.0);
	frame(k, 421, 16.0, 470.0, 328.0, 260.0, 43, FrameLook.Normal);
	const states: NodeState[] = [NodeState.Allocated, NodeState.Allocated, NodeState.Reachable, NodeState.Allocated,
		NodeState.Reachable, NodeState.Locked, NodeState.Locked, NodeState.Reachable];
	const shapes: NodeShape[] = [NodeShape.Notable, NodeShape.Small, NodeShape.Small, NodeShape.Notable,
		NodeShape.Small, NodeShape.Small, NodeShape.Small, NodeShape.Keystone];
	for (let i: int32 = 0; i < LINKS.length; i += 2) {
		const a: int32 = LINKS[i];
		const b: int32 = LINKS[i + 1];
		treeLink(u, NODE_X[a], NODE_Y[a], NODE_X[b], NODE_Y[b],
			states[a] == NodeState.Allocated && states[b] == NodeState.Allocated);
	}
	for (let i: int32 = 0; i < NODE_X.length; i += 1) {
		if (treeNode(u, k, 430 + i, NODE_X[i], NODE_Y[i], shapes[i], states[i])) { picked = i; }
	}
	icon(k, 445, "recenter", 300.0, 690.0, 26.0);
	const names: string[] = ["GATE", "IRON HIDE", "QUICK HANDS", "BRAWLER", "SCAVENGER", "WARDEN", "LOOKOUT", "BLOOD OATH"];
	if (picked >= 0) {
		say(u, k, 440, names[picked] + (shapes[picked] == NodeShape.Keystone ? " - KEYSTONE" : ""), 30.0, 486.0, 300.0, 8.0, EMBER_HOT, 0.0);
	}
}

function oddsPage(u: Ui, k: Kit): void {
	const states: OddsState[] = [OddsState.Ready, OddsState.Computing, OddsState.NotAttackable];
	oddsBlock(u, k, 500, 16.0, 80.0, states[oddsMode], 62, 310, 480, [0.08, 0.12, 0.28, 0.40, 0.33, 0.18],
		"NEWBORN SHIELD - 2 DAYS LEFT", 50, tick);
	if (textLink(u, k, 501, 16.0, 270.0, "NEXT STATE", true)) { oddsMode = (oddsMode + 1) % 3; }
	oddsBlock(u, k, 502, 16.0, 310.0, OddsState.Ready, 38, 120, 260, [0.30, 0.25, 0.20, 0.12, 0.08, 0.05], "", 51, tick);
}
