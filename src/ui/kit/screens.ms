// Hibernal screens behind the dock and the gear, built from the UI kit: Digest, Block, My Pet
// (Pet and Tree tabs), Shop, Settings. hibernal docs/HUD-WIREFRAME.md §5-§9. Each screen is one
// page (sections switch instead of scrolling). Data is a stand-in until the chain client exists.
//
// home.ms owns the Ui, the Kit, the toasts and the dock; it calls screenFrame for every tab but
// Home. A screen asks to go somewhere through `navigate` (a Nav value, read by home.ms).

import { Color, rgba } from "../../void2d/types";
import { Ui, box, pressable, endOverlay } from "../ui";
import { Kit, endKitOverlay, fill, frame, badgeFrame, icon, say, INK, INK_MUTED, EMBER, EMBER_HOT, ALERT_RED,
	DISABLED_INK } from "./kit";
import { FrameLook } from "./frame";
import { button, ButtonStyle, textLink, signButton, SignState, chip, ChipKind, heartPips, bar, bondingBar, balance, delta,
	Rarity, rarityColor, rarityName, rarityBorder, GROWTH_GREEN } from "./components";
import { Toasts, pushToast, toggle, ToggleState, segmented, tabs, radioRow, listRow, RowKind, sectionHeader, labelDivider,
	lightFrame, emptyState } from "./components2";
import { sheet, sheetTop, modal, ModalAnswer, pager, lineageEntry, LineageState, treeNodeScaled, treeLinkIn, NodeShape, NodeState,
	oddsBlock, OddsState } from "./components3";

export enum Nav { Stay, Home, Pet, Block, Shop, Digest, Settings, Gallery }
export let navigate: Nav = Nav.Stay;
// true while a screen shows a sheet or modal: home.ms blocks the base layer's touches
export let overlayOpen: boolean = false;

const BACKDROP: Color = rgba(0.035, 0.031, 0.031, 0.93);
const DIVIDER: Color = rgba(0.243, 0.149, 0.125, 1.0);

function backdrop(k: Kit): void {
	fill(k, 1, 0.0, 0.0, 360.0, 800.0, BACKDROP);
}

function title(u: Ui, k: Kit, id: int32, line: string, right: string): void {
	say(u, k, id, line, 16.0, 30.0, 220.0, 16.0, INK, 0.0);
	if (right != "") { say(u, k, id + 1, right, 140.0, 34.0, 204.0, 8.0, INK_MUTED, 1.0); }
	box(u, 16.0, 52.0, 328.0, 1.0, 0.0, DIVIDER);
}

// ---- stand-in data -------------------------------------------------------------------------

// neighbours: 9 slots of the block (ours is #5)
const N_SLOT: int32[] = [4, 7, 10, 2, 9, 1, 6, 3, 8];
const N_LV: int32[] = [15, 12, 14, 9, 11, 13, 10, 8, 12];
const N_HEARTS: int32[] = [3, 8, 2, 0, 6, 7, 5, 9, 4];
const N_HARVEST: int32[] = [2100, 1300, 1650, 0, 880, 940, 1120, 300, 1410];
const N_BURROW: int32[] = [8400, 3100, 5200, 0, 2600, 4400, 3900, 900, 5100];
const N_WIN: int32[] = [62, 48, 76, -1, 55, 41, 58, -1, 51];
const N_DAY: int32[] = [52, 30, 61, 0, 18, 44, 37, 2, 25];
// 0 player, 1 wild, 2 newborn shield, 3 dead (waiting for heir)
const N_KIND: int32[] = [0, 0, 0, 3, 1, 0, 0, 2, 0];
const N_RAGE: int32[] = [2, 1, 0, 0, 0, 0, 0, 0, 0];
const N_NAME: string[] = ["ASHEN", "MOSS", "CINDER", "-", "WILD 9", "FLINT", "SORREL", "PIP", "BRAMBLE"];

function slotIndex(slot: int32): int32 {
	for (let i: int32 = 0; i < 9; i += 1) { if (N_SLOT[i] == slot) { return i; } }
	return 0 as int32;
}

// ---- Digest --------------------------------------------------------------------------------

let digestDay: int32 = 0 as int32;
let selectedNeighbour: int32 = 0 as int32;

const DAY_SUMMARY: int32[] = [1840, -630, -310, 280, 0, 1520, -420, 0, 0, 0, 1700, -500, -620, 0, 0];
const DAY_HEARTS: string[] = ["9 > 7", "7 > 8", "8 > 6"];
const EV_DAY: int32[] = [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2];
const EV_ICON: string[] = ["worked", "fightLost", "ate", "levelUp", "fightWon", "gearBought", "gift",
	"worked", "ate", "fightWon", "skull", "gearSold", "worked", "fightLost", "fightLost", "ate"];
const EV_TEXT: string[] = ["WORKED", "ROBBED BY SLOT 4", "ATE A MEDIUM PORTION", "LEVELLED UP - LV 11 > 12",
	"ATTACKED SLOT 7 - WON", "MINTED RARE BOOTS", "GAVE YOU A GIFT",
	"WORKED", "ATE A SMALL PORTION", "ATTACKED SLOT 10 - WON", "SLOT 2 DIED - INHERITANCE", "SOLD COMMON GLOVES",
	"WORKED", "ROBBED BY SLOT 4", "BITTEN BY SLOT 4 - -2 HEARTS", "ATE A LARGE PORTION"];
const EV_AMOUNT: int32[] = [420, -310, -315, 0, 280, -300, 60, 380, -120, 150, 150, 90, 400, -320, 0, -500];
const EV_SLOT: int32[] = [0, 4, 0, 0, 7, 0, 0, 0, 0, 10, 2, 0, 0, 4, 4, 0];
const EV_NEW: int32 = 3 as int32;   // the first three of today are unread

function digest(u: Ui, k: Kit): void {
	title(u, k, 1000, "DIGEST", "WHILE YOU WERE AWAY");
	digestDay = segmented(u, k, 1002, 16.0, 62.0, 328.0, ["THIS MORNING", "YESTERDAY", "SEP 30"], digestDay, 41);
	// summary card: alert style on a bad night
	const bad: boolean = digestDay == 2;
	frame(k, 1010, 16.0, 110.0, 328.0, 96.0, 42 + digestDay, bad ? FrameLook.Alert : FrameLook.Normal);
	const labels: string[] = ["EARNED", "FOOD", "ROBBED", "WON", "HEARTS"];
	for (let i: int32 = 0; i < 5; i += 1) {
		const cx: float32 = 30.0 + ((i % 3) as float32) * 104.0;
		const cy: float32 = 124.0 + ((i / 3) as float32) * 36.0;
		say(u, k, 1011 + i, labels[i], cx, cy, 96.0, 8.0, INK_MUTED, 0.0);
		if (i < 4) {
			delta(u, k, 1020 + i, cx, cy + 12.0, 96.0, DAY_SUMMARY[digestDay * 5 + i], 0.0);
		} else {
			say(u, k, 1024, DAY_HEARTS[digestDay], cx, cy + 12.0, 96.0, 8.0, bad ? ALERT_RED : INK, 0.0);
		}
	}
	let pillY: float32 = 214.0;
	if (bad) {
		pillY = 240.0;
		// reason pill (light frame) under the card
		lightFrame(u, 16.0, 212.0, 200.0, 20.0, ALERT_RED);
		say(u, k, 1025, "HEARTS 6 - ROBBED TWICE", 24.0, 218.0, 190.0, 8.0, ALERT_RED, 0.0);
	}
	// events of the day
	let y: float32 = pillY;
	let n: int32 = 0 as int32;
	for (let i: int32 = 0; i < EV_DAY.length; i += 1) {
		if (EV_DAY[i] != digestDay) { continue; }
		if (digestDay == 0 && n == 0) {
			labelDivider(u, k, 1030, 16.0, y, 328.0, "NEW SINCE 23:10", EMBER);
			y += 14.0;
		}
		if (digestDay == 0 && n == EV_NEW) {
			labelDivider(u, k, 1031, 16.0, y, 328.0, "SEEN", INK_MUTED);
			y += 14.0;
		}
		const slot: int32 = EV_SLOT[i];
		const amount: int32 = EV_AMOUNT[i];
		const value: string = amount > 0 ? "+" + amount.toString() : (amount < 0 ? amount.toString() : "");
		const tapped: boolean = listRow(u, k, 1040 + i, 16.0, y, 328.0, EV_ICON[i], EV_TEXT[i], value,
			amount >= 0 ? GROWTH_GREEN : ALERT_RED, RowKind.Plain, slot > 0, false);
		if (digestDay == 0 && n < EV_NEW) { box(u, 18.0, y + 22.0, 4.0, 4.0, 0.0, EMBER_HOT); }
		if (tapped && slot > 0) {
			selectedNeighbour = slotIndex(slot);
			navigate = Nav.Block;
		}
		y += 48.0;
		n += 1;
	}
	say(u, k, 1099, "TAP A SLOT TO SEE IT IN YOUR BLOCK", 16.0, 700.0, 328.0, 8.0, INK_MUTED, 0.5);
}

// ---- Block ---------------------------------------------------------------------------------

let blockSort: int32 = 0 as int32;

function block(u: Ui, k: Kit, tick: int32): void {
	title(u, k, 2000, "YOUR BLOCK", "9 NEIGHBOURS - YOU: #5");
	blockSort = segmented(u, k, 2002, 16.0, 62.0, 328.0, ["THREAT", "LOOT", "WEAK"], blockSort, 51);
	// 3 x 3 grid of cells
	for (let i: int32 = 0; i < 9; i += 1) {
		const cx: float32 = 16.0 + ((i % 3) as float32) * 112.0;
		const cy: float32 = 108.0 + ((i / 3) as float32) * 50.0;
		const sel: boolean = i == selectedNeighbour;
		const dead: boolean = N_KIND[i] == 3;
		if (sel) { box(u, cx, cy, 104.0, 44.0, 0.0, rgba(0.733, 0.682, 0.675, 1.0)); }
		else { lightFrame(u, cx, cy, 104.0, 44.0, dead ? DISABLED_INK : rgba(0.404, 0.247, 0.188, 1.0)); }
		const ink: Color = sel ? rgba(0.09, 0.07, 0.06, 1.0) : INK;
		say(u, k, 2010 + i, "#" + N_SLOT[i].toString(), cx + 8.0, cy + 8.0, 40.0, 8.0, ink, 0.0);
		if (dead) {
			say(u, k, 2020 + i, "HEIR IN 5D", cx + 8.0, cy + 26.0, 90.0, 8.0, sel ? ink : INK_MUTED, 0.0);
		} else {
			const win: int32 = N_WIN[i];
			say(u, k, 2020 + i, win < 0 ? "-" : win.toString() + "%", cx + 52.0, cy + 8.0, 44.0, 8.0,
				sel ? ink : (win >= 50 ? GROWTH_GREEN : (win < 0 ? INK_MUTED : ALERT_RED)), 1.0);
			say(u, k, 2030 + i, "LV" + N_LV[i].toString() + " " + N_HEARTS[i].toString() + "/10" +
				(N_KIND[i] == 1 ? " W" : "") + (N_RAGE[i] > 0 ? " !" : ""), cx + 8.0, cy + 26.0, 90.0, 8.0, sel ? ink : INK_MUTED, 0.0);
		}
		if (pressable(u, 2040 + i, cx, cy, 104.0, 44.0)) { selectedNeighbour = i; }
	}
	// pager + detail
	const s: int32 = selectedNeighbour;
	const sorts: string[] = ["THREAT", "LOOT", "WEAK"];
	selectedNeighbour = pager(u, k, 2050, 16.0, 266.0, 328.0,
		"SLOT " + N_SLOT[s].toString() + " - " + (s + 1).toString() + " OF 9 (" + sorts[blockSort] + ")", s, 9);
	if (N_KIND[s] == 3) {
		emptyState(u, k, 2060, 16.0, 310.0, 328.0, 120.0, "skull", "WAITING FOR HEIR - 5 DAYS LEFT");
		return;
	}
	say(u, k, 2061, N_NAME[s], 16.0, 310.0, 160.0, 16.0, INK, 0.0);
	say(u, k, 2062, "LV " + N_LV[s].toString() + " - DAY " + N_DAY[s].toString() + "/90", 160.0, 314.0, 184.0, 8.0, INK_MUTED, 1.0);
	let cx: float32 = 16.0;
	if (N_KIND[s] == 1) { cx += chip(u, k, 2063, cx, 334.0, "WILD", ChipKind.Outline, INK) + 4.0; }
	if (N_KIND[s] == 2) { cx += chip(u, k, 2064, cx, 334.0, "SHIELD 2D", ChipKind.Outline, INK) + 4.0; }
	if (N_DAY[s] >= 50) { cx += chip(u, k, 2065, cx, 334.0, "FADING", ChipKind.Dashed, INK_MUTED) + 4.0; }
	if (N_RAGE[s] > 0) { cx += chip(u, k, 2066, cx, 334.0, "RAGE " + N_RAGE[s].toString(), ChipKind.Filled, ALERT_RED) + 4.0; }
	heartPips(u, k, 2067, 16.0, 358.0, N_HEARTS[s], 10, 12.0);
	balance(u, k, 2068, 16.0, 380.0, 156.0, "bag", "warning", N_HARVEST[s].toString());
	balance(u, k, 2069, 188.0, 380.0, 156.0, "lock", "", N_BURROW[s].toString());
	const state: OddsState = N_KIND[s] == 2 ? OddsState.NotAttackable : OddsState.Ready;
	const w: int32 = N_WIN[s] < 0 ? 0 as int32 : N_WIN[s];
	oddsBlock(u, k, 2070, 16.0, 410.0, state, w, (N_HARVEST[s] * w) / 400, N_HARVEST[s] / 4,
		[0.08, 0.12, 0.28, 0.40, 0.33, 0.18], "NEWBORN SHIELD - 2 DAYS LEFT", 52, tick);
	sectionHeader(u, k, 2080, 16.0, 594.0, 328.0, "FIGHT LOG - 24H", "");
	if (N_SLOT[s] == 4) {
		listRow(u, k, 2081, 16.0, 612.0, 328.0, "fightLost", "03:10 SLOT 4 > YOU - LOST", "-310", ALERT_RED, RowKind.Plain, false, false);
		listRow(u, k, 2082, 16.0, 660.0, 328.0, "fightWon", "21:40 YOU > SLOT 4 - WON", "+220", GROWTH_GREEN, RowKind.Plain, false, false);
	} else {
		say(u, k, 2083, "NO FIGHTS WITH YOU IN THE LAST 24H", 16.0, 620.0, 328.0, 8.0, INK_MUTED, 0.0);
	}
}

// ---- My Pet --------------------------------------------------------------------------------

let petTab: int32 = 0 as int32;
let petSection: int32 = 0 as int32;
let persona: int32 = 1 as int32;
let personaPicked: int32 = 1 as int32;
let personaState: SignState = SignState.Idle;
let personaSince: int32 = 0 as int32;
let treeSelected: int32 = -1 as int32;
let treeSheetT: float32 = 0.0;

const STAT_NAMES: string[] = ["FORAGE", "MIGHT", "GRIT"];
const STAT_VALUES: int32[] = [18, 26, 21];
const ATTR_NAMES: string[] = ["SPEED", "ARMOR", "ACCURACY", "LIFESTEAL", "BLEED"];
const ATTR_VALUES: string[] = ["12", "8%", "71%", "4%", "2%"];
const GEAR_SLOT: string[] = ["HEAD", "BODY", "HANDS", "FEET"];
const GEAR_NAME: string[] = ["IRON CAP", "", "EMBER GLOVES", "RARE BOOTS"];
const GEAR_BONUS: string[] = ["GRIT +6%", "", "MIGHT +14%", "SPEED +8%"];
const GEAR_SKILL: string[] = ["NO SKILL", "", "SKILL - LOOT WARD", "SKILL - REVIVE"];
const GEAR_WEAR: float32[] = [0.7, 0.0, 0.35, 0.9];
const GEAR_RARITY: Rarity[] = [Rarity.Common, Rarity.Common, Rarity.Epic, Rarity.Rare];

function petHeader(u: Ui, k: Kit): void {
	badgeFrame(k, 3000, 16.0, 26.0, 36.0, 61);
	icon(k, 3000, "pet", 24.0, 34.0, 20.0);
	say(u, k, 3001, "EMBER", 62.0, 30.0, 140.0, 16.0, INK, 0.0);
	say(u, k, 3002, "LV 12 - DAY 34/90", 62.0, 50.0, 160.0, 8.0, INK_MUTED, 0.0);
	icon(k, 3003, "heart", 286.0, 34.0, 12.0);
	say(u, k, 3003, "7/10", 300.0, 36.0, 44.0, 8.0, INK, 1.0);
	petTab = tabs(u, k, 3004, 16.0, 68.0, 328.0, ["PET", "TREE"], [0, 2], petTab);
}

function petStats(u: Ui, k: Kit): void {
	for (let i: int32 = 0; i < 3; i += 1) {
		const y: float32 = 164.0 + (i as float32) * 40.0;
		say(u, k, 3100 + i, STAT_NAMES[i], 16.0, y, 100.0, 8.0, INK, 0.0);
		bar(u, 110.0, y, 180.0, 8.0, (STAT_VALUES[i] as float32) / 40.0, EMBER);
		say(u, k, 3110 + i, STAT_VALUES[i].toString(), 300.0, y, 44.0, 8.0, INK, 1.0);
	}
	for (let i: int32 = 0; i < 5; i += 1) {
		const x: float32 = 16.0 + ((i % 2) as float32) * 168.0;
		const y: float32 = 290.0 + ((i / 2) as float32) * 34.0;
		lightFrame(u, x, y, 160.0, 28.0, rgba(0.404, 0.247, 0.188, 1.0));
		say(u, k, 3120 + i, ATTR_NAMES[i], x + 10.0, y + 10.0, 100.0, 8.0, INK_MUTED, 0.0);
		say(u, k, 3130 + i, ATTR_VALUES[i], x + 90.0, y + 10.0, 60.0, 8.0, INK, 1.0);
	}
	say(u, k, 3140, "TREE: 18/30 POINTS - 2 UNSPENT", 16.0, 404.0, 260.0, 8.0, INK_MUTED, 0.0);
	if (textLink(u, k, 3141, 280.0, 404.0, "TREE", true)) { petTab = 1; }
	sectionHeader(u, k, 3150, 16.0, 436.0, 328.0, "TALENT", "");
	emptyState(u, k, 3151, 16.0, 456.0, 328.0, 70.0, "lock", "HIDDEN - REVEALED AT LEVEL 10 - 3 LEVELS TO GO");
	sectionHeader(u, k, 3160, 16.0, 544.0, 328.0, "VITALS", "");
	say(u, k, 3161, "HUNGER -2 HEARTS/DAY", 16.0, 566.0, 328.0, 8.0, INK, 0.0);
	say(u, k, 3162, "PANTRY S 1 - M 0 - L 2", 16.0, 584.0, 328.0, 8.0, INK, 0.0);
	say(u, k, 3163, "EATS BELOW 4 HEARTS - SET BY THE PET", 16.0, 602.0, 328.0, 8.0, INK_MUTED, 0.0);
	say(u, k, 3164, "AGE", 16.0, 624.0, 60.0, 8.0, INK_MUTED, 0.0);
	bar(u, 60.0, 624.0, 230.0, 8.0, 34.0 / 90.0, GROWTH_GREEN);
	say(u, k, 3165, "D34", 300.0, 624.0, 44.0, 8.0, INK, 1.0);
	say(u, k, 3166, "STATS AT 100% - DECLINE AFTER DAY 50", 16.0, 644.0, 328.0, 8.0, INK_MUTED, 0.0);
}

function petGear(u: Ui, k: Kit): void {
	for (let i: int32 = 0; i < 4; i += 1) {
		const x: float32 = 16.0 + ((i % 2) as float32) * 168.0;
		const y: float32 = 162.0 + ((i / 2) as float32) * 132.0;
		if (GEAR_NAME[i] == "") {
			emptyState(u, k, 3200 + i, x, y, 160.0, 120.0, "", GEAR_SLOT[i] + " - EMPTY");
			continue;
		}
		rarityBorder(u, x, y, 160.0, 120.0, GEAR_RARITY[i]);
		say(u, k, 3200 + i, GEAR_SLOT[i], x + 14.0, y + 14.0, 132.0, 8.0, INK_MUTED, 0.0);
		say(u, k, 3210 + i, GEAR_NAME[i], x + 14.0, y + 32.0, 132.0, 8.0, INK, 0.0);
		chip(u, k, 3220 + i, x + 14.0, y + 48.0, rarityName(GEAR_RARITY[i]), ChipKind.Outline, rarityColor(GEAR_RARITY[i]));
		say(u, k, 3230 + i, GEAR_BONUS[i], x + 14.0, y + 72.0, 132.0, 8.0, EMBER_HOT, 0.0);
		say(u, k, 3240 + i, GEAR_SKILL[i], x + 14.0, y + 86.0, 132.0, 8.0, INK_MUTED, 0.0);
		bar(u, x + 14.0, y + 102.0, 132.0, 5.0, GEAR_WEAR[i], GEAR_WEAR[i] < 0.4 ? ALERT_RED : INK_MUTED);
	}
	sectionHeader(u, k, 3250, 16.0, 434.0, 328.0, "HEIRLOOMS", "KEPT FOR THE NEXT GENERATION");
	emptyState(u, k, 3251, 16.0, 456.0, 160.0, 80.0, "", "EMPTY");
	rarityBorder(u, 184.0, 456.0, 160.0, 80.0, Rarity.Legendary);
	say(u, k, 3252, "GRANDSIRE'S FANG", 198.0, 472.0, 132.0, 8.0, INK, 0.0);
	say(u, k, 3253, "MIGHT +5%", 198.0, 490.0, 132.0, 8.0, EMBER_HOT, 0.0);
	say(u, k, 3254, "YOUR PET BUYS AND SELLS ITS OWN GEAR.", 16.0, 560.0, 328.0, 8.0, INK_MUTED, 0.5);
}

function petBond(u: Ui, k: Kit, tick: int32): void {
	say(u, k, 3300, "BONDING +40", 16.0, 164.0, 200.0, 8.0, INK, 0.0);
	bondingBar(u, k, 3301, 16.0, 182.0, 328.0, 40);
	say(u, k, 3302, "GIFTS RECEIVED: 1,240", 16.0, 214.0, 328.0, 8.0, INK, 0.0);
	say(u, k, 3303, "TALKS THAT COUNT TODAY: 3/5", 16.0, 230.0, 328.0, 8.0, INK, 0.0);
	sectionHeader(u, k, 3310, 16.0, 260.0, 328.0, "BRAIN - PERSONA", "");
	const names: string[] = ["CAUTIOUS", "GREEDY", "VENGEFUL"];
	const lines: string[] = ["AVOIDS FIGHTS IT MIGHT LOSE", "GOES FOR THE FATTEST HARVEST", "HITS BACK WHOEVER ROBBED IT"];
	for (let i: int32 = 0; i < 3; i += 1) {
		if (radioRow(u, k, 3311 + i, 16.0, 278.0 + (i as float32) * 48.0, 328.0, names[i], lines[i], personaPicked == i, persona == i)
			&& personaState != SignState.Waiting) { personaPicked = i; }
	}
	if (personaState == SignState.Waiting && tick - personaSince > 75) {
		personaState = SignState.Done;
		personaSince = tick;
		persona = personaPicked;
	}
	if (personaState == SignState.Done && tick - personaSince > 50) { personaState = SignState.Idle; }
	const changed: boolean = personaPicked != persona;
	let state: SignState = changed ? SignState.Idle : SignState.Disabled;
	if (personaState != SignState.Idle) { state = personaState; }
	if (signButton(u, k, 3320, 16.0, 432.0, 328.0, 44.0, "CHANGE", state, 62, tick)) {
		personaState = SignState.Waiting;
		personaSince = tick;
	}
	say(u, k, 3321, changed || personaState != SignState.Idle ? "NEEDS A SIGNATURE" : "PICK ANOTHER PERSONA TO CHANGE IT",
		16.0, 484.0, 328.0, 8.0, INK_MUTED, 0.0);
	say(u, k, 3322, "YOUR PET DECIDES; THIS ONLY NUDGES IT.", 16.0, 504.0, 328.0, 8.0, INK_MUTED, 0.0);
}

function petLineage(u: Ui, k: Kit): void {
	frame(k, 3400, 16.0, 162.0, 328.0, 160.0, 63, FrameLook.Normal);
	lineageEntry(u, k, 3401, 32.0, 184.0, 300.0, "GEN 1 - FIGHTER - LIVED 90 DAYS", LineageState.Lived, false);
	lineageEntry(u, k, 3402, 32.0, 216.0, 300.0, "GEN 2 - WORKER - DIED DAY 61", LineageState.Died, false);
	lineageEntry(u, k, 3403, 32.0, 248.0, 300.0, "GEN 3 - FIGHTER - NOW - DAY 34", LineageState.Now, true);
	say(u, k, 3404, "HEIR BONUS: +2 STARTING POINTS", 32.0, 290.0, 300.0, 8.0, EMBER_HOT, 0.0);
	say(u, k, 3405, "START PATH: FIGHTER - FIXED AT BIRTH", 16.0, 340.0, 328.0, 8.0, INK_MUTED, 0.0);
	say(u, k, 3406, "GEN 3 - SCARS 1", 16.0, 358.0, 328.0, 8.0, INK_MUTED, 0.0);
}

// tree: a gate, three paths and their notables, keystones between paths
const T_X: float32[] = [180.0, 180.0, 110.0, 250.0, 180.0, 70.0, 290.0, 130.0, 230.0, 180.0, 50.0, 310.0, 110.0, 250.0];
const T_Y: float32[] = [520.0, 460.0, 560.0, 560.0, 400.0, 600.0, 600.0, 640.0, 640.0, 340.0, 650.0, 650.0, 300.0, 300.0];
const T_SHAPE: NodeShape[] = [NodeShape.Notable, NodeShape.Small, NodeShape.Small, NodeShape.Small, NodeShape.Small,
	NodeShape.Small, NodeShape.Small, NodeShape.Small, NodeShape.Small, NodeShape.Notable, NodeShape.Notable,
	NodeShape.Notable, NodeShape.Keystone, NodeShape.Keystone];
const T_STATE: NodeState[] = [NodeState.Allocated, NodeState.Allocated, NodeState.Allocated, NodeState.Reachable,
	NodeState.Allocated, NodeState.Reachable, NodeState.Locked, NodeState.Locked, NodeState.Locked, NodeState.Reachable,
	NodeState.Locked, NodeState.Locked, NodeState.Locked, NodeState.Locked];
const T_LINK: int32[] = [0, 1, 0, 2, 0, 3, 1, 4, 2, 5, 3, 6, 2, 7, 3, 8, 4, 9, 5, 10, 6, 11, 9, 12, 9, 13];
const T_NAME: string[] = ["GATE", "IRON HIDE", "QUICK HANDS", "DEEP POCKETS", "BRAWLER", "SCAVENGER", "FORAGER",
	"LOOKOUT", "STOCKPILE", "BERSERKER", "WARDEN", "HARVEST LORD", "BLOOD OATH", "LAST STAND"];
const T_EFFECT: string[] = ["START", "+6% GRIT", "+4% SPEED", "+6% FORAGE", "+10% MIGHT", "+5% LOOT", "+6% FORAGE",
	"+8% ACCURACY", "+10% STORE", "+20% MIGHT", "+15% ARMOR", "+25% FORAGE", "WIN = HEAL 1 HEART", "REVIVE AT 1 HEART"];

// pan and zoom: screen = TREE_O + (world - TREE_W) * zoom + pan
const CLIP_X: float32 = 26.0;
const CLIP_Y: float32 = 156.0;
const CLIP_W: float32 = 308.0;
const CLIP_H: float32 = 528.0;
const TREE_OX: float32 = 180.0;
const TREE_OY: float32 = 420.0;
const TREE_WX: float32 = 180.0;
const TREE_WY: float32 = 480.0;
const ZOOM_MIN: float32 = 0.7;
const ZOOM_MAX: float32 = 2.6;
let zoom: float32 = 1.0;
let panX: float32 = 0.0;
let panY: float32 = 0.0;
let recentering: boolean = false;
// the gesture in progress
let gestureOn: boolean = false;
let pinching: boolean = false;
let moved: float32 = 0.0;
let startPanX: float32 = 0.0;
let startPanY: float32 = 0.0;
let startZoom: float32 = 1.0;
let startDist: float32 = 1.0;
let anchorX: float32 = 0.0;   // the world point under the pinch's midpoint
let anchorY: float32 = 0.0;
let lastX: float32 = 0.0;
let lastY: float32 = 0.0;

function inTree(x: float32, y: float32): boolean {
	return x >= CLIP_X && x < CLIP_X + CLIP_W && y >= CLIP_Y && y < CLIP_Y + CLIP_H;
}

function screenX(wx: float32): float32 { return TREE_OX + (wx - TREE_WX) * zoom + panX; }
function screenY(wy: float32): float32 { return TREE_OY + (wy - TREE_WY) * zoom + panY; }

function sqrtOf(v: float32): float32 {
	if (v <= 0.0) { return 0.0; }
	let r: float32 = v > 1.0 ? v : 1.0;
	for (let i: int32 = 0; i < 12; i += 1) { r = (r + v / r) * 0.5; }
	return r;
}

// One finger pans, two pinch (the point between them stays put). Any movement past a few
// units makes the gesture a drag: its release is not a tap on a node.
function treeGesture(u: Ui): void {
	if (u.pressed && inTree(u.pressX, u.pressY)) {
		gestureOn = true;
		pinching = false;
		moved = 0.0;
		startPanX = panX;
		startPanY = panY;
		lastX = u.pressX;
		lastY = u.pressY;
		recentering = false;
	}
	if (!gestureOn) { return; }
	if (u.down && u.down2) {
		const dx: float32 = u.x2 - u.x;
		const dy: float32 = u.y2 - u.y;
		const dist: float32 = sqrtOf(dx * dx + dy * dy);
		const mx: float32 = (u.x + u.x2) * 0.5;
		const my: float32 = (u.y + u.y2) * 0.5;
		if (!pinching) {
			pinching = true;
			startDist = dist < 1.0 ? 1.0 : dist;
			startZoom = zoom;
			anchorX = (mx - TREE_OX - panX) / zoom + TREE_WX;
			anchorY = (my - TREE_OY - panY) / zoom + TREE_WY;
			moved = 99.0;
		}
		let z: float32 = startZoom * dist / startDist;
		if (z < ZOOM_MIN) { z = ZOOM_MIN; }
		if (z > ZOOM_MAX) { z = ZOOM_MAX; }
		zoom = z;
		panX = mx - TREE_OX - (anchorX - TREE_WX) * zoom;
		panY = my - TREE_OY - (anchorY - TREE_WY) * zoom;
	} else if (u.down) {
		if (pinching) {
			// back to one finger: carry on panning from here
			pinching = false;
			startPanX = panX - (u.x - u.pressX);
			startPanY = panY - (u.y - u.pressY);
		}
		panX = startPanX + (u.x - u.pressX);
		panY = startPanY + (u.y - u.pressY);
		const sx: float32 = u.x - lastX;
		const sy: float32 = u.y - lastY;
		moved += (sx < 0.0 ? -sx : sx) + (sy < 0.0 ? -sy : sy);
		lastX = u.x;
		lastY = u.y;
	}
	// keep some of the tree on screen
	const limit: float32 = 220.0 * zoom;
	if (panX > limit) { panX = limit; }
	if (panX < -limit) { panX = -limit; }
	if (panY > limit) { panY = limit; }
	if (panY < -limit) { panY = -limit; }
}

function petTree(u: Ui, k: Kit): void {
	say(u, k, 3500, "POINTS: 2 UNSPENT - 18/30 USED", 16.0, 112.0, 328.0, 8.0, INK, 0.0);
	say(u, k, 3501, "WINTER REFUND: 3 AVAILABLE", 16.0, 128.0, 328.0, 8.0, INK_MUTED, 0.0);
	frame(k, 3502, 16.0, 146.0, 328.0, 548.0, 64, FrameLook.Normal);
	if (treeSelected < 0) { treeGesture(u); }
	if (recentering) {
		zoom = zoom + (1.0 - zoom) * 0.2;
		panX = panX * 0.8;
		panY = panY * 0.8;
		const off: float32 = (panX < 0.0 ? -panX : panX) + (panY < 0.0 ? -panY : panY) + (zoom > 1.0 ? zoom - 1.0 : 1.0 - zoom) * 100.0;
		if (off < 0.5) { recentering = false; zoom = 1.0; panX = 0.0; panY = 0.0; }
	}
	const lx: float32 = screenX(180.0);
	const ly: float32 = screenY(270.0);
	if (inTree(lx, ly)) { say(u, k, 3503, "FIGHTER", lx - 40.0, ly, 80.0, 8.0, INK_MUTED, 0.5); }
	for (let i: int32 = 0; i < T_LINK.length; i += 2) {
		const a: int32 = T_LINK[i];
		const b: int32 = T_LINK[i + 1];
		treeLinkIn(u, screenX(T_X[a]), screenY(T_Y[a]), screenX(T_X[b]), screenY(T_Y[b]),
			T_STATE[a] == NodeState.Allocated && T_STATE[b] == NodeState.Allocated, CLIP_X, CLIP_Y, CLIP_W, CLIP_H);
	}
	const dragged: boolean = moved > 8.0;
	for (let i: int32 = 0; i < T_X.length; i += 1) {
		const nx: float32 = screenX(T_X[i]);
		const ny: float32 = screenY(T_Y[i]);
		const r: float32 = 13.0 * zoom;
		if (nx - r < CLIP_X || ny - r < CLIP_Y || nx + r > CLIP_X + CLIP_W || ny + r > CLIP_Y + CLIP_H) { continue; }
		if (treeNodeScaled(u, k, 3510 + i, nx, ny, T_SHAPE[i], T_STATE[i], zoom) && !dragged) { treeSelected = i; }
	}
	icon(k, 3530, "recenter", 306.0, 656.0, 26.0);
	if (pressable(u, 3531, 296.0, 646.0, 48.0, 48.0)) { recentering = true; }
	if (!u.down) { gestureOn = false; }
	say(u, k, 3532, "DRAG TO PAN - PINCH TO ZOOM", 16.0, 706.0, 328.0, 8.0, INK_MUTED, 0.5);
}

function treeSheet(u: Ui, k: Kit): void {
	const target: float32 = treeSelected >= 0 ? 1.0 : 0.0;
	treeSheetT = treeSheetT + (target - treeSheetT) * 0.25;
	if (treeSheetT < 0.01 && treeSelected < 0) { return; }
	overlayOpen = treeSelected >= 0;
	const h: float32 = 220.0;
	if (sheet(u, k, 3600, h, treeSheetT, 65)) { treeSelected = -1; }
	const top: float32 = sheetTop(h, treeSheetT);
	const i: int32 = treeSelected >= 0 ? treeSelected : 0 as int32;
	const states: string[] = ["TAKEN", "REACHABLE", "LOCKED"];
	const shapes: string[] = ["SMALL NODE", "NOTABLE", "KEYSTONE"];
	say(u, k, 3601, T_NAME[i], 32.0, top + 28.0, 220.0, 16.0, INK, 0.0);
	chip(u, k, 3602, 32.0, top + 52.0, states[T_STATE[i] as int32], T_STATE[i] == NodeState.Allocated ? ChipKind.Filled : ChipKind.Outline,
		T_STATE[i] == NodeState.Locked ? INK_MUTED : EMBER);
	say(u, k, 3603, "FIGHTER - " + shapes[T_SHAPE[i] as int32], 32.0, top + 80.0, 296.0, 8.0, INK_MUTED, 0.0);
	say(u, k, 3604, T_EFFECT[i], 32.0, top + 98.0, 296.0, 8.0, EMBER_HOT, 0.0);
	say(u, k, 3605, T_SHAPE[i] == NodeShape.Keystone ? "COST 3 POINTS" : "COST 1 POINT", 32.0, top + 116.0, 296.0, 8.0, INK, 0.0);
	say(u, k, 3606, "YOUR PET SPENDS ITS OWN POINTS.", 32.0, top + 140.0, 296.0, 8.0, INK_MUTED, 0.0);
	if (textLink(u, k, 3607, 284.0, top + 32.0, "CLOSE", true)) { treeSelected = -1; }
	endOverlay(u);
	endKitOverlay(k);
}

function pet(u: Ui, k: Kit, tick: int32): void {
	petHeader(u, k);
	if (petTab == 1) {
		petTree(u, k);
		treeSheet(u, k);
		return;
	}
	petSection = segmented(u, k, 3010, 16.0, 112.0, 328.0, ["STATS", "GEAR", "BOND", "LINEAGE"], petSection, 66);
	if (petSection == 0) { petStats(u, k); }
	else if (petSection == 1) { petGear(u, k); }
	else if (petSection == 2) { petBond(u, k, tick); }
	else { petLineage(u, k); }
}

// ---- Shop ----------------------------------------------------------------------------------

let shopSection: int32 = 0 as int32;
let buyItem: int32 = -1 as int32;
let buyState: SignState = SignState.Idle;
let buySince: int32 = 0 as int32;
let growth: int32 = 110 as int32;   // x1.10 in hundredths
let insurance: int32 = 0 as int32;  // 0 available, 1 armed, 2 used
let skinOwned: boolean = false;
let skinOn: boolean = false;
let skr: int32 = 240 as int32;

function card(u: Ui, k: Kit, id: int32, y: float32, name: string, effect: string, note: string, price: int32, state: SignState, tick: int32): boolean {
	frame(k, id, 16.0, y, 328.0, 76.0, id, FrameLook.Normal);
	say(u, k, id, name, 32.0, y + 16.0, 150.0, 8.0, INK, 0.0);
	say(u, k, id + 1, effect, 32.0, y + 34.0, 150.0, 8.0, EMBER_HOT, 0.0);
	if (note != "") { say(u, k, id + 2, note, 32.0, y + 52.0, 150.0, 8.0, INK_MUTED, 0.0); }
	return signButton(u, k, id + 3, 190.0, y + 16.0, 138.0, 44.0, "BUY " + price.toString() + " SKR", state, id + 4, tick);
}

function shop(u: Ui, k: Kit, q: Toasts, tick: int32): void {
	title(u, k, 4000, "SHOP", "");
	icon(k, 4002, "wallet", 236.0, 30.0, 16.0);
	say(u, k, 4003, skr.toString() + " SKR", 256.0, 34.0, 88.0, 8.0, INK, 1.0);
	const before: int32 = shopSection;
	shopSection = segmented(u, k, 4004, 16.0, 62.0, 328.0, ["FOOD", "GROWTH", "INSURE", "SKINS"], shopSection, 71);
	if (before != shopSection && buyState != SignState.Waiting) { buyItem = -1; buyState = SignState.Idle; }
	// the purchase in flight
	if (buyState == SignState.Waiting && tick - buySince > 75) {
		buyState = SignState.Done;
		buySince = tick;
		pushToast(q, "BOUGHT", false);
		if (shopSection == 1) { growth = growth + 5 * (buyItem + 1) > 120 ? 120 as int32 : growth + 5 * (buyItem + 1); }
		if (shopSection == 2) { insurance = 1; }
		if (shopSection == 3) { skinOwned = true; }
	}
	if (buyState == SignState.Done && tick - buySince > 50) { buyState = SignState.Idle; buyItem = -1; }
	const busy: boolean = buyState != SignState.Idle;
	let picked: int32 = -1 as int32;
	if (shopSection == 0) {
		const names: string[] = ["SMALL", "MEDIUM", "LARGE"];
		const prices: int32[] = [5, 9, 12];
		for (let i: int32 = 0; i < 3; i += 1) {
			const st: SignState = buyItem == i ? buyState : (busy ? SignState.Disabled : SignState.Idle);
			if (card(u, k, 4010 + i * 10, 112.0 + (i as float32) * 88.0, names[i], "+" + (i + 1).toString() + " HEARTS", "", prices[i], st, tick)) { picked = i; }
		}
	} else if (shopSection == 1) {
		say(u, k, 4050, "NOW X" + (growth / 100).toString() + "." + (growth % 100 < 10 ? "0" : "") + (growth % 100).toString() + " - CAP X1.20",
			16.0, 112.0, 328.0, 8.0, INK, 0.0);
		const pct: int32[] = [5, 10, 15];
		const prices: int32[] = [8, 14, 20];
		for (let i: int32 = 0; i < 3; i += 1) {
			const capped: boolean = growth + pct[i] > 120;
			let st: SignState = capped ? SignState.Disabled : SignState.Idle;
			if (buyItem == i) { st = buyState; } else if (busy) { st = SignState.Disabled; }
			if (card(u, k, 4060 + i * 10, 132.0 + (i as float32) * 88.0, "GROWTH +" + pct[i].toString() + "%", "HARVEST - 24H",
				capped ? "CAP X1.20" : "", prices[i], st, tick)) { picked = i; }
		}
	} else if (shopSection == 2) {
		const notes: string[] = ["ONCE PER PET", "ARMED", "USED - NEVER AGAIN"];
		let st: SignState = insurance == 0 ? SignState.Idle : SignState.Disabled;
		if (buyItem == 0) { st = buyState; }
		if (card(u, k, 4100, 112.0, "INSURANCE", "REVIVE ONCE AT 3 HEARTS", notes[insurance], 25, st, tick)) { picked = 0; }
		if (textLink(u, k, 4110, 16.0, 212.0, insurance == 1 ? "DEMO: MARK USED" : "DEMO: RESET", true)) {
			insurance = insurance == 1 ? 2 as int32 : 0 as int32;
		}
	} else {
		rarityBorder(u, 16.0, 112.0, 120.0, 120.0, Rarity.Epic);
		icon(k, 4150, "pet", 46.0, 142.0, 60.0);
		say(u, k, 4151, "ASH CLOAK", 150.0, 120.0, 194.0, 8.0, INK, 0.0);
		say(u, k, 4152, "COSMETIC - NO POWER", 150.0, 138.0, 194.0, 8.0, INK_MUTED, 0.0);
		if (!skinOwned) {
			const st: SignState = buyItem == 0 ? buyState : SignState.Idle;
			if (signButton(u, k, 4153, 150.0, 170.0, 178.0, 44.0, "BUY 30 SKR", st, 72, tick)) { picked = 0; }
		} else if (button(u, k, 4154, 150.0, 170.0, 178.0, 44.0, skinOn ? "TAKE OFF" : "EQUIP", ButtonStyle.Primary, true, 73)) {
			skinOn = !skinOn;
		}
		if (skinOn) { chip(u, k, 4155, 150.0, 150.0, "EQUIPPED", ChipKind.Filled, EMBER); }
	}
	if (picked >= 0) {
		buyItem = picked;
		buyState = SignState.Waiting;
		buySince = tick;
	}
	say(u, k, 4190, "EVERY PURCHASE RAISES BONDING. SKR NEVER BUYS POWER.", 16.0, 696.0, 328.0, 8.0, INK_MUTED, 0.5);
}

// ---- Settings ------------------------------------------------------------------------------

let session: ToggleState = ToggleState.Off;
let sessionSince: int32 = 0 as int32;
let ongoingOn: boolean = true;
let digestOn: boolean = true;
let wallpaperSet: boolean = false;
let askDisconnect: boolean = false;
let connected: boolean = true;

function settings(u: Ui, k: Kit, q: Toasts, tick: int32): void {
	if (textLink(u, k, 5000, 16.0, 34.0, "< HOME", true)) { navigate = Nav.Home; }
	say(u, k, 5001, "SETTINGS", 100.0, 30.0, 160.0, 16.0, INK, 0.5);
	box(u, 16.0, 52.0, 328.0, 1.0, 0.0, DIVIDER);
	sectionHeader(u, k, 5010, 16.0, 66.0, 328.0, "WALLET", "");
	if (connected) {
		if (listRow(u, k, 5011, 16.0, 84.0, 328.0, "wallet", "CONNECTED WALLET", "7XKP...3FQA", INK_MUTED, RowKind.Plain, false, true)) {
			pushToast(q, "ADDRESS COPIED", false);
		}
		if (listRow(u, k, 5012, 16.0, 140.0, 328.0, "", "DISCONNECT", "", INK, RowKind.Destructive, false, true)) { askDisconnect = true; }
	} else {
		if (listRow(u, k, 5013, 16.0, 84.0, 328.0, "wallet", "CONNECT WALLET", "", INK, RowKind.Plain, true, true)) { connected = true; }
	}
	sectionHeader(u, k, 5020, 16.0, 210.0, 328.0, "SESSION KEY", "");
	if (session == ToggleState.Pending && tick - sessionSince > 75) { session = ToggleState.On; }
	say(u, k, 5021, session == ToggleState.On ? "ACTIVE - EXPIRES IN 6 DAYS" : "SIGN FOR YOUR PET YOURSELF",
		16.0, 240.0, 250.0, 8.0, session == ToggleState.On ? GROWTH_GREEN : INK, 0.0);
	if (toggle(u, k, 5022, 296.0, 222.0, session, tick)) {
		if (session == ToggleState.Off) { session = ToggleState.Pending; sessionSince = tick; }
		else { session = ToggleState.Off; pushToast(q, "SESSION KEY REVOKED", false); }
	}
	say(u, k, 5023, "YOUR PET PLAYS ON ITS OWN WITHOUT IT.", 16.0, 258.0, 270.0, 8.0, INK_MUTED, 0.0);
	sectionHeader(u, k, 5030, 16.0, 290.0, 328.0, "LIVE WALLPAPER", wallpaperSet ? "ON" : "OFF");
	if (listRow(u, k, 5031, 16.0, 308.0, 328.0, "home", wallpaperSet ? "CHANGE WALLPAPER" : "SET AS WALLPAPER", "", INK,
		RowKind.Plain, true, false)) { wallpaperSet = true; pushToast(q, "OPENS THE SYSTEM PICKER", false); }
	sectionHeader(u, k, 5040, 16.0, 372.0, 328.0, "NOTIFICATIONS", "");
	say(u, k, 5041, "ONGOING - PET IN THE SHADE", 16.0, 402.0, 250.0, 8.0, INK, 0.0);
	if (toggle(u, k, 5042, 296.0, 384.0, ongoingOn ? ToggleState.On : ToggleState.Off, tick)) { ongoingOn = !ongoingOn; }
	say(u, k, 5043, "MORNING DIGEST", 16.0, 446.0, 250.0, 8.0, INK, 0.0);
	if (toggle(u, k, 5044, 296.0, 428.0, digestOn ? ToggleState.On : ToggleState.Off, tick)) { digestOn = !digestOn; }
	sectionHeader(u, k, 5050, 16.0, 486.0, 328.0, "NETWORK", "");
	listRow(u, k, 5051, 16.0, 504.0, 328.0, "", "NETWORK", "DEVNET", INK_MUTED, RowKind.Locked, false, false);
	sectionHeader(u, k, 5060, 16.0, 566.0, 328.0, "ABOUT", "VERSION 0.1.0 (HACKATHON)");
	if (listRow(u, k, 5061, 16.0, 584.0, 328.0, "", "UI KIT GALLERY", "", INK, RowKind.Plain, true, false)) { navigate = Nav.Gallery; }
	if (listRow(u, k, 5062, 16.0, 632.0, 328.0, "", "HOW THE GAME WORKS", "", INK, RowKind.Plain, true, false)) {
		pushToast(q, "NOT BUILT YET", false);
	}

	if (askDisconnect) {
		overlayOpen = true;
		const a: ModalAnswer = modal(u, k, 5100, "DISCONNECT WALLET?", "YOUR PET KEEPS PLAYING ON ITS OWN.", "DISCONNECT", true, 74);
		if (a == ModalAnswer.Confirm) { connected = false; askDisconnect = false; pushToast(q, "WALLET DISCONNECTED", false); }
		if (a == ModalAnswer.Cancel) { askDisconnect = false; }
		endOverlay(u);
		endKitOverlay(k);
	}
}

// ---- entry ---------------------------------------------------------------------------------

// The dock tab or Settings, drawn over a dark backdrop. `tab` is a Nav value.
export function screenFrame(u: Ui, k: Kit, q: Toasts, tab: Nav, tick: int32): void {
	overlayOpen = false;
	backdrop(k);
	match (tab) {
		Nav.Digest => { digest(u, k); },
		Nav.Block => { block(u, k, tick); },
		Nav.Pet => { pet(u, k, tick); },
		Nav.Shop => { shop(u, k, q, tick); },
		Nav.Settings => { settings(u, k, q, tick); },
		_ => {},
	};
}
