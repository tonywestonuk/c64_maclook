#!/usr/bin/env python3
"""polyhedron_bas.py - Polyhedron as a BASIC program, for the BASIC
application: the solids' corners, faces and edges as DATA, and the
matrix unit's script for a frame, as in the Polyhedron application.

    python3 tools/polyhedron_bas.py flash/BASIC/Polyhedron.bas
"""
import sys
import solids

PROGRAM = """\
REM Polyhedron, in BASIC: the WiC64's matrix unit turns the
REM solid and draws it, and sends back what changed.
REM Keys: 1 to {n} a solid, H the back edges, Q to stop.
x = 0: y = 1: z = 2: ng = 0: sx = 13
DIM ce(1, 0), ax(0, 2), an(0, 2), sp(0, 2), wf(0, 0)
DIM c%(2, {v}), n%(2, {f}), d%(0, {f}), e%(3, {e})
REM the centre, (0 0 1) to pick out z, the angles, the speeds
ce(0, 0) = 128: ce(1, 0) = 82: ax(0, 2) = 1
an(0, 1) = .6: an(0, 2) = .2
sp(0, 0) = .45: sp(0, 1) = .34: sp(0, 2) = .23
NPU LOAD 3, ce
NPU LOAD 12, ax
NPU LOAD 17, an
NPU LOAD 14, sp
NPU LOAD 20, wf
REM script 0: a frame, kept and run by the WiC64
NPU DEFINE 0
  NPU CLOCK 15
  NPU EMUL 16, 14, 15
  NPU ADD 17, 17, 16
  NPU TURN 1, z, 17, 0
  NPU TURN 8, x, 17, 1
  NPU TURN 9, y, 17, 2
  NPU MUL 10, 8, 1
  NPU MUL 10, 9, 10
  NPU MUL 2, 10, 0
  NPU PROJECT 2, 2, 400
  NPU ADD 2, 2, 3
  NPU MUL 11, 12, 10
  NPU MUL 11, 11, 4
  NPU ADD 11, 11, 13
  NPU APPLY 11, 11, ng
  NPU APPLY 11, 11, sx
  NPU PICK 18, 11, 5, 2
  NPU PICK 19, 11, 5, 3
  NPU ADD 18, 18, 19
  NPU ADD 18, 18, 20
  NPU CLEAR
  NPU LINES 2, 5, 18
  NPU SEND
NPU END
s = 1
10 GOSUB 100
20 NPU DRAW 0
GET k$
IF k$ >= "1" AND k$ <= "{n}" THEN s = VAL(k$): GOTO 10
IF k$ = "h" THEN wf(0, 0) = 1 - wf(0, 0): NPU LOAD 20, wf
IF k$ <> "q" THEN 20
END
100 REM solid s: its corners, faces (normal, and distance) and edges
RESTORE
FOR i = 1 TO s
READ nv, nf, ne
IF i = s THEN 110
FOR j = 1 TO 3 * nv + 4 * nf + 4 * ne: READ t: NEXT
NEXT
110 FOR j = 0 TO nv - 1: READ c%(0, j), c%(1, j), c%(2, j): NEXT
FOR j = 0 TO nf - 1: READ n%(0, j), n%(1, j), n%(2, j), d%(0, j): NEXT
FOR j = 0 TO ne - 1: READ e%(0, j), e%(1, j), e%(2, j), e%(3, j): NEXT
NPU LOAD 0, c%, nv
NPU LOAD 4, n%, nf
NPU LOAD 13, d%, nf
NPU LOAD 5, e%, ne
RETURN
"""

CHOSEN = ["Cube", "Octahedron", "Icosahedron"]


def data_lines(nums, per=14):
    return ["DATA " + ", ".join(str(x) for x in nums[i:i + per])
            for i in range(0, len(nums), per)]


def main(out):
    made = []
    for name, make in solids.SOLIDS:
        if name in CHOSEN:
            made.append((name, solids.solid(make())))
    vmax = max(len(p) for _, (p, f, e) in made)
    fmax = max(len(f) for _, (p, f, e) in made)
    emax = max(len(e) for _, (p, f, e) in made)
    text = PROGRAM.format(n=len(made), v=vmax - 1, f=fmax - 1, e=emax - 1)
    for name, (points, faces, edges) in made:
        nums = []
        for p in points:
            nums += [round(x) for x in p]
        for nrm, dist, _ in faces:
            nums += [round(x * 64) for x in nrm]
            nums.append(round((dist / solids.DIST + solids.EDGE_ON) * 64))
        for ed in edges:
            nums += list(ed)
        text += f"REM {name}\n"
        text += f"DATA {len(points)}, {len(faces)}, {len(edges)}\n"
        text += "\n".join(data_lines(nums)) + "\n"
    open(out, "w", newline="\r").write(text)
    print(f"{out}: {len(text)} characters")


if __name__ == "__main__":
    main(sys.argv[1])
