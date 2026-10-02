// Void — Android entry for hibernal's walker scene; build with
// ENTRY=src/examples/androidWalkerEntry.ms (after scripts/sync-hibernal-assets.py).

import { initWalker, frameWalker } from "./walkerScene";

@include("../sokol/bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

function registerVoid(): void {
	voidEmbedRegister(initWalker, frameWalker);
}

registerVoid();
