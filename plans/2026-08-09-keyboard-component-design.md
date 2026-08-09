# In-Process Shared Keyboard Component (`ui_keyboard`)

**Date:** 2026-08-09
**Status:** Approved by user (pending spec review)

## Problem

All on-screen text entry in NX Redux flows through `UIKeyboard_open()`
(`workspace/all/common/ui/ui_keyboard.c`), which spawns the vendored prebuilt
binary `skeleton/SYSTEM/shared/bin/keyboard` via `popen()` and reads the typed
string from its stdout. This has several problems:

- The binary is an opaque 39 KB aarch64 ELF we cannot patch (it predates the
  Brick Pro, forcing the `DEVICE=brick` env workaround in `ui_keyboard.c`).
- Two SDL applications fight over the display; the wrapper must flush stale
  SDL events and call `PAD_reset()` after the child exits.
- The binary's button hints (bottom-right, drawn gray discs) do not match the
  NX Redux hint-bar style (left-aligned PNG glyph buttons).
- The `prompt` parameter of `UIKeyboard_open()` is ignored — no title is shown.
- A second, independent in-process keyboard exists in `netplay/keyboard.c`
  (used by `netplay-wizard/wizard_wifi.c` for WiFi password entry inside
  minarch), duplicating the functionality with a different look.

## Decision

Rewrite `common/ui/ui_keyboard.c` as a real **in-process** SDL keyboard with
the stock binary's visual layout, themed accents, and the NX Redux hint bar.
Delete the prebuilt binary and `netplay/keyboard.c`; every consumer uses the
one shared component.

## Public API (unchanged signature)

```c
void  UIKeyboard_init(void);                  // kept as a no-op (4 call sites in scraper/musicplayer)
char* UIKeyboard_open(const char* prompt);    // malloc'd result; NULL = cancelled
```

- All 9 existing `UIKeyboard_open` call sites (nextui search/rename/collection, scraper
  credentials, settings WiFi password + menu text fields, musicplayer
  playlist/podcast) compile unchanged.
- `prompt` is now rendered as the title.
- Blocking modal loop on the caller's screen surface, same pattern as
  `ui_confirmdialog` / `ui_listdialog`: `PAD_poll()` → handle input → redraw →
  `GFX_flip()`.

## Visual design (stock look + theme accent)

- Black background; bare glyphs, no key borders/boxes.
- Same six-row layout as the stock binary: number row, three QWERTY rows,
  symbols row (`` ` `` `'` `-` `=` `[` `]` `\`), then `Space` / `Confirm` row.
- Shift layer mirrors the binary's shifted labels (`~!@#$%^&*()`, uppercase,
  `{}|:"<>?` etc.).
- Selection cursor: filled circle behind the focused key (pill/rounded-rect
  for wide keys like Space/Confirm), drawn in `THEME_COLOR1` with the
  anti-aliased circle/rounded-rect primitives; the focused glyph flips to the
  contrast color (same treatment as the game-list selection pill).
- Title (the `prompt`) rendered small at the top; typed text below it with a
  caret; theme font (`font1.ttf`) via the common font system.
- Bottom: `UI_renderButtonHintBar` with pairs `{Y: Delete, X: Shift,
  B: Exit, A: Select}` — left-aligned PNG glyph buttons, identical to every
  other NX Redux screen. Hardware hints (battery etc.) keep priority as the
  component already implements.

## Input handling

- D-pad navigation with `PAD_justRepeated()` hold-to-repeat.
- **Analog stick navigation**: use the composite constants
  `BTN_UP/BTN_DOWN/BTN_LEFT/BTN_RIGHT` (`defines.h:307` —
  `BTN_UP = BTN_DPAD_UP | BTN_ANALOG_UP`), which the input layer already feeds
  from the left stick via `PAD_setAnalog()` with proper repeat timing. This
  gives stick navigation for free on devices that have one (Brick Pro,
  Smart Pro, Smart Pro S); devices without a stick are unaffected.
- `A` — select focused key; `B` — exit/cancel (return NULL); `X` — toggle
  shift layer; `Y` — backspace.
- Grid `Confirm` key returns the typed text; `Space` inserts a space.
- Navigation wraps horizontally per row; vertical movement clamps the column
  to the target row's length (stock binary behavior).
- Input buffer capped at 128 characters (matches `netplay/keyboard.c`).

## Consumer changes

| Consumer | Change |
|---|---|
| nextui, scraper, settings, musicplayer | None (API unchanged; already link `ui_keyboard.c`) |
| `netplay-wizard/wizard_wifi.c:251` | `Keyboard_getPassword()` → shared component call |
| `netplay/keyboard.c`, `netplay/keyboard.h` | Deleted |
| minarch Makefile | Add `ui_keyboard.c` if not already linked; remove `netplay/keyboard.c` |
| `skeleton/SYSTEM/shared/bin/keyboard` | Deleted |
| `common/ui/ui_keyboard.c` | Binary-spawn machinery removed (path/chmod init, `DEVICE=brick` hack, popen, post-spawn event flush) |

`Keyboard_show(title)` / `Keyboard_getPassword()` from netplay map directly
onto `UIKeyboard_open(prompt)`.

## Error handling

- Allocation failure → return NULL (callers already handle NULL as "cancelled").
- Empty input + Confirm → return NULL (preserves current wrapper behavior of
  treating empty output as NULL).
- Power/menu hardware events keep flowing through the normal `PAD_poll()` /
  `PWR_update()` path, unlike the external binary which blocked them.

## Risks / early verification

1. **minarch linkage**: minarch already links `ui_buttonhintbar.c`; verify
   `ui_keyboard.c` (now pulling common font/theme globals) compiles and links
   cleanly inside the wizard context on both platforms.
2. **Caller screen state**: each caller's `screen` surface must be valid for a
   modal loop — expected fine since the same apps already run modal confirm
   dialogs.
3. **Analog repeat feel**: verify stick navigation speed on Brick Pro /
   Smart Pro S feels right (repeat timing comes from `PAD_setAnalog`).

## Testing

- Build all affected paks for **both** tg5040 and tg5050 (shared-code rule).
- On-device verification (Brick + Smart Pro S):
  - nextui: Search, game rename, new collection name
  - settings: WiFi password entry
  - musicplayer: playlist name, podcast search
  - scraper: credential entry
  - minarch netplay wizard: WiFi password (joystick + d-pad navigation)
- Confirm the deleted binary is also removed from the device SD during deploy.

## Out of scope

- No changes to keyboard layouts beyond stock parity (no long-press accents,
  no additional locales).
- No standalone binary wrapper (no current consumer; can be added later if a
  shell-script use case appears).
