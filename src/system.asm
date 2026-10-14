; =====================================================================
; SYSTEM - the toolbox of the Commodore 64 desktop (a System 4 /
; Finder 5 look-alike): hardware, events, QuickDraw-style graphics,
; menus, windows, dialogs, desk accessories, and the loader that brings
; the Finder in from the 1541.
;
; Memory map
;   $0002-$008f  zero page (ours; $90-$ff stay the KERNAL's for disk I/O)
;   $0400-$04ff  BASIC's zero page, saved for the floating point ROM
;   $0500-$05ff  the Clipboard
;   $0801-       SYSTEM (this file)
;   FINDER_BASE  the Finder, loaded from disk (up to $9fff)
;   $a000-$afff  strip buffers (text / icon blitting)
;   $b000-$bfff  shift tables
;   $c000-$c3ff  colour matrix + sprite pointers (VIC bank 3)
;   $c400-$c7ff  cursor sprites
;   $c800-$cfff  save-under buffer for menus
;   $d000-$dfff  I/O
;   $e000-$ff3f  hires bitmap
; =====================================================================
!cpu 6510
!to "build/system.prg", cbm
!source "src/zp.asm"
!source "src/macros.asm"

* = $0801
        !byte $0b,$08,$0a,$00,$9e       ; 10 SYS 2061
        !text "2061"
        !byte 0,0,0

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
!source "src/da_calc.asm"
!source "src/da_puzzle.asm"
!source "src/da_clock.asm"
!source "src/da_notepad.asm"
!source "src/da_cpanel.asm"
!source "src/sysstrings.asm"

!source "build/fonts.asm"
!source "build/icons_sys.asm"

sprite_data:
!source "build/sprites.asm"


zp_basic = $0400                ; (the C64's unused text screen)

system_end:
FINDER_BASE = $6800             ; where applications are loaded
!if system_end > FINDER_BASE {
        !error "SYSTEM overlaps FINDER_BASE"
}
