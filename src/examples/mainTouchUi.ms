// Void — desktop entry for the touch UI spike. Left mouse stands in for one finger.

import { initTouchUi, frameTouchUi } from "./touchUi";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(405, 900, initTouchUi, frameTouchUi);
	return 0;
}

main();
