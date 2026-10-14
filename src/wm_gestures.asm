; =====================================================================
; wm_gestures.asm - tracking the close and zoom boxes, dragging,
; growing and zooming windows, and the zoom-rect animation.
; Part of the Interface overlay (src/ovl_interface.asm).
; =====================================================================

; ---------------------------------------------------------------------
; track_box: rx1..ry2 = box.  Inverts its inside while the pointer is
; in it and the button is down.  Carry clear = released inside.
; ---------------------------------------------------------------------
tb_rect: !fill 6
tb_on:   !byte 0
!zone track_box
track_box:
        lda #1
        jsr rect_inset
        ldy #5
-       lda rx1,y
        sta tb_rect,y
        dey
        bpl -
        lda #0
        sta tb_on
        jsr clip_push
        jsr clip_screen
.loop:  jsr .load
        jsr rect_outset1
        jsr mouse_in_rect
        lda #0
        bcs +
        lda #1
+       cmp tb_on
        beq +
        sta tb_on
        jsr .load
        jsr invert_rect
+       jsr wait_frame
        lda mbtn
        bne .loop
        lda tb_on
        beq +
        jsr .load
        jsr invert_rect
+       jsr clip_pop
        lda tb_on
        cmp #1                  ; carry set if on
        eor #1
        lsr                     ; carry = !on
        rts
.load:  ldy #5
-       lda tb_rect,y
        sta rx1,y
        dey
        bpl -
        rts
rect_outset1:
        lda #1
        jmp rect_outset

; ---------------------------------------------------------------------
; XOR outlines (dragging, growing, zoom rects).  Grey dotted frame.
; ---------------------------------------------------------------------
xor_frame:
        jsr clip_push
        jsr clip_screen
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        lda #M_XOR
        sta rmode
        jsr frame_rect
        jmp clip_pop

; ---------------------------------------------------------------------
; win_drag: drag window X by its title bar
; ---------------------------------------------------------------------
dg_id:  !byte 0
dg_mx:  !word 0
dg_my:  !byte 0
dg_dx:  !word 0
dg_dy:  !byte 0
dg_ndx: !word 0
dg_ndy: !byte 0
dg_minx: !word 0
dg_maxx: !word 0
dg_miny: !word 0
dg_maxy: !word 0
dg_r:   !fill 6

!zone win_drag
win_drag:
        stx dg_id
        lda modkeys             ; Command-drag keeps it in the back
        and #MOD_CMD
        bne +
        jsr win_select
+       ldx dg_id
        jsr win_get_rect
        ldy #5
-       lda rx1,y
        sta dg_r,y
        dey
        bpl -
        ; limits for dx: -x1 .. 318-x2 ; dy: 12-y1 .. 198-y2
        sec
        lda #0
        sbc dg_r
        sta dg_minx
        lda #0
        sbc dg_r+1
        sta dg_minx+1
        sec
        lda #<318
        sbc dg_r+3
        sta dg_maxx
        lda #>318
        sbc dg_r+4
        sta dg_maxx+1
        sec
        lda #DESK_Y1
        sbc dg_r+2
        sta dg_miny
        lda #0
        sbc #0
        sta dg_miny+1
        sec
        lda #198
        sbc dg_r+5
        sta dg_maxy
        lda #0
        sbc #0
        sta dg_maxy+1
        lda mouse_x
        sta dg_mx
        lda mouse_x+1
        sta dg_mx+1
        lda mouse_y
        sta dg_my
        lda #0
        sta dg_dx
        sta dg_dx+1
        sta dg_dy
        jsr dg_outline
.loop:  jsr wait_frame
        jsr dg_delta
        lda dg_ndx
        cmp dg_dx
        bne .moved
        lda dg_ndx+1
        cmp dg_dx+1
        bne .moved
        lda dg_ndy
        cmp dg_dy
        beq .same
.moved: jsr dg_outline
        lda dg_ndx
        sta dg_dx
        lda dg_ndx+1
        sta dg_dx+1
        lda dg_ndy
        sta dg_dy
        jsr dg_outline
.same:  lda mbtn
        bne .loop
        jsr dg_outline
        lda dg_dx
        ora dg_dx+1
        ora dg_dy
        beq .out
        ; move
        jsr dg_newrect
        ldy #5
-       lda rx1,y
        sta rn_x1,y
        dey
        bpl -
        ldx dg_id
        lda zlist
        cmp dg_id
        beq +
        jsr win_select          ; Command-dragged: now bring it forward
        ldx dg_id
+       jmp win_set_rect
.out:   rts

; outline at dg_r + (dg_dx, dg_dy)
dg_outline:
        jsr dg_newrect
        jmp xor_frame
dg_newrect:
        clc
        lda dg_r
        adc dg_dx
        sta rx1
        lda dg_r+1
        adc dg_dx+1
        sta rx1+1
        clc
        lda dg_r+3
        adc dg_dx
        sta rx2
        lda dg_r+4
        adc dg_dx+1
        sta rx2+1
        clc
        lda dg_r+2
        adc dg_dy
        sta ry1
        clc
        lda dg_r+5
        adc dg_dy
        sta ry2
        rts

; new delta from the mouse, clamped
dg_delta:
        sec
        lda mouse_x
        sbc dg_mx
        sta dg_ndx
        lda mouse_x+1
        sbc dg_mx+1
        sta dg_ndx+1
        ; clamp to dg_minx..dg_maxx (signed)
        lda dg_ndx
        cmp dg_minx
        lda dg_ndx+1
        sbc dg_minx+1
        bvc +
        eor #$80
+       bpl +
        lda dg_minx
        sta dg_ndx
        lda dg_minx+1
        sta dg_ndx+1
+       lda dg_maxx
        cmp dg_ndx
        lda dg_maxx+1
        sbc dg_ndx+1
        bvc +
        eor #$80
+       bpl +
        lda dg_maxx
        sta dg_ndx
        lda dg_maxx+1
        sta dg_ndx+1
+       ; dy (signed 8 bit range is enough: -199..199 does not fit, use 16)
        sec
        lda mouse_y
        sbc dg_my
        sta t0
        lda #0
        sbc #0
        sta t1                  ; t0/t1 = signed dy
        lda dg_miny
        sta t2
        lda dg_miny+1
        sta t3
        lda t0
        cmp t2
        lda t1
        sbc t3
        bvc +
        eor #$80
+       bpl +
        lda t2
        sta t0
        lda t3
        sta t1
+       lda dg_maxy
        sta t2
        lda dg_maxy+1
        sta t3
        lda t2
        cmp t0
        lda t3
        sbc t1
        bvc +
        eor #$80
+       bpl +
        lda t2
        sta t0
+       lda t0
        sta dg_ndy
        rts

; ---------------------------------------------------------------------
; win_grow: resize the front window X from its grow box
; ---------------------------------------------------------------------
gw_minw = 90
gw_minh = 60
!zone win_grow
win_grow:
        stx dg_id
        jsr win_get_rect
        ldy #5
-       lda rx1,y
        sta dg_r,y
        dey
        bpl -
        ; limits: x2 in x1+minw .. 318 ; y2 in y1+minh .. 198
        ; expressed as deltas for dg_delta
        clc
        lda dg_r
        adc #gw_minw
        sta t0
        lda dg_r+1
        adc #0
        sta t1
        sec
        lda t0
        sbc dg_r+3
        sta dg_minx
        lda t1
        sbc dg_r+4
        sta dg_minx+1
        sec
        lda #<318
        sbc dg_r+3
        sta dg_maxx
        lda #>318
        sbc dg_r+4
        sta dg_maxx+1
        lda dg_r+2
        clc
        adc #gw_minh
        sec
        sbc dg_r+5
        sta dg_miny
        lda #0
        sbc #0
        sta dg_miny+1
        sec
        lda #198
        sbc dg_r+5
        sta dg_maxy
        lda #0
        sbc #0
        sta dg_maxy+1
        lda mouse_x
        sta dg_mx
        lda mouse_x+1
        sta dg_mx+1
        lda mouse_y
        sta dg_my
        lda #0
        sta dg_dx
        sta dg_dx+1
        sta dg_dy
        jsr gw_outline
.loop:  jsr wait_frame
        jsr dg_delta
        lda dg_ndx
        cmp dg_dx
        bne .moved
        lda dg_ndx+1
        cmp dg_dx+1
        bne .moved
        lda dg_ndy
        cmp dg_dy
        beq .same
.moved: jsr gw_outline
        lda dg_ndx
        sta dg_dx
        lda dg_ndx+1
        sta dg_dx+1
        lda dg_ndy
        sta dg_dy
        jsr gw_outline
.same:  lda mbtn
        bne .loop
        jsr gw_outline
        lda dg_dx
        ora dg_dx+1
        ora dg_dy
        beq .out
        jsr gw_newrect
        ldy #5
-       lda rx1,y
        sta rn_x1,y
        dey
        bpl -
        ldx dg_id
        lda #0
        sta w_zoomed,x
        jmp win_set_rect
.out:   rts

gw_newrect:
        ldy #5
-       lda dg_r,y
        sta rx1,y
        dey
        bpl -
        clc
        lda dg_r+3
        adc dg_dx
        sta rx2
        lda dg_r+4
        adc dg_dx+1
        sta rx2+1
        clc
        lda dg_r+5
        adc dg_dy
        sta ry2
        rts
gw_outline:
        jsr gw_newrect
        jsr xor_frame
        ; title bar line too
        jsr gw_newrect
        lda ry1
        clc
        adc #TITLE_H-1
        sta ry1
        sta ry2
        jsr clip_push
        jsr clip_screen
        inc rx1
        bne +
        inc rx1+1
+       lda rx2
        bne +
        dec rx2+1
+       dec rx2
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        lda #M_XOR
        sta rmode
        jsr fill_rect
        jmp clip_pop

; ---------------------------------------------------------------------
; win_zoom: toggle between the user size and nearly full screen
; ---------------------------------------------------------------------
!zone win_zoom
win_zoom:
        stx dg_id
        lda w_zoomed,x
        bne .unzoom
        lda w_x1l,x
        sta w_zx1l,x
        lda w_x1h,x
        sta w_zx1h,x
        lda w_y1,x
        sta w_zy1,x
        lda w_x2l,x
        sta w_zx2l,x
        lda w_x2h,x
        sta w_zx2h,x
        lda w_y2,x
        sta w_zy2,x
        lda #1
        sta w_zoomed,x
        lda #<4
        sta rn_x1
        lda #>4
        sta rn_x1+1
        lda #DESK_Y1+3
        sta rn_y1
        lda #<314
        sta rn_x2
        lda #>314
        sta rn_x2+1
        lda #196
        sta rn_y2
        jmp win_set_rect
.unzoom:
        lda #0
        sta w_zoomed,x
        lda w_zx1l,x
        sta rn_x1
        lda w_zx1h,x
        sta rn_x1+1
        lda w_zy1,x
        sta rn_y1
        lda w_zx2l,x
        sta rn_x2
        lda w_zx2h,x
        sta rn_x2+1
        lda w_zy2,x
        sta rn_y2
        jmp win_set_rect

; ---------------------------------------------------------------------
; Zoom rects (the Finder's opening/closing animation)
; zr_* = small rect (icon), rx1..ry2 = window rect
; ---------------------------------------------------------------------
zb_r:   !fill 6
zr_dir: !byte 0
zr_step: !byte 0

zoom_to_rect:
        lda #0
        beq +
zoom_from_rect:
        lda #1
+       sta zr_dir
        ldy #5
-       lda rx1,y
        sta zb_r,y
        dey
        bpl -
        ; draw 8 steps, then erase them
        lda #1
        sta zr_step
-       jsr zr_rect
        jsr xor_frame
        jsr wait_frame
        inc zr_step
        lda zr_step
        cmp #9
        bne -
        lda #1
        sta zr_step
-       jsr zr_rect
        jsr xor_frame
        inc zr_step
        lda zr_step
        cmp #9
        bne -
        rts

; rect for step zr_step (1..8), from zr_* towards zb_r (or back)
!zone zr_rect
zr_rect:
        lda zr_step
        ldx zr_dir
        beq +
        lda #9
        sec
        sbc zr_step
+       sta t7                  ; fraction in eighths
        ldx #0                  ; x1
        jsr .lerpx
        sta rx1
        sty rx1+1
        ldx #3                  ; x2
        jsr .lerpx
        sta rx2
        sty rx2+1
        ldx #2
        jsr .lerpy
        sta ry1
        ldx #5
        jsr .lerpy
        sta ry2
        rts
.lerpx: ; a = zr[x], b = zb[x] (16 bit) -> a + (b-a)*t7/8
        sec
        lda zb_r,x
        sbc zr_x1,x
        sta t0
        lda zb_r+1,x
        sbc zr_x1+1,x
        sta t1
        jsr .mul
        clc
        lda t2
        adc zr_x1,x
        pha
        lda t3
        adc zr_x1+1,x
        tay
        pla
        rts
.lerpy: sec
        lda zb_r,x
        sbc zr_x1,x
        sta t0
        lda #0
        sbc #0
        sta t1
        jsr .mul
        clc
        lda t2
        adc zr_x1,x
        rts
.mul:   ; t2/t3 = (t0/t1 signed) * t7 / 8
        lda #0
        sta t2
        sta t3
        ldy t7
-       clc
        lda t2
        adc t0
        sta t2
        lda t3
        adc t1
        sta t3
        dey
        bne -
        ldy #3
-       lda t3
        cmp #$80
        ror t3
        ror t2
        dey
        bne -
        rts
