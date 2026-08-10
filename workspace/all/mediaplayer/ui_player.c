#include <stdio.h>
#include <string.h>

#include "vp_defines.h"
#include "api.h"
#include "ui_buttonhintbar.h"
#include "ui_emptystate.h"
#include "ui_menubar.h"
#include "ui_player.h"
#include "ui_icons.h"
#include "ui_list.h"
#include "video_browser.h"

// Selection glide state (one per list surface)
static ListGlide browser_glide;

// For the module's dirty-flag loop: keep redrawing while a pill glides
bool browser_glide_active(void) {
	return UI_listGlideActive(&browser_glide);
}

// Build the display name shown for a browser entry (matches the row loop).
static void browser_entry_display(const VideoFileEntry* entry, char* out, size_t out_sz) {
	if (entry->is_dir) {
		if (Icons_isLoaded()) {
			strncpy(out, entry->name, out_sz - 1);
			out[out_sz - 1] = '\0';
		} else {
			snprintf(out, out_sz, "[%s]", entry->name);
		}
	} else {
		VideoBrowser_getDisplayName(entry->name, out, out_sz);
	}
}

// Render the video file browser
void render_video_browser(SDL_Surface* screen, IndicatorType show_setting,
						  VideoBrowserContext* ctx, ScrollTextState* scroll,
						  int selected_resume_sec) {
	GFX_clear(screen);

	char truncated[256];

	// Determine header title: "Videos" at root, or folder name in subdirectories
	const char* header_title = "Videos";
	if (strcmp(ctx->current_path, VIDEO_ROOT) != 0) {
		const char* slash = strrchr(ctx->current_path, '/');
		if (slash && slash[1] != '\0') {
			header_title = slash + 1;
		}
	}

	UI_renderMenuBar(screen, header_title);

	// Empty state: no videos at root
	if (ctx->entry_count == 0) {
		UI_renderEmptyState(screen, "No videos found",
							"Add videos to /Videos on your SD card", NULL);
		return;
	}

	// Calculate list layout
	ListLayout layout = UI_calcListLayout(screen);
	ctx->items_per_page = layout.items_per_page;

	// Adjust scroll to keep selected item visible
	UI_adjustListScroll(ctx->selected, &ctx->scroll_offset, ctx->items_per_page);

	// Icon dimensions
	int icon_size = Icons_isLoaded() ? SCALE1(24) : 0;
	int icon_spacing = Icons_isLoaded() ? SCALE1(6) : 0;
	int icon_offset = Icons_isLoaded() ? (icon_size + icon_spacing) : 0;

	// Selection glide: size the selected pill (icon prefix counts toward the
	// pill width, matching UI_renderListItemPill below), draw the moving pill
	// BEFORE row content; rows pass selected=false and tint by pill position.
	// Identity is the entries array pointer: entering a folder snaps.
	int rows = ctx->items_per_page;
	if (ctx->scroll_offset + rows > ctx->entry_count)
		rows = ctx->entry_count - ctx->scroll_offset;
	char sel_display[256];
	browser_entry_display(&ctx->entries[ctx->selected], sel_display, sizeof(sel_display));
	char sel_trunc[256];
	int sel_pill_w = UI_calcListPillWidth(font.medium, sel_display, sel_trunc,
										  layout.max_width, icon_offset);
	ListGlideFrame gf = UI_listGlideDraw(&browser_glide, screen,
										 (const void*)ctx->entries,
										 ctx->selected - ctx->scroll_offset, rows,
										 layout.list_y, layout.item_h,
										 sel_pill_w, true);

	// Render visible entries
	for (int i = 0; i < ctx->items_per_page && (ctx->scroll_offset + i) < ctx->entry_count; i++) {
		int idx = ctx->scroll_offset + i;
		VideoFileEntry* entry = &ctx->entries[idx];

		int y = layout.list_y + i * layout.item_h;
		bool row_sel = UI_listGlideRowSelected(&gf, y, layout.item_h);

		// Prepare display name
		char display[256];
		browser_entry_display(entry, display, sizeof(display));

		// Render pill background and get text position
		ListItemPos pos = UI_renderListItemPill(screen, &layout, font.medium, display, truncated,
												y, false, icon_offset);

		// Render icon
		if (Icons_isLoaded()) {
			SDL_Surface* icon = NULL;
			if (entry->is_dir) {
				icon = Icons_getFolder(row_sel);
			} else {
				icon = Icons_getForFormat(entry->format, row_sel);
			}
			if (icon) {
				int icon_y = y + (layout.item_h - icon_size) / 2;
				SDL_Rect src_rect = {0, 0, icon->w, icon->h};
				SDL_Rect dst_rect = {pos.text_x, icon_y, icon_size, icon_size};
				SDL_BlitScaled(icon, &src_rect, screen, &dst_rect);
			}
		}

		// Calculate text position (after icon if present)
		int text_x = pos.text_x + icon_offset;
		int available_width = pos.pill_width - SCALE1(BUTTON_PADDING * 2) - icon_offset;

		// Render text with scrolling for selected item (marquee only once the
		// pill has settled on this row)
		UI_renderListItemText(screen,
							  (row_sel && !gf.animating) ? scroll : NULL,
							  display, font.medium,
							  text_x, pos.text_y, available_width, row_sel);
	}

	// Scroll indicators (up/down arrows)
	UI_renderScrollIndicators(screen, ctx->scroll_offset, ctx->items_per_page, ctx->entry_count);

	// Button hints — offer Resume when the selected video has a saved position
	if (selected_resume_sec > 0) {
		char resume_label[32];
		int h = selected_resume_sec / 3600;
		int m = (selected_resume_sec % 3600) / 60;
		int s = selected_resume_sec % 60;
		if (h > 0)
			snprintf(resume_label, sizeof(resume_label), "RESUME %d:%02d:%02d", h, m, s);
		else
			snprintf(resume_label, sizeof(resume_label), "RESUME %d:%02d", m, s);
		UI_renderButtonHintBar(screen, (char*[]){"MENU", "CONTROLS", "B", "BACK", "X", resume_label, "A", "PLAY", NULL});
	} else {
		UI_renderButtonHintBar(screen, (char*[]){"MENU", "CONTROLS", "B", "BACK", "A", "OPEN", NULL});
	}
}
