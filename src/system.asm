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
;   0-1  $0000-$3fff  zero page, stack, BASIC's zero page copy ($0400),
;                     the Clipboard ($0500), the file service's buffer
;                     ($0600), then the System's core from $0801: jump
;                     table, public data, code
;   2    $4000-$5fff  the System's overlays, loaded from the share when
;                     needed (src/overlay.asm): Interface at $4000,
;                     Shapes at $5000
;   3    $6000-$7fff  the application's core block (APP_BASE)
;   4    $8000-$9fff  the application's page block
;   5    $a000-$bfff  QuickDraw buffers: strips ($a000), shift tables ($b000)
;   6    $c000-$cfff  colour matrix, sprite pointers, cursor sprites ($c400),
;                     QuickDraw's oval table ($c700), menu save-under ($c800)
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
        lda #$34                ; font glyphs under the I/O chips
        sta $01
        lda #<font_image
        sta p0
        lda #>font_image
        sta p0+1
        lda #<FONT_RAM
        sta p1
        lda #>FONT_RAM
        sta p1+1
        ldx #>(font_image_end-font_image+255)
        ldy #0
-       lda (p0),y
        sta (p1),y
        iny
        bne -
        inc p0+1
        inc p1+1
        dex
        bne -
        lda #$35
        sta $01
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
!source "src/net.asm"
!source "src/overlay.asm"
!source "build/ovl_stubs.asm"
!source "src/boot.asm"
!source "src/fp.asm"
!source "src/sysstrings.asm"

!source "build/fonts.asm"
!source "build/icons_sys.asm"


zp_basic = $0400                ; (the C64's unused text screen)

system_end:
APP_BASE  = $6000               ; block 3: applications are loaded here
PAGE_BASE = $8000               ; block 4: an application's page block
!if system_end > OVL_BASE {
        !error "the System's core overlaps block 2 (its overlays)"
}

; Copied into place by start: they are loaded after the end of SYSTEM,
; where applications are later loaded over them.
; Pointer shapes, to $c400.
sprite_data:
!source "build/sprites.asm"

; Font glyphs, to the RAM under the I/O chips (draw_text switches the
; I/O chips out while it reads them).
FONT_RAM = $d000
font_image:
!pseudopc FONT_RAM {
!source "build/fontdata.asm"
font_ram_end:
}
font_image_end:
!if font_ram_end > $e000 {
        !error "font glyphs do not fit under the I/O chips"
}
