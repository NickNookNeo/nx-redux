#include <stdio.h>
#include <string.h>

#include "ui_list.h"
#include "api.h"
#include "ui_buttonhintbar.h"
#include "ui_emptystate.h"
#include "ui_menubar.h"
#include "ui_iptv.h"
#include "ui_fonts.h"
#include "ui_toast.h"
#include "iptv.h"
#include "iptv_curated.h"

// Selection glide state (one per list surface)
static ListGlide iptv_user_glide;
static ListGlide iptv_country_glide;

// For the module's dirty-flag loops: keep redrawing while a pill glides
bool iptv_user_channels_glide_active(void) {
	return UI_listGlideActive(&iptv_user_glide);
}

bool iptv_curated_countries_glide_active(void) {
	return UI_listGlideActive(&iptv_country_glide);
}

// Render user's channel list (main screen)
void render_iptv_user_channels(SDL_Surface* screen, IndicatorType show_setting,
							   int selected, int scroll_offset,
							   ScrollTextState* scroll_state) {
	GFX_clear(screen);
	char truncated[256];

	UI_renderMenuBar(screen, "Online TV");

	int channel_count = IPTV_getUserChannelCount();
	const IPTVChannel* channels = IPTV_getUserChannels();

	ListLayout layout = UI_calcListLayout(screen);
	int scroll = scroll_offset;
	UI_adjustListScroll(selected, &scroll, layout.items_per_page);

	// Selection glide: draw the moving pill BEFORE row content; rows pass
	// selected=false and tint by pill position. Identity is the user channel
	// array pointer (single, stable context).
	ListGlideFrame gf = {layout.list_y, false};
	if (channel_count > 0) {
		int rows = layout.items_per_page;
		if (scroll + rows > channel_count)
			rows = channel_count - scroll;
		char sel_trunc[256];
		int sel_pill_w = UI_calcListPillWidth(font.medium, channels[selected].name,
											  sel_trunc, layout.max_width, 0);
		gf = UI_listGlideDraw(&iptv_user_glide, screen,
							  (const void*)channels,
							  selected - scroll, rows,
							  layout.list_y, layout.item_h,
							  sel_pill_w, true);
	}

	for (int i = 0; i < layout.items_per_page && (scroll + i) < channel_count; i++) {
		int idx = scroll + i;
		const IPTVChannel* ch = &channels[idx];
		int y = layout.list_y + i * layout.item_h;
		bool row_sel = UI_listGlideRowSelected(&gf, y, layout.item_h);

		ListItemPos pos = UI_renderListItemPill(screen, &layout, font.medium,
												ch->name, truncated,
												y, false, 0);

		// Marquee only once the pill has settled on this row
		UI_renderListItemText(screen,
							  (row_sel && !gf.animating) ? scroll_state : NULL,
							  ch->name, font.medium,
							  pos.text_x, pos.text_y,
							  pos.pill_width - SCALE1(BUTTON_PADDING * 2),
							  row_sel);
	}

	UI_renderScrollIndicators(screen, scroll, layout.items_per_page, channel_count);

	UI_renderButtonHintBar(screen, (char*[]){"MENU", "CONTROLS", "B", "BACK", "A", "PLAY", NULL});
}

// Render IPTV empty state (no channels added)
void render_iptv_empty(SDL_Surface* screen, IndicatorType show_setting) {
	GFX_clear(screen);
	UI_renderMenuBar(screen, "Online TV");
	UI_renderEmptyState(screen, "No channels saved",
						"Press Y to manage channels", "MANAGE");
}

// Render curated country list for browsing
void render_iptv_curated_countries(SDL_Surface* screen, IndicatorType show_setting,
								   int selected, int* scroll_offset) {
	GFX_clear(screen);

	int hw = screen->w;
	char truncated[256];

	UI_renderMenuBar(screen, "Browse Channels");

	int country_count = IPTV_curated_get_country_count();
	const CuratedTVCountry* countries = IPTV_curated_get_countries();

	ListLayout layout = UI_calcListLayout(screen);
	UI_adjustListScroll(selected, scroll_offset, layout.items_per_page);

	// Selection glide: moving pill drawn before row content; rows pass
	// selected=false and tint by pill position. Identity is the curated
	// country array pointer (single, stable context).
	ListGlideFrame gf = {layout.list_y, false};
	if (country_count > 0) {
		int rows = layout.items_per_page;
		if (*scroll_offset + rows > country_count)
			rows = country_count - *scroll_offset;
		char sel_trunc[256];
		int sel_pill_w = UI_calcListPillWidth(font.medium, countries[selected].name,
											  sel_trunc, layout.max_width, 0);
		gf = UI_listGlideDraw(&iptv_country_glide, screen,
							  (const void*)countries,
							  selected - *scroll_offset, rows,
							  layout.list_y, layout.item_h,
							  sel_pill_w, true);
	}

	for (int i = 0; i < layout.items_per_page && *scroll_offset + i < country_count; i++) {
		int idx = *scroll_offset + i;
		const CuratedTVCountry* country = &countries[idx];

		int y = layout.list_y + i * layout.item_h;
		bool row_sel = UI_listGlideRowSelected(&gf, y, layout.item_h);

		ListItemPos pos = UI_renderListItemPill(screen, &layout, font.medium,
												country->name, truncated,
												y, false, 0);

		UI_renderListItemText(screen, NULL, country->name, font.medium,
							  pos.text_x, pos.text_y, layout.max_width, row_sel);

		// Channel count on right
		int curated_ch_count = IPTV_curated_get_channel_count(country->code);
		char count_str[32];
		snprintf(count_str, sizeof(count_str), "%d channels", curated_ch_count);
		SDL_Color count_color = row_sel ? COLOR_GRAY : COLOR_DARK_TEXT;
		SDL_Surface* count_text = TTF_RenderUTF8_Blended(font.tiny, count_str, count_color);
		if (count_text) {
			SDL_BlitSurface(count_text, NULL, screen, &(SDL_Rect){hw - count_text->w - SCALE1(PADDING * 2), y + (layout.item_h - count_text->h) / 2});
			SDL_FreeSurface(count_text);
		}
	}

	UI_renderScrollIndicators(screen, *scroll_offset, layout.items_per_page, country_count);

	UI_renderButtonHintBar(screen, (char*[]){"B", "BACK", "A", "SELECT", NULL});
}

// Render curated channels for a country
void render_iptv_curated_channels(SDL_Surface* screen, IndicatorType show_setting,
								  const char* country_code,
								  int selected, int* scroll_offset,
								  const int* sorted_indices, int sorted_count,
								  const char* toast_message, uint32_t toast_time) {
	GFX_clear(screen);

	int hw = screen->w;
	char truncated[256];

	// Get country name for title
	const char* country_name = "Channels";
	const CuratedTVCountry* countries = IPTV_curated_get_countries();
	int country_count = IPTV_curated_get_country_count();
	for (int i = 0; i < country_count; i++) {
		if (strcmp(countries[i].code, country_code) == 0) {
			country_name = countries[i].name;
			break;
		}
	}

	UI_renderMenuBar(screen, country_name);

	int channel_count = 0;
	const CuratedTVChannel* channels = IPTV_curated_get_channels(country_code, &channel_count);

	ListLayout layout = UI_calcListLayout(screen);
	UI_adjustListScroll(selected, scroll_offset, layout.items_per_page);

	// Determine if the currently selected channel is already added
	bool selected_exists = false;
	if (sorted_count > 0 && selected < sorted_count) {
		int sel_actual = sorted_indices[selected];
		if (sel_actual < channel_count) {
			selected_exists = IPTV_userChannelExists(channels[sel_actual].url);
		}
	}

	for (int i = 0; i < layout.items_per_page && *scroll_offset + i < sorted_count; i++) {
		int idx = *scroll_offset + i;
		int actual_idx = sorted_indices[idx];
		const CuratedTVChannel* channel = &channels[actual_idx];
		bool is_selected = (idx == selected);
		bool added = IPTV_userChannelExists(channel->url);

		int y = layout.list_y + i * layout.item_h;

		// Calculate prefix width for added indicator
		int prefix_width = 0;
		if (added) {
			int pw, ph;
			TTF_SizeUTF8(font.small, "[+]", &pw, &ph);
			prefix_width = pw + SCALE1(6);
		}

		// Render pill background and get text position
		int name_max_width = layout.max_width - prefix_width - SCALE1(60);
		int text_width = GFX_truncateText(font.medium, channel->name, truncated, name_max_width, SCALE1(BUTTON_PADDING * 2));
		int pill_width = MIN(layout.max_width, prefix_width + text_width + SCALE1(BUTTON_PADDING));

		SDL_Rect pill_rect = {SCALE1(PADDING), y, pill_width, layout.item_h};
		Fonts_drawListItemBg(screen, &pill_rect, is_selected);

		int text_x = SCALE1(PADDING) + SCALE1(BUTTON_PADDING);
		int text_y = y + (layout.item_h - TTF_FontHeight(font.medium)) / 2;

		// Added indicator prefix
		if (added) {
			SDL_Color prefix_color = Fonts_getListTextColor(is_selected);
			SDL_Surface* prefix_text = TTF_RenderUTF8_Blended(font.small, "[+]", prefix_color);
			if (prefix_text) {
				SDL_BlitSurface(prefix_text, NULL, screen, &(SDL_Rect){text_x, y + (layout.item_h - prefix_text->h) / 2});
				SDL_FreeSurface(prefix_text);
			}
		}

		// Channel name
		UI_renderListItemText(screen, NULL, channel->name, font.medium,
							  text_x + prefix_width, text_y, name_max_width, is_selected);

		// Category on right
		if (channel->category[0]) {
			SDL_Color cat_color = is_selected ? COLOR_GRAY : COLOR_DARK_TEXT;
			SDL_Surface* cat_text = TTF_RenderUTF8_Blended(font.tiny, channel->category, cat_color);
			if (cat_text) {
				SDL_BlitSurface(cat_text, NULL, screen, &(SDL_Rect){hw - cat_text->w - SCALE1(PADDING * 2), y + (layout.item_h - cat_text->h) / 2});
				SDL_FreeSurface(cat_text);
			}
		}
	}

	UI_renderScrollIndicators(screen, *scroll_offset, layout.items_per_page, sorted_count);

	// Toast notification
	UI_renderToast(screen, toast_message, toast_time);

	// Button hints - dynamic based on whether selected channel is already added
	if (selected_exists) {
		UI_renderButtonHintBar(screen, (char*[]){"B", "BACK", "A", "REMOVE", NULL});
	} else {
		UI_renderButtonHintBar(screen, (char*[]){"B", "BACK", "A", "ADD", NULL});
	}
}
