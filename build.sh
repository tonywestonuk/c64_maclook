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

# The WiC64's internal flash: the startup disk, with the System Folder and
# the applications (Frodo serves this folder as volume 0; on a real WiC64
# it is uploaded to the flash with the firmware)
mkdir -p "flash/System Folder" "flash/Empty Folder"
cp build/system.prg "flash/System Folder/System.sys"
cp build/interface.ovl "flash/System Folder/Interface.ovl"
cp build/shapes.ovl "flash/System Folder/Shapes.ovl"
cp build/finder.prg "flash/System Folder/Finder.sys"
cp build/brickles.prg flash/Brickles.app
cp build/sheet.prg flash/Spreadsheet.app
cp build/shapes.prg flash/Shapes.app
# (share/ is a sample network share: documents, kept in the repository)

# The boot floppy: just BOOT, which loads SYSTEM from the share
python3 tools/d64.py build/desktop64.d64 "C64 DESKTOP" build/boot.prg:BOOT
cp build/desktop64.d64 desktop64.d64
ls -l desktop64.d64
