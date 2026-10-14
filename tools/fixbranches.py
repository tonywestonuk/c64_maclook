#!/usr/bin/env python3
"""Rewrite out-of-range branches reported by ACME as inverted branch + jmp."""
import re, subprocess, sys
INV = {"bcc":"bcs","bcs":"bcc","beq":"bne","bne":"beq","bmi":"bpl","bpl":"bmi","bvc":"bvs","bvs":"bvc"}
for it in range(30):
    r = subprocess.run(["acme","-v1","--msvc","-r","build/system.lst","-l","build/system.sym","src/system.asm"],capture_output=True,text=True)
    if "Error" not in r.stdout+r.stderr:
        subprocess.run(["python3","tools/linksym.py","build/system.sym","build/syslink.asm"])
        r = subprocess.run(["acme","-v1","--msvc","-r","build/finder.lst","-l","build/finder.sym","src/finder_main.asm"],capture_output=True,text=True)
        if "Error" not in r.stdout+r.stderr:
            r = subprocess.run(["acme","-v1","--msvc","-r","build/brickles.lst","-l","build/brickles.sym","src/brickles_main.asm"],capture_output=True,text=True)
            if "Error" not in r.stdout+r.stderr:
                r = subprocess.run(["acme","-v1","--msvc","-r","build/sheet.lst","-l","build/sheet.sym","src/sheet_main.asm"],capture_output=True,text=True)
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
