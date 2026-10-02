// Void sokol bridge — Linux. Drives one sokol_app window; the gfx resource and
// frame wrappers are shared and live in bridge.c.
//
// Linux has ONE driver, the sokol_app window. Windows and Android additionally
// carry a host-view driver (views.c plus their voidPlatform* hooks) so a host
// app can embed Void in its own HWND / SurfaceView; nothing on Linux asks for
// that yet, so views.c is deliberately not compiled here and the embed half of
// bridge.h has no implementation. gpu.ms matches: its voidView*/voidEmbed*
// externs sit behind `when (windows || ios || android)`, so MetaScript cannot
// reach them on this target.
//
// That also means the DRIVER_WINDOW / DRIVER_VIEWS switch the other bridges
// need collapses to a single "has voidRun chosen the window yet" flag.

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "bridge.h"
#include "pointer.h"
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"
#include "sokol_log.h"

// views.c owns voidFail on the platforms that compile it. Linux does not, so the
// one definition lives here — same contract: print to stderr and abort, never
// return, so a caller reading a half-set-up driver stops at the cause.
__attribute__((noreturn)) void voidFail(const char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	fputs("void: ", stderr);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
	abort();
}

__attribute__((noreturn)) static void noDriver(const char *op) {
	voidFail("%s before voidRun chose a driver", op);
}

static bool s_window;
static msClosure s_init;
static msClosure s_frame;
static bool s_keys[SAPP_MAX_KEYCODES];

// A MetaScript closure is { fn, env }; a lifted function with no captures has a
// null env and a plain C signature. Same shape the other bridges call.
static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static void _init(void) { call0(s_init); }
static void _frame(void) { call0(s_frame); }

// The left mouse button stands in for one finger (id 0), so a touch UI can be driven on the
// desktop; real touches keep sokol's identifiers. Moves are only reported while the button
// is held: hover means nothing to a touch screen.
static bool s_mouseDown;

static void pushTouches(const sapp_event *e, int phase) {
	for (int i = 0; i < e->num_touches; i++) {
		const sapp_touchpoint *t = &e->touches[i];
		if (t->changed) voidPointerPush(phase, (int)t->identifier, t->pos_x, t->pos_y);
	}
}

static void _event(const sapp_event *e) {
	switch (e->type) {
	case SAPP_EVENTTYPE_KEY_DOWN:
		if (e->key_code == SAPP_KEYCODE_ESCAPE) sapp_request_quit();
		s_keys[e->key_code] = true;
		break;
	case SAPP_EVENTTYPE_KEY_UP:
		s_keys[e->key_code] = false;
		break;
	case SAPP_EVENTTYPE_MOUSE_DOWN:
		if (e->mouse_button != SAPP_MOUSEBUTTON_LEFT) break;
		s_mouseDown = true;
		voidPointerPush(VOID_POINTER_DOWN, 0, e->mouse_x, e->mouse_y);
		break;
	case SAPP_EVENTTYPE_MOUSE_MOVE:
		if (s_mouseDown) voidPointerPush(VOID_POINTER_MOVE, 0, e->mouse_x, e->mouse_y);
		break;
	case SAPP_EVENTTYPE_MOUSE_UP:
		if (e->mouse_button != SAPP_MOUSEBUTTON_LEFT || !s_mouseDown) break;
		s_mouseDown = false;
		voidPointerPush(VOID_POINTER_UP, 0, e->mouse_x, e->mouse_y);
		break;
	case SAPP_EVENTTYPE_TOUCHES_BEGAN: pushTouches(e, VOID_POINTER_DOWN); break;
	case SAPP_EVENTTYPE_TOUCHES_MOVED: pushTouches(e, VOID_POINTER_MOVE); break;
	case SAPP_EVENTTYPE_TOUCHES_ENDED: pushTouches(e, VOID_POINTER_UP); break;
	case SAPP_EVENTTYPE_TOUCHES_CANCELLED: pushTouches(e, VOID_POINTER_CANCEL); break;
	default: break;
	}
}

static void _cleanup(void) { sg_shutdown(); }

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_window) voidFail("voidRun: this process already runs a sokol_app window");
	s_window = true;
	s_init = init;
	s_frame = frame;
	sapp_desc d = {0};
	d.init_cb = _init;
	d.frame_cb = _frame;
	d.event_cb = _event;
	d.cleanup_cb = _cleanup;
	d.width = w;
	d.height = h;
	d.sample_count = sampleCount;
	d.high_dpi = highDpi != 0;
	d.window_title = "Void — sokol";
	d.logger.func = slog_func;
	sapp_run(&d);
}

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 4, 1, init, frame);
}

void voidGfxSetup(void) {
	if (!s_window) noDriver("gfxSetup");
	sg_desc d = {0};
	d.environment = sglue_environment();
	d.logger.func = slog_func;
	// A mesh is two buffers, and a glTF scene is one mesh per node: hibernal's hills, pillars,
	// logs and walker are 64 meshes, which alone fill sokol's default pool of 128.
	d.buffer_pool_size = 1024;
	// the UI kit makes a texture per frame size + seed + look and one per icon
	d.image_pool_size = 1024;
	d.view_pool_size = 1024;
	sg_setup(&d);
}

int voidFbWidth(void) {
	if (!s_window) noDriver("fbWidth");
	return sapp_width();
}

int voidFbHeight(void) {
	if (!s_window) noDriver("fbHeight");
	return sapp_height();
}

float voidDpiScale(void) {
	if (!s_window) noDriver("dpiScale");
	return sapp_dpi_scale();
}

int voidKeyDown(int keycode) {
	if (!s_window || keycode < 0 || keycode >= SAPP_MAX_KEYCODES) return 0;
	return s_keys[keycode] ? 1 : 0;
}

sg_swapchain voidDriverSwapchain(void) {
	if (!s_window) noDriver("beginPass");
	return sglue_swapchain();
}

// sokol_app presents the window itself after the frame callback; only the
// host-view driver has a surface to present by hand.
void voidDriverPresent(void) {}
