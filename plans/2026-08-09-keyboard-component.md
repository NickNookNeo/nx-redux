# In-Process Shared Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vendored prebuilt `skeleton/SYSTEM/shared/bin/keyboard` binary with an in-process shared keyboard component (`common/ui/ui_keyboard.c`) that keeps the stock look but uses NX Redux theming and the standard left-aligned PNG-glyph hint bar.

**Architecture:** `UIKeyboard_open(prompt)` keeps its exact signature but becomes a blocking modal SDL loop drawn on the app's screen (obtained via a new `GFX_getScreen()` accessor), instead of `popen()`-ing an external binary. The duplicate in-process keyboard `netplay/keyboard.c` (used only by the standalone `netplay-wizard` app) is deleted and the wizard switches to the shared component.

**Tech Stack:** C (gnu99), SDL2 + SDL2_ttf, common `api.c` GFX/PAD/PWR layer, docker cross-toolchains `ghcr.io/loveretro/tg5040-toolchain` / `tg5050-toolchain`.

**Spec:** `plans/2026-08-09-keyboard-component-design.md`

## Global Constraints

- **NEVER `git commit`** — stage with `git add` only; the user commits personally. Every "Stage" step below is `git add`, nothing more.
- Shared code in `workspace/all/` must build for **BOTH** `tg5040` and `tg5050` (run both docker builds for every affected module).
- Work happens in the worktree at `.claude/worktrees/keyboard-component` (branch `worktree-keyboard-component`). Run all commands from the worktree root.
- There is no host test suite for SDL UI code; the per-task gate is a clean docker cross-build for both platforms. Final behavioral verification is on-device (Task 4).
- Build command template (from DEV.md, run at worktree root):
  ```bash
  docker run --rm -v $(pwd)/workspace:/root/workspace ghcr.io/loveretro/<PLATFORM>-toolchain:latest \
    /bin/bash -c 'source ~/.bashrc && cd /root/workspace/all/<MODULE> && make PLATFORM=<PLATFORM>'
  ```
  where `<PLATFORM>` ∈ {tg5040, tg5050}.

---

### Task 1: Rewrite `ui_keyboard` as an in-process keyboard

**Files:**
- Modify: `workspace/all/common/api.h` (add `GFX_getScreen` declaration near `GFX_init`, ~line 272)
- Modify: `workspace/all/common/api.c` (add `GFX_getScreen` implementation near `GFX_init`, ~line 283)
- Modify: `workspace/all/common/ui/ui_keyboard.h` (full replacement below)
- Modify: `workspace/all/common/ui/ui_keyboard.c` (full replacement below)

**Interfaces:**
- Consumes: `gfx.screen` (static global in api.c), `UI_fillRoundedRect` (ui_draw.h), `UI_renderButtonHintBar` (ui_buttonhintbar.h), `PAD_poll/PAD_justPressed/PAD_justRepeated/PAD_reset`, `PWR_update`, `GFX_startFrame/GFX_flip/GFX_sync`, `font` (GFX_Fonts global), `THEME_COLOR1`, `THEME_COLOR5_255`, `uintToColour`, `COLOR_WHITE/COLOR_GRAY` (defines.h).
- Produces: `SDL_Surface* GFX_getScreen(void)` (api.h) and `char* UIKeyboard_open(const char* prompt)` — same signature as today, but `prompt` now renders as the title. `UIKeyboard_init(void)` kept as a no-op (4 call sites in scraper/musicplayer still call it).

- [ ] **Step 1: Add the screen accessor to the common API**

In `workspace/all/common/api.h`, directly under `SDL_Surface* GFX_init(int mode);`:

```c
SDL_Surface* GFX_getScreen(void); // current screen surface (owned by GFX; do not free)
```

In `workspace/all/common/api.c`, after the `GFX_init` function body:

```c
SDL_Surface* GFX_getScreen(void) {
	return gfx.screen;
}
```

- [ ] **Step 2: Replace `ui_keyboard.h`**

```c
#ifndef UI_KEYBOARD_H
#define UI_KEYBOARD_H

// Kept for backward compatibility (scraper/musicplayer call it); no-op.
void UIKeyboard_init(void);

// Show the modal in-process on-screen keyboard, blocking until the user
// confirms or cancels. Returns a malloc'd string with the input, or NULL
// if cancelled or empty. Caller must free() the result.
// `prompt` is rendered as the title above the input line.
char* UIKeyboard_open(const char* prompt);

#endif // UI_KEYBOARD_H
```

- [ ] **Step 3: Replace `ui_keyboard.c`**

```c
// In-process on-screen keyboard. Replaces the vendored prebuilt
// SYSTEM/shared/bin/keyboard binary: same bare-glyph black layout,
// themed selection cursor, standard NX Redux button hint bar.
#include "ui_keyboard.h"
#include "ui_draw.h"
#include "ui_buttonhintbar.h"
#include "api.h"
#include "defines.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KB_ROWS 6
#define KB_COLS 10
#define KB_MAX_INPUT 128

// Stock binary layout: number row, three QWERTY rows, symbols row,
// then the wide Space / Confirm row.
static const char* kb_lower[KB_ROWS][KB_COLS] = {
	{"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"},
	{"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"},
	{"a", "s", "d", "f", "g", "h", "j", "k", "l", ";"},
	{"z", "x", "c", "v", "b", "n", "m", ",", ".", "/"},
	{"`", "'", "-", "=", "[", "]", "\\", NULL, NULL, NULL},
	{"Space", "Confirm", NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL}};

static const char* kb_upper[KB_ROWS][KB_COLS] = {
	{"!", "@", "#", "$", "%", "^", "&", "*", "(", ")"},
	{"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"},
	{"A", "S", "D", "F", "G", "H", "J", "K", "L", ":"},
	{"Z", "X", "C", "V", "B", "N", "M", "<", ">", "?"},
	{"~", "\"", "_", "+", "{", "}", "|", NULL, NULL, NULL},
	{"Space", "Confirm", NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL}};

void UIKeyboard_init(void) {
	// No-op: nothing to initialize since the external binary was replaced
	// by this in-process implementation.
}

static int kb_row_len(const char* layout[KB_ROWS][KB_COLS], int row) {
	int n = 0;
	while (n < KB_COLS && layout[row][n])
		n++;
	return n;
}

static void kb_draw(SDL_Surface* screen, const char* title, const char* input,
					int cur_row, int cur_col, int shift) {
	const char* (*layout)[KB_COLS] = shift ? kb_upper : kb_lower;

	SDL_FillRect(screen, NULL, SDL_MapRGB(screen->format, 0, 0, 0));

	SDL_Surface* text;
	int center_x = screen->w / 2;
	SDL_Color focused_color = uintToColour(THEME_COLOR5_255);

	// Vertical layout: title, input line, 6 grid rows; centered as a block.
	int title_h = TTF_FontHeight(font.small);
	int input_h = TTF_FontHeight(font.large);
	int cell_h = SCALE1(44);
	int gap = SCALE1(8);
	int total_h = title_h + gap + input_h + gap * 2 + KB_ROWS * cell_h;
	int y = (screen->h - total_h) / 2;

	// Title (the caller's prompt)
	if (title && title[0]) {
		text = TTF_RenderUTF8_Blended(font.small, title, COLOR_GRAY);
		if (text) {
			SDL_BlitSurface(text, NULL, screen,
							&(SDL_Rect){center_x - text->w / 2, y});
			SDL_FreeSurface(text);
		}
	}
	y += title_h + gap;

	// Typed text with caret; keep the tail visible when it overflows.
	char shown[KB_MAX_INPUT + 2];
	snprintf(shown, sizeof(shown), "%s_", input);
	text = TTF_RenderUTF8_Blended(font.large, shown, COLOR_WHITE);
	if (text) {
		int max_w = screen->w - SCALE1(PADDING * 4);
		if (text->w > max_w) {
			SDL_Rect src = {text->w - max_w, 0, max_w, text->h};
			SDL_BlitSurface(text, &src, screen,
							&(SDL_Rect){center_x - max_w / 2, y});
		} else {
			SDL_BlitSurface(text, NULL, screen,
							&(SDL_Rect){center_x - text->w / 2, y});
		}
		SDL_FreeSurface(text);
	}
	y += input_h + gap * 2;

	// Key grid: bare glyphs, no key boxes; the focused key gets a filled
	// THEME_COLOR1 circle (capsule for the wide Space/Confirm keys), drawn
	// with the anti-aliased rounded-rect primitive.
	int cell_w = (screen->w - SCALE1(PADDING * 2)) / KB_COLS;
	for (int row = 0; row < KB_ROWS; row++) {
		int len = kb_row_len(layout, row);
		int cy = y + row * cell_h + cell_h / 2;

		if (row == KB_ROWS - 1) {
			// Space / Confirm: one wide key centered in each half.
			for (int col = 0; col < len; col++) {
				const char* key = layout[row][col];
				int cx = screen->w / 4 + col * (screen->w / 2);
				bool focused = (row == cur_row && col == cur_col);
				text = TTF_RenderUTF8_Blended(font.large, key,
											  focused ? focused_color : COLOR_WHITE);
				if (!text)
					continue;
				if (focused) {
					int pw = text->w + SCALE1(24) * 2;
					int ph = SCALE1(40);
					UI_fillRoundedRect(screen, cx - pw / 2, cy - ph / 2,
									   pw, ph, ph / 2, THEME_COLOR1);
				}
				SDL_BlitSurface(text, NULL, screen,
								&(SDL_Rect){cx - text->w / 2, cy - text->h / 2});
				SDL_FreeSurface(text);
			}
		} else {
			int start_x = center_x - (len * cell_w) / 2;
			for (int col = 0; col < len; col++) {
				const char* key = layout[row][col];
				int cx = start_x + col * cell_w + cell_w / 2;
				bool focused = (row == cur_row && col == cur_col);
				if (focused) {
					int d = SCALE1(40);
					UI_fillRoundedRect(screen, cx - d / 2, cy - d / 2,
									   d, d, d / 2, THEME_COLOR1);
				}
				text = TTF_RenderUTF8_Blended(font.large, key,
											  focused ? focused_color : COLOR_WHITE);
				if (text) {
					SDL_BlitSurface(text, NULL, screen,
									&(SDL_Rect){cx - text->w / 2, cy - text->h / 2});
					SDL_FreeSurface(text);
				}
			}
		}
	}

	// Standard hint bar: left-aligned PNG glyph buttons.
	UI_renderButtonHintBar(screen, (char*[]){"Y", "DELETE", "X", "SHIFT",
											 "B", "EXIT", "A", "SELECT", NULL});

	GFX_flip(screen);
}

char* UIKeyboard_open(const char* prompt) {
	SDL_Surface* screen = GFX_getScreen();
	if (!screen) {
		LOG_error("UIKeyboard_open: no screen (GFX_init not called?)\n");
		return NULL;
	}

	char input[KB_MAX_INPUT + 1] = {0};
	int len = 0;
	int cur_row = 0, cur_col = 0;
	int shift = 0;
	bool dirty = true;

	// Don't let the button press that opened the keyboard leak in.
	PAD_reset();

	while (1) {
		GFX_startFrame();
		PAD_poll();

		const char* (*layout)[KB_COLS] = shift ? kb_upper : kb_lower;

		if (PAD_justPressed(BTN_B)) {
			PAD_reset();
			return NULL;
		}

		// BTN_UP/DOWN/LEFT/RIGHT are composites (BTN_DPAD_* | BTN_ANALOG_*),
		// so the left analog stick navigates too on devices that have one
		// (Brick Pro / Smart Pro / Smart Pro S) with repeat handled by
		// PAD_setAnalog in the input layer.
		if (PAD_justRepeated(BTN_UP)) {
			cur_row = (cur_row + KB_ROWS - 1) % KB_ROWS;
			int rl = kb_row_len(layout, cur_row);
			if (cur_col >= rl)
				cur_col = rl - 1;
			dirty = true;
		} else if (PAD_justRepeated(BTN_DOWN)) {
			cur_row = (cur_row + 1) % KB_ROWS;
			int rl = kb_row_len(layout, cur_row);
			if (cur_col >= rl)
				cur_col = rl - 1;
			dirty = true;
		} else if (PAD_justRepeated(BTN_LEFT)) {
			int rl = kb_row_len(layout, cur_row);
			cur_col = (cur_col + rl - 1) % rl;
			dirty = true;
		} else if (PAD_justRepeated(BTN_RIGHT)) {
			int rl = kb_row_len(layout, cur_row);
			cur_col = (cur_col + 1) % rl;
			dirty = true;
		} else if (PAD_justPressed(BTN_X)) {
			shift = !shift;
			dirty = true;
		} else if (PAD_justPressed(BTN_Y)) {
			if (len > 0) {
				input[--len] = '\0';
				dirty = true;
			}
		} else if (PAD_justPressed(BTN_A)) {
			const char* key = layout[cur_row][cur_col];
			if (strcmp(key, "Space") == 0) {
				if (len < KB_MAX_INPUT) {
					input[len++] = ' ';
					input[len] = '\0';
					dirty = true;
				}
			} else if (strcmp(key, "Confirm") == 0) {
				PAD_reset();
				if (len == 0)
					return NULL; // empty input = cancel (matches old wrapper)
				return strdup(input);
			} else {
				if (len < KB_MAX_INPUT) {
					input[len++] = key[0];
					input[len] = '\0';
					dirty = true;
				}
			}
		}

		PWR_update(&dirty, NULL, NULL, NULL);

		if (dirty) {
			kb_draw(screen, prompt, input, cur_row, cur_col, shift);
			dirty = false;
		} else {
			GFX_sync();
		}
	}
}
```

- [ ] **Step 4: Compile gate — build nextui for both platforms**

Run at worktree root:
```bash
docker run --rm -v $(pwd)/workspace:/root/workspace ghcr.io/loveretro/tg5040-toolchain:latest \
  /bin/bash -c 'source ~/.bashrc && cd /root/workspace/all/nextui && make PLATFORM=tg5040'
docker run --rm -v $(pwd)/workspace:/root/workspace ghcr.io/loveretro/tg5050-toolchain:latest \
  /bin/bash -c 'source ~/.bashrc && cd /root/workspace/all/nextui && make PLATFORM=tg5050'
```
Expected: both produce `workspace/all/nextui/build/<platform>/nextui.elf` with no errors or new warnings in `ui_keyboard.c` / `api.c`.

- [ ] **Step 5: Stage (do NOT commit)**

```bash
git add workspace/all/common/api.h workspace/all/common/api.c \
        workspace/all/common/ui/ui_keyboard.h workspace/all/common/ui/ui_keyboard.c
```

---

### Task 2: Switch netplay-wizard to the shared keyboard; delete `netplay/keyboard.c`

**Files:**
- Modify: `workspace/all/netplay-wizard/wizard_wifi.c:23` (include) and `:251` (call)
- Modify: `workspace/all/netplay-wizard/wizard.c:50-55` (remove dead minarch shims)
- Modify: `workspace/all/netplay-wizard/Makefile:23-28` (source list, include path)
- Delete: `workspace/all/netplay/keyboard.c`, `workspace/all/netplay/keyboard.h`

**Interfaces:**
- Consumes: `char* UIKeyboard_open(const char* prompt)` from Task 1 (returns malloc'd string or NULL on cancel — same contract `Keyboard_getPassword` had).
- Produces: nothing new; `netplay.elf` behavior unchanged from the caller's perspective.

- [ ] **Step 1: Update `wizard_wifi.c`**

Line 23: replace `#include "keyboard.h"` with `#include "ui_keyboard.h"`.

Line 251: replace
```c
		char* password = Keyboard_getPassword();
```
with
```c
		char* password = UIKeyboard_open("Enter WiFi Password");
```

- [ ] **Step 2: Remove the dead minarch shims from `wizard.c`**

`netplay/keyboard.c` was the only consumer of these shims (see the Makefile comment). Delete this block at `wizard.c:50-55`:
```c
SDL_Surface* minarch_getScreen(void) {
	...
}
void minarch_beforeSleep(void) {}
void minarch_afterSleep(void) {}
void minarch_hdmimon(void) {}
```
Then verify nothing else references them:
```bash
grep -rn "minarch_getScreen\|minarch_beforeSleep\|minarch_afterSleep\|minarch_hdmimon" workspace/all/netplay-wizard/
```
Expected: no matches (if `wizard.c` itself calls any of them elsewhere, keep that shim and note it).

- [ ] **Step 3: Update `netplay-wizard/Makefile`**

- In `SOURCE` (line 27-28): replace `../netplay/keyboard.c` with `$(UI_DIR)/ui_keyboard.c`.
- In `INCDIR` (line 25): remove `-I../minarch/` and delete the two comment lines above it (lines 23-24: "../minarch/ is on the include path only for minarch.h: netplay/keyboard.c ...") — that include existed only for keyboard.c.

- [ ] **Step 4: Delete the duplicate keyboard**

```bash
git rm workspace/all/netplay/keyboard.c workspace/all/netplay/keyboard.h
```
Then verify no remaining references:
```bash
grep -rn "Keyboard_show\|Keyboard_getPassword\|netplay/keyboard" workspace/all --include="*.c" --include="*.h" --include="Makefile*"
```
Expected: no matches.

- [ ] **Step 5: Compile gate — build netplay-wizard for both platforms**

```bash
docker run --rm -v $(pwd)/workspace:/root/workspace ghcr.io/loveretro/tg5040-toolchain:latest \
  /bin/bash -c 'source ~/.bashrc && cd /root/workspace/all/netplay-wizard && make PLATFORM=tg5040'
docker run --rm -v $(pwd)/workspace:/root/workspace ghcr.io/loveretro/tg5050-toolchain:latest \
  /bin/bash -c 'source ~/.bashrc && cd /root/workspace/all/netplay-wizard && make PLATFORM=tg5050'
```
Expected: both produce `workspace/all/netplay-wizard/build/<platform>/netplay.elf` cleanly.

- [ ] **Step 6: Stage (do NOT commit)**

```bash
git add workspace/all/netplay-wizard/wizard_wifi.c workspace/all/netplay-wizard/wizard.c \
        workspace/all/netplay-wizard/Makefile
# keyboard.c/.h deletion already staged by git rm
```

---

### Task 3: Delete the prebuilt binary; build all remaining consumers

**Files:**
- Delete: `skeleton/SYSTEM/shared/bin/keyboard`

**Interfaces:**
- Consumes: Task 1's `ui_keyboard.c` (linked by settings, scraper, ratools, musicplayer — no source changes needed in any of them).
- Produces: final tree state; all six consumer modules build.

- [ ] **Step 1: Remove the binary from the skeleton**

```bash
git rm skeleton/SYSTEM/shared/bin/keyboard
```
Then verify nothing in the repo still references the deployed path:
```bash
grep -rn "bin/keyboard\|keyboard_output" workspace skeleton --include="*.c" --include="*.h" --include="*.sh" --include="Makefile*"
```
Expected: no matches.

- [ ] **Step 2: Compile gate — build the remaining consumers, both platforms**

For each `<MODULE>` in `settings scraper ratools musicplayer` and each `<PLATFORM>` in `tg5040 tg5050`:
```bash
docker run --rm -v $(pwd)/workspace:/root/workspace ghcr.io/loveretro/<PLATFORM>-toolchain:latest \
  /bin/bash -c 'source ~/.bashrc && cd /root/workspace/all/<MODULE> && make PLATFORM=<PLATFORM>'
```
Expected: 8 clean builds (settings.elf, scraper.elf, ratools elfs, musicplayer.elf for both platforms). Note: concurrent builds of the SAME module for different platforms have hit object-file races before (musicplayer opus_obj) — run the two platform builds of a module sequentially, different modules may run in parallel.

- [ ] **Step 3: Stage (do NOT commit)**

Nothing new to add (`git rm` already staged the deletion). Confirm with:
```bash
git status --short
```
Expected: only staged (`A`/`M`/`D`) entries for the files in Tasks 1-3, no unstaged surprises.

---

### Task 4: Deploy and verify on-device (Brick tg5040 + Smart Pro S tg5050)

**Files:** none (deployment/verification only)

**Interfaces:**
- Consumes: built elfs from Tasks 1-3.
- Produces: verified feature; screenshot evidence.

- [ ] **Step 1: Locate deploy targets on the connected device**

The Brick (tg5040) connects over USB adb. For each elf find its on-device home:
```bash
adb shell "ls /mnt/SDCARD/.system/bin/ /mnt/SDCARD/.system/paks/Tools/"
```
Known targets (verify before pushing):
- `nextui.elf` → `/mnt/SDCARD/.system/bin/`
- `settings.elf` → `/mnt/SDCARD/.system/paks/Tools/Settings.pak/`
- `musicplayer.elf` → `/mnt/SDCARD/.system/paks/Tools/Music Player.pak/`
- `scraper.elf` → `/mnt/SDCARD/.system/paks/Tools/Artwork Manager.pak/`
- `netplay.elf` → locate with `adb shell "find /mnt/SDCARD/.system -name 'netplay.elf'"`
- ratools elfs → locate with `adb shell "find /mnt/SDCARD/.system -name 'ratool*'"`

- [ ] **Step 2: Push tg5040 builds to the Brick and remove the old binary**

```bash
adb push workspace/all/nextui/build/tg5040/nextui.elf /mnt/SDCARD/.system/bin/
# ...push each remaining elf to the location found in Step 1...
adb shell "rm /mnt/SDCARD/.system/shared/bin/keyboard"
adb shell reboot
```
Verify sizes/md5 after push (`adb shell md5sum ...` vs local `md5 -q ...`).

- [ ] **Step 3: Verify each entry point on the Brick**

Human-in-the-loop (ask the user to drive, or use framebuffer screenshots
`dd if=/dev/fb0` → BGRA 1024x768 to confirm rendering):
- nextui: Search ("Search" title), game rename, new collection name
- settings: WiFi password entry
- musicplayer: playlist name, podcast search
- scraper: credential entry
- netplay wizard: join flow → WiFi password
Checks per screen: stock-look grid renders (bare glyphs, black bg), THEME_COLOR1 cursor circle, title + typed text with caret, left-aligned PNG hint bar (Y DELETE / X SHIFT / B EXIT / A SELECT), shift layer via X, delete via Y, B cancels (NULL → caller aborts cleanly), Confirm returns text to the caller feature (e.g. search actually filters).

- [ ] **Step 4: Repeat push + verify on Smart Pro S (tg5050 builds)**

Same as Steps 2-3 with `build/tg5050/` artifacts when the SPS is connected. Additionally verify **left analog stick navigation** (SPS has a stick; Brick does not): stick moves the cursor with sane repeat speed, d-pad still works identically.

- [ ] **Step 5: Report results**

Report per-device pass/fail per entry point to the user with screenshots. Any rendering tune-ups (cell size `SCALE1(44)`, cursor diameter `SCALE1(40)`, capsule padding `SCALE1(24)`) get adjusted, rebuilt, re-pushed, and re-staged — these constants are first-guess approximations of the stock binary's proportions.

---

## Self-Review Notes

- Spec coverage: API preservation (T1), stock look + theme accent (T1 `kb_draw`), title+input line (T1), hint bar left-aligned PNG (T1 via `UI_renderButtonHintBar`), analog stick nav (T1 composite BTN_* + T4 SPS verification), netplay switch + dedup deletion (T2), binary deletion (T3), both-platform builds (T1-T3 gates), on-device verification incl. every caller (T4). Empty-input-returns-NULL preserved (T1 Confirm branch).
- The `UIKeyboard_init` no-op is retained so scraper.c:1119/1147, module_playlist.c:69, module_podcast.c:102 need no edits.
- `ratools` links `ui_keyboard.c` but never calls `UIKeyboard_open`; it only needs to keep compiling (T3 gate).
- Layout note: the netplay keyboard used a 5-row QWERTY-with-punctuation layout; the new component deliberately uses the six-row STOCK layout per the user's preference — netplay WiFi passwords still reach every character through the shift layer.
