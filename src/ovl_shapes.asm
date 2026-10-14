; =====================================================================
; Shapes.ovl - System overlay 2, in block 2 at $5000: QuickDraw's
; lines, ovals, circles and round rects.  See src/overlay.asm.
; @overlay 2 "System Folder/Shapes.ovl" $5000
; =====================================================================
!cpu 6510
!to "build/shapes.ovl", cbm
!source "build/ovl2_sys.asm"    ; the System core, less this overlay's own names
!source "src/macros.asm"

* = $5000
; @entries (the System's stubs call them by number: add new ones at the end)
        jmp plot
        jmp move_to
        jmp line_to
        jmp draw_line
        jmp frame_oval
        jmp fill_oval
        jmp frame_circle
        jmp fill_circle
        jmp frame_rrect
        jmp fill_rrect
; @end

!source "src/qd_shapes.asm"

!if * > $6000 {
        !error "Shapes.ovl does not fit its region ($5000-$5fff)"
}
