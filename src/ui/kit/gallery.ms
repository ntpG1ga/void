// Hibernal UI kit gallery: every kit piece on one screen, to review on the phone.
// Run the grass lab with LAB_HUD=2. Grows with each batch of components.

import { rgba } from "../../void2d/types";
import { loadNextPass } from "../../sokol/gpu";
import { Ui, createUi, beginUi, endUi, pressable, held } from "../ui";
import { Kit, createKit, beginKit, endKit, frame, badgeFrame, icon, say, INK, INK_MUTED, EMBER_HOT, EMBER_PRESSED } from "./kit";
import { FrameLook } from "./frame";

const ICONS: string[] = ["heart", "bag", "lock", "warning", "winter", "growth", "insured", "gear",
	"home", "pet", "block", "shop", "digest"];

let ui: Ui | null = null;
let kit: Kit | null = null;
let seedShift: int32 = 0 as int32;

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

	say(u, k, 1, "UI KIT - FRAMES", 16.0, 30.0, 328.0, 16.0, INK, 0.0);
	say(u, k, 2, "TAP A PANEL FOR NEW SEEDS - TAP THE TITLE FOR HOME", 16.0, 52.0, 328.0, 8.0, INK_MUTED, 0.0);
	if (pressable(u, 3, 0.0, 20.0, 360.0, 44.0)) { homeAsked = true; }

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

	// every icon at 24
	say(u, k, 40, "ICONS", 16.0, 540.0, 200.0, 8.0, INK_MUTED, 0.0);
	for (let i: int32 = 0; i < ICONS.length; i += 1) {
		const col: int32 = i % 7;
		const row: int32 = i / 7;
		icon(k, 41 + i, ICONS[i], 16.0 + (col as float32) * 48.0, 556.0 + (row as float32) * 40.0, 24.0);
	}

	endKit(k);
	loadNextPass();
	endUi(u);
}
