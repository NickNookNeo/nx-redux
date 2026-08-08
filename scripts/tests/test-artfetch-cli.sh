#!/usr/bin/env bash
# On-device contract test for scraper.elf --fetch. Covers the offline-
# deterministic paths (unsupported system, missing args). Happy-path scraping
# is verified manually with network. Requires: adb + a connected device with
# the Artwork Manager pak installed.
set -euo pipefail
cd "$(dirname "$0")/../.."

command -v adb >/dev/null || { echo "SKIP: adb not found"; exit 0; }
adb get-state >/dev/null 2>&1 || { echo "SKIP: no device"; exit 0; }

PAK=$(adb shell 'ls -d /mnt/SDCARD/.system/*/paks/Tools/"Artwork Manager.pak" 2>/dev/null | head -1' | tr -d '\r')
[ -n "$PAK" ] || { echo "SKIP: Artwork Manager.pak not on device"; exit 0; }
ELF="$PAK/scraper.elf"
ST=/tmp/artfetch_test.status
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1) unsupported system -> status "error", exit 1 (no network needed)
adb shell "rm -f $ST; cd \"$PAK\"; ./scraper.elf --fetch /tmp/none.sfc --out /tmp/o.png --system NOPE --status $ST; echo RC=\$?" > /tmp/t.out
grep -q 'RC=1' /tmp/t.out || fail "unsupported-system exit code (want 1): $(cat /tmp/t.out)"
[ "$(adb shell "cat $ST 2>/dev/null" | tr -d '\r')" = "error" ] || fail "unsupported-system status (want error)"

# 2) missing args -> exit 2
adb shell "cd \"$PAK\"; ./scraper.elf --fetch /tmp/none.sfc; echo RC=\$?" > /tmp/t.out
grep -q 'RC=2' /tmp/t.out || fail "missing-args exit code (want 2): $(cat /tmp/t.out)"

echo "PASS: test-artfetch-cli"
