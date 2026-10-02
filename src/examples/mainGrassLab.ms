// Void — desktop entry for the grass lab, in a 360×800 portrait window.

import { initLab, frameLab } from "./grassLabScene";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

function main(): int32 {
	voidRun(360, 800, initLab, frameLab);
	return 0;
}

main();
