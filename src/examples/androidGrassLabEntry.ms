// Void — Android entry for the grass lab (the night campfire with grass, wind and the walker);
// build with ENTRY=src/examples/androidGrassLabEntry.ms.

import { initLab, frameLab } from "./grassLabScene";

@include("../sokol/bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

function registerVoid(): void {
	voidEmbedRegister(initLab, frameLab);
}

registerVoid();
