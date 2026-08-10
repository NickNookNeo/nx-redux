#!/bin/sh
# Xtras catalog: gen1recomp + bundled mods (Dramatic Shape Voxel, Running
# Shoes, Wilds of Kanto).
# Contract: idempotent; installs the LATEST upstream releases (resolved from
# the GitHub API at install time, sha256-digest-verified - fail closed);
# visible launcher registered LAST; progress on stdout; exit code is the verdict;
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

# Latest-install model (2026-08-10 spec): the game and the shoes/wilds
# mods resolve to their repos' latest GitHub release at install time -
# no pinned tags/URLs/shas. Integrity comes from the per-asset sha256 digest
# the same API responses carry (settings_updater.c's posture: an integrity
# check, not authentication). The yellow ROM manifest is fetched at the
# resolved game tag (raw.githubusercontent, no digest available - TLS-only).
# The Voxel Mod is the one exception - pinned, see below.
GEN1_REPO="bryanthaboi/gen1recomp"
GEN1_ASSET="*rg34xxsp-stockos64-mod.zip"
# Voxel Mod: upstream DramaticShape/DramaticShapeVoxelMod - and the whole
# DramaticShape account - vanished from GitHub ~2026-08 (API 404s; install
# failure device-reproduced 2026-08-10). The live repo is still TRIED FIRST,
# so if the author ever restores it, latest-release installs resume on their
# own - but a resolve failure there falls back to the newest zip (1.7.2)
# preserved in the community backup repo linkfy/DramaticShapeVoxelModBackup
# (a plain repo file, fetched raw), verified against a sha256 computed from
# that exact file on 2026-08-10 - fails closed if the backup file is ever
# replaced. The fallback cannot mask a dead network: the game repo resolve
# runs before it and fails the whole install first, so reaching the fallback
# means the network works and the repo itself is gone. Overridable ONLY so
# the host test can serve its fixtures.
MOD_REPO="DramaticShape/DramaticShapeVoxelMod"
MOD_ASSET="DRAMATIC_SHAPE*.zip"
: "${NX_VOXEL_URL:=https://raw.githubusercontent.com/linkfy/DramaticShapeVoxelModBackup/main/DRAMATIC_SHAPE-1.7.2.zip}"
: "${NX_VOXEL_SHA256:=fe8af5180e7f430dd9d9667f7370db4d886d25714209dc949413972d3bf82307}"
# Running Shoes: hold-B run speed (extras all off by default; manifest id
# "running_shoes", no deps/conflicts). Contents at the zip root, ~28 KB.
SHOES_REPO="MadeinTaly/gen1recomp-running-shoes"
SHOES_ASSET="running_shoes-*.zip"
# Wilds of Kanto: visible/reactive overworld wild Pokemon (manifest id
# "overworld_wild_spawns"). Its release asset is a source archive - contents
# sit under a "<repo>-<branch>/" wrapper dir, not at the zip root - so the
# install step below finds the manifest.json-bearing dir instead of assuming
# either layout. ~18 MB download, the largest of the mods.
WILDS_REPO="YoDrehDenSwagAuf/overworld-spawn-mod"
WILDS_ASSET="Wilds.of.Kanto*.zip"

# The SYSTEM-shipped 7zzs (same binary settings_updater.c extracts system
# updates with), NOT PortMaster's vendored copy: since the runtime=native
# conversion (2026-08-10) this entry has no PortMaster dependency at launch,
# so the install must not depend on it either (psp/install.sh's posture).
: "${NX_EXTRAS_UNZIP:=$SDCARD_PATH/.system/shared/bin/7zzs.aarch64}"

# TLS: verify whenever a CA bundle exists on the card; only fall back to the
# system updater's --no-check-certificate convention (common/wget_fetch.c;
# the firmware itself ships no CA bundle) when none is found. PortMaster's
# vendored bundle is used opportunistically - the runtime=native conversion
# removed the REQUIREMENT on PortMaster, not the willingness to use its
# certs when present. The .system/shared/ssl path is a seam for a future
# system-shipped bundle and wins when both exist. Verified TLS also protects
# the release-API JSON (which carries the asset digests), closing the
# digest-over-unverified-channel loop the sha256 check alone can't.
NX_WGET_TLS="--no-check-certificate"
for _ca in "$SDCARD_PATH/.system/shared/ssl/ca-certificates.crt" \
           "$SDCARD_PATH/Emus/shared/PortMaster/ssl/certs/ca-certificates.crt"; do
    if [ -f "$_ca" ]; then
        export SSL_CERT_FILE="$_ca"
        NX_WGET_TLS=""
        break
    fi
done

TMPDIR_NX="$SDCARD_PATH/.extras_tmp"
TARGET="$EXTRAS_DATA_DIR/gen1recomp"
LOVE="$TARGET/lovegame"
# Installed-version record (read by extras.elf's update check). The caller
# passes XTRAS_STATE_DIR; the fallback mirrors its device value for a bare
# environment.
: "${XTRAS_STATE_DIR:=$SDCARD_PATH/.userdata/shared/xtras}"

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

fetch() { # url dest sha256(""=skip) label
    echo "Downloading $4..."
    # --timeout=30 bounds dns/connect/read all at once (GNU wget); --tries=2
    # caps retries, so a stalled/half-open connection gives up in ~60s
    # instead of hanging the popen'd read loop that streams this script's
    # stdout indefinitely. Single-token --flag=value form so a naive "skip
    # any -* token" arg shim (see the host test) can't mis-eat a detached
    # value as the next positional arg. $NX_WGET_TLS (see its definition):
    # empty when a CA bundle was found (full TLS verification), otherwise
    # --no-check-certificate with the sha256 check below failing closed on a
    # corrupted download. Deliberately unquoted - "" must expand to no
    # argument. An empty sha (an asset the API ships no digest for, e.g. the
    # raw-hosted yellow manifest) skips the check.
    # shellcheck disable=SC2086
    wget $NX_WGET_TLS -q --timeout=30 --tries=2 -O "$2" "$1" || fail "download failed: $4 (check WiFi)"
    if [ -n "$3" ]; then
        got="$(sha256sum "$2" | cut -d' ' -f1)"
        [ "$got" = "$3" ] || fail "checksum mismatch on $4 - aborting"
    fi
}

# resolve_latest <owner/repo> <asset-glob>: queries the GitHub latest-release
# API and sets RL_TAG, RL_URL (the asset matching the glob) and RL_SHA (that
# asset's sha256 digest, "" when the API ships none). The JSON is scanned as
# a token stream - within each asset object the API emits "name" before
# "digest" before "browser_download_url", so tracking the last-seen name/
# digest pairs each URL with its own asset (same scraping approach
# settings_updater.c uses). Returns non-zero with RL_ERR set when
# unreachable or unparseable - each caller decides whether that is fatal
# (`|| fail "$RL_ERR"`) or a fallback (the Voxel mod).
# Same helper as psp/install.sh's - catalog entries are self-contained by
# contract, so it is duplicated rather than shared.
resolve_latest() {
    _rl_json="$TMPDIR_NX/release.json"
    # shellcheck disable=SC2086  # $NX_WGET_TLS: "" must expand to no argument
    wget $NX_WGET_TLS -q --timeout=30 --tries=2 -O "$_rl_json" \
        "https://api.github.com/repos/$1/releases/latest" \
        || { RL_ERR="could not check the latest version (check WiFi)"; return 1; }
    RL_TAG="$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$_rl_json" | head -1)"
    [ -n "$RL_TAG" ] || { RL_ERR="could not read the latest version info"; return 1; }
    RL_URL=""
    RL_SHA=""
    _rl_name=""
    _rl_digest=""
    while IFS= read -r _rl_tok; do
        case "$_rl_tok" in
            '"name":'*)   _rl_name="$(printf '%s' "$_rl_tok" | cut -d'"' -f4)"; _rl_digest="" ;;
            '"digest":'*) _rl_digest="$(printf '%s' "$_rl_tok" | cut -d'"' -f4 | sed 's/^sha256://')" ;;
            '"browser_download_url":'*)
                # shellcheck disable=SC2254  # $2 is deliberately an unquoted glob
                case "$_rl_name" in
                    $2) RL_URL="$(printf '%s' "$_rl_tok" | cut -d'"' -f4)"; RL_SHA="$_rl_digest"; break ;;
                esac ;;
        esac
    done <<EOF
$(grep -o '"name": *"[^"]*"\|"digest": *"[^"]*"\|"browser_download_url": *"[^"]*"' "$_rl_json")
EOF
    [ -n "$RL_URL" ] || { RL_ERR="latest release has no matching download"; return 1; }
    return 0
}

# Preflight: probe the unzip binary before touching the network. It ships
# with the system itself, so absence means damaged/stale system files, not
# a missing optional add-on. command -v covers both the absolute device
# default and a bare-name override from the host test. (The old PortMaster
# runtime preflight is gone with the runtime=native conversion - nothing
# here needs PortMaster anymore.)
if ! command -v "$NX_EXTRAS_UNZIP" >/dev/null 2>&1; then
    fail "system unzip tool missing - update or reinstall NX Redux, then retry"
fi

rm -rf "$TMPDIR_NX"
mkdir -p "$TMPDIR_NX" "$EXTRAS_DATA_DIR" || fail "cannot create install dirs"
echo "@5 Checking latest versions..."
echo "Checking latest versions..."

resolve_latest "$GEN1_REPO" "$GEN1_ASSET" || fail "$RL_ERR"
GAME_TAG="$RL_TAG"
GAME_URL="$RL_URL"
GAME_SHA="$RL_SHA"
echo "Latest game release: $GAME_TAG"

# Voxel: live repo first, archived backup on any resolve failure (see the
# constants block above - the network is already proven good by this point).
if resolve_latest "$MOD_REPO" "$MOD_ASSET"; then
    MOD_TAG="$RL_TAG"
    MOD_URL="$RL_URL"
    MOD_SHA="$RL_SHA"
    echo "Latest mod release: $MOD_TAG"
else
    MOD_TAG="1.7.2-backup"
    MOD_URL="$NX_VOXEL_URL"
    MOD_SHA="$NX_VOXEL_SHA256"
    echo "Voxel Mod upstream unavailable - using archived $MOD_TAG"
fi

resolve_latest "$SHOES_REPO" "$SHOES_ASSET" || fail "$RL_ERR"
SHOES_TAG="$RL_TAG"
SHOES_URL="$RL_URL"
SHOES_SHA="$RL_SHA"
echo "Latest running shoes release: $SHOES_TAG"

resolve_latest "$WILDS_REPO" "$WILDS_ASSET" || fail "$RL_ERR"
WILDS_TAG="$RL_TAG"
WILDS_URL="$RL_URL"
WILDS_SHA="$RL_SHA"
echo "Latest wilds of kanto release: $WILDS_TAG"

GEN1_YELLOW_URL="https://raw.githubusercontent.com/$GEN1_REPO/$GAME_TAG/tools/rom_manifest_yellow.json"
echo "@10 Starting install..."

fetch "$GAME_URL"        "$TMPDIR_NX/game.zip"    "$GAME_SHA" "gen1recomp $GAME_TAG (~5 MB)"
echo "@20 Downloaded gen1recomp"
fetch "$GEN1_YELLOW_URL" "$TMPDIR_NX/yellow.json" ""          "Yellow ROM manifest (~1 MB)"
echo "@25 Downloaded Yellow manifest"
fetch "$MOD_URL"         "$TMPDIR_NX/mod.zip"     "$MOD_SHA"  "Voxel Mod $MOD_TAG (~8 MB)"
echo "@40 Downloaded Voxel Mod"
fetch "$SHOES_URL"       "$TMPDIR_NX/shoes.zip"   "$SHOES_SHA" "Running Shoes Mod $SHOES_TAG (<1 MB)"
echo "@45 Downloaded Running Shoes Mod"
fetch "$WILDS_URL"       "$TMPDIR_NX/wilds.zip"   "$WILDS_SHA" "Wilds of Kanto $WILDS_TAG (~18 MB)"
echo "@65 Downloaded Wilds of Kanto"

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

# PokePC Followers was bundled briefly on 2026-08-10 and then dropped the
# same day (user-confirmed: Wilds of Kanto ships its own follower system and
# the two overlap) - remove it from any install that picked it up.
rm -rf "$LOVE/mods/pokepcfollowers"

echo "Installing Running Shoes Mod..."
mkdir -p "$LOVE/mods/running_shoes"
extract "$TMPDIR_NX/shoes.zip" "$LOVE/mods/running_shoes" || fail "could not extract running shoes mod"

echo "Installing Wilds of Kanto..."
# Source-archive layout: find the dir holding manifest.json (the zip root
# itself, or a single "<repo>-<branch>/" wrapper) rather than assuming one.
mkdir -p "$TMPDIR_NX/wilds"
extract "$TMPDIR_NX/wilds.zip" "$TMPDIR_NX/wilds" || fail "could not extract wilds of kanto mod"
rm -f "$TMPDIR_NX/wilds.zip" # free ~18 MB before the copy below doubles the payload
WILDS_SRC="$TMPDIR_NX/wilds"
if [ ! -f "$WILDS_SRC/manifest.json" ]; then
    for _wd in "$TMPDIR_NX/wilds"/*/; do
        [ -f "${_wd}manifest.json" ] && WILDS_SRC="${_wd%/}" && break
    done
fi
[ -f "$WILDS_SRC/manifest.json" ] || fail "unexpected wilds of kanto zip layout"
mkdir -p "$LOVE/mods/overworld_wild_spawns"
cp -R "$WILDS_SRC/." "$LOVE/mods/overworld_wild_spawns/" || fail "could not install wilds of kanto mod"
echo "@80 Yellow support and mods installed"

echo "@90 Scanning for ROMs..."
echo "Looking for your Pokemon ROMs..."
# Recognized by SHA-256 via the same busybox sha256sum fetch() already depends
# on - every card that can run this install can run the scan. (The game's own
# importer gates on SHA-1 internally; these are the same three US Red/Blue/
# Yellow dumps, just hashed with the tool the device actually ships. sha1sum
# only exists inside PortMaster's vendored bin, which runtime=native users
# don't have - a card without it used to skip this scan entirely.)
found=0
for dir in "$SDCARD_PATH/Roms/Game Boy (GB)" "$SDCARD_PATH/Roms/Game Boy Color (GBC)"; do
    [ -d "$dir" ] || continue
    for rom in "$dir"/*.gb "$dir"/*.gbc; do
        [ -f "$rom" ] || continue
        [ -f "$LOVE/$(basename "$rom")" ] && { found=$((found+1)); continue; }
        case "$(sha256sum "$rom" | cut -d' ' -f1)" in
            5ca7ba01642a3b27b0cc0b5349b52792795b62d3ed977e98a09390659af96b7b|\
            2a951313c2640e8c2cb21f25d1db019ae6245d9c7121f754fa61afd7bee6452d|\
            8cbaa499397e4f1a679c992ea9382a2dd7942ab398b48c19829c2d9529de47bf)
                echo "  found $(basename "$rom")"
                cp "$rom" "$LOVE/" && found=$((found+1))
                ;;
        esac
    done
done
[ "$found" -eq 0 ] && echo "  none found - copy a US Red/Blue/Yellow ROM into Roms/Xtra Games (EXTRAS)/.data/gen1recomp/lovegame/ later"

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

# Both records carry the resolved game tag: the XTRAS_STATE_DIR file is what
# extras.elf's update check reads; the legacy in-target marker keeps an
# older Xtras.pak (pre-update-tracking) reading this install as installed.
mkdir -p "$XTRAS_STATE_DIR" || fail "cannot create version state dir"
printf '%s\n' "$GAME_TAG" > "$XTRAS_STATE_DIR/gen1recomp.version" || fail "could not write version record"
printf '%s\n' "$GAME_TAG" > "$TARGET/.nx_addon_version" || fail "could not write version marker"

# Display alias: the launcher filename would render as "Gen1recomp" in the
# game list; a map.txt line (filename<TAB>alias - content.c Directory_index)
# sets the shown name without renaming the file, so resume slots, this
# script's own cleanup paths, and existing installs stay keyed to
# Gen1recomp.sh. Upsert keyed on the filename so other entries' alias lines
# in the shared folder are preserved. Written before the launcher lands so
# the entry never appears under the wrong name.
MAP="$EXTRAS_ROMS_DIR/map.txt"
TAB="$(printf '\t')"
{
    [ -f "$MAP" ] && grep -v "^Gen1recomp\.sh$TAB" "$MAP"
    printf 'Gen1recomp.sh\tGen1Recomp (Pokemon R/B/Y)\n'
} > "$MAP.tmp" && mv "$MAP.tmp" "$MAP" || fail "could not write display name"

# LAST STEP: the visible menu entry. Everything above must already be good.
cp "$CATALOG_DIR/files/Gen1recomp.sh" "$EXTRAS_ROMS_DIR/Gen1recomp.sh" || fail "could not register launcher"

rm -rf "$TMPDIR_NX"
echo "@100 Done"
echo "Done. Find Gen1recomp under Xtra Games."
exit 0
