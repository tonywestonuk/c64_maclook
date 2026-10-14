; =====================================================================
; SHEET - a small spreadsheet for the Commodore 64 desktop.
;
; An application like the Finder and Brickles: the System loads it from
; drive 8 to APP_BASE.  Numbers use the BASIC ROM's floating point.
; =====================================================================
!cpu 6510
!to "build/sheet.prg", cbm
!source "build/syslink.asm"
!source "src/macros.asm"

* = APP_BASE
        jmp ss_init             ; entry points, see events.asm
        jmp ss_action
        jmp ss_update_menus
        jmp nop_method          ; nothing on the desktop
        jmp nop_method
        jmp nop_method
        jmp nop_method          ; quit
        !word ss_classes
        !word ss_menus
        !word str_ss_about
        !text "APP!"

!source "src/sheet.asm"

ss_code_end:
SS_BSS = (ss_code_end + $ff) & $ff00
; storage after the code (not part of the file)
ss_type  = SS_BSS
ss_flags = ss_type + NCELLS
ss_dirty = ss_flags + NCELLS
ss_tlo   = ss_dirty + NCELLS
ss_thi   = ss_tlo + NCELLS
ss_vlo   = ss_thi + NCELLS
ss_vhi   = ss_vlo + NCELLS
ss_dlo   = ss_vhi + NCELLS
ss_dhi   = ss_dlo + NCELLS
ss_val   = ss_dhi + NCELLS
ss_text  = ss_val + NCELLS*5
ss_disp  = ss_text + NCELLS*16
SS_BSS_END = ss_disp + NCELLS*12
!if SS_BSS_END > $a000 {
        !error "SHEET too large"
}
