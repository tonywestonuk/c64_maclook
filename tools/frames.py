#!/usr/bin/env python3
"""frames.py - frames a second from pairs of RAM dumps (tests/ph_speed.dsl):
python3 tools/frames.py ADDRESS JIFFIES name_a.bin name_b.bin ..."""
import sys
addr = int(sys.argv[1], 0)
jiffies = int(sys.argv[2])
files = sys.argv[3:]
for a, b in zip(files[::2], files[1::2]):
    fa = open(a, "rb").read()
    fb = open(b, "rb").read()
    n = (fb[addr] | fb[addr + 1] << 8) - (fa[addr] | fa[addr + 1] << 8)
    print(f"{a.split('/')[-1][:-6]:12s} {n:4d} frames in {jiffies} jiffies = {n * 50 / jiffies:.1f} a second")
