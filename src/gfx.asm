; =====================================================================
; gfx.asm - drawing on the 320x200 hires bitmap (bit set = black)
;
; Everything is clipped to the clip rectangle clx1/cly1-clx2/cly2.
; Rectangles are inclusive.  Patterns are 8 bytes, aligned to the
; screen (row = y & 7), exactly like QuickDraw patterns.
; =====================================================================

BITMAP  = $e000
SHR_TAB = $b000         ; page s: x >> s
SHL_TAB = $b800         ; page s: x << (8-s)
STRIP   = $a000         ; 42 columns x 48 rows, column major
MSTRIP  = STRIP + $800  ; mask strip, same layout
STRIP_H = 48
STRIP_W = 42

M_COPY  = 0             ; fill modes
M_OR    = 1
M_XOR   = 2
M_BIC   = 3

B_OR    = 0             ; strip blit modes
B_XOR   = 1
B_BIC   = 2
B_MASK  = 3
B_COPY  = 4
B_MASKGRAY = 5

ICON_SEL     = $01      ; draw_icon flags
ICON_OUTLINE = $02
ICON_PLAIN   = $04
ICON_OPEN    = $08      ; fill the inside with grey (an opened disk/folder)

; ---------------------------------------------------------------------
; tables
; ---------------------------------------------------------------------
crow_lo:  !for r, 0, 24 { !byte <(BITMAP + r*320) }
crow_hi:  !for r, 0, 24 { !byte >(BITMAP + r*320) }
col8_lo:  !for c, 0, 40 { !byte <(c*8) }
col8_hi:  !for c, 0, 40 { !byte >(c*8) }
scol_lo:  !for k, 0, STRIP_W { !byte <(STRIP + k*STRIP_H) }
scol_hi:  !for k, 0, STRIP_W { !byte >(STRIP + k*STRIP_H) }
lmask_tab: !byte $ff,$7f,$3f,$1f,$0f,$07,$03,$01
rmask_tab: !byte $80,$c0,$e0,$f0,$f8,$fc,$fe,$ff
bit_tab:   !byte $80,$40,$20,$10,$08,$04,$02,$01

pat_black: !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
pat_white: !byte $00,$00,$00,$00,$00,$00,$00,$00
pat_gray:  !byte $aa,$55,$aa,$55,$aa,$55,$aa,$55
pat_ltgray: !byte $88,$22,$88,$22,$88,$22,$88,$22
pat_even:  !byte $ff,$00,$ff,$00,$ff,$00,$ff,$00
pat_odd:   !byte $00,$ff,$00,$ff,$00,$ff,$00,$ff

fmlast: !byte 0
andm:   !fill 8
orm:    !fill 8

; ---------------------------------------------------------------------
; init_gfx: build shift tables, clear strips, full-screen clip
; ---------------------------------------------------------------------
init_gfx:
        ldx #0
-       txa
        sta SHR_TAB+$000,x
        lsr
        sta SHR_TAB+$100,x
        lsr
        sta SHR_TAB+$200,x
        lsr
        sta SHR_TAB+$300,x
        lsr
        sta SHR_TAB+$400,x
        lsr
        sta SHR_TAB+$500,x
        lsr
        sta SHR_TAB+$600,x
        lsr
        sta SHR_TAB+$700,x
        txa
        asl
        sta SHL_TAB+$700,x
        asl
        sta SHL_TAB+$600,x
        asl
        sta SHL_TAB+$500,x
        asl
        sta SHL_TAB+$400,x
        asl
        sta SHL_TAB+$300,x
        asl
        sta SHL_TAB+$200,x
        asl
        sta SHL_TAB+$100,x
        lda #0
        sta SHL_TAB+$000,x
        inx
        bne -
        ; clear both strips ($a000-$afff)
        lda #<STRIP
        sta p0
        lda #>STRIP
        sta p0+1
        ldx #16
        lda #0
        tay
-       sta (p0),y
        iny
        bne -
        inc p0+1
        dex
        bne -
        ; fall through
clip_screen:
        lda #0
        sta clx1
        sta clx1+1
        sta cly1
        lda #<319
        sta clx2
        lda #>319
        sta clx2+1
        lda #199
        sta cly2
        rts

; ---------------------------------------------------------------------
; clip stack
; ---------------------------------------------------------------------
clip_sp: !byte 0
clip_stack: !fill 6*8

clip_push:                      ; preserves X and Y
        stx clip_sx
        ldx clip_sp
        lda clx1
        sta clip_stack,x
        lda clx1+1
        sta clip_stack+1,x
        lda cly1
        sta clip_stack+2,x
        lda clx2
        sta clip_stack+3,x
        lda clx2+1
        sta clip_stack+4,x
        lda cly2
        sta clip_stack+5,x
        txa
        clc
        adc #6
        sta clip_sp
        ldx clip_sx
        rts
clip_sx: !byte 0

clip_pop:                       ; preserves X and Y
        stx clip_sx
        lda clip_sp
        sec
        sbc #6
        sta clip_sp
        tax
        lda clip_stack,x
        sta clx1
        lda clip_stack+1,x
        sta clx1+1
        lda clip_stack+2,x
        sta cly1
        lda clip_stack+3,x
        sta clx2
        lda clip_stack+4,x
        sta clx2+1
        lda clip_stack+5,x
        sta cly2
        ldx clip_sx
        rts

; clip = clip AND rect.  Returns carry set if the result is empty.
!zone clip_rect
clip_rect:
        ; clx1 = max(clx1, rx1)
        lda clx1
        cmp rx1
        lda clx1+1
        sbc rx1+1
        bcs +
        lda rx1
        sta clx1
        lda rx1+1
        sta clx1+1
+       ; clx2 = min(clx2, rx2)
        lda rx2
        cmp clx2
        lda rx2+1
        sbc clx2+1
        bcs +
        lda rx2
        sta clx2
        lda rx2+1
        sta clx2+1
+       lda cly1
        cmp ry1
        bcs +
        lda ry1
        sta cly1
+       lda ry2
        cmp cly2
        bcs +
        sta cly2
+       ; empty?
        lda cly2
        cmp cly1
        bcc .empty
        lda clx2
        cmp clx1
        lda clx2+1
        sbc clx1+1
        bcc .empty
        clc
        rts
.empty: sec
        rts

; Does rect intersect the clip rectangle?  Carry clear = yes.
!zone rect_visible
rect_visible:
        lda rx2                 ; rx2 < clx1 -> no
        cmp clx1
        lda rx2+1
        sbc clx1+1
        bcc .no
        lda clx2                ; clx2 < rx1 -> no
        cmp rx1
        lda clx2+1
        sbc rx1+1
        bcc .no
        lda ry2
        cmp cly1
        bcc .no
        lda cly2
        cmp ry1
        bcc .no
        clc
        rts
.no:    sec
        rts

; ---------------------------------------------------------------------
; set_pat: A/Y = pattern address.  set_black etc. also set M_COPY.
; ---------------------------------------------------------------------
set_black:
        lda #<pat_black
        ldy #>pat_black
        bne set_pat_copy
set_white:
        lda #<pat_white
        ldy #>pat_white
        bne set_pat_copy
set_gray:
        lda #<pat_gray
        ldy #>pat_gray
set_pat_copy:
        sta pat
        sty pat+1
        lda #M_COPY
        sta rmode
        rts

; ---------------------------------------------------------------------
; fill_rect: fill rx1,ry1 - rx2,ry2 with pattern pat in mode rmode
; Preserves the rect parameters.
; ---------------------------------------------------------------------
!zone fill_rect
fill_rect:
        lda rx1                 ; fx1 = max(rx1, clx1)
        sta fx1
        lda rx1+1
        sta fx1+1
        lda fx1
        cmp clx1
        lda fx1+1
        sbc clx1+1
        bcs +
        lda clx1
        sta fx1
        lda clx1+1
        sta fx1+1
+       lda rx2                 ; fx2 = min(rx2, clx2)
        sta fx2
        lda rx2+1
        sta fx2+1
        lda clx2
        cmp fx2
        lda clx2+1
        sbc fx2+1
        bcs +
        lda clx2
        sta fx2
        lda clx2+1
        sta fx2+1
+       lda fx2                 ; fx2 < fx1 -> nothing
        cmp fx1
        lda fx2+1
        sbc fx1+1
        bcs .bf296
        jmp .ret
.bf296:
        lda ry1
        cmp cly1
        bcs +
        lda cly1
+       sta fy1
        lda ry2
        cmp cly2
        bcc +
        lda cly2
+       sta fy2
        cmp fy1
        bcs .bf308
        jmp .ret
.bf308:
        sec                     ; fcnt = rows
        sbc fy1
        adc #0
        sta fcnt
        lda fx1+1               ; columns
        lsr
        lda fx1
        ror
        lsr
        lsr
        sta fc1
        lda fx2+1
        lsr
        lda fx2
        ror
        lsr
        lsr
        sta fc2
        lda fx1
        and #7
        tax
        lda lmask_tab,x
        sta flm
        lda fx2
        and #7
        tax
        lda rmask_tab,x
        sta frm
        lda fy1
        and #7
        sta fyoff
        lda fy1
        lsr
        lsr
        lsr
        tax
        lda crow_lo,x
        sta fbase
        lda crow_hi,x
        sta fbase+1
        lda #$19                ; ORA abs,y
        ldx rmode
        cpx #M_XOR
        bne +
        lda #$59                ; EOR abs,y
+       sta .op
        lda #0                  ; no masks built yet
        sta fmlast
        ldx fc1
.col:   stx fcol
        lda #$ff
        cpx fc1
        bne +
        and flm
+       cpx fc2
        bne +
        and frm
+       sta fmask
        cmp fmlast              ; same column mask as before: reuse
        bne +
        jmp .mdone
+       sta fmlast
        ; masks for the 8 pattern rows
        ldy #7
.bm:    lda (pat),y
        and fmask
        sta fpm
        lda rmode
        beq .mcopy
        cmp #M_BIC
        beq .mbic
        lda #$ff                ; OR / XOR
        sta andm,y
        lda fpm
        sta orm,y
        jmp .mnext
.mcopy: lda fmask
        eor #$ff
        sta andm,y
        lda fpm
        sta orm,y
        jmp .mnext
.mbic:  lda fpm
        eor #$ff
        sta andm,y
        lda #0
        sta orm,y
.mnext: dey
        bpl .bm
.mdone: clc
        lda fbase
        adc col8_lo,x
        sta p0
        lda fbase+1
        adc col8_hi,x
        sta p0+1
        ldx fcnt
        ldy fyoff
        lda fmask               ; whole byte, copy mode: just store
        cmp #$ff
        bne .row
        lda rmode
        bne .row
.fast:  lda orm,y
        sta (p0),y
        dex
        beq .cdone
        iny
        cpy #8
        bne .fast
        ldy #0
        lda p0
        clc
        adc #<320
        sta p0
        lda p0+1
        adc #>320
        sta p0+1
        jmp .fast
.row:   lda (p0),y
        and andm,y
.op:    ora orm,y
        sta (p0),y
        dex
        beq .cdone
        iny
        cpy #8
        bne .row
        ldy #0
        lda p0
        clc
        adc #<320
        sta p0
        lda p0+1
        adc #>320
        sta p0+1
        jmp .row
.cdone: ldx fcol
        cpx fc2
        beq .ret
        inx
        jmp .col
.ret:   rts

; Shorthands taking the rect from rx1..ry2
fill_black:
        jsr set_black
        jmp fill_rect
fill_white:
        jsr set_white
        jmp fill_rect
invert_rect:
        jsr set_black
        lda #M_XOR
        sta rmode
        jmp fill_rect

; ---------------------------------------------------------------------
; frame_rect: 1 pixel outline of rx1..ry2 with current pattern/mode.
; Corners are drawn once, so it is safe in XOR mode.
; ---------------------------------------------------------------------
fr_save: !fill 6
!zone frame_rect
frame_rect:
        jsr rect_save
        lda fr_save+2           ; top
        sta ry2
        jsr fill_rect
        lda fr_save+5           ; bottom
        cmp fr_save+2
        beq .done
        sta ry1
        sta ry2
        jsr fill_rect
        ldx fr_save+2           ; sides, if there is room between
        inx
        cpx fr_save+5
        beq .done
        stx ry1
        ldx fr_save+5
        dex
        stx ry2
        lda fr_save
        sta rx1
        sta rx2
        lda fr_save+1
        sta rx1+1
        sta rx2+1
        jsr fill_rect
        lda fr_save+3
        sta rx1
        sta rx2
        lda fr_save+4
        sta rx1+1
        sta rx2+1
        jsr fill_rect
.done:  jmp rect_restore

rect_save:
        ldx #5
-       lda rx1,x
        sta fr_save,x
        dex
        bpl -
        rts
rect_restore:
        ldx #5
-       lda fr_save,x
        sta rx1,x
        dex
        bpl -
        rts

; Rounded rectangle outline (corner radius 2), black
!zone frame_round
frame_round:
        jsr rect_save
        jsr set_black
        ; top and bottom lines, inset by 2
        jsr .inset_x
        lda fr_save+2
        sta ry1
        sta ry2
        jsr fill_rect
        lda fr_save+5
        sta ry1
        sta ry2
        jsr fill_rect
        ; sides inset by 2 vertically
        jsr rect_restore
        ldx fr_save+2
        inx
        inx
        stx ry1
        ldx fr_save+5
        dex
        dex
        stx ry2
        lda rx1
        sta rx2
        lda rx1+1
        sta rx2+1
        jsr fill_rect
        lda fr_save+3
        sta rx1
        sta rx2
        lda fr_save+4
        sta rx1+1
        sta rx2+1
        jsr fill_rect
        ; corner pixels
        jsr rect_restore
        jsr .inset1
        lda fr_save+2
        clc
        adc #1
        sta ry1
        sta ry2
        jsr .plot2
        lda fr_save+5
        sec
        sbc #1
        sta ry1
        sta ry2
        jsr .plot2
        jmp rect_restore
.plot2: ; plot (x1+1, ry1) and (x2-1, ry1)
        lda t6
        sta rx1
        sta rx2
        lda t7
        sta rx1+1
        sta rx2+1
        jsr fill_rect
        lda t4
        sta rx1
        sta rx2
        lda t5
        sta rx1+1
        sta rx2+1
        jmp fill_rect
.inset_x:
        clc
        lda fr_save
        adc #2
        sta rx1
        lda fr_save+1
        adc #0
        sta rx1+1
        sec
        lda fr_save+3
        sbc #2
        sta rx2
        lda fr_save+4
        sbc #0
        sta rx2+1
        rts
.inset1: ; t6/t7 = x1+1, t4/t5 = x2-1
        clc
        lda fr_save
        adc #1
        sta t6
        lda fr_save+1
        adc #0
        sta t7
        sec
        lda fr_save+3
        sbc #1
        sta t4
        lda fr_save+4
        sbc #0
        sta t5
        rts

; ---------------------------------------------------------------------
; Rect helpers.  rect_inset: shrink rx1..ry2 by A pixels on each side.
; ---------------------------------------------------------------------
rect_inset:
        sta t0
        clc
        lda rx1
        adc t0
        sta rx1
        bcc +
        inc rx1+1
+       sec
        lda rx2
        sbc t0
        sta rx2
        bcs +
        dec rx2+1
+       lda ry1
        clc
        adc t0
        sta ry1
        lda ry2
        sec
        sbc t0
        sta ry2
        rts

; rect_outset: grow by A pixels (no clamping, callers keep it on screen)
rect_outset:
        sta t0
        sec
        lda rx1
        sbc t0
        sta rx1
        bcs +
        dec rx1+1
+       clc
        lda rx2
        adc t0
        sta rx2
        bcc +
        inc rx2+1
+       lda ry1
        sec
        sbc t0
        sta ry1
        lda ry2
        clc
        adc t0
        sta ry2
        rts

; ---------------------------------------------------------------------
; Fonts
; ---------------------------------------------------------------------
!zone font_setup
font_setup:
        lda font
        bne .small
        lda #<sysfont_width
        sta fwid
        lda #>sysfont_width
        sta fwid+1
        lda #<sysfont_lo
        sta flo
        lda #>sysfont_lo
        sta flo+1
        lda #<sysfont_hi
        sta fhi
        lda #>sysfont_hi
        sta fhi+1
        lda #sysfont_height
        sta fheight
        rts
.small: lda #<smallfont_width
        sta fwid
        lda #>smallfont_width
        sta fwid+1
        lda #<smallfont_lo
        sta flo
        lda #>smallfont_lo
        sta flo+1
        lda #<smallfont_hi
        sta fhi
        lda #>smallfont_hi
        sta fhi+1
        lda #smallfont_height
        sta fheight
        rts

; text_width: width of string tstr in font -> twidth (16 bit), A = low byte
text_width:
        jsr font_setup
        lda #0
        sta twidth
        sta twidth+1
        ldy #0
-       lda (tstr),y
        beq +
        sty tsi
        tay
        lda (fwid),y
        clc
        adc twidth
        sta twidth
        bcc ++
        inc twidth+1
++      ldy tsi
        iny
        bne -
+       lda twidth
        rts

; char_width: A = char -> A = advance in current font (call font_setup first)
char_width:
        sty tsi
        tay
        lda (fwid),y
        ldy tsi
        rts

; ---------------------------------------------------------------------
; draw_text: string tstr at tx,ty in font, blit mode tmode, clipped.
; The glyph top row is drawn at ty.  Leaves twidth = pixel width.
; ---------------------------------------------------------------------
!zone draw_text
draw_text:
        jsr font_setup
        lda tx
        and #7
        sta tpos
        lda #0
        sta tpos+1
        ldy #0
.ch:    lda (tstr),y
        beq .end
        sty tsi
        tay
        lda (fwid),y
        beq .next
        sta t2
        lda (flo),y
        sta p1
        lda (fhi),y
        sta p1+1
        lda tpos+1
        lsr
        lda tpos
        ror
        lsr
        lsr
        tax
        cpx #STRIP_W-1
        bcs .end
        lda scol_lo,x
        sta p2
        lda scol_hi,x
        sta p2+1
        lda scol_lo+1,x
        sta p3
        lda scol_hi+1,x
        sta p3+1
        lda tpos
        and #7
        clc
        adc #>SHR_TAB
        sta .s1+2
        adc #8
        sta .s2+2
        ldy fheight
        dey
.gl:    lda (p1),y
        tax
        lda (p2),y
.s1:    ora SHR_TAB,x
        sta (p2),y
        lda (p3),y
.s2:    ora SHL_TAB,x
        sta (p3),y
        dey
        bpl .gl
        clc
        lda tpos
        adc t2
        sta tpos
        bcc .next
        inc tpos+1
.next:  ldy tsi
        iny
        bne .ch
.end:   lda tx
        and #7
        sta t0
        sec
        lda tpos
        sbc t0
        sta twidth
        lda tpos+1
        sbc #0
        sta twidth+1
        ; columns used = (tpos + 7) >> 3
        clc
        lda tpos
        adc #7
        sta t0
        lda tpos+1
        adc #0
        lsr
        lda t0
        ror
        lsr
        lsr
        beq .none
        sta bnc
        lda tx+1
        lsr
        lda tx
        ror
        lsr
        lsr
        sta bcol
        lda ty
        sta by
        lda ty+1
        sta by+1
        lda fheight
        sta bnr
        lda tmode
        sta bmode
        jsr blit_strip
        jmp strip_clear
.none:  rts

; draw_str: convenience - A/Y = string, tx/ty set, uses font/tmode
draw_str:
        sta tstr
        sty tstr+1
        jmp draw_text

; ---------------------------------------------------------------------
; blit_strip: copy strip columns 0..bnc-1, rows 0..bnr-1 to the screen
; at column bcol, row by (16 bit signed), mode bmode, clipped.
; ---------------------------------------------------------------------
blit_fns:
        !word bl_or, bl_xor, bl_bic, bl_mask, bl_copy, bl_maskgray

!zone blit_strip
blit_strip:
        ; r0 = max(0, cly1 - by)
        sec
        lda cly1
        sbc by
        sta t0
        lda #0
        sbc by+1
        sta t1
        bpl +
        lda #0
        sta t0
        sta t1
+       lda t1
        beq .bf857
        jmp .none
.bf857:
        lda t0
        cmp bnr
        bcc .bf860
        jmp .none
.bf860:
        sta br0
        ; r1 = min(bnr-1, cly2 - by)
        sec
        lda cly2
        sbc by
        sta t2
        lda #0
        sbc by+1
        bpl .bf869
        jmp .none
.bf869:
        bne .r1max
        lda t2
        cmp bnr
        bcc +
.r1max: ldx bnr
        dex
        txa
+       sec
        sbc br0
        bcs .bf879
        jmp .none
.bf879:
        adc #0
        sta bcnt
        clc
        lda by
        adc br0
        sta t4
        and #7
        sta byoff
        lda t4
        lsr
        lsr
        lsr
        sta bcrow
        ; horizontal clip
        lda clx1+1
        lsr
        lda clx1
        ror
        lsr
        lsr
        sta bcl
        lda clx2+1
        lsr
        lda clx2
        ror
        lsr
        lsr
        sta bcr
        lda clx1
        and #7
        tax
        lda lmask_tab,x
        sta bclm
        lda clx2
        and #7
        tax
        lda rmask_tab,x
        sta bcrm
        lda bmode
        asl
        tax
        lda blit_fns,x
        sta blit_fn
        lda blit_fns+1,x
        sta blit_fn+1
        lda #0
        sta bk
.col:   clc
        lda bcol
        adc bk
        sta bsc
        cmp bcl
        bcc .nextc
        cmp bcr
        beq +
        bcs .none
+       lda #$ff
        ldx bsc
        cpx bcl
        bne +
        and bclm
+       cpx bcr
        bne +
        and bcrm
+       sta bm
        ldx bcrow
        clc
        lda crow_lo,x
        ldx bsc
        adc col8_lo,x
        sta p0
        ldx bcrow
        lda crow_hi,x
        ldx bsc
        adc col8_hi,x
        sta p0+1
        ldx bk
        clc
        lda scol_lo,x
        adc br0
        sta src_lo
        lda scol_hi,x
        adc #0
        sta src_hi
        jsr .call
.nextc: inc bk
        lda bk
        cmp bnc
        bcc .col
.none:  rts
.call:  jmp (blit_fn)

!macro blit_next .loop {
        inx
        cpx bcnt
        beq .done
        iny
        cpy #8
        bne .loop
        ldy #0
        lda p0
        clc
        adc #<320
        sta p0
        lda p0+1
        adc #>320
        sta p0+1
        jmp .loop
.done:  rts
}

!zone bl_or
bl_or:  lda src_lo
        sta .l+1
        lda src_hi
        sta .l+2
        ldy byoff
        ldx #0
.l:     lda $ffff,x
        and bm
        ora (p0),y
        sta (p0),y
        +blit_next .l

!zone bl_xor
bl_xor: lda src_lo
        sta .l+1
        lda src_hi
        sta .l+2
        ldy byoff
        ldx #0
.l:     lda $ffff,x
        and bm
        eor (p0),y
        sta (p0),y
        +blit_next .l

!zone bl_bic
bl_bic: lda src_lo
        sta .l+1
        lda src_hi
        sta .l+2
        ldy byoff
        ldx #0
.l:     lda $ffff,x
        and bm
        eor #$ff
        and (p0),y
        sta (p0),y
        +blit_next .l

!zone bl_mask
bl_mask:
        lda src_lo
        sta .a+1
        sta .b+1
        lda src_hi
        sta .b+2
        clc
        adc #>(MSTRIP-STRIP)
        sta .a+2
        ldy byoff
        ldx #0
.l:
.a:     lda $ffff,x
        and bm
        eor #$ff
        and (p0),y
        sta bt
.b:     lda $ffff,x
        and bm
        ora bt
        sta (p0),y
        +blit_next .l

!zone bl_maskgray
; masked, with the inside of the mask filled with grey
bl_maskgray:
        lda src_lo
        sta .a+1
        sta .b+1
        sta .c+1
        lda src_hi
        sta .b+2
        clc
        adc #>(MSTRIP-STRIP)
        sta .a+2
        sta .c+2
        ldy byoff
        ldx #0
.l:
.a:     lda $ffff,x
        and bm
        eor #$ff
        and (p0),y
        sta bt
.c:     lda $ffff,x
        and pat_gray,y
.b:     ora $ffff,x
        and bm
        ora bt
        sta (p0),y
        +blit_next .l

!zone bl_copy
bl_copy:
        lda src_lo
        sta .b+1
        lda src_hi
        sta .b+2
        lda bm
        eor #$ff
        sta bnm
        ldy byoff
        ldx #0
.l:     lda (p0),y
        and bnm
        sta bt
.b:     lda $ffff,x
        and bm
        ora bt
        sta (p0),y
        +blit_next .l

; clear strip columns 0..bnc-1, rows 0..bnr-1 (STRIP, then MSTRIP)
!zone strip_clear
strip_clear:
        lda #0
        beq +
mstrip_clear:
        lda #>(MSTRIP-STRIP)
+       sta t0
        ldx #0
.c:     lda scol_lo,x
        sta p1
        lda scol_hi,x
        clc
        adc t0
        sta p1+1
        lda #0
        ldy bnr
        dey
-       sta (p1),y
        dey
        bpl -
        inx
        cpx bnc
        bcc .c
        rts

; ---------------------------------------------------------------------
; draw_icon: icon at iptr, top-left at tx (16) / ty (16 signed)
; iflags: ICON_SEL = inverted inside the mask, ICON_OUTLINE = XOR the
; outline (for dragging), ICON_PLAIN = OR the image without a mask.
; ---------------------------------------------------------------------
!zone draw_icon
draw_icon:
        ldy #0
        lda (iptr),y
        sta iw
        iny
        lda (iptr),y
        sta ih
        ; isz = iw * ih
        lda #0
        sta isz
        sta isz+1
        ldx iw
-       clc
        lda isz
        adc ih
        sta isz
        bcc +
        inc isz+1
+       dex
        bne -
        clc
        lda iptr
        adc #3
        sta img
        lda iptr+1
        adc #0
        sta img+1
        clc
        lda img
        adc isz
        sta imask
        lda img+1
        adc isz+1
        sta imask+1
        clc
        lda imask
        adc isz
        sta ioutl
        lda imask+1
        adc isz+1
        sta ioutl+1
        lda tx
        and #7
        clc
        adc #>SHR_TAB
        sta render_strip_sh1+2
        adc #8
        sta render_strip_sh2+2
        lda tx+1
        lsr
        lda tx
        ror
        lsr
        lsr
        sta bcol
        lda ty
        sta by
        lda ty+1
        sta by+1
        ldx iw
        inx
        stx bnc
        lda ih
        sta bnr
        lda iflags
        and #ICON_OUTLINE
        beq .normal
        lda ioutl
        sta p1
        lda ioutl+1
        sta p1+1
        lda #0
        sta rxor
        sta rdst
        jsr render_strip
        lda #B_XOR
.single:
        sta bmode
        jsr blit_strip
        jmp strip_clear
.normal:
        lda iflags
        and #ICON_PLAIN
        beq .masked
        lda img
        sta p1
        lda img+1
        sta p1+1
        lda #0
        sta rxor
        sta rdst
        jsr render_strip
        lda #B_OR
        jmp .single
.masked:
        lda img
        sta p1
        lda img+1
        sta p1+1
        lda imask
        sta p2
        lda imask+1
        sta p2+1
        lda #0
        sta rdst
        lda iflags
        and #ICON_SEL
        beq +
        lda #$80
+       sta rxor
        jsr render_strip
        lda imask
        sta p1
        lda imask+1
        sta p1+1
        lda #0
        sta rxor
        lda #>(MSTRIP-STRIP)
        sta rdst
        jsr render_strip
        lda #B_MASK
        ldx iflags
        cpx #ICON_OPEN
        bne +
        lda #B_MASKGRAY
+       sta bmode
        jsr blit_strip
        jsr strip_clear
        jmp mstrip_clear

; render_strip: source rows at p1 (iw bytes per row, ih rows), optionally
; XORed with p2 (rxor bit 7), shifted, ORed into STRIP (+rdst pages)
!zone render_strip
render_strip:
        lda #0
        sta rj
.col:   ldx rj
        lda scol_lo,x
        sta .d1+1
        sta .d1b+1
        lda scol_hi,x
        clc
        adc rdst
        sta .d1+2
        sta .d1b+2
        lda scol_lo+1,x
        sta .d2+1
        sta .d2b+1
        lda scol_hi+1,x
        clc
        adc rdst
        sta .d2+2
        sta .d2b+2
        clc
        lda p1
        adc rj
        sta p3
        lda p1+1
        adc #0
        sta p3+1
        clc
        lda p2
        adc rj
        sta p4
        lda p2+1
        adc #0
        sta p4+1
        ldx #0
.row:   ldy #0
        lda (p3),y
        bit rxor
        bpl +
        eor (p4),y
+       tay
render_strip_sh1:
        lda SHR_TAB,y
.d1:    ora $ffff,x
.d1b:   sta $ffff,x
render_strip_sh2:
        lda SHL_TAB,y
.d2:    ora $ffff,x
.d2b:   sta $ffff,x
        clc
        lda p3
        adc iw
        sta p3
        bcc +
        inc p3+1
+       clc
        lda p4
        adc iw
        sta p4
        bcc +
        inc p4+1
+       inx
        cpx ih
        bcs +
        jmp .row
+       inc rj
        lda rj
        cmp iw
        bcs +
        jmp .col
+       rts

; icon_size: A/Y = icon -> t0 = width in pixels, t1 = height
icon_size:
        sta p0
        sty p0+1
        ldy #2
        lda (p0),y
        sta t0
        dey
        lda (p0),y
        sta t1
        rts

; ---------------------------------------------------------------------
; Save / restore a screen area: byte columns sv_c1..sv_c2, rows
; sv_y1..sv_y2, to/from SAVEBUF.  Used for pull-down menus.
; ---------------------------------------------------------------------
SAVEBUF = $c800         ; 2K
sv_c1:  !byte 0
sv_c2:  !byte 0
sv_y1:  !byte 0
sv_y2:  !byte 0
sv_dir: !byte 0

!zone save_area
save_area:
        lda #0
        beq +
restore_area:
        lda #1
+       sta sv_dir
        lda #<SAVEBUF
        sta p1
        lda #>SAVEBUF
        sta p1+1
        ldx sv_c1
.col:   stx t2
        ; p0 = screen address of (column, sv_y1 & ~7), Y = sv_y1 & 7
        lda sv_y1
        lsr
        lsr
        lsr
        tay
        clc
        lda crow_lo,y
        adc col8_lo,x
        sta p0
        lda crow_hi,y
        adc col8_hi,x
        sta p0+1
        lda sv_y1
        and #7
        tay
        lda sv_y2
        sec
        sbc sv_y1
        tax
        inx
.row:   stx t3
        ldx #0
        lda sv_dir
        bne .rest
        lda (p0),y
        sta (p1,x)
        jmp +
.rest:  lda (p1,x)
        sta (p0),y
+       inc p1
        bne +
        inc p1+1
+       ldx t3
        dex
        beq .cdone
        iny
        cpy #8
        bne .row
        ldy #0
        lda p0
        clc
        adc #<320
        sta p0
        lda p0+1
        adc #>320
        sta p0+1
        jmp .row
.cdone: ldx t2
        cpx sv_c2
        beq +
        inx
        jmp .col
+       rts
