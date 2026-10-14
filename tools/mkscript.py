#!/usr/bin/env python3
"""Tiny DSL -> Frodo TestInput script.
Lines:  wait N | move x y | click x y | dclick x y | drag x1 y1 x2 y2 | menu mx itemy |
        key NAME | type TEXT | shot NAME | dump NAME
Frame counter advances automatically."""
import sys
f = 450           # boot done by then
out = []
def emit(cmd): out.append(f"{f} {cmd}")
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith("#"): continue
    w = line.split(None, 1); op = w[0]; arg = w[1] if len(w) > 1 else ""
    a = arg.split()
    if op == "wait": f += int(a[0])
    elif op == "start": f = int(a[0])
    elif op == "move": emit(f"mouse {a[0]} {a[1]}"); f += 12
    elif op == "click":
        emit(f"mouse {a[0]} {a[1]}"); f += 12; emit("down"); f += 5; emit("up"); f += int(a[2]) if len(a) > 2 else 40
    elif op == "dclick":
        emit(f"mouse {a[0]} {a[1]}"); f += 12; emit("down"); f += 4; emit("up"); f += 12; emit("down"); f += 4; emit("up"); f += 60
    elif op == "drag":
        emit(f"mouse {a[0]} {a[1]}"); f += 12; emit("down"); f += 8
        x1, y1, x2, y2 = map(int, a[:4])
        for i in range(1, 9):
            emit(f"mouse {x1 + (x2-x1)*i//8} {y1 + (y2-y1)*i//8}"); f += 3
        f += 10; emit("up"); f += 50
    elif op == "menu":
        emit(f"mouse {a[0]} 5"); f += 12; emit("down"); f += 20
        emit(f"mouse {a[0]} {a[1]}"); f += 20; emit("up"); f += 40
    elif op == "key":
        emit(f"keydown {arg}"); f += 3; emit(f"keyup {arg}"); f += 8
    elif op == "cmd":
        emit("keydown 226"); f += 2; emit(f"keydown {arg}"); f += 3; emit(f"keyup {arg}"); f += 1; emit("keyup 226"); f += 30
    elif op == "type":
        emit(f"type {arg}"); f += 4 * len(arg) + 10
    elif op == "shot": emit(f"shot build/{arg}.bmp"); f += 1
    elif op == "dump": emit(f"dump build/{arg}.bin"); f += 1
open(sys.argv[2], "w").write("\n".join(out) + "\n")
print(f + 20)
