// Void — desktop entry for hibernal's walker scene, in a 360×800 portrait window.

import { initWalker, frameWalker } from "./walkerScene";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(360, 800, initWalker, frameWalker);
	return 0;
}

main();
