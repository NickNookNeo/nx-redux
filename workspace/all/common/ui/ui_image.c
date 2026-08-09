#include <stdio.h>
#include <stdlib.h>

#include "ui_image.h"

void UI_calcImageFit(int img_w, int img_h, int max_w, int max_h,
					 int* out_w, int* out_h) {
	double aspect_ratio = (double)img_h / img_w;
	int new_w = max_w;
	int new_h = (int)(new_w * aspect_ratio);

	if (new_h > max_h) {
		new_h = max_h;
		new_w = (int)(new_h / aspect_ratio);
	}

	*out_w = new_w;
	*out_h = new_h;
}

SDL_Surface* UI_convertSurface(SDL_Surface* surface, SDL_Surface* screen) {
	SDL_Surface* converted =
		SDL_ConvertSurfaceFormat(surface, screen->format->format, 0);
	if (converted) {
		SDL_FreeSurface(surface);
		return converted;
	}
	return surface;
}

// JPEG: ends with FF D9, PNG: ends with IEND chunk
bool UI_imageDataComplete(const uint8_t* data, size_t size) {
	if (size < 4)
		return false;
	// JPEG: starts with FF D8, ends with FF D9
	if (data[0] == 0xFF && data[1] == 0xD8) {
		return (data[size - 2] == 0xFF && data[size - 1] == 0xD9);
	}
	// PNG: starts with 89 50 4E 47, ends with IEND chunk (AE 42 60 82)
	if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
		return (size >= 8 &&
				data[size - 4] == 0xAE && data[size - 3] == 0x42 &&
				data[size - 2] == 0x60 && data[size - 1] == 0x82);
	}
	// Unknown format — assume complete
	return true;
}

SDL_Surface* UI_loadValidatedImage(const char* path, size_t max_bytes) {
	FILE* f = fopen(path, "rb");
	if (!f)
		return NULL;

	fseek(f, 0, SEEK_END);
	long fsize = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (fsize <= 0 || (size_t)fsize > max_bytes) {
		fclose(f);
		return NULL;
	}

	uint8_t* data = (uint8_t*)malloc(fsize);
	if (!data) {
		fclose(f);
		return NULL;
	}
	if ((long)fread(data, 1, fsize, f) != fsize) {
		free(data);
		fclose(f);
		return NULL;
	}
	fclose(f);

	if (!UI_imageDataComplete(data, fsize)) {
		free(data);
		remove(path); // Corrupt/incomplete — delete so it gets re-fetched
		return NULL;
	}

	SDL_RWops* rw = SDL_RWFromConstMem(data, fsize);
	SDL_Surface* raw = NULL;
	if (rw)
		raw = IMG_Load_RW(rw, 1);
	free(data);
	if (!raw) {
		remove(path);
		return NULL;
	}

	return raw;
}

// Convert+scale raw to size x size ARGB8888, then punch out either a
// circular mask or a per-corner rounded-rect mask.
static SDL_Surface* maskedFromSurface(SDL_Surface* raw, int size, int radius, bool circle) {
	if (!raw)
		return NULL;

	SDL_Surface* converted = SDL_ConvertSurfaceFormat(raw, SDL_PIXELFORMAT_ARGB8888, 0);
	if (!converted)
		return NULL;

	SDL_Surface* scaled = SDL_CreateRGBSurfaceWithFormat(0, size, size, 32, SDL_PIXELFORMAT_ARGB8888);
	if (!scaled) {
		SDL_FreeSurface(converted);
		return NULL;
	}
	SDL_Rect src = {0, 0, converted->w, converted->h};
	SDL_Rect dst = {0, 0, size, size};
	SDL_BlitScaled(converted, &src, scaled, &dst);
	SDL_FreeSurface(converted);

	uint32_t* pixels = (uint32_t*)scaled->pixels;
	int pitch = scaled->pitch / 4;

	if (circle) {
		int r = size / 2;
		for (int y = 0; y < size; y++) {
			for (int x = 0; x < size; x++) {
				int dx = x - r;
				int dy = y - r;
				if (dx * dx + dy * dy > r * r) {
					pixels[y * pitch + x] = 0; // Fully transparent
				}
			}
		}
	} else if (radius > 0) {
		if (radius > size / 2)
			radius = size / 2;
		for (int py = 0; py < size; py++) {
			for (int px = 0; px < size; px++) {
				int cx = -1, cy = -1;
				if (px < radius && py < radius) {
					cx = radius;
					cy = radius;
				} else if (px >= size - radius && py < radius) {
					cx = size - 1 - radius;
					cy = radius;
				} else if (px < radius && py >= size - radius) {
					cx = radius;
					cy = size - 1 - radius;
				} else if (px >= size - radius && py >= size - radius) {
					cx = size - 1 - radius;
					cy = size - 1 - radius;
				}
				if (cx >= 0 && (px - cx) * (px - cx) + (py - cy) * (py - cy) > radius * radius) {
					pixels[py * pitch + px] = 0; // fully transparent
				}
			}
		}
	}

	return scaled;
}

SDL_Surface* UI_roundedFromSurface(SDL_Surface* raw, int size, int radius) {
	return maskedFromSurface(raw, size, radius, false);
}

SDL_Surface* UI_circleFromSurface(SDL_Surface* raw, int size) {
	return maskedFromSurface(raw, size, 0, true);
}

SDL_Surface* UI_loadRoundedImage(const char* path, int size, int radius) {
	SDL_Surface* raw = IMG_Load(path);
	if (!raw)
		return NULL;

	SDL_Surface* result = UI_roundedFromSurface(raw, size, radius);
	SDL_FreeSurface(raw);
	return result;
}
