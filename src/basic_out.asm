; =====================================================================
; basic_out.asm - the Output window: PRINT's text, INPUT, and drawing
;
; Text is kept a row at a time (out_buf), so the window can be drawn
; again when it is uncovered; drawing isn't kept.  PRINT's characters
; arrive in a queue (oq_buf, from CHROUT) and are drawn between slices.
; CLS, PSET, LINE and CIRCLE run inside BASIC: they draw straight into
; the bitmap, in the window's content (which must be in front).
; =====================================================================

OUT_TOP  = 2            ; the first row's top, in the content
OUT_LEFT = 2
IN_MAX   = 80
IN_BUF   = $0780        ; an INPUT line (the System doesn't use it)

oq_len:   !byte 0
out_row:  !byte 0
out_col:  !byte 0       ; characters in the row
out_x:    !byte 0       ; pixels across the row
out_w:    !byte 0       ; the room across
in_len:   !byte 0       ; INPUT: characters typed so far
out_x1:   !word 0       ; the content, on the screen (for drawing)
out_y1:   !byte 0
out_x2:   !word 0
out_y2:   !byte 0

; ---------------------------------------------------------------------
; Window methods
; ---------------------------------------------------------------------
out_idle:
        jmp run_slice

out_click:
        rts

out_close:
        jsr run_end
        lda #$ff
        sta out_win
        rts

; M_DRAW: the text (the content is white); the matrix unit's picture
; has gone, so it starts again
!zone out_draw
out_draw:
        jsr npu_unplaced
        lda #0
        sta od_row
-       lda od_row
        jsr row_ptr
        jsr row_xy
        lda pa
        ldy pa+1
        jsr draw_plain
        inc od_row
        lda od_row
        cmp #OUT_ROWS
        bne -
        rts
od_row: !byte 0

; M_KEY: INPUT's line, or GET's key
!zone out_key
out_key:
        lda in_state
        cmp #IS_TYPE
        beq .input
        lda run_state
        beq +
        lda key_char
        sta inkey_c
+       rts
.input: lda key_char
        cmp #K_RETURN           ; (BASIC prints the new line)
        bne +
        lda #IS_READY
        sta in_state
        rts
+       cmp #K_DEL
        bne .chr
        lda in_len
        bne .bf90
        jmp .out
.bf90:
        dec in_len
        dec out_col             ; the character goes from the row
        jsr row_ptr_cur
        ldy out_col
        lda (pa),y
        jsr char_width
        sta za
        lda #0
        sta (pa),y
        lda out_x
        sec
        sbc za
        sta out_x
        jsr out_clip            ; and from the screen
        jsr row_xy_cur
        clc
        lda tx
        adc out_x
        sta rx1
        lda tx+1
        adc #0
        sta rx1+1
        clc
        lda rx1
        adc za
        sta rx2
        lda rx1+1
        adc #0
        sta rx2+1
        lda ty
        sta ry1
        clc
        adc #LH-2
        sta ry2
        jsr fill_white
        jmp clip_pop
.chr:   cmp #32
        bcc .out
        cmp #127
        bcs .out
        ldx in_len
        cpx #IN_MAX
        bcs .beep
        jsr char_width          ; room on the row?
        clc
        adc out_x
        bcs .beep
        cmp out_w
        bcs .beep
        lda out_col
        cmp #OUT_COLS-1
        bcs .beep
        lda key_char
        ldx in_len
        sta IN_BUF,x
        inc in_len
        sta out_one
        lda #<out_one
        sta pd
        lda #>out_one
        sta pd+1
        lda #1
        jmp out_text_pd
.beep:  jmp beep
.out:   rts
out_one: !byte 0

; ---------------------------------------------------------------------
; The console
; ---------------------------------------------------------------------
; where the content is (before each slice; drawing uses it)
out_place:
        ldx out_win
        jsr win_get_content
        ldx #5
-       lda wc_x1,x
        sta out_x1,x
        dex
        bpl -
        rts

; empty, at the top
!zone out_reset
out_reset:
        lda #0
        sta out_row
        sta out_col
        sta out_x
        ldx #OUT_ROWS-1         ; every row empty
-       txa
        pha
        jsr row_ptr
        lda #0
        tay
        sta (pa),y
        pla
        tax
        dex
        bpl -
        ldx out_win             ; the width
        jsr win_get_content
        sec
        lda wc_x2
        sbc wc_x1
        sec
        sbc #OUT_LEFT*2
        sta out_w
        rts

; CLS, and Run: the window white, the text gone
out_cls:
        jsr out_reset
out_white:
        jsr npu_unplaced
        jsr out_clip
        jsr fill_white          ; (out_clip left rx1..ry2 = the content)
        jmp clip_pop

; clip to the Output window's content (rx1..ry2 = it, wc_* too)
out_clip:
        jsr clip_push
        jsr clip_screen
        ldx out_win
        jsr win_get_content
        jmp clip_rect

; pa = row A's text
row_ptr:
        tax
        lda #<out_buf
        sta pa
        lda #>out_buf
        sta pa+1
-       dex
        bmi +
        lda #OUT_COLS
        jsr pa_add
        jmp -
+       rts
row_ptr_cur:
        lda out_row
        jmp row_ptr

pa_add: clc
        adc pa
        sta pa
        bcc +
        inc pa+1
+       rts

; tx, ty = the start of row od_row (row_xy) or out_row (row_xy_cur)
row_xy:
        lda od_row
        jmp +
row_xy_cur:
        lda out_row
+       tax
        clc
        lda wc_x1
        adc #OUT_LEFT
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #OUT_TOP
-       dex
        bmi +
        adc #LH
        jmp -
+       sta ty
        lda #0
        sta ty+1
        rts

; out_text: A characters at (pd) onto the rows and the screen, from
; where the last ones ended; 13 starts a new row, and rows wrap
!zone out_text
out_text_pd:
        sta ot_len
        jsr out_clip
        lda #0
        sta ot_i
        jsr .start
.l:     ldy ot_i
        cpy ot_len
        beq .done
        lda (pd),y
        cmp #13
        bne +
        jsr .flush
        jsr out_newline
        jsr .start
        jmp .next
+       sta ot_c
        jsr char_width
        sta ot_w
        clc
        adc out_x
        bcs .wrap
        cmp out_w
        bcs .wrap
        lda out_col
        cmp #OUT_COLS-1
        bcc +
.wrap:  jsr .flush
        jsr out_newline
        jsr .start
+       jsr row_ptr_cur
        ldy out_col
        lda ot_c
        sta (pa),y
        iny
        lda #0
        sta (pa),y
        sty out_col
        clc
        lda out_x
        adc ot_w
        sta out_x
.next:  inc ot_i
        bne .l
.done:  jsr .flush
        jmp clip_pop
.start: lda out_col             ; a run starts here
        sta ot_run
        lda out_x
        sta ot_rx
        rts
.flush: lda out_col             ; draw the run
        cmp ot_run
        beq +
        jsr row_ptr_cur
        jsr row_xy_cur
        clc
        lda tx
        adc ot_rx
        sta tx
        bcc ++
        inc tx+1
++      clc
        lda pa
        adc ot_run
        tax
        lda pa+1
        adc #0
        tay
        txa
        jsr draw_plain
+       rts
ot_len: !byte 0
ot_i:   !byte 0
ot_c:   !byte 0
ot_w:   !byte 0
ot_run: !byte 0
ot_rx:  !byte 0

; the next row (clipped to the content already); at the bottom the
; rows move up and the window is drawn again
!zone out_newline
out_newline:
        lda #0
        sta out_col
        sta out_x
        inc out_row
        lda out_row
        cmp #OUT_ROWS
        bcc .out
        dec out_row
        lda #<(out_buf+OUT_COLS)
        sta mv_src
        lda #>(out_buf+OUT_COLS)
        sta mv_src+1
        lda #<out_buf
        sta mv_dst
        lda #>out_buf
        sta mv_dst+1
        lda #<((OUT_ROWS-1)*OUT_COLS)
        sta mv_n
        lda #>((OUT_ROWS-1)*OUT_COLS)
        sta mv_n+1
        jsr memmove
        jsr row_ptr_cur
        lda #0
        tay
        sta (pa),y
        ldx out_win
        jsr win_get_content
        jsr fill_white
        jsr npu_unplaced
        jmp out_draw
.out:   rts

; draw the queued characters (if the window is in front; if it isn't,
; the program waits for it)
!zone out_flush
out_flush:
        lda oq_len
        beq .rts
        lda out_win
        cmp zlist
        beq +
        sec                     ; (not in front: carry set)
        rts
.rts:   clc
        rts
+       ldx #0
.l:     stx of_i
        cpx oq_len
        beq .done
        lda oq_buf,x
        cmp #$93                ; clear
        bne +
        jsr out_cls
        ldx of_i
        inx
        jmp .l
+       jsr .ok
        bcc .run
        inx
        jmp .l
.run:   stx of_s                ; a run of characters, drawn together
-       inx
        cpx oq_len
        beq +
        lda oq_buf,x
        jsr .ok
        bcc -
+       stx of_i
        txa
        sec
        sbc of_s
        pha
        clc
        lda #<oq_buf
        adc of_s
        sta pd
        lda #>oq_buf
        adc #0
        sta pd+1
        pla
        jsr out_text_pd
        ldx of_i
        jmp .l
.done:  lda #0
        sta oq_len
        clc
        rts
; is A (oq_buf,x) drawn?  carry clear if so (cursor right: a space)
.ok:    cmp #$1d
        bne +
        lda #' '
        sta oq_buf,x
        clc
        rts
+       cmp #13
        beq +
        cmp #32
        bcc ++
        cmp #127
        bcs ++
+       clc
        rts
++      sec
        rts
of_i:   !byte 0
of_s:   !byte 0

; ---------------------------------------------------------------------
; Drawing statements (inside BASIC)
;   CLS   PSET (x, y) [, c]   LINE (x1, y1)-(x2, y2) [, c] [, B | BF]
;   CIRCLE (x, y), r [, c]    BEEP
; Colour 0 is white, anything else black.  Coordinates are from the
; content's top left.
; ---------------------------------------------------------------------
AYINT_  = $b1bf         ; FAC to a signed integer at $64 (high), $65
MINUS_T = $ab           ; BASIC's - token

st_cls: lda #$93
        jmp chrout

st_beep:
        lda #<beep
        sta sc_vec
        lda #>beep
        sta sc_vec+1
        jmp sys_call

; ( x , y ) -> gx, gy on the screen
get_xy: jsr CHKOPN
        jsr get_int
        clc
        adc out_x1
        sta gx
        txa
        adc out_x1+1
        sta gx+1
        jsr CHKCOM
        jsr get_int
        clc
        adc out_y1
        sta gy
        txa
        adc #0
        sta gy+1
        jmp CHKCLS

; A/X = a signed whole number expression (low, high)
get_int:
        jsr FRMNUM
        jsr AYINT_
        lda $65
        ldx $64
        rts

; [, c]: the colour (and C clear); C set if there's a comma but no colour
!zone get_colour
get_colour:
        lda #1
        sta g_c
        jsr CHRGOT_
        cmp #','
        bne .none
        jsr CHRGET
        cmp #','                ; , , B
        beq .skip
        cmp #'B'
        beq .skip
        jsr GETBYT
        stx g_c
.none:  clc
        rts
.skip:  sec
        rts

st_pset:
        jsr need_front
        jsr get_xy
        jsr get_colour
        jsr g_on
        jsr px_plot
        jmp g_off

!zone st_line
st_line:
        jsr need_front
        jsr get_xy
        lda gx
        sta g_x0
        lda gx+1
        sta g_x0+1
        lda gy
        sta g_y0
        lda gy+1
        sta g_y0+1
        jsr CHRGOT_
        cmp #MINUS_T
        beq +
        jmp SNERR
+       jsr CHRGET
        jsr get_xy
        lda #0
        sta g_box
        jsr get_colour
        bcs .box                ; , B or , BF follows
        jsr CHRGOT_
        cmp #','
        bne .draw
        jsr CHRGET
.box:   jsr CHRGOT_
        cmp #','
        bne +
        jsr CHRGET
+       cmp #'B'
        beq +
        jmp SNERR
+       inc g_box
        jsr CHRGET
        cmp #'F'
        bne .draw
        inc g_box
        jsr CHRGET
.draw:  jsr g_on
        lda g_box
        bne +
        jsr px_line
        jmp g_off
+       jsr px_box
        jmp g_off

st_circle:
        jsr need_front
        jsr get_xy
        jsr CHKCOM
        jsr GETBYT
        stx g_r
        jsr get_colour
        jsr g_on
        jsr px_circle
        jmp g_off

; the bitmap readable: RAM at $e000 (interrupts off meanwhile)
g_on:   sei
        lda #$35
        sta $01
        rts
g_off:  lda #$37
        sta $01
        cli
        rts

; one pixel at gx, gy in colour g_c, if it is in the content
!zone px_plot
px_plot:
        lda gx+1
        bmi .out
        lda gx                  ; out_x1 <= gx <= out_x2
        cmp out_x1
        lda gx+1
        sbc out_x1+1
        bcc .out
        lda out_x2
        cmp gx
        lda out_x2+1
        sbc gx+1
        bcc .out
        lda gy+1
        bne .out
        lda gy
        cmp out_y1
        bcc .out
        cmp out_y2
        beq +
        bcs .out
+       lsr                     ; the byte: row * 320 + x & ~7 + y & 7
        lsr
        lsr
        tax
        lda gx
        and #$f8
        clc
        adc row_lo,x
        sta pg
        lda gx+1
        adc row_hi,x
        sta pg+1
        lda gx
        and #7
        tax
        lda gy
        and #7
        tay
        lda bit_tab,x
        ldx g_c
        beq +
        ora (pg),y
        sta (pg),y
        rts
+       eor #$ff
        and (pg),y
        sta (pg),y
.out:   rts
row_lo: !for r, 0, 24 { !byte <($e000 + r*320) }
row_hi: !for r, 0, 24 { !byte >($e000 + r*320) }

; a line from g_x0, g_y0 to gx, gy (Bresenham's)
!zone px_line
px_line:
        lda gx                  ; keep the end
        sta g_x1
        lda gx+1
        sta g_x1+1
        lda gy
        sta g_y1
        lda gy+1
        sta g_y1+1
        lda g_x0                ; start at x0, y0
        sta gx
        lda g_x0+1
        sta gx+1
        lda g_y0
        sta gy
        lda g_y0+1
        sta gy+1
        ldx #1                  ; dx = |x1 - x0|, sx
        sec
        lda g_x1
        sbc gx
        sta l_dx
        lda g_x1+1
        sbc gx+1
        sta l_dx+1
        bpl +
        ldx #$ff
        jsr .neg_dx
+       stx l_sx
        ldx #1                  ; dy = -|y1 - y0|, sy
        sec
        lda g_y1
        sbc gy
        sta l_dy
        lda g_y1+1
        sbc gy+1
        sta l_dy+1
        bmi +
        ldx #$ff                ; (positive: negate it, step down)
        lda #0
        sec
        sbc l_dy
        sta l_dy
        lda #0
        sbc l_dy+1
        sta l_dy+1
        ldx #1
        bne ++
+       ldx #$ff
++      stx l_sy
        clc                     ; err = dx + dy
        lda l_dx
        adc l_dy
        sta l_err
        lda l_dx+1
        adc l_dy+1
        sta l_err+1
.l:     jsr px_plot
        lda gx                  ; at the end?
        cmp g_x1
        bne +
        lda gx+1
        cmp g_x1+1
        bne +
        lda gy
        cmp g_y1
        bne +
        lda gy+1
        cmp g_y1+1
        bne +
        rts
+       lda l_err               ; e2 = 2 * err
        asl
        sta l_e2
        lda l_err+1
        rol
        sta l_e2+1
        lda l_e2                ; e2 >= dy: err += dy, x += sx
        cmp l_dy
        lda l_e2+1
        sbc l_dy+1
        bvc +
        eor #$80
+       bmi +
        clc
        lda l_err
        adc l_dy
        sta l_err
        lda l_err+1
        adc l_dy+1
        sta l_err+1
        lda l_sx
        jsr .addx
+       lda l_dx                ; e2 <= dx: err += dx, y += sy
        cmp l_e2
        lda l_dx+1
        sbc l_e2+1
        bvc +
        eor #$80
+       bmi .l
        clc
        lda l_err
        adc l_dx
        sta l_err
        lda l_err+1
        adc l_dx+1
        sta l_err+1
        clc
        lda gy
        adc l_sy
        sta gy
        lda l_sy
        bmi +
        bcs .bf770
        jmp .l
.bf770:
        inc gy+1
        jmp .l
+       bcc .bf773
        jmp .l
.bf773:
        dec gy+1
        jmp .l
.addx:  clc
        adc gx
        sta gx
        lda l_sx
        bmi +
        bcc ++
        inc gx+1
++      rts
+       bcs +
        dec gx+1
+       rts
.neg_dx:
        lda #0
        sec
        sbc l_dx
        sta l_dx
        lda #0
        sbc l_dx+1
        sta l_dx+1
        rts

; a box from g_x0, g_y0 to gx, gy: its outline (g_box 1) or filled (2),
; drawn by the System (QuickDraw's rectangles)
px_box: lda #<box_sys
        sta sc_vec
        lda #>box_sys
        sta sc_vec+1
        jsr g_off               ; (back to BASIC's banking for the call)
        jsr sys_call
        jmp g_on

!zone box_sys
box_sys:
        jsr out_clip
        lda g_c
        beq +
        jsr set_black
        jmp ++
+       jsr set_white
++      lda #M_COPY
        jsr set_mode
        lda g_x0                ; rx1..ry2, in order, y on the screen
        sta rx1
        lda g_x0+1
        sta rx1+1
        lda gx
        sta rx2
        lda gx+1
        sta rx2+1
        lda g_y0
        ldx g_y0+1
        jsr .y
        sta ry1
        lda gy
        ldx gy+1
        jsr .y
        sta ry2
        lda rx2                 ; (signed) rx1 <= rx2
        cmp rx1
        lda rx2+1
        sbc rx1+1
        bvc +
        eor #$80
+       bpl +
        ldx #1
-       lda rx1,x
        ldy rx2,x
        sta rx2,x
        sty rx1,x
        dex
        bpl -
+       lda ry2
        cmp ry1
        bcs +
        ldx ry1
        sta ry1
        stx ry2
+       lda g_box
        cmp #2
        bne .frame
        jsr fill_rect
        jmp clip_pop
.frame: ldx #5                  ; the four sides
-       lda rx1,x
        sta g_rect,x
        dex
        bpl -
        lda ry1
        sta ry2
        jsr fill_rect
        jsr .back
        lda ry2
        sta ry1
        jsr fill_rect
        jsr .back
        lda rx1
        sta rx2
        lda rx1+1
        sta rx2+1
        jsr fill_rect
        jsr .back
        lda rx2
        sta rx1
        lda rx2+1
        sta rx1+1
        jsr fill_rect
        jmp clip_pop
.back:  ldx #5
-       lda g_rect,x
        sta rx1,x
        dex
        bpl -
        rts
; y (A/X, 16 bit signed) kept on the screen: 0-199
.y:     cpx #0
        beq +
        bmi ++
        lda #199
        rts
++      lda #0
        rts
+       cmp #200
        bcc +
        lda #199
+       rts
g_rect: !fill 6

; a circle round gx, gy of radius g_r (the midpoint way)
!zone px_circle
px_circle:
        ldx #3
-       lda gx,x
        sta c_cx,x
        dex
        bpl -
        lda g_r
        sta c_x
        lda #0
        sta c_y
        sec                     ; err = 1 - r
        lda #1
        sbc g_r
        sta l_err
        lda #0
        sbc #0
        sta l_err+1
.l:     lda c_x
        cmp c_y
        bcc .out
        lda c_x                 ; the eight points
        ldx c_y
        jsr .four
        lda c_y
        ldx c_x
        jsr .four
        inc c_y
        lda l_err+1
        bmi .in
        dec c_x                 ; err += 2 (y - x) + 1
        lda c_y
        sec
        sbc c_x
        sta za
        lda #0
        sbc #0
        sta zb
        asl za
        rol zb
        clc
        lda l_err
        adc za
        sta l_err
        lda l_err+1
        adc zb
        sta l_err+1
        jmp .one
.in:    lda c_y                 ; err += 2y + 1
        asl
        sta za
        lda #0
        rol
        sta zb
        clc
        lda l_err
        adc za
        sta l_err
        lda l_err+1
        adc zb
        sta l_err+1
.one:   inc l_err
        bne .l
        inc l_err+1
        jmp .l
.out:   rts
; (cx +- A, cy +- X)
.four:  sta za
        stx zb
        jsr .x_plus
        jsr .y_plus
        jsr px_plot
        jsr .y_minus
        jsr px_plot
        jsr .x_minus
        jsr .y_plus
        jsr px_plot
        jsr .y_minus
        jmp px_plot
.x_plus:
        clc
        lda c_cx
        adc za
        sta gx
        lda c_cx+1
        adc #0
        sta gx+1
        rts
.x_minus:
        sec
        lda c_cx
        sbc za
        sta gx
        lda c_cx+1
        sbc #0
        sta gx+1
        rts
.y_plus:
        clc
        lda c_cy
        adc zb
        sta gy
        lda c_cy+1
        adc #0
        sta gy+1
        rts
.y_minus:
        sec
        lda c_cy
        sbc zb
        sta gy
        lda c_cy+1
        sbc #0
        sta gy+1
        rts

gx:     !word 0
gy:     !word 0
g_x0:   !word 0
g_y0:   !word 0
g_x1:   !word 0
g_y1:   !word 0
g_c:    !byte 0
g_r:    !byte 0
g_box:  !byte 0
l_dx:   !word 0
l_dy:   !word 0
l_sx:   !byte 0
l_sy:   !byte 0
l_err:  !word 0
l_e2:   !word 0
c_cx:   !word 0
c_cy:   !word 0
c_x:    !byte 0
c_y:    !byte 0
