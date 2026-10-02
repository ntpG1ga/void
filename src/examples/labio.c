// The frame is read back the way void's tests/capture/capture.c does it: glReadPixels on
// Linux (GLES3, the default build), the swapchain's staging copy on Windows (D3D11).
#include "labio.h"
#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
	#define COBJMACROS
	#include <d3d11.h>
	#include <dxgi.h>
	const void *sg_d3d11_device(void);
	const void *sg_d3d11_device_context(void);
	const void *sapp_d3d11_get_swap_chain(void);
	static const GUID LAB_TEXTURE2D_IID =
		{0x6f15aaf2, 0xd208, 0x4e89, {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}};
#else
	#include <GLES3/gl3.h>
	int voidFbWidth(void);
	int voidFbHeight(void);
#endif

int64_t labFileSize(const char *path) {
	FILE *f = fopen(path, "rb");
	if (!f) return -1;
	fseek(f, 0, SEEK_END);
	long size = ftell(f);
	fclose(f);
	return (int64_t)size;
}

static int64_t readInto(const char *path, void *out, int64_t elementSize, int64_t length) {
	FILE *f = fopen(path, "rb");
	if (!f) return 0;
	size_t got = fread(out, (size_t)elementSize, (size_t)length, f);
	fclose(f);
	return (int64_t)got;
}

int64_t labReadFloats(const float *out, int64_t length, const char *path) { return readInto(path, (void *)out, 4, length); }
int64_t labReadWords(const uint32_t *out, int64_t length, const char *path) { return readInto(path, (void *)out, 4, length); }

int32_t labEnvInt(const char *name, int32_t fallback) {
	const char *value = getenv(name);
	return value ? (int32_t)atoi(value) : fallback;
}

// Binary PPM (P6), top row first; ppm2png.py turns it into a PNG.
int32_t labCapture(const char *path) {
#if defined(_WIN32)
	ID3D11Device *device = (ID3D11Device *)sg_d3d11_device();
	ID3D11DeviceContext *context = (ID3D11DeviceContext *)sg_d3d11_device_context();
	IDXGISwapChain *swapChain = (IDXGISwapChain *)sapp_d3d11_get_swap_chain();
	if (!swapChain || !device || !context) return 0;
	ID3D11Texture2D *back = NULL;
	if (FAILED(IDXGISwapChain_GetBuffer(swapChain, 0, &LAB_TEXTURE2D_IID, (void **)&back))) return 0;
	D3D11_TEXTURE2D_DESC desc;
	ID3D11Texture2D_GetDesc(back, &desc);
	desc.Usage = D3D11_USAGE_STAGING;
	desc.BindFlags = 0;
	desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
	desc.MiscFlags = 0;
	ID3D11Texture2D *staging = NULL;
	if (FAILED(ID3D11Device_CreateTexture2D(device, &desc, NULL, &staging))) {
		ID3D11Texture2D_Release(back);
		return 0;
	}
	ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)back);
	D3D11_MAPPED_SUBRESOURCE mapped;
	int ok = 0;
	if (SUCCEEDED(ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped))) {
		FILE *f = fopen(path, "wb");
		if (f) {
			fprintf(f, "P6\n%u %u\n255\n", desc.Width, desc.Height);
			uint8_t *line = (uint8_t *)malloc((size_t)desc.Width * 3);
			for (UINT y = 0; line && y < desc.Height; y++) {
				const uint8_t *row = (const uint8_t *)mapped.pData + (size_t)y * mapped.RowPitch;
				for (UINT x = 0; x < desc.Width; x++) {   // BGRA -> RGB
					line[x * 3 + 0] = row[x * 4 + 2];
					line[x * 3 + 1] = row[x * 4 + 1];
					line[x * 3 + 2] = row[x * 4 + 0];
				}
				fwrite(line, 1, (size_t)desc.Width * 3, f);
			}
			free(line);
			fclose(f);
			ok = 1;
		}
		ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
	}
	ID3D11Texture2D_Release(staging);
	ID3D11Texture2D_Release(back);
	return ok;
#else
	int w = voidFbWidth(), h = voidFbHeight();
	uint8_t *rgba = (uint8_t *)malloc((size_t)w * h * 4);
	if (!rgba) return 0;
	glPixelStorei(GL_PACK_ALIGNMENT, 1);
	glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
	FILE *f = fopen(path, "wb");
	if (!f) { free(rgba); return 0; }
	fprintf(f, "P6\n%d %d\n255\n", w, h);
	for (int y = h - 1; y >= 0; y--) {      // GL hands back the bottom row first
		for (int x = 0; x < w; x++) fwrite(rgba + ((size_t)y * w + x) * 4, 1, 3, f);
	}
	fclose(f);
	free(rgba);
	return 1;
#endif
}

void labExit(int32_t code) { exit(code); }
