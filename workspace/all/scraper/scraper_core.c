#include "scraper_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "utils.h"
#include "scraper_api.h"
#include "scraper_compositor.h"

ScrapeResult scrapeOne(const char* filename, const char* rom_path, int system_id,
					   const char* out_png, ScrapeProgressCb cb, void* userdata) {
	mkdir_p(TMP_DIR);

	if (cb)
		cb("searching", userdata);
	ScraperGameInfo info;
	if (!ScraperAPI_search(filename, rom_path, system_id, &info))
		return SCRAPE_RESULT_NOTFOUND;

	if (cb)
		cb("downloading", userdata);
	char ss_path[512] = "", box_path[512] = "", wheel_path[512] = "";
	bool has_ss = false, has_box = false, has_wheel = false;
	if (info.screenshot_url[0]) {
		snprintf(ss_path, sizeof(ss_path), "%s/screenshot.png", TMP_DIR);
		has_ss = ScraperAPI_downloadFile(info.screenshot_url, ss_path);
	}
	if (info.boxart_url[0]) {
		snprintf(box_path, sizeof(box_path), "%s/boxart.png", TMP_DIR);
		has_box = ScraperAPI_downloadFile(info.boxart_url, box_path);
	}
	if (info.wheel_url[0]) {
		snprintf(wheel_path, sizeof(wheel_path), "%s/wheel.png", TMP_DIR);
		has_wheel = ScraperAPI_downloadFile(info.wheel_url, wheel_path);
	}
	if (!has_ss && !has_box && !has_wheel)
		return SCRAPE_RESULT_NOTFOUND;

	if (cb)
		cb("compositing", userdata);
	SDL_Surface* artwork = Compositor_create(
		has_ss ? ss_path : NULL, has_box ? box_path : NULL, has_wheel ? wheel_path : NULL);
	if (has_ss)
		remove(ss_path);
	if (has_box)
		remove(box_path);
	if (has_wheel)
		remove(wheel_path);
	if (!artwork)
		return SCRAPE_RESULT_ERROR;

	// ensure the .media directory of out_png exists
	char media_dir[512];
	snprintf(media_dir, sizeof(media_dir), "%s", out_png);
	char* slash = strrchr(media_dir, '/');
	if (slash) {
		*slash = '\0';
		mkdir_p(media_dir);
	}

	bool saved = Compositor_savePNG(artwork, out_png);
	SDL_FreeSurface(artwork);
	return saved ? SCRAPE_RESULT_OK : SCRAPE_RESULT_ERROR;
}
