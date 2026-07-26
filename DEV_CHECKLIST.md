# Dev Checklist

Running checklists for work that is **built but not yet verified on hardware**, so a later
session (or another person) can pick up the bring-up without re-deriving what is already known.

One section per in-flight effort. When a section is fully checked off and shipped, delete it —
this file is a to-do list, not a changelog.

Work that is **planned but not yet built** does not belong here — it lives in `DEV_TODO.md`.
Move an entry from there to here once it compiles and needs hardware time.

---

## Upstream-port + fix round (built 2026-07-27)

**Status:** ten DEV_TODO items implemented in one session 2026-07-27 (upstream ports
#667/#697/#699/#728/#783 + SUPA affinity + CFG_sync rewrite + auto-save-on-quit for both
minarch and the N64 overlay + N64 shared saves). Both device platforms build clean. Nothing
committed. All changed elfs + the rebuilt GLideN64 `.so` + N64 launch.sh are **pushed to
both cards** (Brick and Smart Pro S, md5-verified 2026-07-27).

Already verified and removed from this list: **SUPA affinity fix** (crash reproduced on
tg5050 — `PPUThreadAffinity: 0xc` → `MDFN_Error`; with the {0,1,4}-topology masks the game
boots and plays, which itself proves the masks applied, since supafaust throws on any
failed setaffinity); **Keep awake over USB** (incl. finding + fixing upstream #783's
latched-udc-state probe bug; both devices verified — full story in the
`PLAT_isUSBConnected()` comments and the device-deploy notes); **auto-save-on-quit,
both halves** (minarch `Menu_autosaveQuit` + N64 GLideN64 overlay quit → hidden slot 9 +
switcher screenshot + `.minui` repoint, incl. the overlay's deliberate 3-frame delayed
`M64CMD_STOP` so the queued save lands) — user-verified on both Brick and Smart Pro S
2026-07-27.

Full deploy: `make all`, flash zip. Quick iterate: push the single rebuilt `.elf` (reboot required
for nextui/minarch pushes — see Gotchas at the bottom of this file).

### On-device verification

- [ ] **SRAM read unification** (`ma_saves.c`, upstream #667) — save in-game with
      Save Format = SRM (compressed), switch back to the default (uncompressed), relaunch:
      the in-game save must be intact, and after the next in-game save the `.srm` should be
      raw (`head -c8` no longer `#RZIPv1#`). Regression: raw `.srm` still loads, and a
      RetroArch-imported compressed `.srm` loads under the default setting.
- [ ] **Resampler leak fix** (`api.c`, upstream #697) — play any PAL game (or set
      Core Sync = Native) for ~10 min; `VmRSS` in `/proc/<minarch pid>/status` must stay
      flat (before the fix it grew ~11 MB/min).
- [ ] **RETRO_ENVIRONMENT_SHUTDOWN** (`ma_environment.c`, upstream #699) — Doom
      (PRBOOM.pak): in-game menu → Quit must exit cleanly back to nextui. FBNeo: launch a
      known-bad ROM, any button on the error screen must exit. Check the switcher isn't
      left pointing at garbage for the PRBOOM quit (core dies before the menu's autosave —
      quit here goes through the env callback, not ITEM_QUIT, so no slot-9 autosave fires;
      confirm RESUME behaves sanely, i.e. falls back to previous state or START).
- [ ] **CFG_sync rewrite** (`config.c`, upstream issue #789) — four of five checks
      verified via adb on the Brick, 2026-07-27:
      - [x] (a) no redundant writes — file bit-identical (mtime + md5) through a full
            shutdown→boot cycle (nextui shutdown sync + 3× nextval + nextui boot sync).
      - [x] (b) unknown keys survive a real merge write — planted `thirdparty_test=1`
            AND deleted `sshOnBoot`; after reboot the foreign key was preserved in place
            and the missing known key re-appended.
      - [x] (d) materialization — deleted the file; first boot recreated it complete
            (58 keys, defaults incl. `keepAwakeUSB=0`).
      - [x] (e) no `.tmp` stragglers at any checkpoint.
      - [ ] (c) OSD WiFi toggle → change an unrelated setting → WiFi state must not
            clobber (needs physical OSD interaction).
      **Found while testing (the #789 scenario, live):** the card's stale `nextval.elf`
      (called 3× from `MinUI.pak/launch.sh` at every boot; its `CFG_init` used the old
      rewrite-everything sync) was stripping `keepAwakeUSB` at every boot — the new
      nextui then re-appended it as default 0, silently turning the keep-awake toggle
      OFF each reboot. Fixed on the Brick (rebuilt `nextval.elf` pushed, both platforms
      built). **The Smart Pro S card still has the old nextval** — its keep-awake toggle
      resets to Off on every reboot until `workspace/all/nextval/build/tg5050/nextval.elf`
      is pushed to `.system/tg5050/bin/`. Any other stale config.c-linking tool on a card
      (mediaplayer, musicplayer, sync, scraper, portmaster, gametracker, bootlogo) does
      the same when *launched*; a full flash resolves all of them at once.
- [ ] **N64 shared saves** (`launch.sh` both platforms) — launch an N64 game: saves/states
      must land under `.userdata/shared/N64-mupen64plus/data/mupen64plus/save/`; existing
      per-device saves (`.userdata/<dev>/.local/share/mupen64plus/save/`) migrate on first
      launch (existing shared files win). Then the real test: save state on Smart Pro S,
      move the card to the Brick, RESUME must load it (this was the broken promise).
      GLideN64 shader cache must remain per-device (`$HOME/.cache`).
- [ ] **Rewind re-init fix** (upstream #728 + early-out) — enable rewind, play: rewind
      works; changing a rewind option mid-game still takes effect (buffer size change →
      re-init happens); in-game "Restore Defaults" no longer hitches for seconds with a
      big rewind buffer; game launch with rewind enabled allocates once (single
      "Rewind:" init in the log, if logging shows it).

### Follow-ups discovered while implementing

- The `keepAwakeUSB` config key is camelCase, matching its immediate neighbours
  (`disableSleep`, `sshOnBoot`) rather than the older lowercase style the DEV_TODO entry
  suggested — deliberate.
- CFG setters were NOT given per-setter early-returns: `CFG_sync()` now compares content
  before writing, which subsumes the I/O benefit (a redundant set costs a read+compare,
  never a write).
- Core-requested SHUTDOWN (env cmd 7) deliberately does NOT trigger the slot-9 autosave —
  it fires mid-`retro_run` where a state save is unsafe, and the quitting core (Doom quit
  menu / failed init) rarely has a moment worth resuming. Revisit only if PRBOOM quit
  verification above shows a bad switcher experience.

---

## Game Switcher resumable filter + standalone-emulator resume

**Status:** merged to `main` 2026-07-26 (`13a4d3c4`, PR #54).
Switcher filter + setting verified on Brick (tg5040) and Smart Pro S (tg5050). N64 resume
handshake now verified on both Brick and Smart Pro S (tg5050 verified 2026-07-27, see
`.superpowers/sdd/2026-07-26-flycast-dc-pak/n64-tg5050-report.md`).

Two related changes:

1. **Switcher filter** — the Game Switcher lists only games with a resumable save state
   by default; Settings → System → "Game Switcher games" toggles between "Resumable only"
   and "All recent games" (config key `switcherresumableonly`). Non-resumable entries in
   "All" mode show `A START` instead of `A RESUME`.
2. **Standalone resume handshake** — nextui writes the slot to `/tmp/resume_slot.txt` on
   every launch; minarch consumes it in `State_resume()`. The N64 pak (mupen64plus +
   GLideN64 overlay) now consumes it too: `emu_ovl_consume_resume_slot()`
   (`emu_overlay.c`) is called once from `DisplayWindow::swapBuffers` after overlay init
   and auto-loads slots 0-7 via `M64CMD_STATE_SET_SLOT` + `M64CMD_STATE_LOAD`. Slots 8/9
   (fresh launch / minarch auto-resume) are ignored by design.

### On-device verification

- [x] **N64 resume on Smart Pro S** — done, 2026-07-27. `.so` and `N64.pak/` were
      already in sync with the repo on this card (no push needed — see report).
      User-verified end-to-end on real hardware (Mario Kart 64): saved to slot 0 via
      overlay, quit, relaunched — log shows `Core Status: State loaded from:
      Mario Kart 64 (U) [!]-3A67D998.st0` immediately after `[Overlay] Initialized
      successfully`, with no menu button touched, confirming the
      `/tmp/resume_slot.txt` handshake fired automatically. Matches Brick's
      already-verified behavior. Full evidence:
      `.superpowers/sdd/2026-07-26-flycast-dc-pak/n64-tg5050-report.md`.
      Found (not fixed): N64 save-state/SRAM data is not actually shared across
      devices despite `N64.pak/launch.sh`'s comment claiming it is — only the
      `.minui/<rom>.txt` resume marker is genuinely shared; the real `.st0`/`.eep`/
      `.mpk` files land under the per-device `$HOME` (`$USERDATA_PATH`), not
      `$SHARED_USERDATA_PATH`. Not exercised by same-device testing but would
      break resume across a physically-moved SD card. Fixed 2026-07-27 via
      `XDG_DATA_HOME` — verify item in the fix-round section at the top of this file.
- [x] **N64 fresh launch still cold-boots** on Smart Pro S — done, 2026-07-27.
      Verified directly (`/tmp/resume_slot.txt`=8, fresh launch): file consumed
      and unlinked, zero state/resume log lines, confirming
      `emu_ovl_consume_resume_slot()`'s `slot >= EMU_OVL_MAX_SLOTS` guard holds.
- [ ] **Brick Pro (pending hardware)** — switcher filter + setting, and N64 resume if the
      pak gains a tg4040 build.

### Standalone emulators still without resume

The repo ships exactly three standalone (non-minarch) emulator paks; everything else in
`skeleton/EXTRAS/Emus/` launches `minarch.elf` and already resumes via `State_resume()`:

| Pak | Emulator | Resume status |
|---|---|---|
| N64 | mupen64plus + GLideN64 overlay | **Works** (this change) |
| DC | flycast + nx_overlay | **Works**, incl. auto-save-on-quit to hidden slot 9 (consumed via `/tmp/resume_slot.txt`) — same handshake as N64. Merged to `main` 2026-07-27 (`99985dec`, PR #56). User-verified on both physical target devices: Brick (tg5040) hardware 2026-07-26 (HLE boot, overlay menu, save/load slots, quit-to-slot-9, switcher resume) and Smart Pro S (tg5050) in a later full session (real-BIOS boot verified on both devices, needs only `dc_boot.bin`; controller mapping shipped; tg5050 fully verified). Honestly still pending: full RA session test (a live achievement unlock, not just login/HTTPS), and Brick Pro (tg4040) once that hardware arrives. See `workspace/all/other/flycast/README.md` for details. |
| NDS | DraStic (closed-source binary) | **No resume, by design.** No overlay integration and no `.minui/` slot files, so NDS games are hidden by the resumable-only filter and show `A START` in "All" mode — honest behavior. Baking resume in would need DraStic's own savestate CLI/auto-load hooks, if any exist; the emu_overlay approach is not available without source. |

User-installed paks that are not part of this repo (e.g. a community PSP/PPSSPP pak) are
in the same position as NDS unless they write `.minui/<EMU>/<rom>.txt` slot files — if one
does, it must also consume `/tmp/resume_slot.txt` or the switcher's RESUME promise will be
cosmetic (exactly the bug fixed for N64).

### Deferred

Auto-save-on-quit parity: **done** — both halves built 2026-07-27 (minarch
`Menu_autosaveQuit` + N64 GLideN64 overlay) and user-verified on Brick and Smart Pro S
the same day. Every resume-capable emulator now quits to the hidden auto slot the way
DC does. NDS (DraStic) remains out of scope by design.

### Gotchas

- The GLideN64 build needs three aarch64 static libs recreated after applying the patch
  (bundled ones are x86-64; the patch records them content-lessly). Recipe in
  `workspace/all/other/mupen64plus/README.md` — note especially that `libz.a` must be
  a self-built zlib ≥1.2.9, NOT the sysroot's (sysroot zlib lacks `adler32_z` → the .so
  builds fine but fails `dlopen` at runtime with a blank screen).
- mupen64plus patches + docs live in `workspace/all/other/mupen64plus/` (deduped
  2026-07-26; per-platform dirs keep only the gitignored source checkouts). The GLideN64
  patch is regenerated against the pinned `GLIDEN64_COMMIT` in the platform Makefile —
  regenerate against that pin, not upstream master.

---

## Trimui Brick Pro (tg4040)

**Status:** ported 2026-07-25, merged to `main` 2026-07-26 (`c0da09c7`, PR #53). Never run
on hardware — device ordered 2026-07-25.

Ported from upstream NextUI [PR #766](https://github.com/LoveRetro/NextUI/pull/766) plus five
follow-up commits that fix bugs in it: `9dffb9e8` (L4/R4 remapping), `d47fb074` (`MAX_LIGHTS` 5),
`ff202893` (rumble voltage cap), `a20481b7` (mute-buzz voltage), `bade2a41` (minput R-group
layout regression).

### Build and flash

```bash
make all                       # produces releases/NextUI-<date>[-branch]-brickpro.zip
```

Copy the `-brickpro` zip to the SD card as `MinUI.zip` and boot, or for iterating on a single
binary use `make deploy DEVICE=brickpro` (pushes `MinUI.zip` over adb and reboots).

### Already verified — do not re-derive

Confirmed by reading the stock rootfs out of
`sd_recovery_tg4040_brick_pro_v1.1.1_20260717.img` (ext4 at sector 126432; recipe in `OSD.md`):

- `TRIMUI_MODEL` is exactly `Trimui Brick Pro` → `DEVICE=brickpro`
- LED zones are `f1 f2 m lr rear`; brightness nodes `max_scale`, `max_scale_f1f2`,
  `max_scale_lr`, `max_scale_rear` (see the table in `INPUT_MAPPING.md`)
- `/usr/trimui/bin/trimui_inputd` exists, so the tg5040 boot path works unchanged, and its
  turbo interface is the same `/tmp/trimui_inputd/turbo_*` flag files
- the Smart Pro's analog-pad GPIO poke (PD14/PD18) is **commented out** in the Brick Pro's own
  `runtrimui.sh` — its sticks need no GPIO setup
- `trimui_osdd` is a distinct build from the Brick's, which is why the assembled
  `osd-brickpro/` overlay (built from `skeleton/SYSTEM/osd/device/brickpro/` at
  package time) exists

### 1. On-device verification (Brick Pro)

- [ ] **Boots and identifies correctly** — UI is 1024×768 at 3× scale with 7 main rows.
      Confirm `DEVICE=brickpro` (not `smartpro`); a mis-detect shows up as a 1280×720 layout.
- [ ] **SDL joystick indices** — *the main unverified assumption.* Open
      Settings → Input Tester and press everything. Expected: 9/10 = stick clicks (L3/R3),
      11/12 = FN1/FN2 (shown as L4/R4), 13/14 = volume, 15 = HOME, 8 = MENU.
      Wrong indices look like dead or swapped buttons, **not** a crash.
- [ ] **Analog sticks** — both nubs move the on-screen indicators; `L3+R3` enters calibration.
- [ ] **Hall-stick calibration** — check whether `/dev/ttyAS5` / `/dev/ttyAS7`
      (`settings_input.c:68-71`) exist on this model; calibration is a no-op if they don't.
- [ ] **LEDs, all five zones** — Settings → LED Control shows F1 key / F2 key / Top bar /
      Joysticks / L/R triggers. Verify each zone lights the part it names (in particular that
      `lr` is the *joysticks* here and `rear` is the *triggers* — the opposite of the Brick).
- [ ] **LED brightness coupling** — F1 and F2 track each other (shared `max_scale_f1f2`);
      the other three are independent.
- [ ] **Per-zone effect lists** — the code picks by node name (`lr` gets the extended LR
      effects, `rear` gets the standard set). If an effect renders wrong or does nothing,
      adjust the selection in `settings_led.c` (`led_page_create`).
- [ ] **OSD** — long-press `MENU` opens it. Check the background/tile layout at 1024×768, that
      toasts land on-screen, and that the battery widget works (stock layout implies it does).
- [ ] **OSD stock restore** — overlay in `/proc/filesystems`; OSD overlay mount present after
      boot; Settings → Restore stock OSD round-trip (restore, verify rootfs matches
      `skeleton/SYSTEM/osd-stock/brickpro.manifest.md5`, reboot, NX OSD returns)
- [ ] **Rumble** — capped at 2.5 V; confirm it isn't unpleasantly strong at max.
- [ ] **Mute toggle buzz** — the FN-switch mute pulse uses 900000 µV on this model.
- [ ] **Backlight** — brightness ladder uses the Brick curve; check the low end isn't black.
- [ ] **HOME button** — maps to `BTN_HOME`, currently inert (matching Smart Pro S). Decide
      whether it should *do* something here; if so, note that it arrives as a gamepad button
      (index 15), not `KEY_HOMEPAGE`, so keymon's tg5050 Home path does not apply.

### 2. Regression checks (Brick / Smart Pro / Smart Pro S)

Shared code moved, so these need a pass on at least one older device:

- [ ] **Input Tester shoulder rendering** — L1/L2 and R2/R1 pills must look exactly as before.
      This is precisely what upstream broke and had to fix in `bade2a41`.
- [ ] **`pak.cfg` bind round-trip** — bind a shortcut in a game, restart minarch, confirm it
      survived. `BTN_ID_L4`/`BTN_ID_R4` were inserted mid-enum and `LOCAL_BUTTON_COUNT` went
      16 → 18; bindings persist by *name*, so this should hold, but it is the one change that
      could silently corrupt existing configs.
- [ ] **LED page** — Brick still shows 4 zones, Smart Pro/S still 3, and existing
      `ledsettings*.txt` files still parse after the `MAX_LIGHTS` 4 → 5 bump.
- [ ] **Brick Pro OSD background is now the Brick's.** `bg.png` moved into
      `res/<WxH>/` (it is exactly panel-sized, so it is resolution-locked art).
      The 1280×720 pair was byte-identical, so Smart Pro / Smart Pro S are
      unaffected. Brick Pro's stock version differed in 192 of 786,432 pixels:
      54 are ±1 alpha rounding on the panel corners (y≈56–80, invisible), and
      the other **138** are a teal accent (`0,255,163`) mirrored at x=41 and
      x=982, y≈686–711 — a 28 px fully-opaque core plus 110 px of anti-aliased
      edge. Brick's background is plain black there, so Brick Pro loses both
      accents. Judged negligible while the hardware is
      unavailable — look at it once a Brick Pro is in hand and restore
      `device/brickpro/bg.png` if the accents matter.

### 3. Deliberately deferred

Three items were scoped out of the port and are tracked in `DEV_TODO.md`: the PortMaster
device entry, display calibration / white point, and the wrongly-sized 1024×768 music
widget tile. None of them block bring-up.

### Gotchas

- OSD is overlay-mounted read-only at boot — from the SD directly on tg5050,
  via a tmpfs staging copy on tg5040 (its kernel 4.9 overlayfs rejects exFAT
  as a lower layer); no rootfs writes and no stamp on either. If the OSD looks
  stale or dead, check `/proc/mounts` for `/usr/trimui/osd` and
  `/tmp/nx_osd_mount_failed`.
- OSD assets are layered (`common/`, `res/<WxH>/`, `device/<dev>/`) and assembled
  by `scripts/assemble-osd.sh` at package time — edit the layer, not a device tree.
- `make deploy` now takes `DEVICE=` (e.g. `make deploy DEVICE=brickpro`). Passing
  only `PLATFORM=tg5040` deploys `brick`.
- Don't push an `.elf` over a running copy — stop the pak first. Only `nextui`/`minarch`
  need a reboot after pushing; other paks just need to not be running.
- Never `killall nextui` on device: the `kill -9` path powers the unit off.

---

## Thread-pinning `taskset` now actually works — re-verify everything that uses it

**Status:** fixed and merged to `main` 2026-07-27 (`99985dec`, PR #56 — task 11 fix round).
tg5050 (Smart Pro S) is now fully verified: native `taskset`, PS.pak's affinity probe,
DC.pak's pinning, and N64.pak's pinning (2026-07-27, once a game was installed) all
confirmed on real hardware. tg5040 (Brick) N64.pak re-verification with pinning
actually active is still pending.

`skeleton/SYSTEM/shared/bin/taskset` — the binary every pak's `taskset` calls resolved
to via `PATH` — was a `-static` build that aborted with `FATAL: kernel too old` on the
Brick's real 4.9.191 kernel. Every call site wraps `taskset` in `2>/dev/null`, so this
failure was completely silent: **every existing thread-pinning call in the repo has
been a no-op on tg5040 this whole time**, not just for DC.pak. Fixed by dropping
`-static` from `workspace/all/taskset/Makefile` and shipping working, platform-specific,
dynamically-linked binaries at `skeleton/SYSTEM/{tg5040,tg5050}/bin/taskset` (which
shadow the old shared path via existing `PATH` ordering — no call-site changes needed).
The old shared binary was deleted this round, so **there is no fallback anymore** if a
platform's `taskset` turns out to be broken on some device.

- [ ] **N64.pak pinning on Brick, with pinning actually active** — re-verify audio/perf
      with real affinity applied. The masks and the thread-name heuristic
      (`skeleton/EXTRAS/Emus/tg5040/N64.pak/launch.sh:100,108,127`) were written and
      shipped blind, against a `taskset` that always silently failed; they were never
      exercised for real until this fix, the same way DC.pak's pinning was
      evidence-gated by direct measurement (task-11 report) before shipping.
      **Known gap, measured on Smart Pro S 2026-07-27 (reproduced twice, incl. a real
      user session):** the "pin the busiest `mupen64plus`-named thread" heuristic only
      pins ONE of the (at least) two non-main threads named `mupen64plus`; the other is
      left on the unrestricted 0-7 mask. Measured impact is small: its load is bursty
      init/loading work (~3.6% during boot, ~0% in live gameplay), and since NextUI only
      brings cpu0-1/4(/5) online (8-core silicon run as effective 4-core by boot policy),
      "unrestricted" still lands it on the contended cores. The fix (pin unmatched threads
      to LITTLE by default) is written up in `DEV_TODO.md` and should land with this
      re-verify, so it ships measured rather than blind.
- [x] **tg5050 `taskset` + PS.pak on Smart Pro S** — done. The tg5050 binary
      (`skeleton/SYSTEM/tg5050/bin/taskset`) runs natively on real Smart Pro S
      hardware (no "kernel too old" abort). PS.pak's `taskset -c 4,5` launch line
      and its `pin_threads` calls (`skeleton/SYSTEM/tg5050/paks/Emus/PS.pak/launch.sh`)
      were confirmed applying real affinity, not silently falling back to a bare
      launch.
- [x] **DC.pak on Smart Pro S** — done. Same taskset binary; DC.pak's dual-cluster
      pinning was confirmed exact on real Smart Pro S hardware.
- [x] **N64.pak on Smart Pro S** — done, 2026-07-27, once a game was installed.
      All three bare `taskset` calls (`skeleton/EXTRAS/Emus/tg5050/N64.pak/launch.sh:87,95,114`)
      confirmed applying real affinity on two independent sessions (my own launch +
      a real user session): main thread → cpu4, video thread → cpu5, `m64pwq`/`mali-*`
      helpers → cpu0-1, all correct. Known gap (measured, not fixed): a second,
      unnamed `mupen64plus` thread is never pinned — see the Brick bullet above,
      where the fix is recorded as prescribed follow-up. Full evidence + CPU% tables:
      `.superpowers/sdd/2026-07-26-flycast-dc-pak/n64-tg5050-report.md`.
