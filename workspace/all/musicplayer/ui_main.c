#include <stdio.h>
#include <string.h>
#include "defines.h"
#include "api.h"
#include "ui_main.h"
#include "ui_controlshelp.h"
#include "ui_listview.h"
#include "ui_toast.h"
#include "module_menu.h"
#include "resume.h"
#include "background.h"

// Menu items variants (first entry is mutable for Resume/Now Playing swap)
static const char* menu_items_with_first[] = {"Resume", "Library", "Online Radio", "Podcasts", "Settings"};
static const char* menu_items_no_first[] = {"Library", "Online Radio", "Podcasts", "Settings"};

// Cached first_item_mode for callbacks
static int current_first_item_mode = MENU_FIRST_NONE;

// Get label for Now Playing based on background player type
static const char* get_now_playing_label(void) {
	switch (Background_getActive()) {
	case BG_MUSIC:
		return "Music";
	case BG_RADIO:
		return "Radio";
	case BG_PODCAST:
		return "Podcast";
	default:
		return "Audio";
	}
}

// Label callback for first item label and Settings update badge
static const char* main_menu_get_label(int index, const char* default_label,
									   char* buffer, int buffer_size) {
	bool has_first = (current_first_item_mode != MENU_FIRST_NONE);

	// First item: return full label for pill sizing
	if (has_first && index == 0) {
		if (current_first_item_mode == MENU_FIRST_NOW_PLAYING) {
			snprintf(buffer, buffer_size, "Now Playing: %s", get_now_playing_label());
			return buffer;
		}
		// Resume mode
		const char* label = Resume_getLabel();
		if (label) {
			snprintf(buffer, buffer_size, "%s", label);
			return buffer;
		}
	}

	return NULL; // Use default label
}

// Main menu ListView (full mode: the widget owns selection and input;
// MenuModule_run drives it through MusicMainMenu_view()).
static ListView main_menu_view;
static char main_menu_label_buf[256];

ListView* MusicMainMenu_view(void) {
	return &main_menu_view;
}

static void main_menu_get_row(void* ctx, int i, bool selected,
							  ListViewRow* out) {
	const char** items = ctx;
	const char* label = items[i];
	const char* custom = main_menu_get_label(i, label, main_menu_label_buf,
											 sizeof(main_menu_label_buf));
	out->label = custom ? custom : label;
	(void)selected;
}

// Render the main menu
void render_menu(SDL_Surface* screen, IndicatorType show_setting,
				 char* toast_message, uint32_t toast_time, int first_item_mode) {
	(void)show_setting;
	current_first_item_mode = first_item_mode;
	bool has_first = (first_item_mode != MENU_FIRST_NONE);

	// Update the first item label based on mode
	if (first_item_mode == MENU_FIRST_NOW_PLAYING) {
		menu_items_with_first[0] = "Now Playing";
	} else {
		menu_items_with_first[0] = "Resume";
	}

	const char** items = has_first ? menu_items_with_first : menu_items_no_first;
	int count = has_first ? 5 : 4;

	GFX_clear(screen);
	ListView* v = &main_menu_view;
	v->title = "Music Player";
	v->font = font.large;
	v->count = count;
	v->get_row = main_menu_get_row;
	v->ctx = (void*)items;
	v->list_id = (const void*)items;
	v->hint_pairs = (char*[]){"MENU", "CONTROLS", "B", "EXIT", "A", "OPEN", NULL};
	UI_listViewRender(v, screen);

	// Toast notification
	UI_renderToast(screen, toast_message, toast_time);
}

// Controls help text for each page/state

// Main menu controls (A/B shown in footer)
static const ControlHelp main_menu_controls[] = {
	{"Up/Down", "Navigate"},
	{"X", "Clear History/Playback"},
	{NULL, NULL}};

// File browser controls (A/B shown in footer)
static const ControlHelp browser_controls[] = {
	{"Up/Down", "Navigate"},
	{"Y", "Add to Playlist"},
	{"X", "Delete File"},
	{NULL, NULL}};

// Music player controls (A/B shown in footer)
static const ControlHelp player_controls[] = {
	{"X", "Toggle Shuffle"},
	{"Y", "Toggle Repeat"},
	{"Up/R1", "Next Track"},
	{"Down/L1", "Prev Track"},
	{"Left/Right", "Seek"},
	{"L2/" BTN_FN1_NAME, "Toggle Visualizer"},
	{"R2/" BTN_FN2_NAME, "Toggle Lyrics"},
	{"Select", "Screen Off"},
	{"Select + A", "Wake Screen"},
	{NULL, NULL}};

// Radio list controls (A/B shown in footer)
static const ControlHelp radio_list_controls[] = {
	{"Up/Down", "Navigate"},
	{"Y", "Manage Stations"},
	{"X", "Delete Station"},
	{NULL, NULL}};

// Radio playing controls (B shown in footer)
static const ControlHelp radio_playing_controls[] = {
	{"Up/R1", "Next Station"},
	{"Down/L1", "Prev Station"},
	{"Select", "Screen Off"},
	{"Select + A", "Wake Screen"},
	{NULL, NULL}};

// Radio manage stations controls - country list (A/B shown in footer)
static const ControlHelp radio_manage_controls[] = {
	{"Up/Down", "Navigate"},
	{"Y", "Manual Setup Help"},
	{NULL, NULL}};

// Radio browse stations controls - station list (A/B shown in footer)
static const ControlHelp radio_browse_controls[] = {
	{"Up/Down", "Navigate"},
	{"A", "Add/Remove Station"},
	{"Y", "Manual Setup Help"},
	{NULL, NULL}};

// Podcast menu controls (shows subscribed podcasts)
static const ControlHelp podcast_menu_controls[] = {
	{"Up/Down", "Navigate"},
	{"X", "Unsubscribe"},
	{"Y", "Manage Podcasts"},
	{NULL, NULL}};

// Podcast manage menu controls
static const ControlHelp podcast_manage_controls[] = {
	{"Up/Down", "Navigate"},
	{NULL, NULL}};

// Podcast subscriptions list controls
static const ControlHelp podcast_subscriptions_controls[] = {
	{"Up/Down", "Navigate"},
	{"X", "Unsubscribe"},
	{NULL, NULL}};

// Podcast top shows controls
static const ControlHelp podcast_top_shows_controls[] = {
	{"Up/Down", "Navigate"},
	{"A", "Subscribe/Unsubscribe"},
	{"X", "Refresh List"},
	{NULL, NULL}};

// Podcast search results controls
static const ControlHelp podcast_search_controls[] = {
	{"Up/Down", "Navigate"},
	{"A", "Subscribe/Unsubscribe"},
	{NULL, NULL}};

// Podcast episodes list controls
static const ControlHelp podcast_episodes_controls[] = {
	{"Up/Down", "Navigate"},
	{"Y", "Refresh Episodes"},
	{"X", "Mark Played/Unplayed"},
	{NULL, NULL}};

// Podcast playing controls
static const ControlHelp podcast_playing_controls[] = {
	{"Left", "Rewind 10s"},
	{"Right", "Forward 30s"},
	{"Up/Down", "Playback Speed"},
	{"Select", "Screen Off"},
	{"Select + A", "Wake Screen"},
	{NULL, NULL}};

// Playlist list controls (A/B shown in footer)
static const ControlHelp playlist_list_controls[] = {
	{"Up/Down", "Navigate"},
	{"X", "Delete Playlist"},
	{NULL, NULL}};

// Playlist detail controls (A/B shown in footer)
static const ControlHelp playlist_detail_controls[] = {
	{"Up/Down", "Navigate"},
	{"X", "Remove Track"},
	{NULL, NULL}};

// About page controls (A/B shown in footer)
static const ControlHelp about_controls[] = {
	{NULL, NULL}};

// Settings menu controls
static const ControlHelp settings_controls[] = {
	{"Up/Down", "Navigate"},
	{"Left/Right", "Change Value"},
	{NULL, NULL}};

// Generic/default controls
static const ControlHelp default_controls[] = {
	{NULL, NULL}};

// Render controls help dialog overlay
void render_controls_help(SDL_Surface* screen, int app_state) {
	const ControlHelp* controls;
	const char* page_title;

	switch (app_state) {
	case 0: // STATE_MENU
		controls = main_menu_controls;
		page_title = "Main Menu";
		break;
	case 1: // STATE_BROWSER
		controls = browser_controls;
		page_title = "File Browser";
		break;
	case 2: // STATE_PLAYING
		controls = player_controls;
		page_title = "Music Player";
		break;
	case 3: // STATE_RADIO_LIST
		controls = radio_list_controls;
		page_title = "Radio Stations";
		break;
	case 4: // STATE_RADIO_PLAYING
		controls = radio_playing_controls;
		page_title = "Radio Player";
		break;
	case 5: // STATE_RADIO_ADD
		controls = radio_manage_controls;
		page_title = "Manage Stations";
		break;
	case 6: // STATE_RADIO_ADD_STATIONS
		controls = radio_browse_controls;
		page_title = "Browse Stations";
		break;
	case 30: // PODCAST_INTERNAL_MENU
		controls = podcast_menu_controls;
		page_title = "Podcasts";
		break;
	case 31: // PODCAST_INTERNAL_MANAGE
		controls = podcast_manage_controls;
		page_title = "Manage Podcasts";
		break;
	case 32: // PODCAST_INTERNAL_SUBSCRIPTIONS
		controls = podcast_subscriptions_controls;
		page_title = "Subscriptions";
		break;
	case 33: // PODCAST_INTERNAL_TOP_SHOWS
		controls = podcast_top_shows_controls;
		page_title = "Top Shows";
		break;
	case 34: // PODCAST_INTERNAL_SEARCH_RESULTS
		controls = podcast_search_controls;
		page_title = "Search Results";
		break;
	case 35: // PODCAST_INTERNAL_EPISODES
		controls = podcast_episodes_controls;
		page_title = "Episodes";
		break;
	case 36: // PODCAST_INTERNAL_BUFFERING
		controls = default_controls;
		page_title = "Buffering";
		break;
	case 37: // PODCAST_INTERNAL_PLAYING
		controls = podcast_playing_controls;
		page_title = "Podcast Player";
		break;
	case 23: // STATE_ABOUT
		controls = about_controls;
		page_title = "About";
		break;
	case 40: // SETTINGS_INTERNAL_MENU
		controls = settings_controls;
		page_title = "Settings";
		break;
	case 50: // PLAYLIST_LIST_HELP_STATE
		controls = playlist_list_controls;
		page_title = "Playlists";
		break;
	case 51: // PLAYLIST_DETAIL_HELP_STATE
		controls = playlist_detail_controls;
		page_title = "Playlist Tracks";
		break;
	case 55: // LIBRARY_MENU_HELP_STATE
		controls = main_menu_controls;
		page_title = "Library";
		break;
	case 41: // SETTINGS_INTERNAL_ABOUT
		controls = about_controls;
		page_title = "About";
		break;
	default:
		controls = default_controls;
		page_title = "Controls";
		break;
	}

	UI_renderControlsHelp(screen, page_title, controls);
}

// Render screen off hint message (shown before screen turns off)
void render_screen_off_hint(SDL_Surface* screen) {
	int hw = screen->w;
	int hh = screen->h;

	// Fill entire screen with black
	SDL_FillRect(screen, NULL, RGB_BLACK);

	// Render hint message centered
	const char* msg = "Press SELECT + A to wake screen";
	SDL_Surface* msg_surf = TTF_RenderUTF8_Blended(font.medium, msg, COLOR_WHITE);
	if (msg_surf) {
		SDL_BlitSurface(msg_surf, NULL, screen, &(SDL_Rect){(hw - msg_surf->w) / 2, (hh - msg_surf->h) / 2});
		SDL_FreeSurface(msg_surf);
	}
}
