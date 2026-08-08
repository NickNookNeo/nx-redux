#!/bin/sh

cd "$(dirname "$0")" || exit

# Idle big core for the catalog UI
echo 408000 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq 2>/dev/null

./extras.elf > "$LOGS_PATH/Xtras.txt" 2>&1
