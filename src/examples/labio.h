// Grass lab on void: the little the entry needs from C - read the exported data files, read an
// integer from the environment, and save the frame just drawn as a PNG (GL, after commit).
#ifndef GRASS_LAB_IO_H
#define GRASS_LAB_IO_H

#include <stdint.h>

// -1 when the file cannot be opened.
int64_t labFileSize(const char *path);
// float32 / uint32 read into `out` (at most `length` elements); the count read. The array
// comes first and const: msc expands a Span only into a `const T *, int64_t` pair (the
// data is written anyway - the Vec behind it is ours).
int64_t labReadFloats(const float *out, int64_t length, const char *path);
int64_t labReadWords(const uint32_t *out, int64_t length, const char *path);
int32_t labEnvInt(const char *name, int32_t fallback);
// The default framebuffer as a binary PPM, top row first; 1 on success.
int32_t labCapture(const char *path);
void labExit(int32_t code);

#endif
