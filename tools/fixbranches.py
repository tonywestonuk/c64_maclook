#!/usr/bin/env python3
"""Rewrite out-of-range branches reported by ACME as inverted branch + jmp."""
import re, subprocess, sys
INV = {"bcc":"bcs","bcs":"bcc","beq":"bne","bne":"beq","bmi":"bpl","bpl":"bmi","bvc":"bvs","bvs":"bvc"}
PROGRAMS = ["finder", "brickles", "sheet", "shapes"]   # applications, after the System
def acme(name, src):
    return subprocess.run(["acme", "-v1", "--msvc", "-r", f"build/{name}.lst", "-l", f"build/{name}.sym", src],
                          capture_output=True, text=True)
for it in range(30):
    r = acme("system", "src/system.asm")
    if "Error" not in r.stdout+r.stderr:
        subprocess.run(["python3","tools/mkapi.py","build/system.sym","build/sysapi.asm","docs/api.md"])
        for name in PROGRAMS:
            r = acme(name, f"src/{name}_main.asm")
            if "Error" in r.stdout+r.stderr:
                break
    errs = re.findall(r'^(\S+)\((\d+)\) : Error \([^)]*\): Target out of range', r.stdout+r.stderr, re.M)
    if not errs:
        print((r.stdout+r.stderr).strip() or "clean"); break
    byfile = {}
    for f,l in errs: byfile.setdefault(f,set()).add(int(l))
    for f,lines in byfile.items():
        src = open(f).read().split("\n")
        for ln in sorted(lines, reverse=True):
            line = src[ln-1]
            m = re.match(r'^(\S*?)(\s+)(b(?:cc|cs|eq|ne|mi|pl|vc|vs))\s+(\S+)(.*)$', line)
            if not m: print("cannot fix", f, ln, line); continue
            lab, ws, op, tgt, rest = m.groups()
            new = []
            if lab: new.append(lab)
            fx = f".bf{ln}"
            new.append(f"        {INV[op]} {fx}")
            new.append(f"        jmp {tgt}")
            new.append(f"{fx}:")
            src[ln-1:ln] = new
        open(f,"w").write("\n".join(src))
        print("fixed", f, sorted(lines))
