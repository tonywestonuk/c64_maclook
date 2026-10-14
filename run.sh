#!/bin/bash
# Boot the desktop from its disk image in the patched Frodo (1351 mouse
# follows the host pointer).  "./run.sh real" uses full 1541 emulation:
# authentic, but loading takes about a minute.
cd "$(dirname "$0")"
if [ ! -x frodo4/src/Frodo ]; then       # fresh clone: build the emulator first
    (cd frodo4 && ./autogen.sh && make) || exit 1
fi
[ -f desktop64.d64 ] || ./build.sh
FAST=Emul1541Proc=false
[ "$1" = "real" ] && FAST=Emul1541Proc=true
exec frodo4/src/Frodo Mouse1351=true desktop64.d64 $FAST
