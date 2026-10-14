; =====================================================================
; dialog.asm - alerts, modal dialogs, push buttons, word-wrapped text
; =====================================================================



; ---------------------------------------------------------------------
; Alerts.  A/Y = message ('|' starts a new line)
; ---------------------------------------------------------------------
alert_stop:
        ldx #<icon_stop
        stx dlg_icon
        ldx #>icon_stop
        stx dlg_icon+1
        jmp alert_ok
alert_note:
        ldx #<icon_note
        stx dlg_icon
        ldx #>icon_note
        stx dlg_icon+1
alert_ok:
        sta dlg_msg
        sty dlg_msg+1
        lda #1
        sta dlg_nbtn
        lda #<str_ok
        sta dlg_btn
        lda #>str_ok
        sta dlg_btn+1
        jsr beep
        jmp alert_run

; alert_ask: caution icon, OK / Cancel.  A/Y = message, X/... button 0
; label in dlg_btn.  Returns A = 0 for the default button, 1 = Cancel.
alert_ask:
        sta dlg_msg
        sty dlg_msg+1
        lda #<icon_caution
        sta dlg_icon
        lda #>icon_caution
        sta dlg_icon+1
        lda #2
        sta dlg_nbtn
        lda #<str_cancel
        sta dlg_btn+2
        lda #>str_cancel
        sta dlg_btn+3
        jsr beep

!zone alert_run
alert_run:
        lda #DLG_ALERT
        sta dlg_kind
        lda #<44
        ldx #58
        ldy #<275
        jsr dlg_open
        bcc +
        rts
+       jsr dialog_loop
        jmp dlg_close

; open a dialog window: A = x1 (low, x < 256), X = y1, Y = x2 low (x2 < 512,
; high byte from dlg_x2h), height from dlg_h.  Carry set if no window.
!zone dlg_open
dlg_open:
        sta t4
        stx t5
        sty t6
        jsr win_alloc
        bcc +
        rts
+       stx dlg_win
        lda t4
        sta w_x1l,x
        lda #0
        sta w_x1h,x
        lda t5
        sta w_y1,x
        clc
        adc dlg_h
        sta w_y2,x
        lda t6
        sta w_x2l,x
        lda dlg_x2h
        sta w_x2h,x
        lda #WF_DIALOG
        sta w_flags,x
        lda #CL_DIALOG
        sta w_class,x
        lda #0
        sta w_titl,x
        sta w_tith,x
        lda #0
        sta zr_on
        jsr win_open
        clc
        rts

dlg_close:
        lda #1
        sta dlg_x2h
        lda #80
        sta dlg_h
        ldx dlg_win
        lda #0
        sta zr_on
        jsr win_close
        lda dlg_result
        rts

; button rect for button X of the dialog (uses wc_* of dlg_win)
!zone dlg_btn_rect
dlg_btn_rect:
        stx t3
        ldx dlg_win
        jsr win_get_content
        ; x2 = wc_x2 - 12 - 64*i
        sec
        lda wc_x2
        sbc #12
        sta rx2
        lda wc_x2+1
        sbc #0
        sta rx2+1
        ldx t3
        beq +
        sec
        lda rx2
        sbc #64
        sta rx2
        bcs +
        dec rx2+1
+       sec
        lda rx2
        sbc #52
        sta rx1
        lda rx2+1
        sbc #0
        sta rx1+1
        lda wc_y2
        sec
        sbc #7
        sta ry2
        sec
        sbc #13
        sta ry1
        rts

; modal loop: returns dlg_result
!zone dialog_loop
dialog_loop:
        jsr wait_release
.loop:  jsr get_key
        beq .mouse
        cmp #K_RETURN
        beq .default
        cmp #K_ESC
        bne .mouse
        lda dlg_nbtn
        cmp #2
        bcc .mouse
        lda #1
        sta dlg_result
        ldx #1
        jmp .flash
.default:
        lda #0
        sta dlg_result
        ldx #0
.flash: jsr dlg_btn_rect
        lda #1
        jsr rect_inset
        jsr clip_push
        jsr clip_screen
        jsr invert_rect
        lda #8
        jsr wait_frames
        jsr invert_rect
        jmp clip_pop
.mouse: jsr new_press
        bcc .loop
        ldx #0
-       stx u6
        jsr dlg_btn_rect
        jsr mouse_in_rect
        bcc .hit
        ldx u6
        inx
        cpx dlg_nbtn
        bne -
        jsr beep
        jsr wait_release
        jmp .loop
.hit:   jsr track_box
        bcs .loop
        lda u6
        sta dlg_result
        rts

; M_DRAW for dialogs
!zone dialog_draw
dialog_draw:
        lda dlg_kind
        cmp #DLG_CUSTOM
        bne +
        lda dlg_custom
        sta jvec
        lda dlg_custom+1
        sta jvec+1
        jmp (jvec)
+       cmp #DLG_SHUTDOWN
        bne +
        jmp shutdown_draw
+       ; icon
        clc
        lda wc_x1
        adc #10
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #8
        sta ty
        lda #0
        sta ty+1
        sta iflags
        lda dlg_icon
        sta iptr
        lda dlg_icon+1
        sta iptr+1
        jsr draw_icon
        ; message
        lda dlg_msg
        sta q3
        lda dlg_msg+1
        sta q3+1
        clc
        lda wc_x1
        adc #42
        sta wr_x
        lda wc_x1+1
        adc #0
        sta wr_x+1
        lda wc_y1
        clc
        adc #8
        sta wr_y
        lda #170
        sta wr_w
        lda #11
        sta wr_lh
        lda #0
        sta font
        jsr wrap_draw
        ; buttons
        ldx #0
-       stx u6
        jsr draw_button
        ldx u6
        inx
        cpx dlg_nbtn
        bne -
        ; default button ring
        ldx #0
        jsr dlg_btn_rect
        lda #3
        jsr rect_outset
        jsr frame_round
        lda #1
        jsr rect_inset
        jmp frame_round

; draw_button: button X of the dialog
draw_button:
        txa
        asl
        tay
        lda dlg_btn,y
        sta tstr
        lda dlg_btn+1,y
        sta tstr+1
        jsr dlg_btn_rect
; draw a push button in rx..ry with label tstr
push_button:
        jsr fill_white
        jsr frame_round
        lda #0
        sta font
        jsr text_width
        ; centre the label
        clc
        lda rx1
        adc rx2
        sta tx
        lda rx1+1
        adc rx2+1
        sta tx+1
        sec
        lda tx
        sbc twidth
        sta tx
        lda tx+1
        sbc twidth+1
        lsr
        sta tx+1
        lda tx
        ror
        sta tx
        inc tx
        bne +
        inc tx+1
+       lda ry1
        clc
        adc #3
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jmp draw_text

; ---------------------------------------------------------------------
; Word wrapped text: q3 = text, wr_x/wr_y = top-left, wr_w = width,
; wr_lh = line height, font.  '|' and RETURN break lines.
; Leaves wr_cx/wr_cy = position just after the last character, and q3
; at the start of the last line.
; (wr_x .. wr_draw are in public.asm)
; ---------------------------------------------------------------------
wr_pos: !byte 0
wr_end: !byte 0
wr_sp:  !byte 0
wr_wid: !byte 0
wr_spw: !byte 0
wr_skip: !byte 0
wr_line: !fill 64

!zone wrap_draw
wrap_draw:
        jsr font_setup
        lda #0
        sta wr_pos
.line:  ; scan one line
        ldy wr_pos
        lda #$ff
        sta wr_sp
        lda #0
        sta wr_wid
        lda #1
        sta wr_skip
.scan:  lda (q3),y
        beq .brk
        cmp #'|'
        beq .brk
        cmp #K_RETURN
        beq .brk
        jsr char_width
        clc
        adc wr_wid
        bcs .full
        cmp wr_w
        beq +
        bcs .full
+       sta t6
        lda (q3),y
        cmp #' '
        bne +
        sty wr_sp
        lda wr_wid
        sta wr_spw
+       lda t6
        sta wr_wid
        iny
        bne .scan
.full:  ldx wr_sp               ; break at the last space if there was one
        cpx #$ff
        bne .atsp
        lda #0                  ; no space: break inside the word
        sta wr_skip
        cpy wr_pos
        bne .brk
        iny                     ; at least one character per line
        bne .brk
.atsp:  txa
        tay
        lda wr_spw
        sta wr_wid
.brk:   sty wr_end
        ; copy wr_pos..wr_end-1 to wr_line and draw it
        ldx #0
        ldy wr_pos
-       cpy wr_end
        beq +
        cpx #63
        beq +
        lda (q3),y
        sta wr_line,x
        inx
        iny
        bne -
+       lda #0
        sta wr_line,x
        lda wr_draw
        beq +
        lda wr_x
        sta tx
        lda wr_x+1
        sta tx+1
        lda wr_y
        sta ty
        lda #0
        sta ty+1
        lda #<wr_line
        ldy #>wr_line
        jsr draw_str
        jsr font_setup
+       ; caret position = end of this line
        clc
        lda wr_x
        adc wr_wid
        sta wr_cx
        lda wr_x+1
        adc #0
        sta wr_cx+1
        lda wr_y
        sta wr_cy
        ; next line
        ldy wr_end
        lda (q3),y
        beq .done
        lda wr_skip
        beq +
        iny                     ; skip the break character
+       tya                     ; q3 moves on to the next line, so texts
        clc                     ; can be longer than 256 characters
        adc q3
        sta q3
        bcc +
        inc q3+1
+       lda #0
        sta wr_pos
        lda wr_y
        clc
        adc wr_lh
        sta wr_y
        bcs .done
        ; a text ending in a line break puts the caret on the next line
        ldy #0
        lda (q3),y
        beq +
        jmp .line
+
        lda wr_x
        sta wr_cx
        lda wr_x+1
        sta wr_cx+1
        lda wr_y
        sta wr_cy
.done:  rts



; the Clipboard (the System's scrap, shared by everyone)
