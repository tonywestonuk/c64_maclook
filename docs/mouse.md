# Mouse: the position block, the driver, and Frodo's feedback

## The position block (`$FB`–`$FE`)

The mouse driver keeps the pointer's position in four zero-page bytes that
any program can read. `$FB`–`$FE` are left free by BASIC and the KERNAL, so
the block also works alongside BASIC.

| Address | Contents |
|---|---|
| `$FB` | X, high 8 bits |
| `$FC` | Y, high 8 bits |
| `$FD` | bit 7 changed · bit 6 right button · bit 5 left button · bit 4 spare · bits 3–2 Y low 2 bits · bits 1–0 X low 2 bits |
| `$FE` | tracking speed, 0–3 (written by programs, read by the driver) |

- X and Y are **10 bits each, 0–1023, always spanning the whole screen**,
  whatever the video mode. The high bytes alone are a 0–255 position that
  needs only 8-bit maths; the low bits in `$FD` add precision for programs
  that want it.
- **Buttons** are 1 while held.
- **Changed** is set by the driver whenever the position or a button
  differs from the previous update. A program clears it to notice the next
  change. The interrupt rewrites `$FD`, so clear it with interrupts off:

  ```asm
          php
          sei
          lda $fd
          and #$7f
          sta $fd
          plp
  ```

### Converting to screen pixels

| Wanted | From the full 10 bits | From the high byte only |
|---|---|---|
| 320-wide X (hires) | X × 5 ÷ 16 → 0–319 | H × 5 ÷ 4 → 0–318 |
| 160-wide X (multicolour) | X × 5 ÷ 32 → 0–159 | H × 5 ÷ 8 → 0–159 |
| 200-high Y | Y × 25 ÷ 128 → 0–199 | H × 25 ÷ 32 → 0–199 |

All of these are shifts and adds on a 6502.

## Tracking speed

The driver adds each 1351 mouse count times a step size. A unit in Y is 1.6
times smaller than a unit in X (1024 units cover 320 pixels across but only
200 down), so each speed has a pair of steps to keep the feel the same in
both directions:

| `$FE` | X units per count | Y units per count | About |
|---|---|---|---|
| 0 | 2 | 3 | ⅔ pixel |
| 1 | 3 | 5 | 1 pixel (default) |
| 2 | 5 | 8 | 1½ pixels |
| 3 | 6 | 10 | 2 pixels |

Fractions of a pixel build up in the low bits, so slow speeds stay smooth.

## The driver (`src/sys.asm`, `read_mouse`)

It runs in the raster interrupt, once per frame. It's a standard driver for
a Commodore 1351 in control port 1, so it works the same on a real C64, in
VICE and in Frodo:

1. Read the 1351's counters from the SID (`$D419`, `$D41A`), turn the change
   since the last read into a signed movement (±31), multiply by the step
   size, and add it to X (subtract for Y: the 1351 counts upwards).
2. Add joystick movement from port 2, if any.
3. Clamp X and Y to 0–1023, and read the buttons (left = fire line, right =
   up line, or fire on a port 2 joystick).
4. Write the block, setting "changed" if anything differs, and convert to
   pixels for the OS (`mouse_x`, `mouse_y`).

The driver's own copy of the position is private; the block is written
from it each frame, so a program scribbling on the block can't move the
pointer.

## Frodo's feedback (`MouseSync=true`)

A 1351 only reports movement, so on its own the C64 pointer can drift away
from the host pointer, for example when interrupts are off for a while. With
`MouseSync=true`, Frodo closes the loop instead of guessing:

1. Convert the host pointer to the same 0–1023 scale, aimed at the middle of
   the C64 pixel it's over.
2. After each time the C64 has read the paddle registers, read the block,
   work out the gap, divide by the current step size (from `$FE`), and send
   that as the next 1351 movement, at most ±31 counts. Until the C64 reads
   again, the movement waits; nothing piles up.
3. Only chase the host pointer after it has moved, so a joystick in port 2
   still works while the mouse is still.

At speeds 0 and 1 a step is smaller than a pixel, so the C64 pointer lands
on exactly the same pixel as the host pointer. At speeds 2 and 3 a single
count moves more than a pixel, so it can be one pixel out.

Without `MouseSync`, Frodo behaves like a real 1351: it reports movement
only, at most 31 counts from the last value the C64 read.
