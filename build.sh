#!/bin/bash
# Build SYSTEM, its API, and the applications, and put them on a 1541
# disk image.
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/fonts.py build/fonts.asm build/fonts.pbm
python3 tools/icons.py build/icons_sys.asm build/icons_finder.asm build/sprites.asm build/icons.pbm
python3 tools/mkovl.py stubs build/ovl_stubs.asm
acme -v1 --msvc -r build/system.lst -l build/system.sym "$@" src/system.asm
python3 tools/mkapi.py build/system.sym build/sysapi.asm docs/api.md
python3 tools/mkovl.py syms build/system.sym
for o in src/ovl_*.asm; do
    n=$(basename "$o" .asm)
    acme -v1 --msvc -r "build/$n.lst" -l "build/$n.sym" "$@" "$o"
done
acme -v1 --msvc -r build/finder.lst -l build/finder.sym "$@" src/finder_main.asm
acme -v1 --msvc -r build/brickles.lst -l build/brickles.sym "$@" src/brickles_main.asm
acme -v1 --msvc -r build/sheet.lst -l build/sheet.sym "$@" src/sheet_main.asm
acme -v1 --msvc -r build/shapes.lst -l build/shapes.sym "$@" src/shapes_main.asm
acme -v1 --msvc -r build/boot.lst -l build/boot.sym "$@" src/bootstrap.asm

# The network share: what the WiC64 offers the C64 (Frodo serves this
# folder; on real hardware, copy it to the SMB share)
mkdir -p "share/System Folder" "share/Empty Folder"
cp build/system.prg "share/System Folder/System.sys"
cp build/finder.prg "share/System Folder/Finder.sys"
cp build/interface.ovl "share/System Folder/Interface.ovl"
cp build/shapes.ovl "share/System Folder/Shapes.ovl"
cp build/brickles.prg share/Brickles.app
cp build/sheet.prg share/Spreadsheet.app
cp build/shapes.prg share/Shapes.app

# The boot floppy: just BOOT, which loads SYSTEM from the share
python3 tools/d64.py build/desktop64.d64 "C64 DESKTOP" build/boot.prg:BOOT
cp build/desktop64.d64 desktop64.d64
ls -l desktop64.d64
