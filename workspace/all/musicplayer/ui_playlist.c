#include <stdio.h>
#include <string.h>

#include "defines.h"
#include "api.h"
#include "ui_buttonhintbar.h"
#include "ui_emptystate.h"
#include "ui_menubar.h"
#include "ui_playlist.h"
#include "ui_icons.h"
#include "ui_list.h"

// Scroll text state for selected item in playlist lists
static ScrollTextState playlist_scroll = {0};

// Selection glide state (one per list surface)
static ListGlide playlist_list_glide;
static ListGlide playlist_detail_glide;

// For the module's dirty-flag loop: keep redrawing while a pill glides
bool playlist_list_glide_active(void) {
	return UI_listGlideActive(&playlist_list_glide);
}

bool playlist_detail_glide_active(void) {
	return UI_listGlideActive(&playlist_detail_glide);
}

void render_playlist_list(SDL_Surface* screen, IndicatorType show_setting,
						  PlaylistInfo* playlists, int count,
						  int selected, int scroll) {
	GFX_clear(screen);

	int hw = screen->w;
	int hh = screen->h;
	char truncated[256];

	UI_renderMenuBar(screen, "Playlists");

	// Empty state - no playlists
	if (count == 0) {
		UI_renderEmptyState(screen, "No playlists saved", "Press Y to create a playlist", "NEW");
		return;
	}

	ListLayout layout = UI_calcListLayout(screen);

	// Selection glide: size the selected pill (same "%s (%d)" display the
	// row loop builds), draw the moving pill BEFORE row content; rows pass
	// selected=false and tint by pill position.
	int rows = layout.items_per_page;
	if (scroll + rows > count)
		rows = count - scroll;
	char sel_display[256];
	snprintf(sel_display, sizeof(sel_display), "%s (%d)",
			 playlists[selected].name, playlists[selected].track_count);
	char sel_trunc[256];
	int sel_pill_w = UI_calcListPillWidth(font.medium, sel_display, sel_trunc,
										  layout.max_width, 0);
	ListGlideFrame gf = UI_listGlideDraw(&playlist_list_glide, screen,
										 (const void*)playlists,
										 selected - scroll, rows,
										 layout.list_y, layout.item_h,
										 sel_pill_w, true);

	for (int i = 0; i < layout.items_per_page && (scroll + i) < count; i++) {
		int idx = scroll + i;
		int y = layout.list_y + i * layout.item_h;
		bool row_sel = UI_listGlideRowSelected(&gf, y, layout.item_h);

		PlaylistInfo* pl = &playlists[idx];
		char display[256];
		snprintf(display, sizeof(display), "%s (%d)", pl->name, pl->track_count);

		ListItemPos pos = UI_renderListItemPill(screen, &layout, font.medium, display, truncated, y, false, 0);
		int available_width = pos.pill_width - SCALE1(BUTTON_PADDING * 2);
		// Marquee only once the pill has settled on this row
		UI_renderListItemText(screen,
							  (row_sel && !gf.animating) ? &playlist_scroll : NULL,
							  display, font.medium,
							  pos.text_x, pos.text_y, available_width, row_sel);
	}

	UI_renderScrollIndicators(screen, scroll, layout.items_per_page, count);

	UI_renderButtonHintBar(screen, (char*[]){"MENU", "CONTROLS", "B", "BACK", "A", "SELECT", NULL});
}

void render_playlist_detail(SDL_Surface* screen, IndicatorType show_setting,
							const char* playlist_name,
							PlaylistTrack* tracks, int count,
							int selected, int scroll) {
	GFX_clear(screen);

	int hw = screen->w;
	int hh = screen->h;
	char truncated[256];

	char title[300];
	snprintf(title, sizeof(title), "Playlist %s", playlist_name);
	UI_renderMenuBar(screen, title);

	// Empty state
	if (count == 0) {
		UI_renderEmptyState(screen, "No tracks in playlist", "Add tracks from the music browser", NULL);
		return;
	}

	ListLayout layout = UI_calcListLayout(screen);

	// Icon size and spacing (same as browser)
	int icon_size = Icons_isLoaded() ? SCALE1(24) : 0;
	int icon_spacing = Icons_isLoaded() ? SCALE1(6) : 0;
	int icon_offset = icon_size + icon_spacing;

	// Selection glide: moving pill drawn before row content (icon prefix
	// counts toward the pill width, matching UI_renderListItemPill below)
	int rows = layout.items_per_page;
	if (scroll + rows > count)
		rows = count - scroll;
	char sel_trunc[256];
	int sel_pill_w = UI_calcListPillWidth(font.medium, tracks[selected].name,
										  sel_trunc, layout.max_width,
										  icon_offset);
	// Identity: the playlist's name pointer, NOT the tracks array — the
	// module refills one static tracks buffer in place for every playlist,
	// so the array pointer never changes. The name pointer differs per
	// playlist entry, making a playlist switch snap instead of glide.
	ListGlideFrame gf = UI_listGlideDraw(&playlist_detail_glide, screen,
										 (const void*)playlist_name,
										 selected - scroll, rows,
										 layout.list_y, layout.item_h,
										 sel_pill_w, true);

	for (int i = 0; i < layout.items_per_page && (scroll + i) < count; i++) {
		int idx = scroll + i;
		int y = layout.list_y + i * layout.item_h;
		bool row_sel = UI_listGlideRowSelected(&gf, y, layout.item_h);

		char display[256];
		PlaylistTrack* track = &tracks[idx];
		snprintf(display, sizeof(display), "%s", track->name);

		ListItemPos pos = UI_renderListItemPill(screen, &layout, font.medium, display, truncated, y, false, icon_offset);

		// Render icon
		if (Icons_isLoaded()) {
			SDL_Surface* icon = Icons_getForFormat(tracks[idx].format, row_sel);
			if (icon) {
				int icon_y = y + (layout.item_h - icon_size) / 2;
				SDL_Rect src_rect = {0, 0, icon->w, icon->h};
				SDL_Rect dst_rect = {pos.text_x, icon_y, icon_size, icon_size};
				SDL_BlitScaled(icon, &src_rect, screen, &dst_rect);
			}
		}

		int text_x = pos.text_x + icon_offset;
		int available_width = pos.pill_width - SCALE1(BUTTON_PADDING * 2) - icon_offset;
		// Marquee only once the pill has settled on this row
		UI_renderListItemText(screen,
							  (row_sel && !gf.animating) ? &playlist_scroll : NULL,
							  display, font.medium,
							  text_x, pos.text_y, available_width, row_sel);
	}

	UI_renderScrollIndicators(screen, scroll, layout.items_per_page, count);
}

bool playlist_list_needs_scroll_refresh(void) {
	return ScrollText_isScrolling(&playlist_scroll);
}

bool playlist_list_scroll_needs_render(void) {
	return ScrollText_needsRender(&playlist_scroll);
}

void playlist_list_animate_scroll(void) {
	ScrollText_animateOnly(&playlist_scroll);
}
