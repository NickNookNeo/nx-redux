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

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# ---- sandbox SD card --------------------------------------------------
SD="$TMP/sd"
GB_DIR="$SD/Roms/Game Boy (GB)"
GBC_DIR="$SD/Roms/Game Boy Color (GBC)"
mkdir -p "$GB_DIR" "$GBC_DIR" "$SD/.userdata/tg5050/logs"
# A "Red" ROM whose sha1 we control via the sha1sum shim below.
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
  *stockos64-mod.zip)        cp "$TMP/game.zip" "\$out" ;;
  *rom_manifest_yellow.json) cp "$TMP/rom_manifest_yellow.json" "\$out" ;;
  *DRAMATIC_SHAPE*.zip)      cp "$TMP/mod.zip" "\$out" ;;
  *) echo "wget shim: unknown url \$url" >&2; exit 1 ;;
esac
SHIM
chmod +x "$BIN/wget"
# sha1sum shim: reports the pinned Red hash for the Red fixture, junk otherwise.
cat > "$BIN/sha1sum" <<SHIM
#!/usr/bin/env bash
for f in "\$@"; do
  case "\$f" in
    *"Pokemon Red.gb") echo "ea9bcae617fdf159b045185467ae58b2e4a48b9a  \$f" ;;
    *) echo "0000000000000000000000000000000000000000  \$f" ;;
  esac
done
SHIM
chmod +x "$BIN/sha1sum"
# sha256sum shim -> host shasum (macOS has no sha256sum).
cat > "$BIN/sha256sum" <<'SHIM'
#!/usr/bin/env bash
shasum -a 256 "$@"
SHIM
chmod +x "$BIN/sha256sum"

run_install() {
  # Default to the fixtures' real (current) hashes but honor a
  # caller-supplied override (e.g. GEN1_ZIP_SHA256=deadbeef run_install)
  # so the sha mismatch case below actually reaches install.sh
  # unclobbered. Locals so nothing leaks as global state between the
  # repeated calls below (test 2 rebuilds game.zip with new content, so
  # each call must recompute rather than reuse a stale hash).
  local zip_sha="${GEN1_ZIP_SHA256:-$(sha "$TMP/game.zip")}"
  local yellow_sha="${GEN1_YELLOW_SHA256:-$(sha "$TMP/rom_manifest_yellow.json")}"
  local mod_sha="${GEN1_MOD_SHA256:-$(sha "$TMP/mod.zip")}"
  PATH="$BIN:$PATH" \
  PLATFORM=tg5050 \
  SDCARD_PATH="$SD" \
  LOGS_PATH="$SD/.userdata/tg5050/logs" \
  EXTRAS_ROMS_DIR="$SD/Roms/Xtra Games (EXTRAS)" \
  EXTRAS_PORTS_DIR="$SD/Roms/Xtra Games (EXTRAS)/.ports" \
  CATALOG_DIR="$ENTRY" \
  NX_EXTRAS_UNZIP=unzip \
  GEN1_ZIP_SHA256="$zip_sha" \
  GEN1_YELLOW_SHA256="$yellow_sha" \
  GEN1_MOD_SHA256="$mod_sha" \
  bash "$ENTRY/install.sh"
}

G="$SD/Roms/Xtra Games (EXTRAS)/.ports/gen1recomp"

# ---- 0. preflight: PortMaster runtime dependency probes ---------------
# Task 15 fix round 1 (user-reproduced on-device bug): a bare
# `[ -d Emus/shared/PortMaster ]` check is insufficient - the nx-redux
# skeleton itself ships patchedScripts/ and files/ under that same
# directory, so the dir exists even when the real runtime (unzip binary,
# control.txt) was never unpacked or was removed. install.sh now probes
# those two files directly. Both scenarios below run before either probe
# file exists, so both genuinely exercise the failure path.

# 0a. skeleton-shipped dir present (patchedScripts/ + files/, like a real
# card) but neither runtime probe file - this is the user's exact
# reproduced scenario (PortMaster removed/never installed, dir survives
# from the skeleton anyway). Fixture content is arbitrary; install.sh
# never reads it, only -x/-f the two runtime paths.
mkdir -p "$SD/Emus/shared/PortMaster/patchedScripts" "$SD/Emus/shared/PortMaster/files"
echo 'stub' > "$SD/Emus/shared/PortMaster/patchedScripts/SteelAssault.sh"
if run_install > "$TMP/log0a.txt" 2>&1; then
  fail "preflight: skeleton-only PortMaster dir (no runtime files) did not abort"
else pass "preflight: skeleton-only PortMaster dir (no runtime files) aborts"; fi
grep -q 'PortMaster runtime not set up' "$TMP/log0a.txt" \
  && pass "preflight (0a): message printed" || fail "preflight (0a): message missing"
! grep -q 'Downloading' "$TMP/log0a.txt" \
  && pass "preflight (0a): no download attempted" || fail "preflight (0a): a download was attempted despite missing runtime files"
[ ! -d "$G" ] \
  && pass "preflight (0a): nothing written to install target" || fail "preflight (0a): install target created despite missing runtime files"
[ ! -e "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "preflight (0a): no launcher registered" || fail "preflight (0a): launcher registered despite missing runtime files"

# 0b. dir fully absent too - the original (now-superseded) failure mode,
# kept as a regression guard.
rm -rf "$SD/Emus/shared/PortMaster"
if run_install > "$TMP/log0b.txt" 2>&1; then
  fail "preflight: fully-absent PortMaster dir did not abort"
else pass "preflight: fully-absent PortMaster dir aborts"; fi
grep -q 'PortMaster runtime not set up' "$TMP/log0b.txt" \
  && pass "preflight (0b): message printed" || fail "preflight (0b): message missing"
! grep -q 'Downloading' "$TMP/log0b.txt" \
  && pass "preflight (0b): no download attempted" || fail "preflight (0b): a download was attempted despite missing dir"

# PortMaster runtime now genuinely present (both probe files) - every
# scenario below is the happy path for this dependency. Fake content is
# fine; install.sh only checks -x/-f, never reads either file.
mkdir -p "$SD/Emus/shared/PortMaster/bin"
echo 'fake-7zzs' > "$SD/Emus/shared/PortMaster/bin/7zzs.aarch64"
chmod +x "$SD/Emus/shared/PortMaster/bin/7zzs.aarch64"
echo 'fake-control' > "$SD/Emus/shared/PortMaster/control.txt"

# ---- 1. fresh install -------------------------------------------------
if run_install > "$TMP/log1.txt" 2>&1; then pass "fresh install exits 0"
else fail "fresh install exited non-zero: $(tail -3 "$TMP/log1.txt")"; fi
[ -f "$G/bin/love.aarch64" ]                        && pass "runtime extracted"        || fail "runtime missing"
[ -f "$G/lovegame/tools/rom_manifest_yellow.json" ] && pass "yellow manifest in place" || fail "yellow manifest missing"
[ -f "$G/lovegame/mods/DRAMATIC_SHAPE/manifest.json" ] && pass "voxel mod installed"   || fail "voxel mod missing"
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
grep -q 'GAMEDIR="$SHDIR/.ports/gen1recomp"' \
  "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh"      && pass "launcher is nx-patched"  || fail "launcher not patched"
[ -f "$G/lovegame/Pokemon Red.gb" ]                  && pass "ROM scan copied Red"      || fail "Red not copied"
[ ! -f "$G/lovegame/Tetris.gb" ]                     && pass "ROM scan skipped junk"    || fail "junk ROM copied"
[ "$(cat "$G/.nx_addon_version" 2>/dev/null)" = "0.1.75+mod1.6.2" ] \
                                                     && pass "version marker written"  || fail "version marker wrong"
# Task 11: install.sh's "@NN status text" progress hints - a bare "@90 " (NN
# followed by a space) proves the hint syntax parses correctly, and that the
# original human-readable message on the very next line ("Looking for your
# Pokemon ROMs...", asserted just below) still stands unprefixed/untouched.
grep -q '@90 ' "$TMP/log1.txt"                       && pass "install emits @NN progress hints" \
                                                      || fail "no @NN progress hint found in install output"
grep -q '^Looking for your Pokemon ROMs\.\.\.$' "$TMP/log1.txt" \
                                                     && pass "hint line doesn't clobber the adjacent message line" \
                                                     || fail "message line after a hint was altered"

# ---- 2. reinstall preserves user data ---------------------------------
mkdir -p "$G/lovegame/red" "$G/conf"
echo 'save' > "$G/lovegame/red/cache.bin"
echo 'opts' > "$G/lovegame/options.lua"
echo 'love-bin-v2' > "$FIX/gen1recomp/bin/love.aarch64"
(cd "$FIX" && zip -qr "$TMP/game.zip" Gen1recomp.sh gen1recomp)  # rebuild zip
if run_install > "$TMP/log2.txt" 2>&1; then pass "reinstall exits 0"
else fail "reinstall exited non-zero: $(tail -3 "$TMP/log2.txt")"; fi
[ "$(cat "$G/lovegame/red/cache.bin")" = "save" ] && pass "ROM cache preserved"    || fail "ROM cache clobbered"
[ "$(cat "$G/lovegame/options.lua")" = "opts" ]   && pass "options.lua preserved"  || fail "options.lua clobbered"
[ "$(cat "$G/bin/love.aarch64")" = "love-bin-v2" ] && pass "engine payload updated" || fail "engine not updated"

# ---- 3. sha mismatch aborts before touching the install ---------------
rm -rf "$SD/Roms/Xtra Games (EXTRAS)"
if GEN1_ZIP_SHA256="deadbeef" run_install > "$TMP/log3.txt" 2>&1; then
  fail "sha mismatch did not abort"
else pass "sha mismatch aborts"; fi
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

# Corrupt the mod payload in place. run_install() (below) recomputes its sha
# default from the CURRENT file when GEN1_MOD_SHA256 isn't overridden, so the
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

# ---- 5. ROM auto-scan degrades gracefully when no sha1 tool is on PATH ----
# Device-verified gap: busybox on the card has no sha1sum applet, so bare
# `sha1sum` in the ROM scan resolved to nothing in the real Xtras launch
# chain - install still succeeded but silently copied 0 ROMs. Reproduce "no
# sha1 tool anywhere" deterministically: build an isolated PATH containing
# only the exact binaries install.sh needs (this test's own wget/sha256sum
# shims, plus the real system mkdir/rm/cp/basename/cut/unzip/dirname by
# direct symlink), and nothing else - a bare `PATH="$BIN:$PATH"` prepend
# wouldn't prove anything on a host that already has a real sha1sum
# elsewhere on its inherited PATH (this dev machine does: /sbin/sha1sum).
BIN_NOSHA1="$TMP/bin_nosha1"
mkdir -p "$BIN_NOSHA1"
# shasum (not sha1sum) is what the sha256sum shim below shells out to
# internally (macOS has no real sha256sum) - it lives in a different real
# directory (/usr/bin) than this host's real sha1sum (/sbin), so symlinking
# it by exact binary keeps the "no sha1sum anywhere on PATH" guarantee.
for c in bash mkdir rm cp basename cut unzip dirname shasum; do
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

# Compute the shas with the CURRENT (unmodified) PATH/shasum, as separate
# statements before the PATH override below - a `PATH=... VAR=$(cmd) ...`
# prefix list is not safe to rely on for ordering: bash applies earlier
# prefix assignments before expanding later ones' command substitutions on
# the same line, so folding these into that line would make `sha` itself
# resolve against the isolated (sha1-less, and shasum-less) PATH too.
zip_sha="$(sha "$TMP/game.zip")"
yellow_sha="$(sha "$TMP/rom_manifest_yellow.json")"
mod_sha="$(sha "$TMP/mod.zip")"

rm -rf "$SD/Roms/Xtra Games (EXTRAS)"
if PATH="$BIN_NOSHA1" \
   PLATFORM=tg5050 \
   SDCARD_PATH="$SD" \
   LOGS_PATH="$SD/.userdata/tg5050/logs" \
   EXTRAS_ROMS_DIR="$SD/Roms/Xtra Games (EXTRAS)" \
   EXTRAS_PORTS_DIR="$SD/Roms/Xtra Games (EXTRAS)/.ports" \
   CATALOG_DIR="$ENTRY" \
   NX_EXTRAS_UNZIP=unzip \
   GEN1_ZIP_SHA256="$zip_sha" \
   GEN1_YELLOW_SHA256="$yellow_sha" \
   GEN1_MOD_SHA256="$mod_sha" \
   bash "$ENTRY/install.sh" > "$TMP/log5.txt" 2>&1
then pass "install with no sha1 tool anywhere still exits 0"
else fail "install with no sha1 tool anywhere exited non-zero: $(tail -3 "$TMP/log5.txt")"; fi
[ ! -f "$G/lovegame/Pokemon Red.gb" ] \
  && pass "no sha1 tool: ROM scan skipped, nothing copied" || fail "no sha1 tool: a ROM was copied anyway"
grep -qi 'ROM auto-scan skipped' "$TMP/log5.txt" \
  && pass "no sha1 tool: skip message printed" || fail "no sha1 tool: skip message missing"
[ -f "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "no sha1 tool: rest of install still completed (launcher registered)" \
  || fail "no sha1 tool: install did not complete despite the scan being non-fatal"

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
  EXTRAS_PORTS_DIR="$SD/Roms/Xtra Games (EXTRAS)/.ports" \
  CATALOG_DIR="$ENTRY" \
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

if run_uninstall > "$TMP/log6.txt" 2>&1; then pass "uninstall exits 0"
else fail "uninstall exited non-zero: $(tail -3 "$TMP/log6.txt")"; fi

[ ! -e "$SD/Roms/Xtra Games (EXTRAS)/Gen1recomp.sh" ] \
  && pass "uninstall: launcher removed"        || fail "uninstall: launcher still present"
[ ! -e "$G/.nx_addon_version" ]                 \
  && pass "uninstall: version marker removed"  || fail "uninstall: version marker still present"
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
[ "$(cat "$G/.nx_addon_version" 2>/dev/null)" = "0.1.75+mod1.6.2" ] \
  && pass "reinstall after uninstall: version marker restored" || fail "reinstall after uninstall: version marker missing"
[ "$(cat "$G/lovegame/red/cache.bin" 2>/dev/null)" = "save" ] \
  && pass "reinstall after uninstall: save cache still kept"   || fail "reinstall after uninstall: save cache lost"

say ""
if [ "$FAILS" -eq 0 ]; then say "ALL PASS"; exit 0; else say "$FAILS FAILURE(S)"; exit 1; fi
