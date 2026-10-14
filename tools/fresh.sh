#!/bin/bash
# fresh copies of the volumes for a test that changes them:
#   eval $(tools/fresh.sh)    -> FLASH_DIR, SHARE_DIR in build/test_*
DIR=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$DIR/build/test_flash" "$DIR/build/test_share"
cp -R "$DIR/flash" "$DIR/build/test_flash"
cp -R "$DIR/share" "$DIR/build/test_share"
echo "export FLASH_DIR=$DIR/build/test_flash SHARE_DIR=$DIR/build/test_share"
