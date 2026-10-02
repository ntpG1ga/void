// Void pointer queue — touch and mouse, one shape for every host.
//
// The OS hit-tests nothing for us: everything is drawn into one surface, so all a host can
// report is "a pointer went down / moved / went up at (x, y) on your surface". Hosts push
// those raw events here (sokol_app's event callback on Linux, the Kotlin touch listener
// through JNI on Android); MetaScript takes the whole batch once per frame and does the
// hit-testing itself (src/input/pointer.ms, src/ui/ui.ms).
//
// Coordinates are surface pixels, origin top-left: what sokol_app and MotionEvent both give.
// Pushes may come from another thread than the frame (Android: UI thread vs render thread),
// so push and take are guarded; reads after a take touch only the frame's own copy.
#ifndef VOID_POINTER_H
#define VOID_POINTER_H

enum {
	VOID_POINTER_DOWN = 0,
	VOID_POINTER_MOVE = 1,
	VOID_POINTER_UP = 2,
	VOID_POINTER_CANCEL = 3,
};

void voidPointerPush(int phase, int id, float x, float y);

// Moves every pushed event into the frame's batch and returns how many there are. The
// batch stays readable through the getters below until the next take.
int voidPointerTake(void);
int voidPointerPhase(int i);
int voidPointerId(int i);
float voidPointerX(int i);
float voidPointerY(int i);

#endif
