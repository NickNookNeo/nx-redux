#!/usr/bin/env bash
# Host-side test for the gen1recomp Xtras catalog installer.
# Network and device binaries are shimmed via PATH; all paths are sandboxed.
# A && pass "..." || fail "..." is used throughout below: pass()/fail() only
# printf and never fail, so the || branch never runs when the check is true.
# shellcheck disable=SC2015
# Single quotes are deliberate in the grep patterns below: they must match
# literal $SHDIR/$GAMEDIR text inside the installed launcher file, not
# expand against this script's own variables.
# shellcheck disable=SC2016
set -u

FAILS=0
say()  { printf '%s\n' "$*"; }
pass() { say "PASS: $*"; }
fail() { say "FAIL: $*"; FAILS=$((FAILS+1)); }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENTRY="$ROOT/skeleton/SYSTEM/tg5050/paks/Tools/Xtras.pak/catalog/gen1recomp"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- fixtures ---------------------------------------------------------
# Fake upstream game zip: Gen1recomp.sh + gen1recomp/{bin,libs.aarch64,lovegame}
FIX="$TMP/fix"
mkdir -p "$FIX/gen1recomp/bin" "$FIX/gen1recomp/libs.aarch64" \
         "$FIX/gen1recomp/lovegame/tools" "$FIX/gen1recomp/lovegame/src"
echo 'upstream-launcher' > "$FIX/Gen1recomp.sh"
echo 'love-bin-v1'       > "$FIX/gen1recomp/bin/love.aarch64"
echo 'liblove'           > "$FIX/gen1recomp/libs.aarch64/liblove-11.5.so"
echo 'main'              > "$FIX/gen1recomp/lovegame/main.lua"
echo '{"red":1}'         > "$FIX/gen1recomp/lovegame/tools/rom_manifest.json"
(cd "$FIX" && zip -qr "$TMP/game.zip" Gen1recomp.sh gen1recomp)

echo '{"yellow":1}' > "$TMP/rom_manifest_yellow.json"

MODFIX="$TMP/modfix"
mkdir -p "$MODFIX/assets"
echo '{"id":"DRAMATIC_SHAPE"}' > "$MODFIX/manifest.json"
echo 'voxels' > "$MODFIX/assets/a.bin"
(cd "$MODFIX" && zip -qr "$TMP/mod.zip" manifest.json assets)

# Running Shoes fixture: versioned asset name, contents at the zip root.
SHOESFIX="$TMP/shoesfix"
mkdir -p "$SHOESFIX"
echo '{"id":"running_shoes"}' > "$SHOESFIX/manifest.json"
echo 'lua' > "$SHOESFIX/main.lua"
(cd "$SHOESFIX" && zip -qr "$TMP/shoes.zip" manifest.json main.lua)

# Wilds of Kanto fixture: a GitHub SOURCE archive - everything under a
# "<repo>-<branch>/" wrapper dir, NOT at the zip root - so this exercises
# install.sh's manifest.json-locating step, not just a plain extract.
WILDSFIX="$TMP/wildsfix"
mkdir -p "$WILDSFIX/overworld-spawn-mod-main/assets"
echo '{"id":"overworld_wild_spawns"}' > "$WILDSFIX/overworld-spawn-mod-main/manifest.json"
echo 'lua'    > "$WILDSFIX/overworld-spawn-mod-main/main.lua"
echo 'sprite' > "$WILDSFIX/overworld-spawn-mod-main/assets/a.png"
(cd "$WILDSFIX" && zip -qr "$TMP/wilds.zip" overworld-spawn-mod-main)

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Fake GitHub latest-release API responses. Decoy assets sit FIRST so the
# "matched by glob, paired with its own digest" logic is actually exercised.
# Field order inside each asset (name -> digest -> browser_download_url)
# mirrors the real API - resolve_latest's token-stream walk depends on it.
write_game_json() { # digest
  cat > "$TMP/game_release.json" <<EOF
{
  "tag_name": "v9.9.9",
  "name": "Release v9.9.9",
  "assets": [
    {
      "name": "gen1recomp-9.9.9-linux.zip",
      "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
      "browser_download_url": "https://github.com/bryanthaboi/gen1recomp/releases/download/v9.9.9/gen1recomp-9.9.9-linux.zip"
    },
    {
      "name": "gen1recomp-9.9.9-rg34xxsp-stockos64-mod.zip",
      "digest": "sha256:$1",
      "browser_download_url": "https://github.com/bryanthaboi/gen1recomp/releases/download/v9.9.9/gen1recomp-9.9.9-rg34xxsp-stockos64-mod.zip"
    }
  ]
}
EOF
}
write_mod_json() { # digest
  cat > "$TMP/mod_release.json" <<EOF
{
  "tag_name": "v1.2.3",
  "name": "Release v1.2.3",
  "assets": [
    {
      "name": "DRAMATIC_SHAPE-1.2.3.zip",
      "digest": "sha256:$1",
      "browser_download_url": "https://github.com/DramaticShape/DramaticShapeVoxelMod/releases/download/v1.2.3/DRAMATIC_SHAPE-1.2.3.zip"
    }
  ]
}
EOF
}
write_shoes_json() { # digest
  cat > "$TMP/shoes_release.json" <<EOF
{
  "tag_name": "v1.4.1",
  "name": "running_shoes 1.4.1",
  "assets": [
    {
      "name": "running_shoes-1.4.1.zip",
      "digest": "sha256:$1",
      "browser_download_url": "https://github.com/MadeinTaly/gen1recomp-running-shoes/releases/download/v1.4.1/running_shoes-1.4.1.zip"
    }
  ]
}
EOF
}
write_wilds_json() { # digest
  cat > "$TMP/wilds_release.json" <<EOF
{
  "tag_name": "v1.12.1",
  "name": "Wilds of Kanto v1.12.1",
  "assets": [
    {
      "name": "Wilds.of.Kanto.v1.12.1.zip",
      "digest": "sha256:$1",
      "browser_download_url": "https://github.com/YoDrehDenSwagAuf/overworld-spawn-mod/releases/download/v1.12.1/Wilds.of.Kanto.v1.12.1.zip"
    }
  ]
}
EOF
}

# ---- sandbox SD card --------------------------------------------------
SD="$TMP/sd"
GB_DIR="$SD/Roms/Game Boy (GB)"
GBC_DIR="$SD/Roms/Game Boy Color (GBC)"
mkdir -p "$GB_DIR" "$GBC_DIR" "$SD/.userdata/tg5050/logs"
# A "Red" ROM whose sha256 we control via the sha256sum shim below.
echo 'red-rom' > "$GB_DIR/Pokemon Red.gb"
echo 'junk'    > "$GB_DIR/Tetris.gb"

# ---- PATH shims -------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"
# wget shim: serves fixtures by matching the URL tail.
cat > "$BIN/wget" <<SHIM
#!/usr/bin/env bash
out=""; url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -O) out="\$2"; shift ;;
    -*) ;;
    *) url="\$1" ;;
  esac
  shift
done
case "\$url" in
  *bryanthaboi/gen1recomp/releases/latest) cp "$TMP/game_release.json" "\$out" ;;
  *DramaticShapeVoxelMod/releases/latest)
    # flag file simulates the (real, 2026-08-10) deleted/private upstream
    if [ -f "$TMP/voxel_upstream_down" ]; then exit 1; fi
    cp "$TMP/mod_release.json" "\$out" ;;
  *gen1recomp-running-shoes/releases/latest) cp "$TMP/shoes_release.json" "\$out" ;;
  *overworld-spawn-mod/releases/latest)    cp "$TMP/wilds_release.json" "\$out" ;;
  *stockos64-mod.zip)        cp "$TMP/game.zip" "\$out" ;;
  *rom_manifest_yellow.json) cp "$TMP/rom_manifest_yellow.json" "\$out" ;;
  *DRAMATIC_SHAPE*.zip)      cp "$TMP/mod.zip" "\$out" ;;
  *running_shoes-*.zip)      cp "$TMP/shoes.zip" "\$out" ;;
  *Wilds.of.Kanto*.zip)      cp "$TMP/wilds.zip" "\$out" ;;
  *) echo "wget shim: unknown url \$url" >&2; exit 1 ;;
esac
SHIM
chmod +x "$BIN/wget"
# sha256sum shim -> host shasum (macOS has no sha256sum), EXCEPT the Red ROM
# fixture, which reports the pinned real-dump sha256 the install.sh ROM scan
# whitelists (the scan is sha256-keyed since 2026-08-10 - sha1sum only ever
# existed inside PortMaster's vendored bin, which runtime=native users don't
# have). Everything else (download digest checks) hashes for real.
cat > "$BIN/sha256sum" <<SHIM
#!/usr/bin/env bash
for f in "\$@"; do
  case "\$f" in
    *"Pokemon Red.gb")
      echo "5ca7ba01642a3b27b0cc0b5349b52792795b62d3ed977e98a09390659af96b7b  \$f"
      exit 0 ;;
  esac
done
shasum -a 256 "\$@"
SHIM
chmod +x "$BIN/sha256sum"

run_install() {
  # Regenerate the API fixtures each call: digests default to the CURRENT
  # payload hashes (test 2 rebuilds game.zip; test 4 corrupts mod.zip and
  # relies on its hash being recomputed so the failure lands at extract,
  # not fetch), and the GAME_DIGEST override lets the mismatch scenario
  # serve a bad digest without touching the happy-path plumbing. The voxel
  # mod has BOTH a live-API fixture (mod_release.json, used when the
  # upstream-down flag file is absent) and the pinned-backup override
  # NX_VOXEL_SHA256 below (used when the fallback path runs, test 1b) -
  # each follows the same recompute-from-current-payload rule.
  write_game_json "${GAME_DIGEST:-$(sha "$TMP/game.zip")}"
  write_mod_json  "${MOD_DIGEST:-$(sha "$TMP/mod.zip")}"
  write_shoes_json "${SHOES_DIGEST:-$(sha "$TMP/shoes.zip")}"
  write_wilds_json "${WILDS_DIGEST:-$(sha "$TMP/wilds.zip")}"
  NX_VOXEL_SHA256="$(sha "$TMP/mod.zip")" \
  PATH="$BIN:$PATH" \
  PLATFORM=tg5050 \
  SDCARD_PATH="$SD" \
  LOGS_PATH="$SD/.userdata/tg5050/logs" \
  EXTRAS_ROMS_DIR="$SD/Roms/Xtra Games (EXTRAS)" \
  EXTRAS_DATA_DIR="$SD/Roms/Xtra Games (EXTRAS)/.data" \
  CATALOG_DIR="$ENTRY" \
  XTRAS_STATE_DIR="$SD/.userdata/shared/xtras" \
  NX_EXTRAS_UNZIP="${NX_EXTRAS_UNZIP_OVERRIDE:-unzip}" \
  bash "$ENTRY/install.sh"
}

G="$SD/Roms/Xtra Games (EXTRAS)/.data/gen1recomp"

# ---- 0. preflight: system unzip tool probe ----------------------------
# Since the runtime=native conversion (2026-08-10) nothing here depends on
# PortMaster; the only preflight is the SYSTEM-shipped 7zzs (psp/install.sh
# posture). A missing/broken system tree must abort before any network use.
if NX_EXTRAS_UNZIP_OVERRIDE="$TMP/no-such-7zzs" run_install > "$TMP/log0.txt" 2>&1; then
  fail "preflight: missing system unzip did not abort"
else pass "preflight: missing system unzip aborts"; fi
grep -q 'system unzip tool missing' "$TMP/log0.txt" \
  && pass "preflight: message printed" || fail "preflight: message missing"
! grep -q 'Downloading' "$TMP/log0.txt" \
  && pass "preflight: no download attempted" || fail "preflight: a download was attempted despite missing unzip"
[ ! -d "$G" ] \
  && pass "preflight: nothing written to install target" || fail "preflight: install target created despite missing unzip"
[ ! -e "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "preflight: no launcher registered" || fail "preflight: launcher registered despite missing unzip"

# ---- 1. fresh install -------------------------------------------------
if run_install > "$TMP/log1.txt" 2>&1; then pass "fresh install exits 0"
else fail "fresh install exited non-zero: $(tail -3 "$TMP/log1.txt")"; fi
[ -f "$G/bin/love.aarch64" ]                        && pass "runtime extracted"        || fail "runtime missing"
[ -f "$G/lovegame/tools/rom_manifest_yellow.json" ] && pass "yellow manifest in place" || fail "yellow manifest missing"
[ -f "$G/lovegame/mods/DRAMATIC_SHAPE/manifest.json" ] && pass "voxel mod installed"   || fail "voxel mod missing"
[ -f "$G/lovegame/mods/running_shoes/manifest.json" ] && pass "running shoes mod installed" || fail "running shoes mod missing"
# Wrapper dir must be stripped: manifest.json at the mod root, not nested.
[ -f "$G/lovegame/mods/overworld_wild_spawns/manifest.json" ] \
                                                     && pass "wilds of kanto mod installed (wrapper stripped)" || fail "wilds of kanto mod missing or still wrapped"
[ ! -d "$G/lovegame/mods/overworld_wild_spawns/overworld-spawn-mod-main" ] \
                                                     && pass "wilds of kanto wrapper dir not nested" || fail "wilds of kanto wrapper dir leaked into mod folder"
[ -f "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] && pass "launcher registered"     || fail "launcher missing"
# The EXTRAS platform runtime self-installs under .system/paks/Emus -
# nextui's first-priority PAKS_PATH lookup location (hasEmu() in
# content.c checks it before the flat Emus/ and platform-subfolder
# Emus/$PLATFORM/ fallbacks) - not under Emus/$PLATFORM, which is the
# community-pak convention.
[ -f "$SD/.system/paks/Emus/EXTRAS.pak/launch.sh" ] \
  && pass "EXTRAS.pak self-installed under .system/paks/Emus" \
  || fail "EXTRAS.pak not self-installed under .system/paks/Emus"
[ ! -e "$SD/Emus/tg5050/EXTRAS.pak" ] \
  && pass "EXTRAS.pak not leaked into legacy Emus/\$PLATFORM location" \
  || fail "EXTRAS.pak wrongly installed at legacy Emus/\$PLATFORM location"
grep -q 'GAMEDIR="$SHDIR/.data/gen1recomp"' \
  "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh"      && pass "launcher is nx-patched"  || fail "launcher not patched"
# runtime=native contract: extras_games_launch.sh execs the entry directly
# only when this marker sits in the script's first 20 lines.
head -20 "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" | grep -q '^# NX_RUNTIME: native' \
                                                     && pass "launcher carries the native runtime marker" || fail "native runtime marker missing from launcher"
# First-launch stall fix (2026-08-10): the 512MB swapfile dd must run in a
# backgrounded subshell (closing "') &'" at column 0), not in the game's
# critical path - in the foreground it was 10-20s of black screen that read
# as a broken launch.
grep -q '^) &' "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" \
                                                     && pass "launcher swapfile block is backgrounded" || fail "launcher swapfile block runs in the foreground"
# Display alias (map.txt is filename<TAB>alias, content.c Directory_index):
# without it the list shows the launcher basename "Gen1recomp" (lowercase r).
MAPFILE="$SD/Roms/Xtra Games (EXTRAS)/map.txt"
TAB="$(printf '\t')"
[ "$(grep -c "^Gen1recomp\.sh$TAB" "$MAPFILE" 2>/dev/null)" = "1" ] \
                                                     && pass "display alias written once"  || fail "display alias missing or duplicated"
grep -q "^Gen1recomp\.sh${TAB}Gen1Recomp (Pokemon R/B/Y)\$" "$MAPFILE" \
                                                     && pass "display alias has the right name" || fail "display alias name wrong"
[ -f "$G/lovegame/Pokemon Red.gb" ]                  && pass "ROM scan copied Red"      || fail "Red not copied"
[ ! -f "$G/lovegame/Tetris.gb" ]                     && pass "ROM scan skipped junk"    || fail "junk ROM copied"
[ "$(cat "$G/.nx_addon_version" 2>/dev/null)" = "v9.9.9" ] \
                                                     && pass "version marker written"  || fail "version marker wrong"
[ "$(cat "$SD/.userdata/shared/xtras/gen1recomp.version" 2>/dev/null)" = "v9.9.9" ] \
                                                     && pass "version record written"  || fail "version record wrong"
grep -q 'Latest game release: v9.9.9' "$TMP/log1.txt" \
                                                     && pass "resolved game release announced" || fail "no resolved game release line"
grep -q 'Latest mod release: v1.2.3' "$TMP/log1.txt" \
                                                     && pass "resolved mod release announced (live upstream)" || fail "no resolved mod release line"
grep -q 'Latest running shoes release: v1.4.1' "$TMP/log1.txt" \
                                                     && pass "resolved running shoes release announced" || fail "no resolved running shoes release line"
grep -q 'Latest wilds of kanto release: v1.12.1' "$TMP/log1.txt" \
                                                     && pass "resolved wilds release announced" || fail "no resolved wilds release line"
# Task 11: install.sh's "@NN status text" progress hints - a bare "@90 " (NN
# followed by a space) proves the hint syntax parses correctly, and that the
# original human-readable message on the very next line ("Looking for your
# Pokemon ROMs...", asserted just below) still stands unprefixed/untouched.
grep -q '@90 ' "$TMP/log1.txt"                       && pass "install emits @NN progress hints" \
                                                      || fail "no @NN progress hint found in install output"
grep -q '^Looking for your Pokemon ROMs\.\.\.$' "$TMP/log1.txt" \
                                                     && pass "hint line doesn't clobber the adjacent message line" \
                                                     || fail "message line after a hint was altered"

# ---- 1b. voxel upstream gone -> archived-backup fallback ---------------
# Reality as of 2026-08-10: the DramaticShape account 404s (deleted or
# private - the API can't tell). The live repo is still tried first so a
# restored repo resumes latest-tracking on its own; this scenario flips the
# shim to fail that ONE API call. The install must still succeed, announce
# the fallback, and install the voxel mod from the pinned backup URL (whose
# DRAMATIC_SHAPE-*.zip basename the download shim case serves the same way).
touch "$TMP/voxel_upstream_down"
rm -rf "$G/lovegame/mods/DRAMATIC_SHAPE"   # so success below proves a fresh install
if run_install > "$TMP/log1b.txt" 2>&1; then pass "install with dead voxel upstream exits 0"
else fail "install with dead voxel upstream exited non-zero: $(tail -3 "$TMP/log1b.txt")"; fi
grep -q 'Voxel Mod upstream unavailable - using archived 1.7.2-backup' "$TMP/log1b.txt" \
  && pass "voxel fallback announced" || fail "no voxel fallback announcement"
[ -f "$G/lovegame/mods/DRAMATIC_SHAPE/manifest.json" ] \
  && pass "voxel mod installed from backup" || fail "voxel mod missing after fallback"
! grep -q '^ERROR' "$TMP/log1b.txt" \
  && pass "fallback surfaced no error" || fail "fallback surfaced an ERROR line"
rm -f "$TMP/voxel_upstream_down"

# ---- 2. reinstall preserves user data ---------------------------------
mkdir -p "$G/lovegame/red" "$G/conf"
echo 'save' > "$G/lovegame/red/cache.bin"
echo 'opts' > "$G/lovegame/options.lua"
# A foreign alias line (another catalog entry / a user rename) must survive
# the reinstall's upsert, and our own line must not duplicate.
printf 'Other.sh\tOther Game\n' >> "$MAPFILE"
# A pokepcfollowers dir left by the briefly-bundled (2026-08-10, dropped
# same day) follower mod must be cleaned up by the reinstall.
mkdir -p "$G/lovegame/mods/pokepcfollowers"
echo 'stale' > "$G/lovegame/mods/pokepcfollowers/manifest.json"
echo 'love-bin-v2' > "$FIX/gen1recomp/bin/love.aarch64"
(cd "$FIX" && zip -qr "$TMP/game.zip" Gen1recomp.sh gen1recomp)  # rebuild zip
if run_install > "$TMP/log2.txt" 2>&1; then pass "reinstall exits 0"
else fail "reinstall exited non-zero: $(tail -3 "$TMP/log2.txt")"; fi
[ "$(cat "$G/lovegame/red/cache.bin")" = "save" ] && pass "ROM cache preserved"    || fail "ROM cache clobbered"
[ "$(cat "$G/lovegame/options.lua")" = "opts" ]   && pass "options.lua preserved"  || fail "options.lua clobbered"
[ "$(cat "$G/bin/love.aarch64")" = "love-bin-v2" ] && pass "engine payload updated" || fail "engine not updated"
[ "$(grep -c "^Gen1recomp\.sh$TAB" "$MAPFILE" 2>/dev/null)" = "1" ] \
                                                  && pass "reinstall: alias upserted, not duplicated" || fail "reinstall: alias duplicated or lost"
grep -q "^Other\.sh${TAB}Other Game\$" "$MAPFILE" && pass "reinstall: foreign alias line kept" || fail "reinstall: foreign alias line lost"
[ ! -d "$G/lovegame/mods/pokepcfollowers" ] \
                                                  && pass "reinstall: stale pokepcfollowers removed" || fail "reinstall: stale pokepcfollowers still present"

# ---- 3. digest mismatch aborts before touching the install ------------
rm -rf "$SD/Roms/Xtra Games (EXTRAS)"
if GAME_DIGEST="deadbeef" run_install > "$TMP/log3.txt" 2>&1; then
  fail "digest mismatch did not abort"
else pass "digest mismatch aborts"; fi
[ ! -e "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "no launcher registered on failure" || fail "launcher registered despite failure"
grep -qi 'checksum' "$TMP/log3.txt" && pass "failure names the checksum" || fail "no checksum message"

# ---- 4. failure after $TARGET is dirtied removes the stale launcher ---
# Start from a clean, successful install so a real launcher is registered
# (test 3 above tore the EXTRAS dir down and aborted before touching it).
rm -rf "$SD/Roms/Xtra Games (EXTRAS)"
if run_install > "$TMP/log4-setup.txt" 2>&1; then pass "setup: baseline install exits 0"
else fail "setup: baseline install exited non-zero: $(tail -3 "$TMP/log4-setup.txt")"; fi
[ -f "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "setup: baseline launcher present" || fail "setup: baseline launcher missing"

# Corrupt the voxel payload in place. run_install() recomputes its
# NX_VOXEL_SHA256 override from the CURRENT file each call, so the
# download/checksum step still passes and the failure instead happens during
# extraction - i.e. after the game payload overlay-copy has already started
# writing into $TARGET, which is exactly the scenario the fix covers.
echo 'not a zip file' > "$TMP/mod.zip"
if run_install > "$TMP/log4.txt" 2>&1; then
  fail "corrupt mod payload did not abort"
else pass "corrupt mod payload aborts"; fi
[ -f "$G/bin/love.aarch64" ] \
  && pass "target payload preserved despite mid-install failure" || fail "target payload missing after failed reinstall"
[ ! -e "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "stale launcher removed after mid-install failure" || fail "stale launcher still present after mid-install failure"
grep -q 'install broken, launcher removed' "$TMP/log4.txt" \
  && pass "failure explains launcher removal" || fail "no launcher-removal explanation in log"

# ---- 5. ROM auto-scan works with NO sha1 tool anywhere on PATH ----------
# The original field gap: the scan was sha1-keyed, busybox on the card has no
# sha1sum applet and the only sha1sum lives inside PortMaster's vendored bin
# - so runtime=native users (no PortMaster) always got "install succeeded,
# 0 ROMs copied". The scan is sha256-keyed now (same busybox sha256sum the
# download digest checks already require), so it must WORK on a PATH with no
# sha1 tool at all. Prove that deterministically: an isolated PATH containing
# only the exact binaries install.sh needs (this test's own wget/sha256sum
# shims, plus the real system mkdir/rm/cp/basename/cut/unzip/dirname by
# direct symlink), and nothing else - a bare `PATH="$BIN:$PATH"` prepend
# wouldn't prove anything on a host that has a real sha1sum elsewhere on its
# inherited PATH (this dev machine does: /sbin/sha1sum).
BIN_NOSHA1="$TMP/bin_nosha1"
mkdir -p "$BIN_NOSHA1"
# shasum is what the sha256sum shim shells out to internally (macOS has no
# real sha256sum) - it lives in a different real directory (/usr/bin) than
# this host's real sha1sum (/sbin), so symlinking it by exact binary keeps
# the "no sha1sum anywhere on PATH" guarantee.
for c in bash mkdir rm cp mv basename cut unzip dirname shasum sed grep head; do
  tool_path="$(command -v "$c")" || { fail "host is missing '$c', can't build the no-sha1 PATH fixture"; tool_path=""; }
  [ -n "$tool_path" ] && ln -s "$tool_path" "$BIN_NOSHA1/$c"
done
ln -s "$BIN/wget" "$BIN_NOSHA1/wget"
ln -s "$BIN/sha256sum" "$BIN_NOSHA1/sha256sum"

# Test 4 left $TMP/mod.zip corrupted on purpose (not a valid archive); zip
# won't overwrite it in place ("Zip file structure invalid"), so remove it
# before rebuilding a valid one - needed so this install can reach the
# ROM-scan step instead of failing earlier at extract.
rm -f "$TMP/mod.zip"
(cd "$MODFIX" && zip -qr "$TMP/mod.zip" manifest.json assets)

# Write the API fixtures (and the voxel pin override) with the CURRENT
# (unmodified) PATH/shasum, as separate statements before the PATH override
# below - the digest defaults inside them run `sha`, which must not resolve
# against the isolated (sha1-less, and shasum-less) PATH.
write_game_json "$(sha "$TMP/game.zip")"
write_mod_json  "$(sha "$TMP/mod.zip")"
write_shoes_json "$(sha "$TMP/shoes.zip")"
write_wilds_json "$(sha "$TMP/wilds.zip")"
VOXEL_SHA_NOSHA1="$(sha "$TMP/mod.zip")"

rm -rf "$SD/Roms/Xtra Games (EXTRAS)"
if NX_VOXEL_SHA256="$VOXEL_SHA_NOSHA1" \
   PATH="$BIN_NOSHA1" \
   PLATFORM=tg5050 \
   SDCARD_PATH="$SD" \
   LOGS_PATH="$SD/.userdata/tg5050/logs" \
   EXTRAS_ROMS_DIR="$SD/Roms/Xtra Games (EXTRAS)" \
   EXTRAS_DATA_DIR="$SD/Roms/Xtra Games (EXTRAS)/.data" \
   CATALOG_DIR="$ENTRY" \
   XTRAS_STATE_DIR="$SD/.userdata/shared/xtras" \
   NX_EXTRAS_UNZIP=unzip \
   bash "$ENTRY/install.sh" > "$TMP/log5.txt" 2>&1
then pass "install with no sha1 tool anywhere exits 0"
else fail "install with no sha1 tool anywhere exited non-zero: $(tail -3 "$TMP/log5.txt")"; fi
[ -f "$G/lovegame/Pokemon Red.gb" ] \
  && pass "no sha1 tool: ROM scan still copied Red (sha256-keyed)" || fail "no sha1 tool: ROM scan copied nothing"
[ ! -f "$G/lovegame/Tetris.gb" ] \
  && pass "no sha1 tool: junk ROM still skipped" || fail "no sha1 tool: junk ROM copied"
! grep -qi 'ROM auto-scan skipped' "$TMP/log5.txt" \
  && pass "no sha1 tool: no skip message printed" || fail "no sha1 tool: scan still skipped itself"
[ -f "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "no sha1 tool: install completed (launcher registered)" \
  || fail "no sha1 tool: install did not complete"

# ---- 6. uninstall keeps saves ------------------------------------------
# uninstall.sh's contract (Task 9): keep-saves - remove the launcher, the
# marker, and the engine/runtime payload, but never touch anything a play
# session would have written (ROM save caches, options.lua, conf/, the
# user's own ROM copies). Needs no network shims at all.
run_uninstall() {
  PATH="$BIN:$PATH" \
  PLATFORM=tg5050 \
  SDCARD_PATH="$SD" \
  LOGS_PATH="$SD/.userdata/tg5050/logs" \
  EXTRAS_ROMS_DIR="$SD/Roms/Xtra Games (EXTRAS)" \
  EXTRAS_DATA_DIR="$SD/Roms/Xtra Games (EXTRAS)/.data" \
  CATALOG_DIR="$ENTRY" \
  XTRAS_STATE_DIR="$SD/.userdata/shared/xtras" \
  bash "$ENTRY/uninstall.sh"
}

# Fresh baseline install (normal PATH, so the ROM auto-scan runs) - section 5
# above deliberately left the sandbox in a no-ROM state, which isn't a useful
# starting point for proving preserved user data survives uninstall.
rm -rf "$SD/Roms/Xtra Games (EXTRAS)"
if run_install > "$TMP/log6-setup.txt" 2>&1; then pass "setup: uninstall-test baseline install exits 0"
else fail "setup: uninstall-test baseline install exited non-zero: $(tail -3 "$TMP/log6-setup.txt")"; fi

# Simulate save data + config a real play session would have created -
# nothing install.sh itself writes, so nothing already asserts these exist.
mkdir -p "$G/lovegame/red" "$G/conf"
echo 'save' > "$G/lovegame/red/cache.bin"
echo 'opts' > "$G/lovegame/options.lua"
echo 'cfg'  > "$G/conf/settings.cfg"
# A foreign alias line: uninstall must drop only this entry's line.
printf 'Other.sh\tOther Game\n' >> "$MAPFILE"

if run_uninstall > "$TMP/log6.txt" 2>&1; then pass "uninstall exits 0"
else fail "uninstall exited non-zero: $(tail -3 "$TMP/log6.txt")"; fi

[ ! -e "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "uninstall: launcher removed"        || fail "uninstall: launcher still present"
! grep -q "^Gen1recomp\.sh$TAB" "$MAPFILE" 2>/dev/null \
  && pass "uninstall: display alias removed"   || fail "uninstall: display alias still present"
grep -q "^Other\.sh${TAB}Other Game\$" "$MAPFILE" 2>/dev/null \
  && pass "uninstall: foreign alias line kept" || fail "uninstall: foreign alias line lost"
[ ! -e "$G/.nx_addon_version" ]                 \
  && pass "uninstall: version marker removed"  || fail "uninstall: version marker still present"
[ ! -e "$SD/.userdata/shared/xtras/gen1recomp.version" ] \
  && pass "uninstall: version record removed"  || fail "uninstall: version record still present"
[ ! -d "$G/bin" ]                               \
  && pass "uninstall: bin/ removed"             || fail "uninstall: bin/ still present"
[ ! -d "$G/libs.aarch64" ]                      \
  && pass "uninstall: libs.aarch64/ removed"    || fail "uninstall: libs.aarch64/ still present"
[ ! -f "$G/lovegame/main.lua" ]                 \
  && pass "uninstall: engine main.lua removed"  || fail "uninstall: main.lua still present"
[ ! -d "$G/lovegame/tools" ]                    \
  && pass "uninstall: lovegame/tools removed"   || fail "uninstall: lovegame/tools still present"
[ ! -d "$G/lovegame/mods" ]                     \
  && pass "uninstall: lovegame/mods removed"    || fail "uninstall: lovegame/mods still present"

[ "$(cat "$G/lovegame/red/cache.bin" 2>/dev/null)" = "save" ] \
  && pass "uninstall: ROM save cache kept"      || fail "uninstall: ROM save cache lost"
[ "$(cat "$G/lovegame/options.lua" 2>/dev/null)" = "opts" ]   \
  && pass "uninstall: options.lua kept"         || fail "uninstall: options.lua lost"
[ "$(cat "$G/conf/settings.cfg" 2>/dev/null)" = "cfg" ]       \
  && pass "uninstall: conf/ kept"               || fail "uninstall: conf/ lost"
[ -f "$G/lovegame/Pokemon Red.gb" ]             \
  && pass "uninstall: copied ROM kept"          || fail "uninstall: copied ROM lost"

grep -qi 'saves and ROMs kept' "$TMP/log6.txt" \
  && pass "uninstall: kept-message printed"     || fail "uninstall: kept-message missing"
# Task 11: uninstall.sh's own "@NN status text" progress hints.
grep -q '@100 ' "$TMP/log6.txt"                 \
  && pass "uninstall emits @NN progress hints"  || fail "no @NN progress hint found in uninstall output"

# Idempotent: nothing above still exists, so a second run must exit 0 too
# rather than erroring on already-missing paths.
if run_uninstall > "$TMP/log6b.txt" 2>&1; then pass "uninstall: second run exits 0 (idempotent)"
else fail "uninstall: second run exited non-zero: $(tail -3 "$TMP/log6b.txt")"; fi
[ "$(cat "$G/lovegame/red/cache.bin" 2>/dev/null)" = "save" ] \
  && pass "uninstall: idempotent run didn't touch saves either" || fail "uninstall: second run touched saves"

# ---- 7. reinstall after uninstall fully restores the entry -------------
if run_install > "$TMP/log7.txt" 2>&1; then pass "reinstall after uninstall exits 0"
else fail "reinstall after uninstall exited non-zero: $(tail -3 "$TMP/log7.txt")"; fi
[ -f "$G/bin/love.aarch64" ] \
  && pass "reinstall after uninstall: engine restored"   || fail "reinstall after uninstall: engine missing"
[ -f "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "reinstall after uninstall: launcher restored" || fail "reinstall after uninstall: launcher missing"
grep -q "^Gen1recomp\.sh${TAB}Gen1Recomp (Pokemon R/B/Y)\$" "$MAPFILE" 2>/dev/null \
  && pass "reinstall after uninstall: display alias restored" || fail "reinstall after uninstall: display alias missing"
[ "$(cat "$G/.nx_addon_version" 2>/dev/null)" = "v9.9.9" ] \
  && pass "reinstall after uninstall: version marker restored" || fail "reinstall after uninstall: version marker missing"
[ "$(cat "$G/lovegame/red/cache.bin" 2>/dev/null)" = "save" ] \
  && pass "reinstall after uninstall: save cache still kept"   || fail "reinstall after uninstall: save cache lost"

say ""
if [ "$FAILS" -eq 0 ]; then say "ALL PASS"; exit 0; else say "$FAILS FAILURE(S)"; exit 1; fi
