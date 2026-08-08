#!/bin/sh
# EXTRAS platform runtime dispatcher (Task 15). $1 is the launched entry's
# own script (e.g. Roms/Xtra Games (EXTRAS)/Gen1recomp.sh). Two branches:
#   - native: the entry's own script carries a "# NX_RUNTIME: native"
#     marker line in its first 20 lines -> exec it directly, no wrapper.
#     Native entries own their ENTIRE runtime themselves (env vars,
#     background services, cleanup) - this dispatcher does nothing else
#     for them. Declared in the entry's meta.txt via runtime=native.
#     No native catalog entry exists yet, so this branch is currently
#     unreached in practice; it's a seam for future entries.
#   - ports (default - no marker, e.g. gen1recomp's meta.txt declares
#     runtime=ports explicitly): run through the proven PORTS runtime,
#     as today.
# nx-redux uses a flattened SD card layout (.system/paks/...) - see
# PORTS_PAK_DIR in portmaster.c (SDCARD_PATH "/Emus/PORTS.pak", no
# platform subdir) and the release packaging, which flattens the SYSTEM
# tree - there is no supported platform-subdir card layout to fall back
# to. ports_launch.sh resolves the .ports data dir from the rom's own
# directory, so it works for "Xtra Games (EXTRAS)" unchanged.

if head -20 "$1" 2>/dev/null | grep -q "^# NX_RUNTIME: native"; then
    exec "$1"
fi

if [ -f "$SYSTEM_PATH/paks/Tools/PortMaster.pak/ports_launch.sh" ]; then
    exec "$SYSTEM_PATH/paks/Tools/PortMaster.pak/ports_launch.sh" "$@"
fi

echo "extras_games_launch.sh: ports_launch.sh not found in $SYSTEM_PATH/paks/Tools/PortMaster.pak/" >&2
exit 1
