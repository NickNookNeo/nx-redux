#!/usr/bin/env bash
# Verifies fetchart.sh maps positional args to the scraper --fetch CLI and runs
# from the pak dir. Stubs scraper.elf; no device or network needed.
set -euo pipefail
cd "$(dirname "$0")/../.."
SH="skeleton/SYSTEM/tg5040/paks/Tools/Artwork Manager.pak/fetchart.sh"
[ -f "$SH" ] || { echo "FAIL: $SH missing" >&2; exit 1; }
[ -x "$SH" ] || { echo "FAIL: $SH not executable" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/pak"
cp "$SH" "$TMP/pak/fetchart.sh"
cat > "$TMP/pak/scraper.elf" <<EOF
#!/bin/sh
echo "ARGS=\$*" > "$TMP/got.txt"
echo "CWD=\$(pwd)" >> "$TMP/got.txt"
EOF
chmod +x "$TMP/pak/scraper.elf" "$TMP/pak/fetchart.sh"

( cd /; "$TMP/pak/fetchart.sh" /roms/Game.sfc /roms/.media/Game.png SFC /tmp/st )

grep -qF -- "ARGS=--fetch /roms/Game.sfc --out /roms/.media/Game.png --system SFC --status /tmp/st" \
  "$TMP/got.txt" || { echo "FAIL: arg mapping: $(cat "$TMP/got.txt")" >&2; exit 1; }
grep -qF "CWD=$TMP/pak" "$TMP/got.txt" || { echo "FAIL: cwd not pak dir: $(cat "$TMP/got.txt")" >&2; exit 1; }
echo "PASS: test-artfetch-sh"
