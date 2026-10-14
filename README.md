# c64_maclook

A Macintosh System 4 / Finder 5 style desktop for the **Commodore 64**, running
in 320×200 two-colour hires mode on a real 1 MHz 6510 with 64K of RAM.
Everything is written from scratch in 6502 assembly.

It has a menu bar with pull-down menus, overlapping windows, a Finder with icons,
and real applications loaded from a 1541 disk that replace the Finder while
they run, the way the Mac worked before MultiFinder. Like the Mac's Toolbox,
the System is used only through a published API: a jump table at a fixed
address ([docs/api.md](docs/api.md)), so applications don't need rebuilding
when the System changes. It has since been given a Commodore theme: a C= logo
in place of the Apple, a happy C64 at start-up, a 1541 floppy icon, and disk
space counted in blocks.

![Desktop](docs/screenshots/desktop.png)

| | |
|---|---|
| ![Menus](docs/screenshots/menu.png) | ![Scroll bars](docs/screenshots/scrolling.png) |
| ![Brickles](docs/screenshots/brickles.png) | ![Spreadsheet](docs/screenshots/spreadsheet.png) |

## What's in it

- **SYSTEM** (the boot file, 18K): a QuickDraw-style graphics library
  (patterns, clipping, proportional Chicago and Geneva style fonts, masked
  icons), window manager, menu manager, alerts and dialogs, event handling
  with a 1351 mouse or joystick, and a loader that brings applications in
  from drive 8. It boots, then loads the Finder.
- **Desk accessories** (Calculator, Note Pad, Puzzle, Alarm Clock, Key Caps,
  Control Panel) are out of the System for now. Their source is in
  `src/da_*.asm`; they'll come back as separate files loaded from disk.
- **FINDER**: disk and folder windows that scroll both ways, dragging icons
  between folders and to the Trash, Get Info, New Folder, Duplicate, Put Back,
  Clean Up, renaming icons by typing, zoom-rect animations, Restart and Shut
  Down.
- **BRICKLES**: a Breakout game. The ball and paddle are hardware sprites.
- **SHEET**: a small spreadsheet with formulas (`+ - * / ( )`, cell
  references, `SUM AVG MIN MAX COUNT` over ranges), automatic recalculation,
  number formats, and Cut/Copy/Paste through the shared Clipboard.

## Quick start (macOS)

```sh
brew install acme python autoconf automake pkg-config sdl2 gtk+3
brew install imagemagick      # optional: only the screenshot tests need it

cd frodo4 && ./autogen.sh && make && cd ..   # the patched emulator
./build.sh                                    # assemble everything -> desktop64.d64
./run.sh                                      # boot it
```

`run.sh` builds Frodo itself if it hasn't been built yet. A ready-made
`desktop64.d64` is included, so `./build.sh` is only needed after changing
the source.

`./run.sh` uses Frodo's fast disk mode. `./run.sh real` uses full,
cycle-exact 1541 emulation: authentic, but booting takes about a minute.

### Using it

- The C64 pointer follows your Mac's pointer; there's no need to capture the
  mouse. A joystick in port 2 also works. Programs can read the mouse from a
  small block in zero page ([docs/mouse.md](docs/mouse.md)).
- **Command key = C=**, which is Alt/Option on your keyboard (e.g. C= Q quits
  an application).
- Frodo maps keys by their position on a C64 keyboard, so some symbols are in
  unexpected places: `=` is PageDown, `*` is `]`, `:` is `;`, `+` is `-`,
  and `-` is `=`.
- Double-click **Brickles** or **Spreadsheet** in the System Disk window to
  launch them. Quit brings the Finder back.

## How it fits together

The 64K are eight 8K blocks:

```
block 0-2  $0000-$5fff  zero page, stack, KERNAL variables, BASIC's zero page
                        copy ($0400), the Clipboard ($0500), then SYSTEM from
                        $0801: jump table ($0810), public data, code
block 3    $6000-$7fff  the running application's core (FINDER, BRICKLES, SHEET)
block 4    $8000-$9fff  the application's page block
block 5    $a000-$bfff  QuickDraw's buffers: text/icon strips, shift tables
block 6    $c000-$cfff  colour matrix, pointer sprites, menu save-under
           $d000-$dfff  I/O
block 7    $e000-$ff3f  the hires bitmap
```

The C64 boots SYSTEM with `LOAD"*",8,1`. SYSTEM then loads FINDER with the
KERNAL's LOAD while showing "Welcome to Commodore 64."

Applications call the System only through its jump table, and read its
public data at fixed addresses after the table. Both are described in
[docs/api.md](docs/api.md), which `tools/mkapi.py` generates along with
`build/sysapi.asm`, the include file applications are built with. New calls
are added at the end of the table, so existing applications keep working.

An application starts with a table of entry points that SYSTEM calls (see
`src/events.asm`): init, menu action, menu update, desktop draw, desktop
click, key, quit, plus pointers to its window classes, its menus and its
"About" text.

| Source | What |
|---|---|
| `src/system.asm` | SYSTEM: memory map and entry point |
| `src/jumptab.asm`, `src/public.asm` | the API: jump table and public data |
| `src/gfx.asm` | rectangles, patterns, clipping, text and icon blitting |
| `src/wm.asm`, `menu.asm`, `dialog.asm`, `events.asm` | windows, menus, dialogs, event loop |
| `src/sys.asm` | IRQ, 1351 mouse, keyboard, pointer sprites, beep |
| `src/loader.asm`, `boot.asm` | disk loading, start-up, app switching |
| `src/fp.asm` | BASIC ROM floating point bridge |
| `src/da_*.asm` | desk accessories (not built for now) |
| `src/finder*.asm` | the Finder |
| `src/brickles*.asm`, `src/sheet*.asm` | the applications |
| `tools/fonts.py`, `tools/icons.py` | fonts, icons and cursors drawn as ASCII art |
| `tools/mkapi.py` | publishes the API: `build/sysapi.asm`, `docs/api.md` |
| `tools/d64.py` | disk image writer |

## The patched Frodo

`frodo4/` is [Frodo 4](https://github.com/cebix/frodo4) by Christian Bauer
(upstream commit `59f096d`) with two additions. They're shown as one commit
in this repo's history, and also as `patches/frodo4-mouse1351-testbench.patch`.

- **1351 mouse emulation** (`Mouse1351=true`): the host pointer drives an
  emulated Commodore 1351 on the SID's paddle registers. Stock Frodo has no
  mouse support.
- **Mouse feedback** (`MouseSync=true`): Frodo reads the C64 driver's
  position block at `$FB`–`$FE` and sends exactly the movement that puts the
  C64 pointer on the same pixel as the host pointer, so it can't drift.
  The block and the driver are described in [docs/mouse.md](docs/mouse.md).
- **Test-bench scripting** (`TestInput=script.txt` with `TestBench=true`): a
  frame-by-frame script of `mouse x y`, `down`/`up`, `keydown`/`keyup`
  (SDL key names or raw scancode numbers), `type text`, `shot file.bmp`,
  `dump file.bin` (64K RAM and CPU registers) and `quit`.

## Testing

Everything was developed headlessly with those scripts:

```sh
python3 tools/mkscript.py tests/calc.dsl tests/calc.txt   # small DSL -> script
tools/shot.sh tests/smoke.txt build/pub_ 630             # run, save screenshots
python3 tools/peek.py build/b5.bin app_loaded zcount     # inspect a RAM dump
```

`tools/fixbranches.py` rewrites 6502 branches that ACME reports as out of
range.

## Known issues

- The Finder's disk contents are a built-in table, not the real 1541
  directory, so moved, renamed or trashed icons are forgotten on Restart or
  when switching applications. Documents can't be saved yet.
- View by Name/Date/Size/Kind, Print and Erase Disk are not implemented.

## Credits

A fan-made tribute to the original Macintosh Finder by Bruce Horn and Steve
Capps. Not affiliated with Apple or Commodore. Frodo 4 is by Christian Bauer
and licensed under GPL-2.0; the C64 ROM images in `frodo4/src` are as
published in upstream Frodo. Assembled with [ACME](https://sourceforge.net/projects/acme-crossass/).

Built by Tony Weston with Claude Code.
