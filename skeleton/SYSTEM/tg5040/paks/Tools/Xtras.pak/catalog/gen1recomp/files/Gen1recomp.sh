#!/bin/bash
# gen1recomp launcher — upstream RG34XXSP port script with nx-redux patches:
#   1. GAMEDIR under .ports/ (nx Ports convention)
#   2. tg5050 tuning: eMMC swapfile (OOM guard) + big-core pinning + governors

export HOME="${HOME:-/root}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/PORTS/PortMaster"
fi

SHDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
source "$controlfolder/control.txt"
get_controls
# shellcheck disable=SC1090,SC1091
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# nx patch 1: game data lives in .ports/ like every nx port
GAMEDIR="$SHDIR/.ports/gen1recomp"
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1
: > "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs.aarch64:${LD_LIBRARY_PATH:-}"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"
export LOVE_GRAPHICS_USE_OPENGLES="${LOVE_GRAPHICS_USE_OPENGLES:-1}"
export POKEPORT_GBCFX="${POKEPORT_GBCFX:-0}"

$ESUDO chmod a+x ./bin/love.aarch64 2>/dev/null || chmod a+x ./bin/love.aarch64
$ESUDO chmod 666 /dev/uinput 2>/dev/null || true

# nx patch 2: per-platform tuning. Verified on tg5050 2026-08-06: the game +
# voxel mod peak ~750MB on a 1GB device (kernel OOM-kills without swap; exFAT
# SD can't host swap so the eMMC rootfs carries it), and schedutil both idles
# the clusters mid-frequency and lets the render thread drift off the big
# cores. The MinUI launch loop restores CPU state after the game exits.
NX_TASKSET=""
case "${PLATFORM:-}" in
  tg5050)
    if [ ! -f /swapfile ]; then
      # If dd or mkswap fails partway (e.g. full rootfs leaves a truncated
      # /swapfile), remove it so `[ ! -f /swapfile ]` doesn't pass forever -
      # without this, every later launch skips creation, swapon silently
      # fails, and voxel-mod sessions OOM-kill with no swap ever retried.
      # shellcheck disable=SC2015
      # (deliberate, not an if/then/else stand-in: `|| rm -f` here means
      # "clean up on ANY failure in the chain", not just when dd fails.)
      dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null \
        && chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 \
        || rm -f /swapfile
    fi
    swapon /swapfile 2>/dev/null
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    echo performance > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor 2>/dev/null
    command -v taskset >/dev/null 2>&1 && NX_TASKSET="taskset -c 4-7"
    ;;
esac

if [ -n "${GPTOKEYB:-}" ]; then
  $GPTOKEYB "love.aarch64" &
fi
if type pm_platform_helper >/dev/null 2>&1; then
  pm_platform_helper "$GAMEDIR/bin/love.aarch64"
fi

$NX_TASKSET ./bin/love.aarch64 "$GAMEDIR/lovegame"

if type pm_finish >/dev/null 2>&1; then
  pm_finish
else
  # Word splitting intended below: pidof may list several PIDs.
  # shellcheck disable=SC2046
  kill -9 $(pidof gptokeyb) 2>/dev/null || true
fi
