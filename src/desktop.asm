; =====================================================================
; desktop.asm - desktop pattern, menu bar, screen corners
; =====================================================================

desk_pat: !byte $aa,$55,$aa,$55,$aa,$55,$aa,$55

; fill the current clip rectangle with the desktop pattern
!zone paint_desktop
paint_desktop:
        ldx #5
-       lda clx1,x
        sta rx1,x
        dex
        bpl -
        lda #<desk_pat
        ldy #>desk_pat
        jsr set_pat_copy
        jmp fill_rect

; draw_menubar: white bar, line, titles, corners
!zone draw_menubar
draw_menubar:
        jsr clip_push
        jsr clip_screen
        +rect 0, 0, 319, MENUBAR_LINE-1
        jsr fill_white
        +rect 0, MENUBAR_LINE, 319, MENUBAR_LINE
        jsr fill_black
        jsr menu_draw_titles
        jsr draw_corners
        jmp clip_pop

; the rounded corners of the Mac screen (inside the current clip)
corner_tab:     ; x1, x2, y   (x as 16 bit)
        !word 0, 2
        !byte 0
        !word 0, 1
        !byte 1
        !word 0, 0
        !byte 2
        !word 317, 319
        !byte 0
        !word 318, 319
        !byte 1
        !word 319, 319
        !byte 2
        !word 0, 2
        !byte 199
        !word 0, 1
        !byte 198
        !word 0, 0
        !byte 197
        !word 317, 319
        !byte 199
        !word 318, 319
        !byte 198
        !word 319, 319
        !byte 197
!zone draw_corners
draw_corners:
        jsr set_black
        ldx #0
-       lda corner_tab,x
        sta rx1
        lda corner_tab+1,x
        sta rx1+1
        lda corner_tab+2,x
        sta rx2
        lda corner_tab+3,x
        sta rx2+1
        lda corner_tab+4,x
        sta ry1
        sta ry2
        stx u7
        jsr fill_rect
        lda u7
        clc
        adc #5
        tax
        cpx #12*5
        bne -
        rts

; redraw everything (after boot / restart)
!zone redraw_all
redraw_all:
        jsr draw_menubar
        +rect 0, DESK_Y1, 319, 199
        jmp redraw_region
