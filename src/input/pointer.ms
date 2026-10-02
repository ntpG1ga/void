// Void pointer input — the MetaScript side of src/sokol/pointer.c.
//
// Hosts push raw touch and mouse events into a C queue; once per frame, takePointerEvents()
// hands the whole batch over, in the order they happened. Coordinates are surface pixels,
// origin top-left. What was touched is not known here: the UI hit-tests (src/ui/ui.ms).

@include("../sokol/pointer.h");

extern function voidPointerTake(): int32;
extern function voidPointerPhase(i: int32): int32;
extern function voidPointerId(i: int32): int32;
extern function voidPointerX(i: int32): float32;
extern function voidPointerY(i: int32): float32;

export enum PointerPhase { Down, Move, Up, Cancel }

export struct PointerEvent {
	phase: PointerPhase;
	id: int32;
	x: float32;
	y: float32;
}

function phaseOf(raw: int32): PointerPhase {
	return match (raw) {
		0 => PointerPhase.Down,
		1 => PointerPhase.Move,
		2 => PointerPhase.Up,
		_ => PointerPhase.Cancel,
	};
}

export function takePointerEvents(): PointerEvent[] {
	const n: int32 = voidPointerTake();
	const events: PointerEvent[] = [];
	for (let i: int32 = 0; i < n; i += 1) {
		events.push({ phase: phaseOf(voidPointerPhase(i)), id: voidPointerId(i), x: voidPointerX(i), y: voidPointerY(i) });
	}
	return events;
}
