#!/usr/bin/env python3
"""Minimal 1541 D64 writer.
usage: d64.py out.d64 "DISK NAME" file.prg:NAME [file2.prg:NAME2 ...]"""
import sys

SPT = [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5          # sectors per track 1..35
img = bytearray(174848)
used = {t: set() for t in range(1, 36)}
used[18].update({0, 1})


def off(t, s):
    return (sum(SPT[:t - 1]) + s) * 256


def petscii(name, n=16):
    return name.upper().encode('ascii')[:n].ljust(n, b'\xa0')


# tracks nearest the directory first, sectors interleaved by 10
order = []
for d in range(1, 18):
    for t in (18 - d, 18 + d):
        if 1 <= t <= 35:
            order.append(t)
state = {'ti': 0, 's': 0}


def alloc():
    while True:
        t = order[state['ti']]
        if len(used[t]) == SPT[t - 1]:
            state['ti'] += 1
            state['s'] = 0
            continue
        s = state['s']
        while s in used[t]:
            s = (s + 1) % SPT[t - 1]
        used[t].add(s)
        state['s'] = (s + 10) % SPT[t - 1]
        return t, s


entries = []
for arg in sys.argv[3:]:
    path, _, name = arg.rpartition(':')
    data = open(path, 'rb').read()
    chunks = [data[i:i + 254] for i in range(0, len(data), 254)]
    secs = [alloc() for _ in chunks]
    for i, c in enumerate(chunks):
        o = off(*secs[i])
        if i + 1 < len(chunks):
            img[o], img[o + 1] = secs[i + 1]
        else:
            img[o], img[o + 1] = 0, len(c) + 1
        img[o + 2:o + 2 + len(c)] = c
    entries.append((name, secs[0], len(chunks)))
    print(f"{name}: {len(chunks)} blocks", file=sys.stderr)

# directory 18/1 (8 entries per sector is plenty here)
o = off(18, 1)
img[o:o + 2] = b'\x00\xff'
for k, (name, (t, s), blocks) in enumerate(entries):
    e = o + 2 + 32 * k
    img[e] = 0x82                              # PRG, closed
    img[e + 1], img[e + 2] = t, s
    img[e + 3:e + 19] = petscii(name)
    img[e + 28] = blocks & 255
    img[e + 29] = blocks >> 8
# BAM 18/0
o = off(18, 0)
img[o:o + 4] = bytes([18, 1, 0x41, 0])
for t in range(1, 36):
    free = [s for s in range(SPT[t - 1]) if s not in used[t]]
    bits = sum(1 << s for s in free)
    img[o + 4 * t: o + 4 * t + 4] = bytes([len(free), bits & 255, (bits >> 8) & 255, bits >> 16])
img[o + 0x90:o + 0xa0] = petscii(sys.argv[2])
img[o + 0xa0:o + 0xab] = b'\xa0\xa0' + b'64' + b'\xa0' + b'2A' + b'\xa0\xa0\xa0\xa0'
open(sys.argv[1], 'wb').write(img)
