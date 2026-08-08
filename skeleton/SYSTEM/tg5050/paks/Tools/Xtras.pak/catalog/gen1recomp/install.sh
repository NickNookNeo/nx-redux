#!/bin/sh
# Xtras catalog: gen1recomp + Dramatic Shape Voxel Mod.
# Contract: idempotent; sha256-pinned downloads (fail closed); visible
# launcher registered LAST; progress on stdout; exit code is the verdict;
# every network command must carry a timeout (the caller streams our stdout
# via a blocking popen()/fgets() read loop with no watchdog of its own - an
# untimed command here stalls the whole UI, not just this script).
#
# Progress hints (Task 11): a line of the form "@NN status text" (NN = a
# bare 1-3 digit decimal 0-100, then exactly one space, then free text)
# tells the caller to set the on-screen progress bar to NN% and show
# "status text" as the current stage; any other line is ordinary
# human-readable output and is shown as the smaller detail line below the
# bar instead. Always emit a hint as its OWN line - never appended to an
# existing message line - so message strings anything else greps for
# (checksum failures, "kept", etc.) stay byte-for-byte intact. Every line, hints
# included, is still tee'd verbatim to the persistent on-device log, so
# nothing here reduces what's recorded on disk vs. what's shown on screen.
set -u

GEN1_TAG="v0.1.75"
GEN1_ZIP_URL="https://github.com/bryanthaboi/gen1recomp/releases/download/${GEN1_TAG}/gen1recomp-0.1.75-rg34xxsp-stockos64-mod.zip"
GEN1_YELLOW_URL="https://raw.githubusercontent.com/bryanthaboi/gen1recomp/${GEN1_TAG}/tools/rom_manifest_yellow.json"
GEN1_MOD_URL="https://github.com/DramaticShape/DramaticShapeVoxelMod/releases/download/v1.6.2/DRAMATIC_SHAPE-1.6.2.zip"
# Env-overridable so the host test can substitute fixtures; on a device an
# attacker who controls the environment already owns the SD card.
: "${GEN1_ZIP_SHA256:=eb3a101c3184551407c6a221fe035a2486383941c36661bf9a38596ae086f525}"
: "${GEN1_YELLOW_SHA256:=ff1c83919442013c92f6f9df0b1359a1415a59870640046d83dfa0582978a29c}"
: "${GEN1_MOD_SHA256:=92c99d40a4b8d79b8cd950cc8dce8f7be34624b26e0434a85b95ec0aab76e572}"
VERSION="0.1.75+mod1.6.2"

: "${NX_EXTRAS_UNZIP:=$SDCARD_PATH/Emus/shared/PortMaster/bin/7zzs.aarch64}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-$SDCARD_PATH/Emus/shared/PortMaster/ssl/certs/ca-certificates.crt}"

# sha1sum is NOT on the device PATH in the Xtras launch chain (device-
# verified: /mnt/SDCARD/.system/bin:/mnt/SDCARD/.system/shared/bin:/usr/
# trimui/bin:/usr/sbin:/usr/bin:/sbin:/bin - busybox on the card has no
# sha1sum applet). The only copy on the card lives under PortMaster's vendored
# bin/. Resolved once here; the ROM auto-scan below skips gracefully (not a
# fatal error) if neither resolves.
NX_SHA1="$(command -v sha1sum || true)"
if [ -z "$NX_SHA1" ] && [ -x "$SDCARD_PATH/Emus/shared/PortMaster/bin/sha1sum" ]; then
    NX_SHA1="$SDCARD_PATH/Emus/shared/PortMaster/bin/sha1sum"
fi

TMPDIR_NX="$SDCARD_PATH/.extras_tmp"
TARGET="$EXTRAS_PORTS_DIR/gen1recomp"
LOVE="$TARGET/lovegame"

# Set true once we start writing into $TARGET (the overlay-copy below).
# Before that point a failure leaves any prior successful install (and its
# registered launcher) fully untouched, so there is nothing to unregister.
# From that point on a failure may leave $TARGET half-overwritten, so if a
# launcher from a previous install is still sitting in $EXTRAS_ROMS_DIR we
# pull it so no broken, half-updated entry stays launchable; re-running
# install recovers everything (overlay-copy never deletes user data).
TARGET_DIRTY=0

fail() {
    echo "ERROR: $1"
    if [ "$TARGET_DIRTY" = "1" ] && [ -f "$EXTRAS_ROMS_DIR/Gen1recomp.sh" ]; then
        rm -f "$EXTRAS_ROMS_DIR/Gen1recomp.sh"
        echo "install broken, launcher removed - re-run install"
    fi
    rm -rf "$TMPDIR_NX"
    exit 1
}

extract() { # zip dest
    case "$NX_EXTRAS_UNZIP" in
        *7zzs*) "$NX_EXTRAS_UNZIP" x -y -o"$2" "$1" >/dev/null || return 1 ;;
        *)      "$NX_EXTRAS_UNZIP" -q -o "$1" -d "$2" || return 1 ;;
    esac
}

fetch() { # url dest sha256 label
    echo "Downloading $4..."
    # --timeout=30 bounds dns/connect/read all at once (GNU wget); --tries=2
    # caps retries, so a stalled/half-open connection gives up in ~60s
    # instead of hanging the popen'd read loop that streams this script's
    # stdout indefinitely. Single-token --flag=value form so a naive "skip
    # any -* token" arg shim (see the host test) can't mis-eat a detached
    # value as the next positional arg.
    wget -q --timeout=30 --tries=2 -O "$2" "$1" || fail "download failed: $4 (check WiFi)"
    got="$(sha256sum "$2" | cut -d' ' -f1)"
    [ "$got" = "$3" ] || fail "checksum mismatch on $4 - aborting"
}

# Preflight (Task 15, fix round 1): fail closed, before touching the
# network at all, if the PortMaster runtime this entry depends on wasn't
# actually unpacked. A bare `[ -d Emus/shared/PortMaster ]` is NOT enough -
# the nx-redux skeleton itself ships patchedScripts/ and files/ under that
# same directory, so the dir exists even when PortMaster was removed or
# never installed (device-reproduced: preflight passed, downloads
# succeeded, then died unactionably at extract - missing 7zzs). Probe the
# actual runtime files instead: the unzip binary (extraction dependency,
# also this script's own $NX_EXTRAS_UNZIP default) and control.txt
# (PortMaster's own installed-runtime marker - needed by the launch chain
# even if install itself somehow succeeded without it).
if [ ! -x "$SDCARD_PATH/Emus/shared/PortMaster/bin/7zzs.aarch64" ] || [ ! -f "$SDCARD_PATH/Emus/shared/PortMaster/control.txt" ]; then
    fail "PortMaster runtime not set up - open Tools > PortMaster first, then retry"
fi

rm -rf "$TMPDIR_NX"
mkdir -p "$TMPDIR_NX" "$EXTRAS_PORTS_DIR" || fail "cannot create install dirs"
echo "@5 Starting install..."

fetch "$GEN1_ZIP_URL"    "$TMPDIR_NX/game.zip"    "$GEN1_ZIP_SHA256"    "gen1recomp 0.1.75 (~5 MB)"
echo "@20 Downloaded gen1recomp"
fetch "$GEN1_YELLOW_URL" "$TMPDIR_NX/yellow.json" "$GEN1_YELLOW_SHA256" "Yellow ROM manifest (~1 MB)"
echo "@35 Downloaded Yellow manifest"
fetch "$GEN1_MOD_URL"    "$TMPDIR_NX/mod.zip"     "$GEN1_MOD_SHA256"    "Voxel Mod 1.6.2 (~8 MB)"
echo "@55 Downloaded Voxel Mod"

echo "@70 Extracting..."
echo "Extracting game..."
mkdir -p "$TMPDIR_NX/game"
extract "$TMPDIR_NX/game.zip" "$TMPDIR_NX/game" || fail "could not extract game zip"
[ -d "$TMPDIR_NX/game/gen1recomp" ] || fail "unexpected zip layout"

# Overlay-copy: the payload carries no user data (no saves, no options.lua,
# no ROM caches, no ROMs), so copying WITHOUT deleting preserves everything
# a previous install created. Never rm -rf $TARGET.
mkdir -p "$TARGET"
TARGET_DIRTY=1
cp -R "$TMPDIR_NX/game/gen1recomp/." "$TARGET/" || fail "copy into install target failed"

echo "Adding Yellow support..."
mkdir -p "$LOVE/tools"
cp "$TMPDIR_NX/yellow.json" "$LOVE/tools/rom_manifest_yellow.json" || fail "yellow manifest copy failed"

echo "Installing Voxel Mod..."
mkdir -p "$LOVE/mods/DRAMATIC_SHAPE"
extract "$TMPDIR_NX/mod.zip" "$LOVE/mods/DRAMATIC_SHAPE" || fail "could not extract voxel mod"
echo "@80 Yellow support and mods installed"

echo "@90 Scanning for ROMs..."
echo "Looking for your Pokemon ROMs..."
found=0
if [ -z "$NX_SHA1" ]; then
    echo "  ROM auto-scan skipped (no sha1 tool) - copy ROMs manually into Roms/Xtra Games (EXTRAS)/.ports/gen1recomp/lovegame/"
else
    for dir in "$SDCARD_PATH/Roms/Game Boy (GB)" "$SDCARD_PATH/Roms/Game Boy Color (GBC)"; do
        [ -d "$dir" ] || continue
        for rom in "$dir"/*.gb "$dir"/*.gbc; do
            [ -f "$rom" ] || continue
            [ -f "$LOVE/$(basename "$rom")" ] && { found=$((found+1)); continue; }
            case "$("$NX_SHA1" "$rom" | cut -d' ' -f1)" in
                ea9bcae617fdf159b045185467ae58b2e4a48b9a|\
                d7037c83e1ae5b39bde3c30787637ba1d4c48ce2|\
                cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1)
                    echo "  found $(basename "$rom")"
                    cp "$rom" "$LOVE/" && found=$((found+1))
                    ;;
            esac
        done
    done
    [ "$found" -eq 0 ] && echo "  none found - copy a US Red/Blue/Yellow ROM into Roms/Xtra Games (EXTRAS)/.ports/gen1recomp/lovegame/ later"
fi

# Self-install the EXTRAS platform runtime. The skeleton SYSTEM tree
# normally ships this pak out of the box (skeleton/SYSTEM/<plat>/paks/
# Emus/EXTRAS.pak/launch.sh, same script as extras_games_launch.sh below)
# - this block is the repair path for a card whose skeleton is missing or
# stale (e.g. an older release, or a card migrated from the legacy
# platform-tag layout) rather than the normal install-time trigger.
# Installed under .system/paks/Emus - nextui's first-priority PAKS_PATH
# lookup location (checked before the flat Emus/ and platform-subfolder
# Emus/$PLATFORM/ fallbacks, see hasEmu() in content.c) - not
# Emus/$PLATFORM, which is the community-pak convention, not where system-
# provided runtimes like this one belong.
PAK_DIR="$(cd "$(dirname "$CATALOG_DIR")/.." && pwd)"   # .../Xtras.pak
EMU_PAK="$SDCARD_PATH/.system/paks/Emus/EXTRAS.pak"
if [ ! -f "$EMU_PAK/launch.sh" ] && [ -f "$PAK_DIR/extras_games_launch.sh" ]; then
    echo "Registering Xtra Games platform..."
    mkdir -p "$EMU_PAK"
    cp "$PAK_DIR/extras_games_launch.sh" "$EMU_PAK/launch.sh" || fail "could not install EXTRAS.pak"
fi

echo "$VERSION" > "$TARGET/.nx_addon_version" || fail "could not write version marker"

# LAST STEP: the visible menu entry. Everything above must already be good.
cp "$CATALOG_DIR/files/Gen1recomp.sh" "$EXTRAS_ROMS_DIR/Gen1recomp.sh" || fail "could not register launcher"

rm -rf "$TMPDIR_NX"
echo "@100 Done"
echo "Done. Find Gen1recomp under Xtra Games."
exit 0
