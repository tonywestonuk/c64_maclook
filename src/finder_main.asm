; =====================================================================
; FINDER - the desktop application, loaded by the System from drive 8.
; It uses the System only through its API (build/sysapi.asm).
; =====================================================================
!cpu 6510
!to "build/finder.prg", cbm
!source "build/sysapi.asm"
!source "src/macros.asm"

* = APP_BASE
        jmp app_init            ; entry points, see events.asm
        jmp app_action
        jmp update_menus
        jmp draw_desk_icons
        jmp app_desk_click
        jmp rename_key
        jmp app_quit
        !word app_classes
        !word app_menus
        !word str_i_about
        !text "APP!"

app_init:
        jmp finder_init

app_quit:
        rts

app_menus:
        !word str_m_file, str_m_edit, str_m_view, str_m_special
        !word items_file, items_edit, items_view, items_special

; mouse down on the desktop: an icon, or deselect
app_desk_click:
        lda #DESKTOP
        jsr obj_at_mouse
        cpx #NOOBJ
        beq +
        jmp icon_click
+       lda #NOOBJ
        sta last_obj
        jmp deselect

!source "src/finder.asm"
!source "src/finder_win.asm"
!source "src/finder_str.asm"
!source "build/icons_finder.asm"

finder_end:
!if finder_end > $a000 {
        !error "FINDER too large"
}
