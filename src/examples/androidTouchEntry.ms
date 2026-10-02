// Void — Android entry for the touch UI spike. The Kotlin shell forwards MotionEvents through
// VoidNative.touch into the pointer queue; build with ENTRY=src/examples/androidTouchEntry.ms.

import { initTouchUi, frameTouchUi } from "./touchUi";

@include("../sokol/bridge.h");
extern function voidEmbedRegister(init: () => void, frame: () => void): void;

function registerVoid(): void {
	voidEmbedRegister(initTouchUi, frameTouchUi);
}

registerVoid();
