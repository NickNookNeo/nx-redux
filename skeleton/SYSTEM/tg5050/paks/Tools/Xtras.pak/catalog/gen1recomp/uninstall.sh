#!/bin/sh
# Xtras catalog: gen1recomp keep-saves uninstall.
# Contract: run with the same env as install.sh, streamed the same way.
# Removes the visible launcher FIRST (reverse of install's register-last),
# then the version marker, then the engine/runtime payload. PRESERVES user
# data: lovegame/red|blue|yellow (ROM save caches), the user's own *.gb/
# *.gbc ROMs, lovegame/options.lua, and conf/ - none of those paths are
# touched below. Idempotent (safe on an already-uninstalled, partially
# uninstalled, or never-installed entry - every removal is a no-op-safe
# rm -f/-rf). Exit code is the verdict; every step prints a progress line.
# Needs no network access at all, so (unlike install.sh) no command here
# needs a timeout - only busybox rm/printf-safe commands are used.
# Progress hints (Task 11): same "@NN status text" convention as install.sh -
# see its header for the full contract text.
set -u

TARGET="$EXTRAS_PORTS_DIR/gen1recomp"
LOVE="$TARGET/lovegame"

echo "@10 Removing launcher..."
echo "Removing launcher..."
rm -f "$EXTRAS_ROMS_DIR/Gen1recomp.sh"

echo "@30 Removing version marker..."
echo "Removing version marker..."
rm -f "$TARGET/.nx_addon_version"

echo "@55 Removing engine..."
echo "Removing engine..."
rm -rf "${TARGET:?}/bin" "${TARGET:?}/libs.aarch64" "${TARGET:?}/licenses"

echo "@80 Removing game runtime..."
echo "Removing game runtime..."
rm -rf "${LOVE:?}/src" "${LOVE:?}/data" "${LOVE:?}/assets" "${LOVE:?}/libs" "${LOVE:?}/tools" "${LOVE:?}/mods"
rm -f "$LOVE/main.lua" "$LOVE/conf.lua" "$LOVE/portable.txt"

echo "@100 Done"
echo "Done. Saves and ROMs kept - reinstall to play again."
exit 0
