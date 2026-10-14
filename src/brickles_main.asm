; =====================================================================
; BRICKLES - a Breakout game for the Commodore 64 desktop.
;
; An application, like the Finder: the System loads it from drive 8 to
; APP_BASE and calls the entry points below.  Quit reloads the Finder.
; =====================================================================
!cpu 6510
!to "build/brickles.prg", cbm
!source "build/sysapi.asm"
!source "src/macros.asm"

* = APP_BASE
        jmp bk_init             ; entry points, see events.asm
        jmp bk_action
        jmp bk_update_menus
        jmp nop_method          ; nothing on the desktop
        jmp nop_method
        jmp nop_method
        jmp bk_quit
        !word bk_classes
        !word bk_menus
        !word str_bk_about
        !text "APP!"

!source "src/brickles.asm"

bk_end:
!if bk_end > $a000 {
        !error "BRICKLES too large"
}
