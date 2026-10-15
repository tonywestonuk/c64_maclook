# The matrix unit (WiC64 command `$90`)

The WiC64's ESP32 is far quicker at arithmetic than the C64's 6510, and it
has a floating point unit. The matrix unit lets the C64 use it as a
coprocessor: the C64 sends matrices, the ESP32 works on them (multiplies
them, rotates them, applies the functions of a neural network) and sends
the results back.

It has **32 matrix registers**, numbered 0 to 31, which keep their contents
between requests: data that doesn't change (a model's points, a network's
weights) is sent once, and each request after that sends only what changed.
It also keeps up to **8 scripts**: programs sent once and run again by a
two-byte request, so that an animation costs the C64 almost nothing a frame.
And it can **draw**: it keeps a copy of the C64's screen, draws lines on it,
and sends back only the bytes that changed, laid out as the C64's bitmap is,
in a **burst** that the C64 writes straight into screen memory.
A matrix has 1 to 255 rows and 1 to 255 columns; the registers together hold
at most 8,192 elements on a real WiC64 (65,536 in Frodo's emulation).

One request, command `$90`, carries a **program**: a list of instructions.
They run in order; the results of its `STORE` instructions, one after the
other, are the response. A program can be as long as a request allows
(64K). The same unit is in Frodo's emulated WiC64 and in the firmware
(`npu/npu.cpp`, shared by both). In Frodo, `CLOCK` keeps the emulated C64's
time; on a real WiC64, the ESP32's.

From the System, call `npu_run` (see [api.md](api.md)) with the program at
`fs_dptr` (`fs_dlen` bytes); the results go to `fs_rptr` (at most `fs_rmax`
bytes), their length to `fs_rlen`. Carry is set on an error, with the status
in A. For a program that draws, call `npu_draw` instead: its results (from
`SEND`) go straight into the bitmap. The constants below are in
`build/sysapi.asm` with an `NPU_` prefix.

## Numbers

Inside the unit, elements are 32-bit floating point numbers. The C64 sends
and receives them as **fixed-point** numbers, in a format given by one byte:

| Bits | |
|---|---|
| 0–3 | fraction bits *f* (0–15): the number is the integer ÷ 2^*f* |
| 4–5 | type: `0` signed 16 bits (`NPU_S16`), `1` signed 8 bits (`NPU_S8`), `2` unsigned 8 bits (`NPU_U8`) |

So `$00` is a plain 16-bit integer, `$08` a 16-bit number with 8 fraction
bits (−128 to 127.996), `$16` a signed byte with 6 fraction bits. 16-bit
numbers are little-endian. Results are rounded to the nearest and held to
the type's range; a result that isn't a number (0 ÷ 0) is stored as 0.

Constants in instructions (*k* below) are signed 32-bit numbers with 16
fraction bits (16.16): `$00010000` is 1.0. Angles for `ROTATE` are 16 bits,
65,536 to a full turn (`$4000` is a quarter turn); `TURN` takes its angle,
in radians, from a register, where a script can move it on.

Matrices are sent row by row. A point set is usually held one point per
**column**: a 2×*n* matrix has the *x* coordinates in row 0 and the *y*
coordinates in row 1, so that `MUL` by a rotation matrix transforms them all.

## Instructions

*r*, *d*, *a* and *b* are register numbers; *d* is where the result goes (it
may be the same as *a* or *b*).

| Code | Instruction | Operands | |
|---|---|---|---|
| `$00` | `END` | | Stop here (the end of the request does too) |
| `$01` | `LOAD` | *r*, rows, cols, format, data | A matrix from the C64 |
| `$02` | `STORE` | *r*, format | Send *r* back: rows (1), cols (1), then the elements |
| `$03` | `FILL` | *r*, rows, cols, *k* | Every element *k* |
| `$04` | `IDENT` | *r*, *n* | The *n*×*n* identity matrix |
| `$05` | `RANGE` | *r*, rows, cols, *start*, *step* | Element *i* (row by row) = *start* + *i*·*step* |
| `$06` | `COPY` | *d*, *a* | |
| `$07` | `TRANSP` | *d*, *a* | Transposed |
| `$08` | `JOIN` | *d*, *a*, *b*, how | how `0`: *b*'s columns after *a*'s; `1`: *b*'s rows below *a*'s |
| `$09` | `FREE` | *r* | Empty *r*, giving back its memory |
| `$0A` | `RESET` | | Empty all the registers and scripts |
| `$0B` | `DEFINE` | *s*, length (2), instructions | Keep the instructions as script *s* (0–7), without running them |
| `$0C` | `RUN` | *s* | Run script *s*; its `STORE`s go into this response |
| `$0D` | `CLOCK` | *r* | 1×1: the seconds since the last `CLOCK` (0 the first time, at most 0.25) |
| `$10` | `ADD` | *d*, *a*, *b* | *a* + *b*, element by element |
| `$11` | `SUB` | *d*, *a*, *b* | *a* − *b* |
| `$12` | `EMUL` | *d*, *a*, *b* | *a* × *b*, element by element |
| `$13` | `EDIV` | *d*, *a*, *b* | *a* ÷ *b*, element by element |
| `$14` | `MUL` | *d*, *a*, *b* | The matrix product *a*·*b* (*a*'s columns = *b*'s rows) |
| `$15` | `SCALE` | *d*, *a*, *k* | *a* × *k* |
| `$16` | `OFFSET` | *d*, *a*, *k* | *a* + *k* |
| `$17` | `APPLY` | *d*, *a*, function | A function of each element (below) |
| `$18` | `SOFTMAX` | *d*, *a* | Softmax of each column |
| `$19` | `SUM` | *d*, *a*, how | how `0`: the sum of each column (1×cols); `1`: of each row (rows×1) |
| `$1A` | `ARGMAX` | *d*, *a* | For each column, the row of its largest element (1×cols) |
| `$1B` | `PICK` | *d*, *a*, *b*, row | 1×cols of *b*: element *j* is element number *b*(row, *j*) of *a* (row by row) |
| `$20` | `ROTATE` | *r*, axis, angle | A rotation matrix: axis `0` *x*, `1` *y*, `2` *z* (3×3), `3` in the plane (2×2) |
| `$21` | `PROJECT` | *d*, *a*, *k* | Perspective: *a* is 3×*n* (*x*, *y*, *z*); *d* is 2×*n*, *x*·*k*/(*k*+*z*), *y*·*k*/(*k*+*z*), seen from *k* in front |
| `$22` | `TURN` | *d*, axis, *a*, *i* | As `ROTATE`, by the angle in element *i* (row by row) of *a*, in radians |
| `$30` | `SCREEN` | *x* (2), *y* (2), *w* (2), *h* (2) | Draw in the *w*×*h* rectangle at *x*, *y* on the C64's screen, which is white there (below) |
| `$31` | `CLEAR` | | Make the rectangle white |
| `$32` | `LINES` | *p*, *e*, *m* | Lines between the points of *p* (2×*n*: *x* above *y*, from the rectangle's top left), from point *e*(0, *j*) to point *e*(1, *j*), for each column *j* of *e* where *m*(0, *j*) > 0 (*m* = 255: all of them) |
| `$33` | `SEND` | | → the bytes of the screen that changed since the last `SEND` (below) |

For `ADD`, `SUB`, `EMUL` and `EDIV`, *b* may be the same size as *a*, or a
single row, a single column or a single element, which is then used for
every row, column or element of *a* (a "broadcast"): adding a 2×1 column
moves every point of a 2×*n* matrix.

Rotation matrices turn column vectors anticlockwise in ordinary axes; on the
screen, where *y* grows downwards, `ROTATE` *r*, 3, angle turns points
clockwise.

Scripts can run scripts, up to 4 deep. A script is copied when it runs, so
it may `DEFINE` a new version of itself for next time.

`APPLY` functions: `0` negate, `1` absolute value, `2` ReLU, `3` sigmoid,
`4` tanh, `5` square root (0 for negative numbers), `6` exp, `7` natural log,
`8` sin, `9` cos (radians), `10` round, `11` floor, `12` square, `13` step (1
above 0, else 0).

## Status

`0` is success. Errors (the text, which names the instruction, is available
from command `$2A`, the status message):

| Status | |
|---|---|
| 20 | a bad program: an unknown instruction, bad operands, or one cut short |
| 32 | a register or a script was used before it was set |
| 33 | the sizes don't fit (`MUL` of 2×3 by 2×5, say) |
| 34 | out of matrix memory (or of script memory: 4K for all 8) |
| 35 | the results are too big for one response |

The instructions before the one that failed have been carried out, but no
results are sent. An error in a script says so: "Script 0, instruction 5
(MUL): ...".


## Drawing on the C64's screen

The unit keeps its own copy of the C64's 320×200 hires screen, laid out as the
C64's bitmap is (byte (*y* ÷ 8)·320 + (*x* ÷ 8)·8 + *y* mod 8, a bit per pixel,
set for black), and a second copy of what the C64 has been sent.

- `SCREEN` says where to draw: a rectangle on the screen (a window's content,
  say), white on the C64 at that moment. Drawing is clipped to the whole bytes
  inside it, so nothing outside the rectangle is ever sent.
- `CLEAR` and `LINES` draw on the copy, not on the C64.
- `SEND` sends the bytes inside the rectangle that differ from what the C64
  has, as **runs**: offset in the bitmap (2 bytes; bit 15 set if the bytes are
  8 apart, along a pixel row, at most 32 of them), count (1, at most 255), and
  the bytes. A frame of a turning solid is typically 1–3K.

`npu_draw` sends the program with command **`$91`**, the same as `$90` except
that the response comes in a **burst** (below), and writes each run straight
into the bitmap at `$E000`, after checking that it lies inside it. A run that
doesn't makes the call fail with `FS_IOERR`; the application should then
redraw its window and start again with `SCREEN`. `SEND`'s runs must be the
program's only results.

## The burst

In the standard protocol the WiC64 answers each byte the C64 reads with a
FLAG2 pulse, and the C64 waits for it before the next read. In a burst it
doesn't wait: after the usual turn round (PA2 low, one FLAG2 pulse, one read
of `$DD01` to start), the C64 reads `$DD01` back to back, the status, size and
payload, as fast as it can: 7 cycles apart at the quickest. Each read pulses
PC2; the WiC64 has the next byte on the port before the next read. The C64
writes a byte of a run in 17 cycles (21 for a run along a pixel row), against
about 120 with the standard protocol.

The WiC64's interrupt is too slow for that, so the firmware sends a burst from
a loop that watches PC2's edge latch (with PC2's interrupt off and the task
scheduler paused; Wi-Fi runs on the other core). A burst response is at most
12,000 bytes. In Frodo every byte is on the port at once.

## Example: a solid turned and drawn in 3D

The Polyhedron application (`src/polyhedron_main.asm`) keeps a solid on the
WiC64, and draws nothing itself. At the start it sends the centre of its
window, the starting angles and a script for one frame:

```
LOAD    3, 2, 1, S16, cx, cy     ; the centre
LOAD    12, 1, 3, S8, 0, 0, 1    ; (0 0 1): picks out z
LOAD    17, 1, 3, S16+8, ...     ; the angles about z, x and y (radians)
LOAD    14, ...                  ; the speeds
LOAD    20, 1, 1, U8, 0          ; 1 to show the back edges too
DEFINE  0, length:               ; script 0, a frame:
  CLOCK   15                     ;   the seconds since the last frame
  EMUL    16, 14, 15             ;   × the speeds (14, 1×3)
  ADD     17, 17, 16             ;   the angles move on
  TURN    1, z, 17, 0
  TURN    8, x, 17, 1
  TURN    9, y, 17, 2
  MUL     10, 8, 1
  MUL     10, 9, 10              ;   the whole turn, 3×3
  MUL     2, 10, 0               ;   the corners turned, 3×v
  PROJECT 2, 2, 400              ;   in perspective, 2×v
  ADD     2, 2, 3                ;   in the middle of the window
  MUL     11, 12, 10             ;   the turn's z row ..
  MUL     11, 11, 4              ;   .. × the faces' normals: their z, 1×f
  ADD     11, 11, 13             ;   + distance / 400: negative faces the eye
  APPLY   11, 11, neg
  APPLY   11, 11, step           ;   1 for the faces in front
  PICK    18, 11, 5, 2           ;   for each edge, the faces in front
  PICK    19, 11, 5, 3           ;   either side of it
  ADD     18, 18, 19
  ADD     18, 18, 20             ;   (+ 1 for every edge, to show them all)
  CLEAR
  LINES   2, 5, 18               ;   the edges with a face in front
  SEND                           ;   -> what changed on the screen
```

When a solid is chosen it sends its corners (register 0, 3×*v*), its faces'
outward normals (4, 3×*f*), the faces' distances from the centre ÷ 400 (13,
1×*f*) and its edges (5, 4×*e*: from, to, and the faces either side), made by
`tools/solids.py`. Each frame is then, through `npu_draw`,

```
RUN     0
```

with `SCREEN` in front when the window has been opened, moved or uncovered
(its content is then white), and `LOAD`s of the speeds or of register 20 when
they change. Two bytes go to the WiC64, and the changed bytes come back
straight into the screen. In the emulator that is 27 frames a second for the
soccer ball (60 corners, 90 edges), and one a frame (50) for the cube.
