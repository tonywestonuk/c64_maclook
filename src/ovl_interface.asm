; =====================================================================
; Interface.ovl - System overlay 1, in block 2 at $4000: alerts and
; dialogs, tracking the close and zoom boxes, dragging, growing and
; zooming windows, and the start-up and shut-down screens.
; See src/overlay.asm.
; @overlay 1 "System Folder/Interface.ovl" $4000
; =====================================================================
!cpu 6510
!to "build/interface.ovl", cbm
!source "build/ovl1_sys.asm"    ; the System core, less this overlay's own names
!source "src/macros.asm"

* = $4000
; @entries (the System's stubs call them by number: add new ones at the end)
        jmp alert_note
        jmp alert_stop
        jmp dlg_open
        jmp dlg_close
        jmp wrap_draw
        jmp dialog_draw
        jmp track_box
        jmp win_drag
        jmp win_grow
        jmp win_zoom
        jmp zoom_to_rect
        jmp boot_screen
        jmp shut_down
        jmp zoom_from_rect
; @end

!source "src/dialog.asm"
!source "src/wm_gestures.asm"
!source "src/startup.asm"
!source "build/icons_ovl.asm"

!if * > app_spare {
        !error "Interface.ovl must end below app_spare: applications use the rest"
}
