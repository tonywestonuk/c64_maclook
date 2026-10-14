#!/bin/bash
# Boot the desktop in the patched Frodo: the 1351 mouse follows the host
# pointer, and an emulated WiC64 on the user port offers flash/ as its
# internal flash (the startup disk) and share/ as a network share.  The
# disk image only holds BOOT, which loads the System from the flash.  "./run.sh real" uses full 1541 emulation for BOOT.
cd "$(dirname "$0")"
if [ ! -x frodo4/src/Frodo ]; then       # fresh clone: build the emulator first
    (cd frodo4 && ./autogen.sh && make) || exit 1
fi
[ -f desktop64.d64 ] || ./build.sh
FAST=Emul1541Proc=false
[ "$1" = "real" ] && FAST=Emul1541Proc=true
exec frodo4/src/Frodo Mouse1351=true MouseSync=true WiC64=true WiC64Flash="$PWD/flash" WiC64Share="Public=$PWD/share" desktop64.d64 $FAST
