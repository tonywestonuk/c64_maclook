; =====================================================================
; da_notepad.asm - Note Pad: 8 pages of word-wrapped text
; =====================================================================

NP_PAGES = 8
NP_LEN   = 200          ; bytes per page, including the terminator

np_win:   !byte $ff
np_page:  !byte 0
np_caret: !byte 0         ; caret currently drawn
np_timer: !byte 0
np_blink: !byte 30        ; frames per blink (Control Panel)
np_cx:    !word 0         ; caret position
np_cy:    !byte 0
np_pnum:  !fill 4

np_text:
        !text "This is the Note Pad.  Type here, and click the folded "
        !text "corner to turn the page.", 0
        !fill NP_LEN - (* - np_text)
        !fill NP_LEN*(NP_PAGES-1)

!zone np_open
np_open:
        lda #CL_NOTEPAD
        jsr da_find
        bcs +
        jmp win_select
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx np_win
        +winrect 60, 50, 240, 162
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_NOTEPAD
        sta w_class,x
        lda #<str_o_notepad
        sta w_titl,x
        lda #>str_o_notepad
        sta w_tith,x
        lda #0
        sta np_caret
        ldx np_win
        jmp win_open

np_close:
        lda #$ff
        sta np_win
        lda #0
        sta np_caret
        rts

; q3 = current page
np_page_ptr:
        lda np_page
        ldx #NP_LEN
        jsr mul8
        clc
        adc #<np_text
        sta q3
        txa
        adc #>np_text
        sta q3+1
        rts

!zone np_draw
np_draw:
        lda #0
        sta np_caret
        jsr np_page_ptr
        clc
        lda wc_x1
        adc #5
        sta wr_x
        lda wc_x1+1
        adc #0
        sta wr_x+1
        lda wc_y1
        clc
        adc #3
        sta wr_y
        sec
        lda wc_x2
        sbc wc_x1
        sec
        sbc #10
        sta wr_w
        lda #9
        sta wr_lh
        lda #1
        sta font
        lda #B_OR
        sta tmode
        jsr wrap_draw
        lda wr_cx
        sta np_cx
        lda wr_cx+1
        sta np_cx+1
        lda wr_cy
        sta np_cy
        ; folded corner at the bottom left: a triangle with a diagonal edge
        lda #0
        sta u5
-       clc
        lda wc_x1
        adc u5
        sta rx1
        sta rx2
        lda wc_x1+1
        adc #0
        sta rx1+1
        sta rx2+1
        lda wc_y2
        sec
        sbc #12
        clc
        adc u5
        sta ry1
        lda wc_y2
        sta ry2
        jsr fill_white
        lda ry1
        sta ry2
        jsr fill_black
        inc u5
        lda u5
        cmp #13
        bne -
        ; page number
        lda np_page
        clc
        adc #1
        ldx #0
        jsr utoa
        clc
        lda wc_x1
        adc #15
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y2
        sec
        sbc #9
        sta ty
        lda #0
        sta ty+1
        lda #1
        sta font
        lda #<numbuf
        ldy #>numbuf
        jsr draw_str
        ; line along the top of the corner area
        rts

; blink the caret while the Note Pad is in front
!zone np_idle
np_idle:
        cpx zlist
        bne .out
        inc np_timer
        lda np_timer
        cmp np_blink
        bcc .out
        lda #0
        sta np_timer
        jsr np_toggle_caret
.out:   rts

np_toggle_caret:
        lda np_caret
        eor #1
        sta np_caret
        jsr clip_push
        ldx np_win
        jsr win_get_content
        jsr clip_screen
        jsr clip_rect
        lda np_cx
        sta rx1
        sta rx2
        lda np_cx+1
        sta rx1+1
        sta rx2+1
        lda np_cy
        sta ry1
        clc
        adc #7
        sta ry2
        jsr invert_rect
        jmp clip_pop

np_hide_caret:
        lda np_caret
        beq +
        jsr np_toggle_caret
+       lda #0
        sta np_timer
        rts

; redraw the text area of the front Note Pad
np_redraw:
        jsr np_hide_caret
        jsr clip_push
        jsr clip_screen
        ldx np_win
        jsr win_get_content
        jsr clip_rect
        jsr fill_white
        ldx np_win
        lda #M_DRAW
        jsr win_call
        jmp clip_pop

!zone np_key
np_key:
        jsr np_page_ptr
        ldy #0                  ; end of text
-       lda (q3),y
        beq +
        iny
        bne -
+       lda key_char
        cmp #K_DEL
        bne .ins
        cpy #0
        bne .bf238
        jmp .out
.bf238:
        dey
        lda #0
        sta (q3),y
        jmp np_redraw
.ins:   cmp #K_RETURN
        beq +
        cmp #32
        bcs .bf246
        jmp .out
.bf246:
        cmp #127
        bcc .bf248
        jmp .out
.bf248:
+       cpy #NP_LEN-1
        bcc .bf250
        jmp .full
.bf250:
        sta (q3),y
        iny
        lda #0
        sta (q3),y
        ; fast path: printable character that fits on the line
        lda key_char
        cmp #32
        bcs .bf258
        jmp .slow
.bf258:
        jsr np_hide_caret
        lda #1
        sta font
        jsr font_setup
        lda key_char
        jsr char_width
        clc
        adc np_cx
        sta t0
        lda np_cx+1
        adc #0
        sta t1
        ldx np_win
        jsr win_get_content
        sec
        lda wc_x2
        sbc #4
        sta t2
        lda wc_x2+1
        sbc #0
        sta t3
        lda t2
        cmp t0
        lda t3
        sbc t1
        bcc .slow
        lda t0                  ; new caret x (t0/t1 get clobbered by drawing)
        sta np_nx
        lda t1
        sta np_nx+1
        lda key_char
        cmp #' '                ; a space might start a new word wrap later
        beq .slow2
        sta np_ch
        lda np_cx
        sta tx
        lda np_cx+1
        sta tx+1
        lda np_cy
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jsr clip_push
        jsr clip_screen
        lda #<np_ch
        ldy #>np_ch
        jsr draw_str
        jsr clip_pop
.slow2: lda np_nx
        sta np_cx
        lda np_nx+1
        sta np_cx+1
        rts
.slow:  jmp np_redraw
.full:  jmp beep
.out:   rts
np_ch:  !byte 0, 0
np_nx:  !word 0

; click: the folded corner turns pages
!zone np_click
np_click:
        lda mouse_y
        sec
        sbc wc_y2
        clc
        adc #13
        bcc .out                ; above the corner
        lda mouse_x
        sec
        sbc wc_x1
        cmp #13
        bcs .out
        ; lower triangle = next page, upper = previous
        sta t0
        lda mouse_y
        sec
        sbc wc_y2
        clc
        adc #12                 ; 0..12 down the corner
        cmp t0
        bcc .prev
        lda np_page
        clc
        adc #1
        and #NP_PAGES-1
        jmp .set
.prev:  lda np_page
        sec
        sbc #1
        and #NP_PAGES-1
.set:   sta np_page
        jsr np_redraw
        jsr wait_release
.out:   rts

; Edit menu: whole-page cut / copy / paste / clear
!zone np_edit
np_edit:
        jsr np_page_ptr
        lda key_char
        cmp #EDIT_COPY
        beq .copy
        cmp #EDIT_CUT
        beq .cut
        cmp #EDIT_CLEAR
        beq .clear
        cmp #EDIT_PASTE
        beq .paste
        rts
.cut:   jsr .copy
.clear: ldy #0
        tya
        sta (q3),y
        jmp np_redraw
.copy:  ldy #0
-       lda (q3),y
        sta clip_buf,y
        beq +
        iny
        bne -
+       sty clip_len
        rts
.paste: ldy #0                  ; append the clipboard
-       lda (q3),y
        beq +
        iny
        bne -
+       ldx #0
-       cpx clip_len
        beq +
        cpy #NP_LEN-1
        bcs +
        lda clip_buf,x
        sta (q3),y
        inx
        iny
        bne -
+       lda #0
        sta (q3),y
        jmp np_redraw
