#!/bin/sh
# Headless single-ROM box-art fetch, spawned by NextUI's "Fetch Box Art".
# Args: <rom_path> <out_png> <system_tag> <status_file>
cd "$(dirname "$0")"
./scraper.elf --fetch "$1" --out "$2" --system "$3" --status "$4"
