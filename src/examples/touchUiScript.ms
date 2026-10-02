// Void — scripted run of the touch UI spike. Pushes synthetic touches into the same C queue
// the hosts feed (src/sokol/pointer.c), so everything from takePointerEvents to the demo's
// state is exercised in a real window without a mouse. Prints the state after each gesture,
// then exits.

import { initTouchUi, frameTouchUi, touchUiState } from "./touchUi";
import { designToSurfaceX, designToSurfaceY } from "../ui/ui";

@include("../sokol/bridge.h");
@include("../sokol/pointer.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;
extern function voidPointerPush(phase: int32, id: int32, x: float32, y: float32): void;

const DOWN: int32 = 0 as int32;
const MOVE: int32 = 1 as int32;
const UP: int32 = 2 as int32;
const FINGER: int32 = 0 as int32;

let frame: int32 = 0 as int32;

function touch(phase: int32, x: float32, y: float32): void {
	voidPointerPush(phase, FINGER, designToSurfaceX(x), designToSurfaceY(y));
}

function report(what: string): void {
	console.log(what + ": " + touchUiState());
}

function scripted(): void {
	frame = frame + 1;
	const f = frame;
	// Each gesture is pushed before this frame's UI runs, so the frame below sees it.
	if (f === 10 || f === 20 || f === 30 || f === 40) { touch(DOWN, 94.0, 686.0); }
	if (f === 12 || f === 22 || f === 32 || f === 42) { touch(UP, 94.0, 686.0); }
	if (f === 50) { touch(DOWN, 266.0, 686.0); }
	if (f === 52) { touch(UP, 266.0, 686.0); }
	// Press Talk, slide off it, lift elsewhere: no talk.
	if (f === 60) { touch(DOWN, 266.0, 686.0); }
	if (f === 62) { touch(MOVE, 266.0, 500.0); }
	if (f === 64) { touch(UP, 266.0, 500.0); }
	// Drag the pet by (+60, +96).
	if (f === 70) { touch(DOWN, 180.0, 374.0); }
	if (f === 72) { touch(MOVE, 200.0, 420.0); }
	if (f === 74) { touch(MOVE, 240.0, 470.0); }
	if (f === 76) { touch(UP, 240.0, 470.0); }
	// A tap shorter than a frame: down and up land in the same batch.
	if (f === 80) {
		touch(DOWN, 180.0, 744.0);
		touch(UP, 180.0, 744.0);
	}

	frameTouchUi();

	if (f === 1) { report("start"); }
	if (f === 12) { report("tap Feed"); }
	if (f === 22) { report("tap Feed"); }
	if (f === 32) { report("tap Feed"); }
	if (f === 42) { report("tap Feed while full"); }
	if (f === 52) { report("tap Talk"); }
	if (f === 64) { report("press Talk, lift off it"); }
	if (f === 76) { report("drag pet"); }
	if (f === 80) { report("one-frame tap Reset"); }
	if (f === 90) { process.exit(0); }
}

function main(): int32 {
	voidRun(405, 900, initTouchUi, scripted);
	return 0;
}

main();
