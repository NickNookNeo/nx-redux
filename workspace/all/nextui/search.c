#include "search.h"
#include "utils.h"
#include "config.h"
#include "content.h"
#include "defines.h"
#include "display_helper.h"
#include "gamelist.h"
#include "imgloader.h"
#include "launcher.h"
#include "types.h"
#include "ui_buttonhintbar.h"
#include "ui_message.h"
#include "ui_keyboard.h"
#include "ui_list.h"
#include "api.h"

#include <libgen.h>
#include <stdlib.h>
#include <string.h>

static Array* search_results = NULL;
static int search_selected = 0;
static int search_scroll = 0;
static ScrollTextState search_list_scroll = {0};
static ListGlide search_glide; // selection-pill glide for the results list

void Search_init(void) {
	search_results = NULL;
	search_selected = 0;
	search_scroll = 0;
}

void Search_quit(void) {
	if (search_results) {
		EntryArray_free(search_results);
		search_results = NULL;
	}
}

bool Search_open(void) {
	char* query = UIKeyboard_open("Search");
	PAD_poll();
	PAD_reset();

	if (!query || strlen(query) == 0) {
		if (query)
			free(query);
		return false;
	}

	// Free previous results
	if (search_results) {
		EntryArray_free(search_results);
		search_results = NULL;
	}

	search_results = Content_searchRoms(query);
	free(query);

	search_selected = 0;
	search_scroll = 0;
	memset(&search_list_scroll, 0, sizeof(search_list_scroll));
	// Snap the pill to the top on every new query: the result Array is
	// rebuilt per query so its pointer identity normally changes, but the
	// free-then-realloc could reuse the same address — reset defensively.
	memset(&search_glide, 0, sizeof(search_glide));

	return true;
}

SearchResult Search_handleInput(unsigned long now) {
	(void)now;
	SearchResult result = {0};
	result.screen = SCREEN_SEARCH;

	int total = search_results ? search_results->count : 0;

	if (PAD_justPressed(BTN_B)) {
		result.screen = SCREEN_GAMELIST;
		result.dirty = true;
		result.folderbgchanged = true;
		GFX_clearLayers(LAYER_SCROLLTEXT);
		ScrollText_clear(&search_list_scroll);
		return result;
	}

	if (total == 0)
		return result;

	int old_selected = search_selected;
	ListLayout layout = UI_calcListLayout(screen);
	int items_per_page = layout.items_per_page;

	if (PAD_justRepeated(BTN_UP)) {
		search_selected--;
		if (search_selected < 0)
			search_selected = total - 1;
	} else if (PAD_justRepeated(BTN_DOWN)) {
		search_selected++;
		if (search_selected >= total)
			search_selected = 0;
	} else if (PAD_justRepeated(BTN_LEFT)) {
		search_selected -= items_per_page;
		if (search_selected < 0)
			search_selected = 0;
	} else if (PAD_justRepeated(BTN_RIGHT)) {
		search_selected += items_per_page;
		if (search_selected >= total)
			search_selected = total - 1;
	}

	UI_adjustListScroll(search_selected, &search_scroll, items_per_page);

	if (search_selected != old_selected)
		result.dirty = true;

	if (PAD_justPressed(BTN_A) && total > 0) {
		Entry* entry = search_results->items[search_selected];
		Entry_open(entry);
		result.startgame = true;
		result.dirty = true;
	}

	return result;
}

void Search_render(SDL_Surface* screen, int lastScreen) {
	if (lastScreen != SCREEN_SEARCH) {
		onBackgroundLoaded(NULL);
		GFX_clearLayers(LAYER_THUMBNAIL);
		// we just cleared the shared folder background; make the game list
		// reload it on return instead of trusting its stale change-detection
		GameList_invalidateBackground();
	}

	int total = search_results ? search_results->count : 0;

	// Button hints
	{
		char* hints[5] = {NULL};
		int hi = 0;
		hints[hi++] = "B";
		hints[hi++] = "BACK";
		if (total > 0) {
			hints[hi++] = "A";
			hints[hi++] = "OPEN";
		}
		hints[hi] = NULL;
		UI_renderButtonHintBar(screen, hints);
	}

	if (total == 0) {
		UI_renderCenteredMessage(screen, "No results");
		return;
	}

	bool had_thumb = false;
	int ox = screen->w;

	if (CFG_getShowGameArt()) {
		Entry* selected_entry = search_results->items[search_selected];

		char thumbpath[1024];
		ROM_mediaArtPath(selected_entry->path, thumbpath, sizeof(thumbpath));
		had_thumb = startLoadThumb(thumbpath);
		int max_w = (int)(screen->w - (screen->w * CFG_getGameArtWidth()));
		if (had_thumb)
			ox = (int)(max_w)-SCALE1(BUTTON_MARGIN * 5);
	}

	ListLayout layout = UI_calcListLayout(screen);
	int items_per_page = layout.items_per_page;

	UI_adjustListScroll(search_selected, &search_scroll, items_per_page);

	// The thumbnail width adjustment is uniform across all rows, so apply it
	// once up front and both the pre-pass and the row loop share it.
	if (had_thumb)
		layout.max_width = MAX(0, ox + SCALE1(BUTTON_MARGIN) - SCALE1(PADDING * 2));

	// Selection glide: size the selected pill and draw the moving pill BEFORE
	// the row content; rows then pass selected=false and tint their text by
	// pill position. The selected row's name is trimmed and sized with the
	// same max_width the loop uses.
	int rows = items_per_page;
	if (search_scroll + rows > total)
		rows = total - search_scroll;
	char* sel_name = ((Entry*)search_results->items[search_selected])->name;
	trimSortingMeta(&sel_name);
	char sel_trunc[256];
	int sel_pill_w = UI_calcListPillWidth(font.large, sel_name, sel_trunc,
										  layout.max_width, 0);
	ListGlideFrame gf = UI_listGlideDraw(&search_glide, screen,
										 (const void*)search_results,
										 search_selected - search_scroll, rows,
										 layout.list_y, layout.item_h,
										 sel_pill_w, true);

	for (int i = 0; i < items_per_page && (search_scroll + i) < total; i++) {
		int idx = search_scroll + i;
		Entry* entry = search_results->items[idx];
		char* entry_name = entry->name;

		trimSortingMeta(&entry_name);

		int y = layout.list_y + i * layout.item_h;
		bool row_sel = UI_listGlideRowSelected(&gf, y, layout.item_h);

		char truncated[256];
		ListItemPos pos = UI_renderListItemPill(
			screen, &layout, font.large,
			entry_name, truncated, y, false, 0);
		int text_width = pos.pill_width - SCALE1(BUTTON_PADDING * 2);
		UI_renderListItemText(screen,
							  (row_sel && !gf.animating) ? &search_list_scroll : NULL,
							  entry_name, font.large,
							  pos.text_x, pos.text_y, text_width, row_sel);
	}

	UI_renderScrollIndicators(screen, search_scroll, items_per_page, total);
}

// True while the results-list selection pill is mid-glide — nextui.c keeps
// the screen dirty until it settles (same contract as GameList_pillAnimating).
bool Search_pillAnimating(void) {
	return UI_listGlideActive(&search_glide);
}

// Marquee driving for the results list, mirroring GameList_scrollBusy /
// GameList_scrollTickIdle: renders stop once the screen settles, so
// nextui.c's idle loop must keep ticking the selected row's scroll-text
// (activate after the 1s delay, then animate) or a long name never scrolls.
bool Search_scrollBusy(void) {
	return ScrollText_isScrolling(&search_list_scroll) ||
		   ScrollText_needsRender(&search_list_scroll);
}

void Search_scrollTickIdle(void) {
	ScrollText_activateAfterDelay(&search_list_scroll);
	if (ScrollText_isScrolling(&search_list_scroll))
		ScrollText_animateOnly(&search_list_scroll);
}
