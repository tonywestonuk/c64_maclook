; =====================================================================
; qd_shapes.asm - QuickDraw lines, ovals, circles and round rects
;
; Everything is drawn in the current pattern (pat) and mode (rmode), set
; with set_black, set_white, set_gray or set_pat_copy and then set_mode,
; and clipped to the clip rectangle, exactly like fill_rect.  Shapes
; draw their spans with fill_rect, so patterns line up with the screen.
; The rect parameters (rx1..ry2) are left as they were.
; =====================================================================

OV_X = $c700            ; oval half-widths per row (128 bytes, block 6)


; ---------------------------------------------------------------------
; plot: one pixel at A/X = x (signed), Y = y
; ---------------------------------------------------------------------
pl_x:   !word 0
pl_y:   !byte 0
pl_bit: !byte 0
!zone plot
plot:
        sta pl_x
        stx pl_x+1
        sty pl_y
plot_pl:                        ; the pixel in pl_x, pl_y
        lda pl_y                ; clip
        cmp cly1
        bcc .out
        lda cly2
        cmp pl_y
        bcc .out
        lda pl_x+1
        bmi .out
        lda pl_x
        cmp clx1
        lda pl_x+1
        sbc clx1+1
        bcc .out
        lda clx2
        cmp pl_x
        lda clx2+1
        sbc pl_x+1
        bcc .out
        lda pl_y                ; address of the byte
        lsr
        lsr
        lsr
        tax
        lda pl_x+1
        lsr
        lda pl_x
        ror
        lsr
        lsr
        tay
        clc
        lda crow_lo,x
        adc col8_lo,y
        sta p0
        lda crow_hi,x
        adc col8_hi,y
        sta p0+1
        lda pl_x
        and #7
        tax
        lda bit_tab,x
        sta pl_bit
        lda pl_y
        and #7
        tay
        lda (pat),y             ; the pattern's bit for this pixel
        and pl_bit
        ldx rmode
        beq .copy
        cpx #M_XOR
        beq .xor
        cpx #M_BIC
        beq .bic
        ora (p0),y              ; M_OR
        sta (p0),y
.out:   rts
.xor:   eor (p0),y
        sta (p0),y
        rts
.bic:   eor #$ff
        and (p0),y
        sta (p0),y
        rts
.copy:  sta t0
        lda pl_bit
        eor #$ff
        and (p0),y
        ora t0
        sta (p0),y
        rts

; ---------------------------------------------------------------------
; The pen: move_to / line_to take A/X = x, Y = y
; ---------------------------------------------------------------------
; (draw_line's variables first: line_to falls through into it)
ln_x2:  !word 0
ln_dx:  !word 0
ln_dy:  !word 0
ln_err: !word 0
ln_e2:  !word 0
ln_sx:  !byte 0
ln_sy:  !byte 0

move_to:
        sta pn_x
        stx pn_x+1
        sty pn_y
        rts

line_to:
        pha
        lda pn_x
        sta rx1
        lda pn_x+1
        sta rx1+1
        lda pn_y
        sta ry1
        pla
        sta rx2
        sta pn_x
        stx rx2+1
        stx pn_x+1
        sty ry2
        sty pn_y
        ; fall through

; ---------------------------------------------------------------------
; draw_line: from rx1,ry1 to rx2,ry2 (Bresenham).  Straight lines are
; filled as rectangles.
; ---------------------------------------------------------------------
!zone draw_line
draw_line:
        jsr ov_save
        lda ry1
        cmp ry2
        beq .straight
        lda rx1
        cmp rx2
        bne .slope
        lda rx1+1
        cmp rx2+1
        bne .slope
.straight:                      ; horizontal or vertical: a thin rect
        jsr ov_order
        jsr fill_rect
        jmp ov_restore
.slope: lda rx1
        sta pl_x
        lda rx1+1
        sta pl_x+1
        lda ry1
        sta pl_y
        lda rx2
        sta ln_x2
        lda rx2+1
        sta ln_x2+1
        ; dx = |x2 - x1|, sx = direction
        ldx #1
        sec
        lda rx2
        sbc rx1
        sta ln_dx
        lda rx2+1
        sbc rx1+1
        sta ln_dx+1
        bpl +
        ldx #$ff
        sec
        lda #0
        sbc ln_dx
        sta ln_dx
        lda #0
        sbc ln_dx+1
        sta ln_dx+1
+       stx ln_sx
        ; dy = |y2 - y1|, sy = direction
        ldx #1
        sec
        lda ry2
        sbc ry1
        bcs +
        ldx #$ff
        eor #$ff
        adc #1
+       sta ln_dy
        lda #0
        sta ln_dy+1
        stx ln_sy
        ; both ends on the screen: the fast way
        lda rx1+1
        bmi .slow
        lda rx2+1
        bmi .slow
        lda rx1
        cmp #<320
        lda rx1+1
        sbc #>320
        bcs .slow
        lda rx2
        cmp #<320
        lda rx2+1
        sbc #>320
        bcs .slow
        lda ry1
        cmp #200
        bcs .slow
        lda ry2
        cmp #200
        bcs .slow
        jsr ln_fast
        jmp ov_restore
.slow:  ; err = dx - dy
        sec
        lda ln_dx
        sbc ln_dy
        sta ln_err
        lda ln_dx+1
        sbc #0
        sta ln_err+1
.loop:  jsr plot_pl
        lda pl_x
        cmp ln_x2
        bne +
        lda pl_x+1
        cmp ln_x2+1
        bne +
        lda pl_y
        cmp ry2
        bne .bf215
        jmp .done
.bf215:
+       lda ln_err              ; e2 = 2 * err
        asl
        sta ln_e2
        lda ln_err+1
        rol
        sta ln_e2+1
        ; e2 > -dy, i.e. e2 + dy > 0: err -= dy, x += sx
        clc
        lda ln_e2
        adc ln_dy
        tax
        lda ln_e2+1
        adc ln_dy+1
        bmi .noxs
        bne +
        txa
        beq .noxs
+       sec
        lda ln_err
        sbc ln_dy
        sta ln_err
        lda ln_err+1
        sbc ln_dy+1
        sta ln_err+1
        lda ln_sx
        bmi +
        inc pl_x
        bne .noxs
        inc pl_x+1
        jmp .noxs
+       lda pl_x
        bne +
        dec pl_x+1
+       dec pl_x
.noxs:  ; e2 < dx, i.e. e2 - dx < 0: err += dx, y += sy
        sec
        lda ln_e2
        sbc ln_dx
        lda ln_e2+1
        sbc ln_dx+1
        bpl .loop
        clc
        lda ln_err
        adc ln_dx
        sta ln_err
        lda ln_err+1
        adc ln_dx+1
        sta ln_err+1
        clc
        lda pl_y
        adc ln_sy
        sta pl_y
        jmp .loop
.done:  jmp ov_restore

; ---------------------------------------------------------------------
; ln_fast: draw_line for ends on the screen.  Walks the bitmap address
; (p0 + Y, Y = y & 7) and the bit mask along the line, and only tests
; the clip rect per pixel if an end is outside it.
; In: pl_x/pl_y = start, ln_dx/ln_dy/ln_sx/ln_sy (draw_line).
; ---------------------------------------------------------------------
lf_bit:  !byte 0
lf_n:    !word 0        ; pixels left
lf_clip: !byte 0        ; 1 = test each pixel against the clip rect
!zone ln_fast
ln_fast:
        ; are both ends inside the clip rect?
        lda #0
        sta lf_clip
        ldx #0
        jsr .inclip
        ldx #3
        jsr .inclip
        ; start address and bit
        lda pl_y
        lsr
        lsr
        lsr
        tax
        lda pl_x+1
        lsr
        lda pl_x
        ror
        lsr
        lsr
        tay
        clc
        lda crow_lo,x
        adc col8_lo,y
        sta p0
        lda crow_hi,x
        adc col8_hi,y
        sta p0+1
        lda pl_x
        and #7
        tax
        lda bit_tab,x
        sta lf_bit
        ; which axis is longer?
        lda ln_dx+1
        bne .xmajor
        lda ln_dx
        cmp ln_dy
        bcs .xmajor
        ; --- y major: one pixel per row
        lda ln_dy
        sta lf_n
        lda #0
        sta lf_n+1
        lda ln_dy               ; err = dy / 2
        lsr
        sta ln_err
        lda #0
        sta ln_err+1
        lda pl_y
        and #7
        tay
.ym:    jsr .pix
        lda lf_n
        bne +
        rts
+       dec lf_n
        jsr .stepy
        sec                     ; err -= dx
        lda ln_err
        sbc ln_dx
        sta ln_err
        lda ln_err+1
        sbc ln_dx+1
        sta ln_err+1
        bpl .ym
        clc                     ; err < 0: err += dy, step x
        lda ln_err
        adc ln_dy
        sta ln_err
        lda ln_err+1
        adc #0
        sta ln_err+1
        jsr .stepx
        jmp .ym
        ; --- x major: one pixel per column
.xmajor:
        lda ln_dx
        sta lf_n
        lda ln_dx+1
        sta lf_n+1
        lda ln_dx+1             ; err = dx / 2
        lsr
        sta ln_err+1
        lda ln_dx
        ror
        sta ln_err
        lda pl_y
        and #7
        tay
.xm:    jsr .pix
        lda lf_n
        ora lf_n+1
        bne +
        rts
+       lda lf_n
        bne +
        dec lf_n+1
+       dec lf_n
        jsr .stepx
        sec                     ; err -= dy
        lda ln_err
        sbc ln_dy
        sta ln_err
        lda ln_err+1
        sbc #0
        sta ln_err+1
        bpl .xm
        clc                     ; err < 0: err += dx, step y
        lda ln_err
        adc ln_dx
        sta ln_err
        lda ln_err+1
        adc ln_dx+1
        sta ln_err+1
        jsr .stepy
        jmp .xm

; one step along x: the bit, and every 8 pixels the next byte
.stepx: lda ln_sx
        bmi .left
        inc pl_x
        bne +
        inc pl_x+1
+       lsr lf_bit
        bcc +
        ror lf_bit              ; $80 (the carry)
        clc
        lda p0
        adc #8
        sta p0
        bcc +
        inc p0+1
+       rts
.left:  lda pl_x
        bne +
        dec pl_x+1
+       dec pl_x
        asl lf_bit
        bcc +
        rol lf_bit              ; $01
        sec
        lda p0
        sbc #8
        sta p0
        bcs +
        dec p0+1
+       rts
; one step along y: Y, and every 8 rows the next character row
.stepy: lda ln_sy
        bmi .up
        inc pl_y
        iny
        cpy #8
        bne +
        ldy #0
        clc
        lda p0
        adc #<320
        sta p0
        lda p0+1
        adc #>320
        sta p0+1
+       rts
.up:    dec pl_y
        dey
        bpl +
        ldy #7
        sec
        lda p0
        sbc #<320
        sta p0
        lda p0+1
        sbc #>320
        sta p0+1
+       rts

; the pixel at (p0),y in the pattern and mode
.pix:   lda lf_clip
        beq +
        lda pl_y                ; outside the clip rect: skip
        cmp cly1
        bcc .no
        lda cly2
        cmp pl_y
        bcc .no
        lda pl_x
        cmp clx1
        lda pl_x+1
        sbc clx1+1
        bcc .no
        lda clx2
        cmp pl_x
        lda clx2+1
        sbc pl_x+1
        bcc .no
+       lda (pat),y
        and lf_bit
        ldx rmode
        beq .copy
        cpx #M_XOR
        beq .xor
        cpx #M_BIC
        beq .bic
        ora (p0),y
        sta (p0),y
.no:    rts
.xor:   eor (p0),y
        sta (p0),y
        rts
.bic:   eor #$ff
        and (p0),y
        sta (p0),y
        rts
.copy:  sta t0
        lda lf_bit
        eor #$ff
        and (p0),y
        ora t0
        sta (p0),y
        rts

; end X (0 = rx1/ry1, 3 = rx2/ry2) outside the clip rect: lf_clip = 1
.inclip:
        lda ry1,x
        cmp cly1
        bcc .outc
        lda cly2
        cmp ry1,x
        bcc .outc
        lda rx1,x
        cmp clx1
        lda rx1+1,x
        sbc clx1+1
        bcc .outc
        lda clx2
        cmp rx1,x
        lda clx2+1
        sbc rx1+1,x
        bcc .outc
        rts
.outc:  lda #1
        sta lf_clip
        rts

; ---------------------------------------------------------------------
; Ovals.  All the curved shapes are an ellipse with half-widths a, b
; around (ov_cx, ov_cy), stretched by ov_ox pixels across and ov_oy
; down the middle: an oval has a stretch of 0 or 1 (even sizes), a
; round rect the length of its straight sides.  The midpoint algorithm
; finds the half-width OV_X[y] of each row y = 0..b of the quadrant;
; the shape is then drawn as spans with fill_rect.
; ---------------------------------------------------------------------
ov_cx:  !word 0         ; centre (top left of the stretch), signed
ov_cy:  !word 0
ov_a:   !byte 0
ov_b:   !byte 0
ov_ox:  !word 0
ov_oy:  !byte 0
ov_r:   !byte 0         ; radius parameter
ov_sv:  !fill 6         ; the caller's rect

; oval inside rx1..ry2
frame_oval:
        jsr ov_save
        jsr ov_from_rect
        bcs ov_restore
        jsr ov_frame
        jmp ov_restore
fill_oval:
        jsr ov_save
        jsr ov_from_rect
        bcs ov_restore
        jsr ov_fill
        jmp ov_restore

; circle around rx1,ry1 with radius A (up to 127)
frame_circle:
        jsr ov_save
        jsr ov_from_circle
        jsr ov_frame
        jmp ov_restore
fill_circle:
        jsr ov_save
        jsr ov_from_circle
        jsr ov_fill
        jmp ov_restore

; rect rx1..ry2 with corners of radius A
frame_rrect:
        jsr ov_save
        jsr ov_from_rrect
        bcs ov_restore
        jsr ov_frame
        jmp ov_restore
fill_rrect:
        jsr ov_save
        jsr ov_from_rrect
        bcs ov_restore
        jsr ov_fill
        ; fall through
ov_restore:
        ldx #5
-       lda ov_sv,x
        sta rx1,x
        dex
        bpl -
        rts
ov_save:
        sta ov_r
        ldx #5
-       lda rx1,x
        sta ov_sv,x
        dex
        bpl -
        lda ov_r
        rts

; ov_order: put rx1 <= rx2 and ry1 <= ry2
!zone ov_order
ov_order:
        lda rx2
        cmp rx1
        lda rx2+1
        sbc rx1+1
        bvc +
        eor #$80
+       bpl +
        ldx rx1
        lda rx2
        sta rx1
        stx rx2
        ldx rx1+1
        lda rx2+1
        sta rx1+1
        stx rx2+1
+       lda ry2
        cmp ry1
        bcs +
        ldx ry1
        sta ry1
        stx ry2
+       rts

; rect -> ellipse.  Carry set if the rect is empty.
!zone ov_from_rect
ov_from_rect:
        jsr ov_order
        jsr ov_size             ; t0/t1 = width - 1, t2 = height - 1
        lda t1                  ; a = (w-1)/2 (wider than 512: give up)
        cmp #2
        bcs .no
        lsr
        lda t0
        ror
        sta ov_a
        lda t0
        and #1
        sta ov_ox
        lda #0
        sta ov_ox+1
        lda t2
        lsr
        sta ov_b
        lda t2
        and #1
        sta ov_oy
        jmp ov_centre
.no:    sec
        rts

; rect + corner radius A -> stretched circle.  Carry set if empty.
!zone ov_from_rrect
ov_from_rrect:
        jsr ov_order
        jsr ov_size
        lda ov_r                ; r = min(A, (w-1)/2, (h-1)/2, 127)
        bpl +
        lda #127
+       sta ov_a
        lda t1
        lsr
        lda t0
        ror
        ldx t1
        cpx #2
        bcs +                   ; very wide: no limit from the width
        cmp ov_a
        bcs +
        sta ov_a
+       lda t2
        lsr
        cmp ov_a
        bcs +
        sta ov_a
+       lda ov_a
        sta ov_b
        asl                     ; ox = (w-1) - 2r, oy = (h-1) - 2r
        sta t3
        sec
        lda t0
        sbc t3
        sta ov_ox
        lda t1
        sbc #0
        sta ov_ox+1
        sec
        lda t2
        sbc t3
        sta ov_oy
        ; fall through
ov_centre:                      ; cx = rx1 + a, cy = ry1 + b
        clc
        lda rx1
        adc ov_a
        sta ov_cx
        lda rx1+1
        adc #0
        sta ov_cx+1
        clc
        lda ry1
        adc ov_b
        sta ov_cy
        lda #0
        adc #0
        sta ov_cy+1
        clc
        rts

; t0/t1 = rx2 - rx1, t2 = ry2 - ry1 (after ov_order)
ov_size:
        sec
        lda rx2
        sbc rx1
        sta t0
        lda rx2+1
        sbc rx1+1
        sta t1
        sec
        lda ry2
        sbc ry1
        sta t2
        rts

; centre rx1,ry1, radius A -> circle
ov_from_circle:
        lda ov_r
        bpl +
        lda #127
+       sta ov_a
        sta ov_b
        lda #0
        sta ov_ox
        sta ov_ox+1
        sta ov_oy
        lda rx1
        sta ov_cx
        lda rx1+1
        sta ov_cx+1
        lda ry1
        sta ov_cy
        lda #0
        sta ov_cy+1
        rts

; ---------------------------------------------------------------------
; ov_curve: OV_X[y] = half-width of row y (0..b) of an ellipse with
; half-widths a, b.  Midpoint algorithm, all terms times 4 so they stay
; whole numbers, in 32 bits.
; ---------------------------------------------------------------------
; 32 bit arithmetic on the variables below: X = destination, Y = source,
; as offsets from ov_v
!macro add32 .d, .s {
        ldx #.d-ov_v
        ldy #.s-ov_v
        jsr ov_add
}
!macro sub32 .d, .s {
        ldx #.d-ov_v
        ldy #.s-ov_v
        jsr ov_sub
}
ov_add: clc
        lda ov_v,x
        adc ov_v,y
        sta ov_v,x
        lda ov_v+1,x
        adc ov_v+1,y
        sta ov_v+1,x
        lda ov_v+2,x
        adc ov_v+2,y
        sta ov_v+2,x
        lda ov_v+3,x
        adc ov_v+3,y
        sta ov_v+3,x
        rts
ov_sub: sec
        lda ov_v,x
        sbc ov_v,y
        sta ov_v,x
        lda ov_v+1,x
        sbc ov_v+1,y
        sta ov_v+1,x
        lda ov_v+2,x
        sbc ov_v+2,y
        sta ov_v+2,x
        lda ov_v+3,x
        sbc ov_v+3,y
        sta ov_v+3,x
        rts
ov_v:
ov_a2:  !fill 4         ; a*a
ov_b2:  !fill 4
ov_a24: !fill 4         ; 4*a*a
ov_b24: !fill 4
ov_a28: !fill 4         ; 8*a*a
ov_b28: !fill 4
ov_dx:  !fill 4         ; 8*b*b*x
ov_dy:  !fill 4         ; 8*a*a*y
ov_d:   !fill 4         ; the decision value
ov_t:   !fill 4
ov_x:   !byte 0
ov_y:   !byte 0

ov_ca:  !byte 0          ; the curve in OV_X (b = $ff: none yet)
ov_cb:  !byte $ff
!zone ov_curve
ov_curve:
        lda ov_a                ; the same as last time: OV_X has it
        cmp ov_ca
        bne +
        lda ov_b
        cmp ov_cb
        bne +
        rts
+       lda ov_a
        sta ov_ca
        lda ov_b
        sta ov_cb
        lda ov_a                ; squares
        tax
        jsr mul8
        sta ov_a2
        stx ov_a2+1
        lda ov_b
        tax
        jsr mul8
        sta ov_b2
        stx ov_b2+1
        lda #0
        sta ov_a2+2
        sta ov_a2+3
        sta ov_b2+2
        sta ov_b2+3
        ldx #3                  ; 4*a2, 8*a2, 4*b2, 8*b2
-       lda ov_a2,x
        sta ov_a24,x
        lda ov_b2,x
        sta ov_b24,x
        dex
        bpl -
        ldx #2
-       asl ov_a24
        rol ov_a24+1
        rol ov_a24+2
        rol ov_a24+3
        asl ov_b24
        rol ov_b24+1
        rol ov_b24+2
        rol ov_b24+3
        dex
        bne -
        ldx #3
-       lda ov_a24,x
        sta ov_a28,x
        lda ov_b24,x
        sta ov_b28,x
        dex
        bpl -
        asl ov_a28
        rol ov_a28+1
        rol ov_a28+2
        rol ov_a28+3
        asl ov_b28
        rol ov_b28+1
        rol ov_b28+2
        rol ov_b28+3
        ; x = 0, y = b, dx = 0, dy = 8*a2*b
        lda #0
        sta ov_x
        ldx #3
-       sta ov_dx,x
        sta ov_dy,x
        dex
        bpl -
        lda ov_b
        sta ov_y
        beq +
        sta ov_x                ; (as a counter)
-       +add32 ov_dy, ov_a28
        dec ov_x
        bne -
+       ; d = 4*b2 - dy/2 + a2
        ldx #3
-       lda ov_dy,x
        sta ov_t,x
        lda ov_b24,x
        sta ov_d,x
        dex
        bpl -
        lsr ov_t+3
        ror ov_t+2
        ror ov_t+1
        ror ov_t
        +sub32 ov_d, ov_t
        +add32 ov_d, ov_a2
        ; region 1: while dx < dy
.r1:    lda ov_dx               ; dx - dy < 0 ?
        cmp ov_dy
        lda ov_dx+1
        sbc ov_dy+1
        lda ov_dx+2
        sbc ov_dy+2
        lda ov_dx+3
        sbc ov_dy+3
        bmi .bf627
        jmp .r2
.bf627:
        ldx ov_y
        lda ov_x
        sta OV_X,x
        inc ov_x
        +add32 ov_dx, ov_b28
        lda ov_d+3
        bmi +
        dec ov_y                ; d >= 0: y-- too
        +sub32 ov_dy, ov_a28
        +sub32 ov_d, ov_dy
+       +add32 ov_d, ov_dx
        +add32 ov_d, ov_b24
        jmp .r1
.r2:    ; d = d - (dx + dy)/2 + 3*(a2 - b2)
        ldx #3
-       lda ov_dx,x
        sta ov_t,x
        dex
        bpl -
        +add32 ov_t, ov_dy
        lsr ov_t+3
        ror ov_t+2
        ror ov_t+1
        ror ov_t
        +sub32 ov_d, ov_t
        ldx #3
-       lda ov_a2,x
        sta ov_t,x
        dex
        bpl -
        +sub32 ov_t, ov_b2
        +add32 ov_d, ov_t
        +add32 ov_d, ov_t
        +add32 ov_d, ov_t
        ; region 2: while y >= 0
.loop2: ldx ov_y
        bpl .bf664
        jmp .end
.bf664:
        lda ov_x
        sta OV_X,x
        dec ov_y
        +sub32 ov_dy, ov_a28
        lda ov_d+3              ; d > 0: only y moves
        bmi .both
        ora ov_d+2
        ora ov_d+1
        ora ov_d
        beq .both
        +add32 ov_d, ov_a24
        +sub32 ov_d, ov_dy
        jmp .loop2
.both:  inc ov_x
        +add32 ov_dx, ov_b28
        +add32 ov_d, ov_dx
        +sub32 ov_d, ov_dy
        +add32 ov_d, ov_a24
        jmp .loop2
.end:   lda ov_a                ; the middle row reaches a exactly
        sta OV_X
        rts

; ---------------------------------------------------------------------
; Drawing the spans
; ---------------------------------------------------------------------
ov_row:  !word 0        ; row of the span, signed
ov_yi:   !byte 0        ; quadrant row being drawn
ov_in:   !byte 0        ; inner half-width (frame)
ov_out:  !byte 0        ; outer half-width

; rx1 = cx - A, rx2 = cx + Y + ox (half-widths A on the left, Y on the right)
ov_span_x:
        sta t3
        sty t4
        sec
        lda ov_cx
        sbc t3
        sta rx1
        lda ov_cx+1
        sbc #0
        sta rx1+1
        clc
        lda ov_cx
        adc t4
        sta rx2
        lda ov_cx+1
        adc #0
        sta rx2+1
        clc
        lda rx2
        adc ov_ox
        sta rx2
        lda rx2+1
        adc ov_ox+1
        sta rx2+1
        rts

; fill rx1..rx2 on the rows of quadrant row ov_yi: above (cy - y) and
; below (cy + y + oy); once if they are the same row
!zone ov_rows
ov_rows:
        sec                     ; above
        lda ov_cy
        sbc ov_yi
        sta ov_row
        lda ov_cy+1
        sbc #0
        sta ov_row+1
        jsr ov_one
        lda ov_yi
        ora ov_oy
        beq .out
        clc                     ; below
        lda ov_cy
        adc ov_yi
        sta ov_row
        lda ov_cy+1
        adc #0
        sta ov_row+1
        clc
        lda ov_row
        adc ov_oy
        sta ov_row
        bcc ov_one
        inc ov_row+1
        ; fall through
ov_one:                         ; fill rx1..rx2 on row ov_row, if on screen
        lda ov_row+1
        bne .out
        lda ov_row
        cmp #200
        bcs .out
        sta ry1
        sta ry2
        jmp hline
.out:   rts

; ---------------------------------------------------------------------
; hline: fill rx1..rx2 (signed) on row ry1 in the pattern and mode,
; clipped.  The fast path for the spans of the curved shapes.
; ---------------------------------------------------------------------
hl_x1:  !word 0
hl_x2:  !word 0
hl_c1:  !byte 0
hl_c2:  !byte 0
hl_rm:  !byte 0
hl_pb:  !byte 0         ; the pattern's byte for this row
hl_pm:  !byte 0
hl_m:   !byte 0
!zone hline
hline:
        lda ry1                 ; clip
        cmp cly1
        bcc .out
        lda cly2
        cmp ry1
        bcc .out
        lda rx2+1
        bmi .out
        lda rx2                 ; x2 = min(rx2, clx2)
        sta hl_x2
        lda rx2+1
        sta hl_x2+1
        lda clx2
        cmp hl_x2
        lda clx2+1
        sbc hl_x2+1
        bcs +
        lda clx2
        sta hl_x2
        lda clx2+1
        sta hl_x2+1
+       lda rx1+1               ; x1 = max(rx1, clx1)
        bmi .clx1
        lda rx1
        cmp clx1
        lda rx1+1
        sbc clx1+1
        bcc .clx1
        lda rx1
        sta hl_x1
        lda rx1+1
        sta hl_x1+1
        jmp +
.clx1:  lda clx1
        sta hl_x1
        lda clx1+1
        sta hl_x1+1
+       lda hl_x2               ; nothing left
        cmp hl_x1
        lda hl_x2+1
        sbc hl_x1+1
        bcs +
.out:   rts
+       lda hl_x1+1             ; columns and edge masks
        lsr
        lda hl_x1
        ror
        lsr
        lsr
        sta hl_c1
        lda hl_x2+1
        lsr
        lda hl_x2
        ror
        lsr
        lsr
        sta hl_c2
        lda hl_x2
        and #7
        tax
        lda rmask_tab,x
        sta hl_rm
        lda ry1                 ; the pattern's byte
        and #7
        tay
        lda (pat),y
        sta hl_pb
        sty t0                  ; address of the first byte
        lda ry1
        lsr
        lsr
        lsr
        tax
        ldy hl_c1
        clc
        lda crow_lo,x
        adc col8_lo,y
        sta p0
        lda crow_hi,x
        adc col8_hi,y
        sta p0+1
        clc
        lda p0
        adc t0
        sta p0
        bcc +
        inc p0+1
+       lda hl_x1
        and #7
        tax
        lda lmask_tab,x
        ldy #0
        ldx hl_c1
        cpx hl_c2
        bne +
        and hl_rm               ; all in one byte
        jmp hl_apply
+       jsr hl_apply            ; first byte
        lda hl_c2               ; whole bytes in between
        sec
        sbc hl_c1
        tax
        dex
        beq .last
        lda rmode
        beq .copy
        cmp #M_XOR
        beq .xor
        cmp #M_BIC
        beq .bic
.or:
        tya
        clc
        adc #8
        tay
        bcc +
        inc p0+1
+       lda hl_pb
        ora (p0),y
        sta (p0),y
        dex
        bne .or
        beq .last
.xor:
        tya
        clc
        adc #8
        tay
        bcc +
        inc p0+1
+       lda hl_pb
        eor (p0),y
        sta (p0),y
        dex
        bne .xor
        beq .last
.bic:   lda hl_pb
        eor #$ff
        sta hl_pm
.bic2:
        tya
        clc
        adc #8
        tay
        bcc +
        inc p0+1
+       lda hl_pm
        and (p0),y
        sta (p0),y
        dex
        bne .bic2
        beq .last
.copy:
        tya
        clc
        adc #8
        tay
        bcc +
        inc p0+1
+       lda hl_pb
        sta (p0),y
        dex
        bne .copy
.last:  jsr hl_next
        lda hl_rm
        ; fall through
hl_apply:                       ; A = mask: one byte at (p0),y
        sta hl_m
        and hl_pb
        sta hl_pm
        lda rmode
        beq .acopy
        cmp #M_XOR
        beq .axor
        cmp #M_BIC
        beq .abic
        lda hl_pm
        ora (p0),y
        sta (p0),y
        rts
.axor:  lda hl_pm
        eor (p0),y
        sta (p0),y
        rts
.abic:  lda hl_pm
        eor #$ff
        and (p0),y
        sta (p0),y
        rts
.acopy: lda hl_m
        eor #$ff
        and (p0),y
        ora hl_pm
        sta (p0),y
        rts
hl_next:                        ; the next byte along: 8 further on
        tya
        clc
        adc #8
        tay
        bcc +
        inc p0+1
+       rts

; the middle rows cy+1 .. cy+oy-1 (the straight sides), rx1..rx2
!zone ov_middle
ov_middle:
        lda ov_oy
        cmp #2
        bcc .out
        clc                     ; first = cy + 1, last = cy + oy - 1
        lda ov_cy
        adc #1
        sta t5
        lda ov_cy+1
        adc #0
        sta t6
        clc
        lda ov_cy
        adc ov_oy
        sta t7
        lda ov_cy+1
        adc #0
        tax
        lda t7
        bne +
        dex
+       dec t7
        txa                     ; last < 0: nothing
        bmi .out
        bne +                   ; last beyond the screen: 199
        lda t7
        cmp #200
        bcc ++
+       lda #199
        sta t7
++      lda t6                  ; first beyond the screen: nothing
        bmi +
        bne .out
        lda t5
        cmp #200
        bcs .out
        bcc ++
+       lda #0                  ; first above the screen: 0
        sta t5
++      lda t5
        sta ry1
        lda t7
        sta ry2
        cmp ry1
        bcc .out
        jmp fill_rect
.out:   rts

; filled: one span per row, then the middle as one rect
!zone ov_fill
ov_fill:
        jsr ov_curve
        lda ov_b
        sta ov_yi
.row:   ldx ov_yi
        lda OV_X,x
        tay
        jsr ov_span_x
        jsr ov_rows
        dec ov_yi
        bpl .row
        lda OV_X
        tay
        jsr ov_span_x
        jmp ov_middle

; outline: on each row, the part of the curve not covered by the row
; nearer the top or bottom
!zone ov_frame
ov_frame:
        jsr ov_curve
        lda ov_b
        sta ov_yi
        ; top and bottom rows: the whole span
        tax
        lda OV_X,x
        tay
        jsr ov_span_x
        jsr ov_rows
.row:   dec ov_yi
        bmi .sides
        ldx ov_yi
        lda OV_X,x
        sta ov_out
        lda OV_X+1,x            ; inner = the row before, at most out - 1
        cmp ov_out
        bcc +
        lda ov_out
        beq .one                ; a single pixel wide column
        sec
        sbc #1
+       sta ov_in
        ; left: cx - out .. cx - in - 1
        lda ov_out
        ldy #0
        jsr ov_span_x
        sec
        lda ov_cx
        sbc ov_in
        sta rx2
        lda ov_cx+1
        sbc #0
        sta rx2+1
        lda rx2
        bne +
        dec rx2+1
+       dec rx2
        jsr ov_rows
        ; right: cx + in + 1 + ox .. cx + out + ox
        ldy ov_out
        lda #0
        jsr ov_span_x
        ldy ov_in
        iny
        lda #0
        jsr ov_span_x_left
        jsr ov_rows
        jmp .row
.one:   lda #0                  ; out = 0: cx .. cx + ox
        tay
        jsr ov_span_x
        jsr ov_rows
        jmp .row
.sides: ; the straight sides of the middle
        lda OV_X
        tay
        jsr ov_span_x           ; left side: x = cx - OV_X[0]
        lda rx1
        sta rx2
        lda rx1+1
        sta rx2+1
        jsr ov_middle
        lda #0                  ; right side: x = cx + OV_X[0] + ox
        ldy OV_X
        jsr ov_span_x
        lda OV_X
        ora ov_ox
        ora ov_ox+1
        beq .out                ; the same column as the left side
        lda rx2
        sta rx1
        lda rx2+1
        sta rx1+1
        jmp ov_middle
.out:   rts

; rx1 = cx + Y + ox (keeps rx2)
ov_span_x_left:
        sty t4
        clc
        lda ov_cx
        adc t4
        sta rx1
        lda ov_cx+1
        adc #0
        sta rx1+1
        clc
        lda rx1
        adc ov_ox
        sta rx1
        lda rx1+1
        adc ov_ox+1
        sta rx1+1
        rts
