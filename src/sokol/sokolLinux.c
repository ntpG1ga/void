// sokol implementation unit — Linux (GLES3 over EGL). Plain C, compiled by gpu.ms.
//
// GLES3 and not desktop GL, because shader.glsl.h is generated for
//   metal_macos:metal_ios:metal_sim:glsl300es:wgsl:hlsl5
// so glsl300es is the only GL variant in the tree. SOKOL_GLCORE would need a
// glsl410 variant added to that sokol-shdc line, which regenerates a header
// every other platform shares — a bigger change than this backend needs.
//
// sokol_app reaches GLES3 on Linux through EGL on its own: the _SAPP_LINUX
// branch of sokol_app.h selects EGL when SOKOL_GLES3 is defined, so
// SOKOL_FORCE_EGL (which only matters for SOKOL_GLCORE) is not set here.
#define SOKOL_IMPL
#define SOKOL_GLES3
#define SOKOL_NO_ENTRY
#include "sokol_gfx.h"
#include "sokol_app.h"
#include "sokol_log.h"
#include "sokol_glue.h"
