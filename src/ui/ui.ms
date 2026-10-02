// Void UI — a small immediate-mode layer over void2d, for touch HUDs.
//
// Every frame the app calls beginUi, then one function per widget, then endUi. The same call
// that draws a widget also answers whether it was pressed, so where a thing is drawn and where
// it can be touched never drift apart (the Dear ImGui idea). Hit-testing is ours: the OS only
// reports pointer positions on the surface (src/input/pointer.ms).
//
// Layout is in design units: a fixed 360×800 portrait canvas, letterboxed into the surface.
// Pointer pixels are mapped back through the same letterbox before any hit-test.
//
// void2d is retained (a Node2D tree), so the immediate API sits on top of it: boxes are drawn
// into one Graphics node cleared each frame, and each text is a label node kept by widget id,
// updated in place (void2d reshapes a label only when its text or style changes), and hidden
// in a frame that does not draw it.
//
// Only the first finger down is tracked. Ids are the caller's: one id per widget, never 0.

import { Scene, scene, add, setScaleMode, present } from "../void2d/scene";
import { Node2D, group, graphics, label, addChild } from "../void2d/node";
import { clear, fillRoundedRect } from "../void2d/graphics";
import { Color, rgba, ScaleMode } from "../void2d/types";
import { faceFor } from "../void2d/labelText";
import { fbWidth, fbHeight, dpiScale } from "../sokol/gpu";
import { PointerPhase, takePointerEvents } from "../input/pointer";

export const DESIGN_W: float32 = 360.0;
export const DESIGN_H: float32 = 800.0;
const NO_POINTER: int32 = -1 as int32;
const NO_WIDGET: int32 = 0 as int32;

export interface Ui {
	sc: Scene;
	boxes: Node2D;
	texts: Node2D;
	labelIds: int32[];
	labelNodes: Node2D[];
	labelUsed: boolean[];
	pointerId: int32;
	// The tracked pointer, in design units. `pressed` / `released` hold for the one frame in
	// which the pointer went down / up, with where it happened; both can hold in the same
	// frame when a tap was shorter than a frame.
	down: boolean;
	x: float32;
	y: float32;
	pressed: boolean;
	pressX: float32;
	pressY: float32;
	released: boolean;
	releaseX: float32;
	releaseY: float32;
	// The widget that took the current press. A press belongs to the widget it started on,
	// so sliding onto another widget and lifting there does not press that one.
	activeId: int32;
	// Overlay layer (sheets, modals): drawn above everything else, and while `blockBase` is
	// set only overlay widgets take touches. The kit adds its own layers in the same order.
	boxesTop: Node2D;
	textsTop: Node2D;
	overlay: boolean;
	blockBase: boolean;
	// A second finger, for pinch: tracked while the first one is down. It never presses a
	// widget; gestures read it (down2, x2, y2).
	secondId: int32;
	down2: boolean;
	x2: float32;
	y2: float32;
}

export function createUi(clearColor: Color): Ui {
	// Load the default font now: on Android and iOS only init runs inside the asset root, so
	// a font first touched by a frame's text() would not be found.
	faceFor(0 as int32);
	const sc = scene(clearColor);
	sc.setScaleMode(ScaleMode.LetterBox, DESIGN_W, DESIGN_H);
	const boxes = graphics();
	const texts = group();
	const boxesTop = graphics();
	const textsTop = group();
	sc.add(boxes);
	sc.add(texts);
	sc.add(boxesTop);
	sc.add(textsTop);
	return {
		sc: sc, boxes: boxes, texts: texts, labelIds: [], labelNodes: [], labelUsed: [],
		pointerId: NO_POINTER, down: false, x: 0.0, y: 0.0,
		pressed: false, pressX: 0.0, pressY: 0.0, released: false, releaseX: 0.0, releaseY: 0.0,
		activeId: NO_WIDGET,
		boxesTop: boxesTop, textsTop: textsTop, overlay: false, blockBase: false,
		secondId: NO_POINTER, down2: false, x2: 0.0, y2: 0.0,
	};
}

// The letterbox of sceneViewMatrix (ScaleMode.LetterBox), inverted: surface pixels → design.
function designScale(): float32 {
	const wf: float32 = (fbWidth() as float32) / dpiScale();
	const hf: float32 = (fbHeight() as float32) / dpiScale();
	return wf / DESIGN_W < hf / DESIGN_H ? wf / DESIGN_W : hf / DESIGN_H;
}

function toDesignX(px: float32): float32 {
	const r: float32 = designScale();
	const wf: float32 = (fbWidth() as float32) / dpiScale();
	const offset: float32 = (wf - DESIGN_W * r) * 0.5;
	return (px / dpiScale() - offset) / r;
}

function toDesignY(py: float32): float32 {
	const r: float32 = designScale();
	const hf: float32 = (fbHeight() as float32) / dpiScale();
	const offset: float32 = (hf - DESIGN_H * r) * 0.5;
	return (py / dpiScale() - offset) / r;
}

// Design units → surface pixels: where a native overlay (a Kotlin EditText over a sheet) has
// to sit, and how a scripted test places its touches.
export function designToSurfaceX(x: float32): float32 {
	const r: float32 = designScale();
	const wf: float32 = (fbWidth() as float32) / dpiScale();
	const offset: float32 = (wf - DESIGN_W * r) * 0.5;
	return (x * r + offset) * dpiScale();
}

export function designToSurfaceY(y: float32): float32 {
	const r: float32 = designScale();
	const hf: float32 = (fbHeight() as float32) / dpiScale();
	const offset: float32 = (hf - DESIGN_H * r) * 0.5;
	return (y * r + offset) * dpiScale();
}

export function beginUi(ui: Ui): void {
	ui.pressed = false;
	ui.released = false;
	for (const e of takePointerEvents()) {
		const ex: float32 = toDesignX(e.x);
		const ey: float32 = toDesignY(e.y);
		match (e.phase) {
			PointerPhase.Down => {
				if (ui.pointerId === NO_POINTER) {
					ui.pointerId = e.id;
					ui.down = true;
					ui.pressed = true;
					ui.pressX = ex;
					ui.pressY = ey;
					ui.x = ex;
					ui.y = ey;
				} else if (ui.secondId === NO_POINTER && e.id !== ui.pointerId) {
					ui.secondId = e.id;
					ui.down2 = true;
					ui.x2 = ex;
					ui.y2 = ey;
				}
			},
			PointerPhase.Move => {
				if (e.id === ui.pointerId) {
					ui.x = ex;
					ui.y = ey;
				} else if (e.id === ui.secondId) {
					ui.x2 = ex;
					ui.y2 = ey;
				}
			},
			PointerPhase.Up => {
				if (e.id === ui.pointerId) {
					ui.pointerId = NO_POINTER;
					ui.down = false;
					ui.released = true;
					ui.releaseX = ex;
					ui.releaseY = ey;
					ui.x = ex;
					ui.y = ey;
				} else if (e.id === ui.secondId) {
					ui.secondId = NO_POINTER;
					ui.down2 = false;
				}
			},
			PointerPhase.Cancel => {
				if (e.id === ui.pointerId) {
					ui.pointerId = NO_POINTER;
					ui.down = false;
					ui.activeId = NO_WIDGET;
				}
				if (e.id === ui.secondId) {
					ui.secondId = NO_POINTER;
					ui.down2 = false;
				}
			},
		};
	}
	ui.boxes.clear();
	ui.boxesTop.clear();
	ui.overlay = false;
	for (let i: int32 = 0; i < ui.labelUsed.length; i += 1) { ui.labelUsed[i] = false; }
}

export function endUi(ui: Ui): void {
	// A press released over nothing that claimed it ends here.
	if (ui.released) { ui.activeId = NO_WIDGET; }
	for (let i: int32 = 0; i < ui.labelNodes.length; i += 1) {
		ui.labelNodes[i].visible = ui.labelUsed[i];
	}
	ui.sc.present();
}

function inside(px: float32, py: float32, x: float32, y: float32, w: float32, h: float32): boolean {
	return px >= x && px < x + w && py >= y && py < y + h;
}

// Everything drawn between beginOverlay and endOverlay goes on the overlay layer.
export function beginOverlay(ui: Ui): void { ui.overlay = true; }
export function endOverlay(ui: Ui): void { ui.overlay = false; }

export function box(ui: Ui, x: float32, y: float32, w: float32, h: float32, radius: float32, color: Color): void {
	if (ui.overlay) { ui.boxesTop.fillRoundedRect(x, y, w, h, radius, color); }
	else { ui.boxes.fillRoundedRect(x, y, w, h, radius, color); }
}

// `align` places the text within `w`: 0 left, 0.5 centred, 1 right. void2d aligns a label
// around its own x (a line starts at x - width * align), so x moves to that point of the span.
export function text(ui: Ui, id: int32, s: string, x: float32, y: float32, w: float32, size: float32, color: Color, align: float32): void {
	let at: int32 = -1 as int32;
	for (let i: int32 = 0; i < ui.labelIds.length; i += 1) {
		if (ui.labelIds[i] === id) { at = i; }
	}
	if (at < 0) {
		const n = label(s, size, color);
		if (ui.overlay) { ui.textsTop.addChild(n); } else { ui.texts.addChild(n); }
		ui.labelIds.push(id);
		ui.labelNodes.push(n);
		ui.labelUsed.push(true);
		at = (ui.labelNodes.length - 1) as int32;
	}
	const n = ui.labelNodes[at];
	n.text = s;
	n.size = size;
	n.color = color;
	n.align = align;
	n.maxWidth = w;
	n.x = x + w * align;
	n.y = y;
	ui.labelUsed[at] = true;
}

// Held: the widget's own press, with the pointer still over it.
export function held(ui: Ui, id: int32, x: float32, y: float32, w: float32, h: float32): boolean {
	if (ui.blockBase && !ui.overlay) { return false; }
	return ui.activeId === id && ui.down && inside(ui.x, ui.y, x, y, w, h);
}

// Claims a press that starts inside the rectangle; true in the frame the press is released
// inside it again. Draws nothing: button() and custom widgets draw on top of it.
export function pressable(ui: Ui, id: int32, x: float32, y: float32, w: float32, h: float32): boolean {
	if (ui.blockBase && !ui.overlay) { return false; }
	if (ui.pressed && inside(ui.pressX, ui.pressY, x, y, w, h)) { ui.activeId = id; }
	if (ui.released && ui.activeId === id) {
		ui.activeId = NO_WIDGET;
		return inside(ui.releaseX, ui.releaseY, x, y, w, h);
	}
	return false;
}

export function button(ui: Ui, id: int32, x: float32, y: float32, w: float32, h: float32, caption: string, enabled: boolean): boolean {
	const clicked: boolean = pressable(ui, id, x, y, w, h) && enabled;
	let fill: Color = rgba(0.26, 0.29, 0.36, 1.0);
	if (!enabled) { fill = rgba(0.18, 0.19, 0.22, 1.0); }
	else if (held(ui, id, x, y, w, h)) { fill = rgba(0.42, 0.47, 0.58, 1.0); }
	ui.boxes.fillRoundedRect(x, y, w, h, 12.0, fill);
	const size: float32 = 18.0;
	let ink: Color = rgba(0.95, 0.96, 1.0, 1.0);
	if (!enabled) { ink = rgba(0.55, 0.57, 0.62, 1.0); }
	text(ui, id, caption, x, y + (h - size * 1.25) * 0.5, w, size, ink, 0.5);
	return clicked;
}
