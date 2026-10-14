#!/usr/bin/env python3
"""peek.py dump.bin name[:len] ... - show memory at symbols from build/os.sym"""
import re, sys
syms = {}
for f in ("build/system.sym", "build/finder.sym", "build/brickles.sym", "build/sheet.sym"):
  for line in open(f):
    m = re.match(r'\s*(\S+)\s*=\s*\$([0-9a-fA-F]+)', line)
    if m: syms[m.group(1)] = int(m.group(2), 16)
d = open(sys.argv[1], "rb").read()
a, x, y, p, sp, pcl, pch = d[0x10000:0x10007]
pc = pcl | pch << 8
near = min((v, k) for k, v in syms.items() if v <= pc and pc - v < 0x400) if pc >= 0x801 else (0, "?")
print(f"PC=${pc:04x} ({near[1]}+{pc-near[0]}) A={a:02x} X={x:02x} Y={y:02x} P={p:02x} SP={sp:02x}")
for arg in sys.argv[2:]:
    name, _, n = arg.partition(":")
    addr = syms[name] if name in syms else int(name, 16)
    n = int(n) if n else 1
    print(f"{name:14s} ${addr:04x}: " + " ".join(f"{b:02x}" for b in d[addr:addr + n]))
