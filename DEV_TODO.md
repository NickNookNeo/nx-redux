# Dev TODO

Work that is **planned but not built** — decided on, scoped, and worth doing, with no code
written yet. Each entry records enough context (why, where, known constraints) that a later
session can start implementing without re-deriving the design.

The two dev to-do files are a pipeline:

| File | Holds | Exit condition |
|---|---|---|
| `DEV_TODO.md` (this file) | designed / requested, nothing written | move the entry to `DEV_CHECKLIST.md` once it builds |
| `DEV_CHECKLIST.md` | built, not yet verified on hardware | delete the section once verified and shipped |

Neither file is a changelog — delete an entry when it lands, don't mark it done and keep it.

---

## N64: pin the unmatched `mupen64plus` threads

**Found:** 2026-07-27 on Smart Pro S (reproduced twice, incl. a real user session).
Deliberately left out of the flycast merge (`99985dec`) — the evidence said low impact, and the change
belongs with a measured Brick re-verify.

`launch.sh`'s "pin the busiest `mupen64plus`-named thread" heuristic
(`skeleton/EXTRAS/Emus/tg5040/N64.pak/launch.sh` pinning block and the tg5050 twin)
only pins ONE of the (at least) two non-main threads named `mupen64plus`;
the other keeps the unrestricted 0-7 mask.

- [ ] Add an else-branch to the scan loop that pins every unmatched thread to LITTLE by
      default. `DC.pak`'s `pin_threads()` is the reference pattern.

Measured impact is small — the stray thread's load is bursty init/loading work (~3.6%
during boot, ~0% in live gameplay), and since NextUI only brings cpu0-1/4(/5) online,
"unrestricted" still lands it on the contended cores. Do this together with the pending
Brick pinning re-verification in `DEV_CHECKLIST.md`, so the fix ships measured rather than
blind (which is how the original masks got here).

---

## Audio output routing + quality options

**Requested:** 2026-07-27 (GitHub comment on the music player + the flycast audio
investigation). **Not started.** Big enough to deserve its own design session
(brainstorming first) — deliberately kept out of the 2026-07-27 fix round.

Today every app plays through ALSA `default` = `softvol → dmix(48 kHz) → internal codec`,
hardcoded in the firmware's `/etc/asound.conf`. USB-C DACs enumerate as ALSA card 1 but
nothing routes to them; BT audio plumbing exists on-device (`bluealsa`, `pulseaudio`,
alsa-lib plugin modules all shipped) but the default PCM never reaches it. The 3.5 mm
jack "works" only because the codec chip switches speaker→headphone amp in hardware.

- [ ] **Music player** (the GitHub request): settings for output device (system default
      vs. detected USB DAC — cards visible in `/proc/asound/cards`), sample-rate mode
      (fixed 48 kHz vs. follow-source-when-sink-accepts, fallback to resample), SRC
      resampler quality (`src-sinc-fastest`/`medium`/`best` — currently hardcoded
      fastest), and buffer size (currently fixed 2048). Direct `hw:` output bypasses
      `softvol`, so device volume keys won't apply — fine for USB DACs (own volume),
      must be documented.
- [ ] **Sink-aware output for emulators** (flycast/minarch/N64): same routing question.
      flycast currently always opens SDL default at 48 kHz (deliberate — see
      `workspace/all/other/flycast/README.md` audio section). A USB/BT-aware path would
      need per-sink rate choice (USB DACs often prefer source rate) and a volume story.
      The internal codec HAS hardware volume controls (`DAC Volume`, `HPOUT Gain` —
      verified via amixer on tg5050), so a hw-volume route exists if softvol is bypassed.
- [ ] **BT audio**: confirm whether the stock/NextUI stack can route game audio to BT at
      all (bluealsa PCM open from an app), before promising it anywhere.

**Per-sink rate policy (design decision, 2026-07-27):** the output rate must follow the
selected sink, not a global constant — internal codec via dmix = always 48 kHz (dmix is
fixed there; anything else hits alsa-lib's linear resampler, the exact bug fixed in
flycast); direct `hw:` to the internal codec or a USB DAC = open at source rate,
negotiated, falling back to the nearest supported rate with an in-app quality resample
(SRC/SDL), never ALSA `plug`; Bluetooth = match whatever rate the A2DP codec negotiated
via the bluealsa PCM. Crucially, the rate CANNOT be autodetected through the `default`
PCM — `plug` accepts any rate and converts silently — so the policy keys off the
user-selected output device: `default` → force 48 kHz, `hw:X`/bluealsa → negotiate.

---

## Trimui Brick Pro: deferred from the port

Scoped out of the Brick Pro port (`c0da09c7`) on purpose. None of these block the port's
hardware bring-up (that checklist lives in `DEV_CHECKLIST.md`).

- [ ] **PortMaster device entry** — its detection keys off `/proc/device-tree/model`, which
      isn't recoverable from the firmware image. Brick Pro currently resolves to
      `trimui-smart-pro`, exactly as the Brick does today (no regression). To fix: read
      `cat /proc/device-tree/model` on the device and add an entry in
      `workspace/all/portmaster/portmaster.c` (`patch_device_info`) alongside the tg5050
      one. **Blocked on hardware.**
- [ ] **Display calibration / white point** — upstream's `displaycal.h` does not exist in
      this fork at all, so upstream's Brick Pro calibration commits (`64160e99`,
      `45406e12`) were out of scope. Porting white-point correction is its own piece of
      work.
- [ ] **Music widget tile is the wrong size on 1024×768** —
      `skeleton/SYSTEM/osd/common/widgets/app_music/skin/block4x2.png` is 540×260 and
      `block4x2_sel.png` is 544×264, both byte-identical to the 1280×720 versions; the
      1024×768 grid tiles are 556×268 and 560×272. So Brick and Brick Pro draw the music
      widget's 4×2 tile 16 px too narrow and 8 px too short. Pre-existing well before the
      OSD dedup refactor — the reorg only made it visible by putting the two variants side
      by side. **Blocked on an asset:** a 1024×768 pair does not exist anywhere in the
      repo. Until one is produced the file correctly stays in `common/`, since there is
      only one variant to ship.
