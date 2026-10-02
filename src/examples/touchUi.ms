// Void — touch UI spike: a Hibernal-shaped HUD on src/ui/ui.ms. Tap Feed and Talk, drag the
// pet. Runs on the desktop window (left mouse = one finger) and inside the Android shell.

import { gfxSetup } from "../sokol/gpu";
import { setup2d } from "../void2d/draw";
import { rgba } from "../void2d/types";
import { Ui, createUi, beginUi, endUi, box, text, button, pressable, held, DESIGN_W } from "../ui/ui";

const TITLE: int32 = 1 as int32;
const HEARTS: int32 = 2 as int32;
const FEED: int32 = 3 as int32;
const TALK: int32 = 4 as int32;
const PET: int32 = 5 as int32;
const PET_NAME: int32 = 6 as int32;
const STATUS: int32 = 7 as int32;
const POINTER: int32 = 8 as int32;
const RESET: int32 = 9 as int32;

const MAX_HEARTS: int32 = 10 as int32;
const MAX_TALKS: int32 = 5 as int32;
const PET_SIZE: float32 = 88.0;

let ui: Ui | null = null;
let hearts: int32 = 7 as int32;
let talks: int32 = 3 as int32;
let petX: float32 = 136.0;
let petY: float32 = 330.0;
let grabX: float32 = 0.0;
let grabY: float32 = 0.0;
let status: string = "Tap Feed or Talk, drag the pet";

// One line of the demo's state, for the scripted run (touchUiScript.ms).
export function touchUiState(): string {
	return "hearts=" + hearts.toString() + " talks=" + talks.toString()
		+ " pet=" + (petX as int32).toString() + "," + (petY as int32).toString() + " status=\"" + status + "\"";
}

export function initTouchUi(): void {
	gfxSetup();
	setup2d();
	ui = createUi(rgba(0.07, 0.08, 0.10, 1.0));
}

export function frameTouchUi(): void {
	if (ui === null) { return; }
	const u = ui as Ui;
	beginUi(u);

	const white = rgba(0.95, 0.96, 1.0, 1.0);
	const dim = rgba(0.62, 0.66, 0.74, 1.0);
	text(u, TITLE, "Hibernal HUD spike", 16.0, 36.0, DESIGN_W - 32.0, 22.0, white, 0.0);

	// Heart pips, then the count.
	for (let i: int32 = 0; i < MAX_HEARTS; i += 1) {
		const on = rgba(0.90, 0.32, 0.38, 1.0);
		const off = rgba(0.25, 0.26, 0.30, 1.0);
		box(u, 16.0 + (i as float32) * 22.0, 80.0, 16.0, 16.0, 4.0, i < hearts ? on : off);
	}
	text(u, HEARTS, hearts.toString() + " / " + MAX_HEARTS.toString(), 250.0, 78.0, 94.0, 18.0, dim, 1.0);

	// The pet: press it and drag. The grab offset is taken in the frame the press lands.
	pressable(u, PET, petX, petY, PET_SIZE, PET_SIZE);
	if (held(u, PET, petX - 400.0, petY - 400.0, PET_SIZE + 800.0, PET_SIZE + 800.0)) {
		if (u.pressed) {
			grabX = u.x - petX;
			grabY = u.y - petY;
		}
		petX = u.x - grabX;
		petY = u.y - grabY;
	}
	const petColor = held(u, PET, petX, petY, PET_SIZE, PET_SIZE) ? rgba(0.98, 0.78, 0.35, 1.0) : rgba(0.86, 0.62, 0.28, 1.0);
	box(u, petX, petY, PET_SIZE, PET_SIZE, 28.0, petColor);
	text(u, PET_NAME, "pet", petX, petY + PET_SIZE * 0.5 - 11.0, PET_SIZE, 16.0, rgba(0.12, 0.10, 0.08, 1.0), 0.5);

	// Action row, above where the dock would be.
	if (button(u, FEED, 16.0, 660.0, 156.0, 52.0, "Feed", hearts < MAX_HEARTS)) {
		hearts = hearts + 1;
		status = "Fed: hearts " + hearts.toString();
	}
	const talkCaption = "Talk " + talks.toString() + "/" + MAX_TALKS.toString();
	if (button(u, TALK, 188.0, 660.0, 156.0, 52.0, talkCaption, talks > 0)) {
		talks = talks - 1;
		status = "Talked: " + talks.toString() + " left today";
	}
	if (button(u, RESET, 16.0, 724.0, 328.0, 40.0, "Reset", true)) {
		hearts = 3 as int32;
		talks = MAX_TALKS;
		petX = 136.0;
		petY = 330.0;
		status = "Reset";
	}

	text(u, STATUS, status, 16.0, 580.0, DESIGN_W - 32.0, 16.0, white, 0.0);
	const px = (u.x as int32).toString();
	const py = (u.y as int32).toString();
	text(u, POINTER, "pointer " + px + ", " + py + (u.down ? "  down" : "  up"), 16.0, 606.0, DESIGN_W - 32.0, 14.0, dim, 0.0);

	endUi(u);
}
