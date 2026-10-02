// Hibernal Home HUD over the grass lab: the charred-wood chrome is baked offline at device
// resolution (hibernal art/ui-kit/tools/renderHomeHd.py with HUD_CHROME=1 → assets/hud/
// homeTop.png and homeBottom.png, 1080 px wide = 360 design units at 3x); text, numbers and
// touch are live, on src/ui/ui.ms. Layout follows hibernal docs/HUD-WIREFRAME.md §4.
//
// The 3D renderer commits its own frame, so the caller skips that commit (skipNextCommit)
// and the HUD's 2D pass loads the 3D image instead of clearing it (loadNextPass).

import { makeImage, makeView, loadNextPass } from "../sokol/gpu";
import { Node2D, sprite, at, addChildAt } from "../void2d/node";
import { rgba, tile, Color } from "../void2d/types";
import { addFont } from "../void2d/labelText";
import { loadImageSync, imageWidth, imageHeight, freeImage } from "../assets/image";
import { Ui, createUi, beginUi, endUi, box, text, pressable, held, DESIGN_W } from "../ui/ui";

const HUD_DIR: string = "assets/hud/";
const MAX_HEARTS: int32 = 10 as int32;
const MAX_TALKS: int32 = 5 as int32;
const TOAST_SECONDS: int32 = 150 as int32;   // frames at 30 fps

// widget / label ids
const HEARTS: int32 = 1 as int32;
const HARVEST: int32 = 2 as int32;
const BURROW: int32 = 3 as int32;
const LEVEL: int32 = 4 as int32;
const AGE: int32 = 5 as int32;
const WINTER: int32 = 6 as int32;
const GROWTH: int32 = 7 as int32;
const TOAST: int32 = 8 as int32;
const FEED: int32 = 9 as int32;
const TALK: int32 = 10 as int32;
const DOCK: int32 = 20 as int32;   // 20..24

let ui: Ui | null = null;
let silk: int32 = 0 as int32;
let hearts: int32 = 7 as int32;
let talks: int32 = 3 as int32;
let toast: string = "MOVED 620 TO BURROW - NEXT IN 8H";
let toastLeft: int32 = TOAST_SECONDS;

const TEXT_LIGHT: Color = rgba(0.824, 0.831, 0.824, 1.0);
const EMBER_HOT: Color = rgba(0.969, 0.549, 0.227, 1.0);
const EMBER_PRESSED: Color = rgba(1.0, 0.75, 0.45, 1.0);
const TOAST_STRIP: Color = rgba(0.047, 0.051, 0.063, 0.82);

function chrome(name: string, x: float32, y: float32, w: float32, h: float32): Node2D {
	const pixels = loadImageSync(HUD_DIR + name, 4);
	const view: uint32 = makeView(makeImage(pixels, imageWidth(), imageHeight()));
	freeImage(pixels);
	return sprite(tile(view, w, h)).at(x, y);
}

// The gear opens the UI kit gallery until Settings exists; the caller polls this.
let galleryAsked: boolean = false;
export function takeGalleryRequest(): boolean {
	const asked: boolean = galleryAsked;
	galleryAsked = false;
	return asked;
}

// setup2d is the caller's (once, before any HUD screen).
export function initHudHome(): void {
	silk = addFont(HUD_DIR + "Silkscreen-Regular.ttf");
	const u = createUi(rgba(0.0, 0.0, 0.0, 1.0));
	// chrome under the live boxes and labels
	u.sc.root.addChildAt(chrome("homeBottom.png", 0.0, 600.0, DESIGN_W, 200.0), 0);
	u.sc.root.addChildAt(chrome("homeTop.png", 0.0, 0.0, DESIGN_W, 250.0), 0);
	ui = u;
}

// ui.text, in Silkscreen
function say(u: Ui, id: int32, s: string, x: float32, y: float32, w: float32, size: float32, color: Color, align: float32): void {
	text(u, id, s, x, y, w, size, color, align);
	for (let i: int32 = 0; i < u.labelIds.length; i += 1) {
		if (u.labelIds[i] === id) { u.labelNodes[i].fontId = silk; }
	}
}

function showToast(s: string): void {
	toast = s;
	toastLeft = TOAST_SECONDS;
}

// A framed button baked in the chrome: only its label and its touch live here.
function chromeButton(u: Ui, id: int32, x: float32, y: float32, w: float32, h: float32, caption: string, enabled: boolean): boolean {
	const clicked: boolean = pressable(u, id, x, y, w, h) && enabled;
	const down: boolean = held(u, id, x, y, w, h);
	const ink: Color = !enabled ? rgba(0.45, 0.43, 0.42, 1.0) : down ? EMBER_PRESSED : EMBER_HOT;
	say(u, id, caption, x, y + 18.0 + (down ? 1.0 : 0.0), w, 8.0, ink, 0.5);
	return clicked;
}

export function frameHudHome(): void {
	if (ui === null) { return; }
	const u = ui as Ui;
	beginUi(u);

	// status card values (icons and frame are baked)
	say(u, HEARTS, hearts.toString() + "/" + MAX_HEARTS.toString(), 62.0, 53.0, 90.0, 8.0, TEXT_LIGHT, 0.0);
	say(u, HARVEST, "1,240", 62.0, 71.0, 90.0, 8.0, TEXT_LIGHT, 0.0);
	say(u, BURROW, "5,600", 62.0, 89.0, 90.0, 8.0, TEXT_LIGHT, 0.0);
	say(u, LEVEL, "LV12", 34.0, 112.0, 30.0, 8.0, TEXT_LIGHT, 0.0);
	say(u, AGE, "D34", 100.0, 112.0, 48.0, 8.0, TEXT_LIGHT, 1.0);

	// badge numbers
	say(u, WINTER, "12", 304.0, 106.0, 40.0, 8.0, TEXT_LIGHT, 0.5);
	say(u, GROWTH, "X1.1", 304.0, 154.0, 40.0, 8.0, TEXT_LIGHT, 0.5);

	// toast: frameless strip, one at a time
	if (toastLeft > 0) {
		box(u, 16.0, 612.0, DESIGN_W - 32.0, 36.0, 0.0, TOAST_STRIP);
		say(u, TOAST, toast, 16.0, 625.0, DESIGN_W - 32.0, 8.0, TEXT_LIGHT, 0.5);
		toastLeft = toastLeft - 1;
	}

	if (chromeButton(u, FEED, 16.0, 668.0, 156.0, 48.0, "FEED", hearts < MAX_HEARTS)) {
		hearts = hearts + 1;
		showToast("FED - HEARTS " + hearts.toString() + "/" + MAX_HEARTS.toString());
	}
	if (chromeButton(u, TALK, 188.0, 668.0, 156.0, 48.0, "TALK " + talks.toString() + "/" + MAX_TALKS.toString(), true)) {
		if (talks > 0) {
			talks = talks - 1;
			showToast("TALKED - " + talks.toString() + " LEFT TODAY");
		} else {
			showToast("NO MORE BONDING TODAY");
		}
	}

	// gear: 48 x 48 target round the 36 px box at the top right
	if (pressable(u, 30, DESIGN_W - 12.0 - 48.0, 28.0, 48.0, 48.0)) { galleryAsked = true; }

	// dock labels (icons, frame and the Home underline are baked)
	const names: string[] = ["HOME", "PET", "BLOCK", "SHOP", "DIGEST"];
	for (let i: int32 = 0; i < 5; i += 1) {
		const cx: float32 = 24.0 + 62.0 * (i as float32) + 31.0;
		const id: int32 = DOCK + i;
		if (pressable(u, id, cx - 31.0, 728.0, 62.0, 56.0) && i > 0) {
			showToast(names[i] + " - NOT BUILT YET");
		}
		say(u, id, names[i], cx - 31.0, 762.0, 62.0, 8.0, i == 0 ? EMBER_HOT : TEXT_LIGHT, 0.5);
	}

	loadNextPass();
	endUi(u);
}
