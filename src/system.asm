; =====================================================================
; SYSTEM - the toolbox of the Commodore 64 desktop (a System 4 /
; Finder 5 look-alike): hardware, events, QuickDraw-style graphics,
; menus, windows, dialogs, and the loader that brings applications in
; from the 1541.  It boots, then loads the Finder.
;
; Applications use it only through the jump table at $0810 and the
; public data after it (see src/jumptab.asm, src/public.asm and the
; generated build/sysapi.asm), so they need not be rebuilt for a new
; System.
;
; Memory map: the 64K are eight 8K blocks
;   0-2  $0000-$5fff  zero page, stack, KERNAL variables, BASIC's zero
;                     page copy ($0400), the Clipboard ($0500), then
;                     SYSTEM from $0801: jump table, public data, code
;   3    $6000-$7fff  the application's core block (APP_BASE)
;   4    $8000-$9fff  the application's page block
;   5    $a000-$bfff  QuickDraw buffers: strips ($a000), shift tables ($b000)
;   6    $c000-$cfff  colour matrix, sprite pointers, cursor sprites ($c400),
;                     menu save-under ($c800)
;        $d000-$dfff  I/O
;   7    $e000-$ff3f  hires bitmap
; =====================================================================
!cpu 6510
!to "build/system.prg", cbm
!source "src/zp.asm"
!source "src/macros.asm"

* = $0801
        !byte $0b,$08,$0a,$00,$9e       ; 10 SYS 2061
        !text "2061"
        !byte 0,0,0
        jmp start                       ; $080d

!source "src/jumptab.asm"               ; $0810
!source "src/public.asm"

!zone start
start:  sei
        cld
        ldx #$ff
        txs
        ldx #2                  ; keep BASIC's zero page for the FP ROM
-       lda $00,x
        sta zp_basic,x
        inx
        bne -
        lda #$35                ; RAM + I/O, no ROMs
        sta $01
        ldx #0                  ; cursor sprites to $c400
-       lda sprite_data,x
        sta SPRITES,x
        lda sprite_data+$100,x
        sta SPRITES+$100,x
        inx
        bne -
        jsr hw_init
        jsr init_gfx
        lda #0
        sta mouse_x
        sta mouse_x+1
        sta mouse_y
        cli
        jmp reboot              ; boot screens, load the Finder, event loop

!source "src/sys.asm"
!source "src/gfx.asm"
!source "src/util.asm"
!source "src/desktop.asm"
!source "src/menu.asm"
!source "src/wm.asm"
!source "src/events.asm"
!source "src/loader.asm"
!source "src/boot.asm"
!source "src/dialog.asm"
!source "src/fp.asm"
!source "src/sysstrings.asm"

!source "build/fonts.asm"
!source "build/icons_sys.asm"


zp_basic = $0400                ; (the C64's unused text screen)

system_end:
APP_BASE  = $6000               ; block 3: applications are loaded here
PAGE_BASE = $8000               ; block 4: an application's page block
!if system_end > APP_BASE {
        !error "SYSTEM overlaps APP_BASE"
}

; Pointer shapes, copied to $c400 by start.  They are loaded after the
; end of SYSTEM, where the Finder is then loaded over them.
sprite_data:
!source "build/sprites.asm"
