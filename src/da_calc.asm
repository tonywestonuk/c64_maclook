; =====================================================================
; da_calc.asm - Calculator desk accessory (BASIC ROM floating point)
; =====================================================================

CB_W = 18               ; button size
CB_H = 13

calc_acc:   !fill 5         ; accumulator (packed float)
calc_entry: !fill 16        ; number being typed
calc_disp:  !fill 20        ; what the display shows
calc_op:    !byte 0         ; pending operator (0 = none)
calc_have:  !byte 0         ; entry has digits
calc_win:   !byte $ff

; buttons: label, x, y, w, h, key
!macro cbtn .lbl, .x, .y, .w, .h, .key {
        !byte .lbl, .x, .y, .w, .h, .key
}
calc_buttons:
        +cbtn 'C', 8, 22, CB_W, CB_H, 'c'
        +cbtn 'E', 29, 22, CB_W, CB_H, 'e'
        +cbtn '=', 50, 22, CB_W, CB_H, '='
        +cbtn '*', 71, 22, CB_W, CB_H, '*'
        +cbtn '7', 8, 38, CB_W, CB_H, '7'
        +cbtn '8', 29, 38, CB_W, CB_H, '8'
        +cbtn '9', 50, 38, CB_W, CB_H, '9'
        +cbtn '/', 71, 38, CB_W, CB_H, '/'
        +cbtn '4', 8, 54, CB_W, CB_H, '4'
        +cbtn '5', 29, 54, CB_W, CB_H, '5'
        +cbtn '6', 50, 54, CB_W, CB_H, '6'
        +cbtn '-', 71, 54, CB_W, CB_H, '-'
        +cbtn '1', 8, 70, CB_W, CB_H, '1'
        +cbtn '2', 29, 70, CB_W, CB_H, '2'
        +cbtn '3', 50, 70, CB_W, CB_H, '3'
        +cbtn '+', 71, 70, CB_W, CB_H+16, '+'
        +cbtn '0', 8, 86, CB_W+21, CB_H, '0'
        +cbtn '.', 50, 86, CB_W, CB_H, '.'
CALC_NB = (* - calc_buttons) / 6
cb_lbl: !byte 0, 0

!zone calc_open
calc_open:
        lda #CL_CALC
        jsr da_find
        bcs +
        jmp win_select
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx calc_win
        +winrect 210, 40, 309, 156
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_CALC
        sta w_class,x
        lda #<str_o_calc
        sta w_titl,x
        lda #>str_o_calc
        sta w_tith,x
        jsr calc_clear
        ldx calc_win
        jmp win_open

calc_close:
        lda #$ff
        sta calc_win
        rts

; C: everything to zero
calc_clear:
        ldx #4
        lda #0
-       sta calc_acc,x
        dex
        bpl -
        sta calc_op
        sta calc_have
        sta calc_entry
        lda #'0'
        sta calc_disp
        lda #0
        sta calc_disp+1
        rts

; ---------------------------------------------------------------------
!zone calc_draw
calc_draw:
        ; display box
        jsr calc_disp_rect
        jsr set_black
        jsr frame_rect
        jsr calc_show
        ; buttons
        ldx #0
-       stx u6
        jsr calc_draw_btn
        ldx u6
        inx
        cpx #CALC_NB
        bne -
        rts

calc_disp_rect:
        clc
        lda wc_x1
        adc #8
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        clc
        lda wc_x1
        adc #88
        sta rx2
        lda wc_x1+1
        adc #0
        sta rx2+1
        lda wc_y1
        clc
        adc #4
        sta ry1
        clc
        adc #13
        sta ry2
        rts

; show calc_disp right-aligned in the display
calc_show:
        jsr calc_disp_rect
        lda #1
        jsr rect_inset
        jsr fill_white
        lda #0
        sta font
        lda #<calc_disp
        sta tstr
        lda #>calc_disp
        sta tstr+1
        jsr text_width
        sec
        lda rx2
        sbc #2
        sta tx
        lda rx2+1
        sbc #0
        sta tx+1
        sec
        lda tx
        sbc twidth
        sta tx
        lda tx+1
        sbc twidth+1
        sta tx+1
        lda ry1
        clc
        adc #2
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jmp draw_text

; X = button -> rx..ry, q0 -> record
calc_btn_rect:
        txa
        asl
        sta t0
        asl
        clc
        adc t0                  ; *6
        clc
        adc #<calc_buttons
        sta q0
        lda #>calc_buttons
        adc #0
        sta q0+1
        ldy #1
        lda (q0),y
        clc
        adc wc_x1
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        iny
        lda (q0),y
        clc
        adc wc_y1
        sta ry1
        iny
        lda (q0),y
        clc
        adc rx1
        sta rx2
        lda rx1+1
        adc #0
        sta rx2+1
        lda rx2
        bne +
        dec rx2+1
+       dec rx2
        iny
        lda (q0),y
        clc
        adc ry1
        sta ry2
        dec ry2
        rts

calc_draw_btn:
        jsr calc_btn_rect
        jsr fill_white
        jsr set_black
        jsr frame_rect
        ; shadow on the right and bottom
        jsr rect_save
        lda ry2
        clc
        adc #1
        sta ry1
        sta ry2
        inc rx1
        bne +
        inc rx1+1
+       inc rx2
        bne +
        inc rx2+1
+       jsr fill_black
        jsr rect_restore
        inc ry1
        inc ry2
        lda rx2
        clc
        adc #1
        sta rx1
        sta rx2
        lda rx2+1
        adc #0
        sta rx1+1
        sta rx2+1
        jsr fill_black
        jsr rect_restore
        ; label
        ldy #0
        lda (q0),y
        sta cb_lbl
        lda #<cb_lbl
        sta tstr
        lda #>cb_lbl
        sta tstr+1
        lda #0
        sta font
        jsr text_width
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
        adc ry2
        ror
        sec
        sbc #3
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jmp draw_text

; ---------------------------------------------------------------------
!zone calc_click
calc_click:
        ldx #0
-       stx u6
        jsr calc_btn_rect
        jsr mouse_in_rect
        bcc .hit
        ldx u6
        inx
        cpx #CALC_NB
        bne -
        rts
.hit:   jsr track_box
        bcs .out
        ldx u6
        jsr calc_btn_rect
        ldy #5
        lda (q0),y
        jmp calc_input
.out:   rts

calc_key:
        lda key_char
        cmp #K_RETURN
        bne +
        lda #'='
+       cmp #'C'
        bne +
        lda #'c'
+       cmp #'E'
        bne +
        lda #'e'
+       cmp #K_DEL
        bne .bf334
        jmp calc_backspace
.bf334:
        ; flash the matching button
        sta u5
        ldx #0
-       stx u6
        jsr calc_btn_rect
        ldy #5
        lda (q0),y
        cmp u5
        beq +
        ldx u6
        inx
        cpx #CALC_NB
        bne -
        rts
+       ldx calc_win
        jsr win_get_content
        ldx u6
        jsr calc_btn_rect
        lda #1
        jsr rect_inset
        jsr invert_rect
        lda #4
        jsr wait_frames
        jsr invert_rect
        lda u5
        ; fall through

; A = key: digit, '.', operator, '=', 'c', 'e'
!zone calc_input
calc_input:
        cmp #'c'
        bne +
        jsr calc_clear
        jmp calc_refresh
+       cmp #'e'
        bne +
        lda #0
        sta calc_have
        sta calc_entry
        lda #'0'
        sta calc_disp
        lda #0
        sta calc_disp+1
        jmp calc_refresh
+       cmp #'.'
        beq .digit
        cmp #'0'
        bcc .op
        cmp #'9'+1
        bcs .op
.digit: ldx calc_have
        bne +
        ldx #0
        stx calc_entry
        inc calc_have
+       ldx #0                  ; find the end, refuse a second '.'
-       ldy calc_entry,x
        beq +
        cpy #'.'
        bne ++
        cmp #'.'
        beq .out
++      inx
        bne -
+       cpx #10
        bcs .out
        sta calc_entry,x
        lda #0
        sta calc_entry+1,x
        jsr calc_entry_to_disp
        jmp calc_refresh
.op:    cmp #'+'
        beq .isop
        cmp #'-'
        beq .isop
        cmp #'*'
        beq .isop
        cmp #'/'
        beq .isop
        cmp #'='
        bne .out
.isop:  sta u4
        lda calc_have
        beq .noentry
        jsr calc_compute        ; acc = acc op entry (or entry)
        bcc +
        jsr calc_error
        jmp calc_refresh
+       lda #0
        sta calc_have
.noentry:
        lda u4
        cmp #'='
        bne +
        lda #0
+       sta calc_op
        jmp calc_refresh
.out:   rts

calc_backspace:
        lda calc_have
        beq +
        ldx #0
-       lda calc_entry,x
        beq ++
        inx
        bne -
++      cpx #0
        beq +
        lda #0
        sta calc_entry-1,x
        jsr calc_entry_to_disp
        jmp calc_refresh
+       rts

calc_entry_to_disp:
        ldx #0
-       lda calc_entry,x
        sta calc_disp,x
        beq +
        inx
        bne -
+       cpx #0
        bne +
        lda #'0'
        sta calc_disp
        lda #0
        sta calc_disp+1
+       rts

calc_error:
        jsr calc_clear
        ldx #0
-       lda str_error,x
        sta calc_disp,x
        beq +
        inx
        bne -
+       jmp beep

; redraw the display (window is in front when the user types/clicks)
calc_refresh:
        ldx calc_win
        cpx #$ff
        beq +
        jsr win_get_content
        jsr clip_push
        jsr clip_screen
        jsr calc_disp_rect
        jsr clip_rect
        jsr calc_show
        jmp clip_pop
+       rts

; ---------------------------------------------------------------------
; calc_compute: acc = acc <calc_op> entry, or acc = entry when no op.
; Display = result.  Carry set on error.
; ---------------------------------------------------------------------
!zone calc_compute
calc_compute:
        jsr fp_begin
        lda #<calc_entry
        sta TXTPTR
        lda #>calc_entry
        sta TXTPTR+1
        jsr CHRGOT
        jsr FIN                 ; FAC = entry
        lda calc_op
        beq .store
        cmp #'/'
        bne +
        lda FAC_EXP             ; divide by zero?
        bne ++
        jmp fp_error
++      lda #<calc_acc
        ldy #>calc_acc
        jsr FDIV
        jmp .store
+       cmp #'*'
        bne +
        lda #<calc_acc
        ldy #>calc_acc
        jsr FMULT
        jmp .store
+       cmp #'-'
        bne +
        lda #<calc_acc
        ldy #>calc_acc
        jsr FSUB
        jmp .store
+       lda #<calc_acc
        ldy #>calc_acc
        jsr FADD
.store: ldx #<calc_acc
        ldy #>calc_acc
        jsr MOVMF
        jsr FOUT
        ; copy without the leading space
        ldx #0
        ldy #0
        lda $0100
        cmp #' '
        bne +
        iny
+
-       lda $0100,y
        sta calc_disp,x
        beq +
        inx
        iny
        cpx #13
        bne -
        lda #0
        sta calc_disp,x
+       jmp fp_end

; Edit menu: Copy puts the display on the Clipboard, Paste types it
!zone calc_edit
calc_edit:
        lda key_char
        cmp #EDIT_COPY
        bne .paste
        ldx #0
-       lda calc_disp,x
        sta clip_buf,x
        beq +
        inx
        bne -
+       stx clip_len
        rts
.paste: cmp #EDIT_PASTE
        bne .out
        ldx #0
-       cpx clip_len
        beq .out
        stx u3
        lda clip_buf,x
        cmp #'.'
        beq +
        cmp #'0'
        bcc ++
        cmp #'9'+1
        bcs ++
+       jsr calc_input
++      ldx u3
        inx
        bne -
.out:   rts

str_error: !text "Error", 0

; ---------------------------------------------------------------------
; da_find: A = class -> X = its window, carry clear if open
; ---------------------------------------------------------------------
!zone da_find
da_find:
        sta t0
        ldx #0
-       lda w_used,x
        beq +
        lda w_class,x
        cmp t0
        bne +
        clc
        rts
+       inx
        cpx #MAXWIN
        bne -
        sec
        rts

; win_refresh: redraw the content of window X correctly even if other
; windows overlap it
win_refresh:
        stx t7
        jsr win_get_content
        lda #$ff
        sta rr_skip
        jmp redraw_region
