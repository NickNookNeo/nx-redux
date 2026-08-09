#!/bin/sh
# NX_RUNTIME: native
# gen1recomp launcher — self-contained native runtime entry (2026-08-10
# conversion; extras_games_launch.sh execs this directly, no PortMaster).
#
# Why native works: the bundled LOVE 11.5 runtime resolves every shared-lib
# dependency without PortMaster - love.aarch64 needs only libc + the bundled
# liblove/libluajit (libs.aarch64/), and liblove's own deps come from the
# firmware: SDL2 + mpg123 from /usr/trimui/lib, freetype/openal/theoradec/
# vorbisfile/z/stdc++ from /usr/lib (device-verified on tg5040 2026-08-10).
# POSIX sh on purpose: /bin/bash on these cards is a symlink ports_launch.sh
# creates INTO PortMaster's vendored bin - a bash shebang would quietly
# reintroduce the dependency this entry just dropped.
#
# What this script owns (native entries own their ENTIRE runtime):
#   - LD_LIBRARY_PATH (bundled libs first, then the firmware SDL)
#   - Nintendo-layout SDL controller override (physical A = confirm), same
#     xbox_layout user toggle PortMaster ports honor
#   - audio routing: copy audiomon's .asoundrc so ALSA follows the chosen
#     output sink (BT/USB DAC), plus the anti-pop speaker mute dance
#   - /tmp/stay_awake + sleepmon.elf (power-button sleep, system binary on
#     the launch-chain PATH), mirroring ports_launch.sh - which also never
#     clears stay_awake; the MinUI launch loop handles post-exit state
#   - CPU: performance governor; tg5050 additionally gets the eMMC swapfile
#     (OOM guard, verified 2026-08-06: game + voxel mod peak ~750MB on a
#     1GB device; exFAT SD can't host swap) and big-core pinning. The MinUI
#     launch loop restores CPU state after the game exits.

SHDIR="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR="$SHDIR/.ports/gen1recomp"
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1
: > "$GAMEDIR/log.txt"
exec > "$GAMEDIR/log.txt" 2>&1

export HOME="$CONFDIR"
export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs.aarch64:/usr/trimui/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Audio-output routing: audiomon maintains the ALSA config for the active
# sink under USERDATA_PATH; ALSA discovers it via $HOME/.asoundrc. Refresh
# every launch (and drop a stale copy when routing was reset) so in-game
# audio follows the sink chosen in Settings.
if [ -f "${USERDATA_PATH:-}/.asoundrc" ]; then
    cp -f "$USERDATA_PATH/.asoundrc" "$HOME/.asoundrc"
else
    rm -f "$HOME/.asoundrc"
fi

# get_controls' positional (Xbox-convention) mapping would land confirm on
# physical B; apply the default-nintendo override for the TRIMUI Player1
# GUID unless the user opted into positional layout via the shared toggle.
NX_SHARED_USERDATA="${SHARED_USERDATA_PATH:-${SDCARD_PATH:-/mnt/SDCARD}/.userdata/shared}"
if [ ! -f "$NX_SHARED_USERDATA/PORTS-portmaster/xbox_layout" ]; then
    export SDL_GAMECONTROLLERCONFIG="030000005e0400008e02000014010000,TRIMUI Player1,a:b1,b:b0,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b3,y:b2,platform:Linux,"
fi
export LOVE_GRAPHICS_USE_OPENGLES="${LOVE_GRAPHICS_USE_OPENGLES:-1}"
export POKEPORT_GBCFX="${POKEPORT_GBCFX:-0}"

chmod a+x ./bin/love.aarch64 2>/dev/null

echo "1" > /tmp/stay_awake

NX_SLEEPMON_PID=""
cleanup() {
    [ -n "$NX_SLEEPMON_PID" ] && kill "$NX_SLEEPMON_PID" 2>/dev/null
    echo 0 > /sys/class/speaker/mute 2>/dev/null
    rm -f "$HOME/.asoundrc"
}
trap cleanup EXIT INT TERM HUP QUIT

# Anti-pop: mute the speaker over LOVE/OpenAL init, then unmute and let
# syncsettings.elf restore the user's saved volume (same dance
# ports_launch.sh does for every port).
echo 1 > /sys/class/speaker/mute 2>/dev/null
( sleep 5; echo 0 > /sys/class/speaker/mute 2>/dev/null; syncsettings.elf 2>/dev/null ) &

# Power-button sleep/poweroff handler for the duration of the game.
if command -v sleepmon.elf >/dev/null 2>&1; then
    sleepmon.elf &
    NX_SLEEPMON_PID=$!
fi

# Per-platform tuning; MinUI's launch loop restores CPU state afterwards.
NX_TASKSET=""
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
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
    echo performance > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor 2>/dev/null
    command -v taskset >/dev/null 2>&1 && NX_TASKSET="taskset -c 4-7"
    ;;
esac

$NX_TASKSET ./bin/love.aarch64 "$GAMEDIR/lovegame"
