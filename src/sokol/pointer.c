// Void pointer queue — see pointer.h.

#include <stdatomic.h>

#include "pointer.h"

#define VOID_POINTER_CAP 128

typedef struct {
	int phase;
	int id;
	float x;
	float y;
} VoidPointerEvent;

static VoidPointerEvent s_pending[VOID_POINTER_CAP];
static int s_pendingCount;
static VoidPointerEvent s_frame[VOID_POINTER_CAP];
static int s_frameCount;
static atomic_flag s_lock = ATOMIC_FLAG_INIT;

static void lock(void) {
	while (atomic_flag_test_and_set_explicit(&s_lock, memory_order_acquire)) {}
}

static void unlock(void) { atomic_flag_clear_explicit(&s_lock, memory_order_release); }

void voidPointerPush(int phase, int id, float x, float y) {
	lock();
	// A move only says where the pointer is now, so consecutive moves of one pointer
	// collapse into the last. Down, up and cancel are never dropped by that; if the
	// queue is still full, the newest event is lost, never an older transition.
	VoidPointerEvent *last = s_pendingCount > 0 ? &s_pending[s_pendingCount - 1] : 0;
	if (phase == VOID_POINTER_MOVE && last && last->phase == VOID_POINTER_MOVE && last->id == id) {
		last->x = x;
		last->y = y;
	} else if (s_pendingCount < VOID_POINTER_CAP) {
		s_pending[s_pendingCount++] = (VoidPointerEvent){ phase, id, x, y };
	}
	unlock();
}

int voidPointerTake(void) {
	lock();
	for (int i = 0; i < s_pendingCount; i++) s_frame[i] = s_pending[i];
	s_frameCount = s_pendingCount;
	s_pendingCount = 0;
	unlock();
	return s_frameCount;
}

static const VoidPointerEvent *at(int i) {
	static const VoidPointerEvent none = { VOID_POINTER_CANCEL, -1, 0.0f, 0.0f };
	return (i >= 0 && i < s_frameCount) ? &s_frame[i] : &none;
}

int voidPointerPhase(int i) { return at(i)->phase; }
int voidPointerId(int i) { return at(i)->id; }
float voidPointerX(int i) { return at(i)->x; }
float voidPointerY(int i) { return at(i)->y; }
