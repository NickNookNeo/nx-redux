# Dev Checklist

Running checklists for work that is **built but not yet verified on hardware**, so a later
session (or another person) can pick up the bring-up without re-deriving what is already known.

One section per in-flight effort. When a section is fully checked off and shipped, delete it —
this file is a to-do list, not a changelog.

Work that is **planned but not yet built** does not belong here — it lives in `DEV_TODO.md`.
Move an entry from there to here once it compiles and needs hardware time.

---

## Boot: failed MinUI.zip extraction must not brick the boot loop (built 2026-08-01)

Found live on Smart Pro S (fresh install, 2026-08-01): a truncated MinUI.zip
(card pulled before the 230 MB copy flushed) made `.tmp_update/<plat>.sh`
extract nothing, then `rm -f MinUI.zip` unconditionally — every later boot had
no zip, no `.system`, no splash, and fell through to `poweroff`. Looks like a
dead device. Fixed in both `workspace/{tg5040,tg5050}/install/boot.sh`: the
zip is consumed only when unzip succeeds; on failure a show2 error line is
displayed for 10 s and the zip is kept so the next boot retries. The pakz
loop got the same success-gated consume — a corrupt pakz is renamed
`<name>.failed` (kept for diagnosis, but not re-matched by the `*.pakz` glob,
so no per-boot retry nag) and boot continues normally.

- [ ] Happy path: fresh install extracts and launches normally (both devices).
- [ ] Corrupt-zip path: truncate a MinUI.zip on card (`head -c 10M`), boot →
      "Install failed" splash shows ~10 s, MinUI.zip still on card, device
      powers off; replacing the zip and rebooting installs cleanly.
- [ ] Corrupt-pakz path: truncate a pakz on card, boot → "Package install
      failed" splash ~5 s, file renamed `.failed`, system boots normally and
      the next boot does NOT re-attempt it.

---

## Upstream-port + fix round (built 2026-07-27)

**Status:** ten DEV_TODO items implemented 2026-07-27, committed as `1ccc1030`. All
changed elfs + the rebuilt GLideN64 `.so` + N64 launch.sh are pushed to both cards
(Brick and Smart Pro S, md5-verified 2026-07-27).

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

## Xtras pak (2026-08-08)

- [x] tg5040 Brick: Tools → Xtras lists Gen1Recomp; WiFi install e2e (downloads sha256-pinned, ROM auto-scan copies Red/Blue/Yellow via sha1 fallback, launcher registered last)
- [x] tg5040: reinstall preserves saves/caches/options (canary-verified on device)
- [x] tg5040: game boots via Emus/EXTRAS.pak with .ports layout; no swap/taskset tuning fires (tg5050-only by design); user-confirmed 2D gameplay
- [x] tg5040: final user eyeball of the segmented GAMES/TOOLS tabs after the UI redesign — mechanical re-verify (folder mv to "Xtra Games", uninstall/reinstall flows) already done on device
- [x] tg5050 Smart Pro S: voxel session >10 min to confirm the eMMC swapfile absorbs the ~750MB peak — mechanical e2e already done on device (install, uninstall/reinstall); note the platform-subdir layout fallback that was in extras_games_launch.sh at the time of that e2e run was removed (nx-redux has no supported platform-subdir card layout — see PORTS_PAK_DIR in portmaster.c), so this no longer needs re-covering
- [ ] Release build: `make <plat>` packages Xtras.pak with extras.elf + catalog (verify once before tagging)
- [ ] Future catalog entries checklist: pin sha256 for every download; every network command carries a timeout (popen streaming has no C-side watchdog); install.sh idempotent + registers launcher LAST; uninstall.sh keeps saves; no bare tool names beyond busybox (device PATH is minimal — sha1sum needs the PortMaster-bin fallback); host test in scripts/tests/; for a GAME entry, install.sh must create its `.ports` data dir named EXACTLY the catalog folder id (e.g. `$EXTRAS_PORTS_DIR/<id>`) — extras.c's read_installed() derives the version-marker path directly from AddonEntry.id with no other lookup, so a mismatched dir name reads back as permanently "not installed"; meta.txt supports an optional `runtime=ports|native` key (Task 15) — absent means `ports` (today's only kind, e.g. gen1recomp declares it explicitly); extras.c's `meta_set()` ignores unknown keys, so adding it needs no C change/rebuild; a `ports`-runtime entry depends on the PortMaster runtime already being unpacked at `Emus/shared/PortMaster/` — install.sh preflights that dir and fails closed with "PortMaster runtime not set up - open Tools > PortMaster first, then retry" before any download if it's missing; a `native` entry must ALSO have its own launcher script carry a `# NX_RUNTIME: native` marker line within its first 20 lines — `extras_games_launch.sh` / skeleton `Emus/EXTRAS.pak/launch.sh` grep for that marker and `exec` the entry's script directly (bypassing ports_launch.sh and the PortMaster dependency entirely), so a native entry owns its whole runtime itself (env vars, background services, cleanup); no native entry exists yet, this is a seam for one
- [ ] Task 13b naming sweep (pak Add-ons→Xtras, app addons→extras, platform tag ADDON→EXTRAS) re-verify on both devices at next deploy: `mv "Roms/Xtra Games (ADDON)" "Roms/Xtra Games (EXTRAS)"`, `rm -rf Emus/<plat>/ADDON.pak`, old `Add-ons.pak` dir removed before pushing the new `Xtras.pak`; the skeleton SYSTEM tree now ships `Emus/EXTRAS.pak` directly under `.system/paks/Emus/` (install.sh's self-install is only the repair path for a stale/missing skeleton) — a card that already picked up `Emus/<plat>/EXTRAS.pak` from a pre-Task-14 build of this branch needs `mv /mnt/SDCARD/Emus/<plat>/EXTRAS.pak /mnt/SDCARD/.system/paks/Emus/EXTRAS.pak` (or just `rm -rf` it and let the fresh skeleton push / self-install repair land it at the corrected `.system/paks/Emus/EXTRAS.pak` location)

### Notes

- Internal platform tag is EXTRAS ("Xtra Games (EXTRAS)" is display name only); nx-redux SD layouts are flattened on every device (`.system/paks/...`, see `PORTS_PAK_DIR` in portmaster.c) — `extras_games_launch.sh` targets that single path, no platform-subdir fallback (removed Task 14).
- `extras_games_launch.sh` / skeleton `Emus/EXTRAS.pak/launch.sh` (4 byte-identical copies) is a two-branch dispatcher (Task 15): a `# NX_RUNTIME: native` marker in the launched entry script's first 20 lines execs it directly; otherwise it execs `ports_launch.sh` as before. See the "Future catalog entries checklist" item above for the full `runtime=` contract.
