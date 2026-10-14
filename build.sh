#!/bin/bash
# Build SYSTEM, its API, and the applications, and put them on a 1541
# disk image.
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/fonts.py build/fonts.asm build/fonts.pbm
python3 tools/icons.py build/icons_sys.asm build/icons_finder.asm build/sprites.asm build/icons.pbm
acme -v1 --msvc -r build/system.lst -l build/system.sym "$@" src/system.asm
python3 tools/mkapi.py build/system.sym build/sysapi.asm docs/api.md
acme -v1 --msvc -r build/finder.lst -l build/finder.sym "$@" src/finder_main.asm
acme -v1 --msvc -r build/brickles.lst -l build/brickles.sym "$@" src/brickles_main.asm
acme -v1 --msvc -r build/sheet.lst -l build/sheet.sym "$@" src/sheet_main.asm
python3 tools/d64.py build/desktop64.d64 "C64 DESKTOP" build/system.prg:SYSTEM build/finder.prg:FINDER build/brickles.prg:BRICKLES build/sheet.prg:SHEET
cp build/desktop64.d64 desktop64.d64
ls -l desktop64.d64
