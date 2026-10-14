#!/bin/bash
# usage: tools/shot.sh script.txt out_prefix [frames]
# Runs the OS headless in Frodo's testbench mode with scripted input.
# "shot name.bmp" lines in the script save screenshots (converted to PNG).
SCRIPT=$1; OUT=$2; N=${3:-3000}
DIR=$(cd "$(dirname "$0")/.." && pwd)
CFG=$(mktemp -t frodocfg)
cd "$DIR"
"$DIR/frodo4/src/Frodo" -c "$CFG" TestBench=true TestMaxFrames=$N TestInput="$SCRIPT" \
   LimitSpeed=false SIDType=NONE FastReset=true Mouse1351=true MouseSync=true WiC64=true WiC64Share="$DIR/share" \
   "$DIR/desktop64.d64" Emul1541Proc=false >/dev/null 2>&1
rm -f "$CFG"
for f in ${OUT}*.bmp; do
  [ -f "$f" ] && magick "$f" -crop 320x200+32+35 +repage -scale 200% "${f%.bmp}.png" && rm "$f"
done
true
