#!/bin/sh
# run.sh - the firmware's test bench, on the host (see c64sim.cpp)
#
#   test/run.sh             the protocol, the flash volume and the matrix unit
#   test/run.sh --smb       also a network share, served by impacket on
#                           127.0.0.1:4450 (pip install impacket; see
#                           smbserver.py; PYTHON= the python that has it)
#
# Needs a C++17 compiler and cmake (for libsmb2, built for the host).

set -e
cd "$(dirname "$0")"
FW=..
B=build
mkdir -p $B

# libsmb2, as fetched for the firmware
if [ ! -d $FW/lib/libsmb2/libsmb2/lib ]; then
    git clone -q https://github.com/sahlberg/libsmb2.git $FW/lib/libsmb2/libsmb2
    git -C $FW/lib/libsmb2/libsmb2 checkout -q 4cce769
fi
if [ ! -f $B/libsmb2/lib/libsmb2.a ]; then
    cmake -S $FW/lib/libsmb2/libsmb2 -B $B/libsmb2 -DBUILD_SHARED_LIBS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_LIBKRB5=OFF -DENABLE_GSSAPI=OFF -DENABLE_LIBDCERPC=OFF -DENABLE_UTILS=OFF > $B/libsmb2.log
    cmake --build $B/libsmb2 --target smb2 -j 8 >> $B/libsmb2.log
fi

c++ -std=c++17 -g -O1 -Wall -Wno-unused-function -Ishim -I$FW/lib/libsmb2/libsmb2/include -I../../npu \
    -o $B/c64sim c64sim.cpp shim/shim.cpp ../../npu/npu.cpp \
    $FW/src/userport.cpp $FW/src/fileservice.cpp $FW/src/flash_volume.cpp $FW/src/smb_volume.cpp \
    $B/libsmb2/lib/libsmb2.a -lpthread

# a fresh copy of the startup disk, and an empty share
rm -rf $B/flash $B/share
cp -R ../../flash $B/flash
mkdir -p $B/share/Documents
echo "On the share" > "$B/share/Read Me.txt"

if [ "$1" = "--smb" ]; then
    ${PYTHON:-python3} smbserver.py PUBLIC $B/share 4450 > $B/smbserver.log 2>&1 &
    SMB=$!
    trap 'kill $SMB 2>/dev/null' EXIT
    sleep 2
    $B/c64sim $B/flash --smb 127.0.0.1:4450/PUBLIC
else
    $B/c64sim $B/flash
fi
