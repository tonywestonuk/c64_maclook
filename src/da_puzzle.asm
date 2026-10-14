; =====================================================================
; da_puzzle.asm - the 15 puzzle
; =====================================================================

PZ_TW = 18              ; tile pitch
PZ_TH = 16

puz_board: !fill 16      ; 1..15, 0 = hole
puz_win:   !byte $ff
puz_lbl:   !fill 3

!zone puz_open
puz_open:
        lda #CL_PUZZLE
        jsr da_find
        bcs +
        jmp win_select
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx puz_win
        +winrect 110, 70, 188, 152
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_PUZZLE
        sta w_class,x
        lda #<str_o_puzzle
        sta w_titl,x
        lda #>str_o_puzzle
        sta w_tith,x
        jsr puz_shuffle
        ldx puz_win
        jmp win_open

puz_close:
        lda #$ff
        sta puz_win
        rts

; solved board, then lots of random legal moves
!zone puz_shuffle
puz_shuffle:
        ldx #14
-       txa
        clc
        adc #1
        sta puz_board,x
        dex
        bpl -
        lda #0
        sta puz_board+15
        lda #0
        sta u4
.again: jsr random
        and #3
        jsr puz_move_dir
        dec u4
        bne .again
        rts

; move a tile into the hole from direction A (0 up,1 down,2 left,3 right)
puz_move_dir:
        sta t3
        jsr puz_hole            ; X = hole index
        stx t2
        lda t3
        bne +
        cpx #12                 ; tile below moves up
        bcs .no
        txa
        clc
        adc #4
        jmp .swap
+       cmp #1
        bne +
        cpx #4                  ; tile above moves down
        bcc .no
        txa
        sec
        sbc #4
        jmp .swap
+       cmp #2
        bne +
        txa                     ; tile to the right moves left
        and #3
        cmp #3
        beq .no
        txa
        clc
        adc #1
        jmp .swap
+       txa                     ; tile to the left moves right
        and #3
        beq .no
        txa
        sec
        sbc #1
.swap:  tay
        lda puz_board,y
        ldx t2
        sta puz_board,x
        lda #0
        sta puz_board,y
.no:    rts

puz_hole:
        ldx #15
-       lda puz_board,x
        beq +
        dex
        bpl -
+       rts

; ---------------------------------------------------------------------
!zone puz_draw
puz_draw:
        ; grey background behind the tiles
        jsr puz_board_rect
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        jsr fill_rect
        jsr set_black
        jsr frame_rect
        ldx #0
-       stx u5
        jsr puz_draw_tile
        ldx u5
        inx
        cpx #16
        bne -
        rts

puz_board_rect:
        clc
        lda wc_x1
        adc #2
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        clc
        lda rx1
        adc #4*PZ_TW
        sta rx2
        lda rx1+1
        adc #0
        sta rx2+1
        lda wc_y1
        clc
        adc #2
        sta ry1
        clc
        adc #4*PZ_TH
        sta ry2
        rts

; rect of tile X (inside the board)
puz_tile_rect:
        stx t0
        txa
        and #3
        tay
        lda #0
-       dey
        bmi +
        clc
        adc #PZ_TW
        bne -
+       clc
        adc #3
        adc wc_x1
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        clc
        lda rx1
        adc #PZ_TW-2
        sta rx2
        lda rx1+1
        adc #0
        sta rx2+1
        lda t0
        lsr
        lsr
        tay
        lda #0
-       dey
        bmi +
        clc
        adc #PZ_TH
        bne -
+       clc
        adc #3
        adc wc_y1
        sta ry1
        clc
        adc #PZ_TH-2
        sta ry2
        rts

puz_draw_tile:
        stx u6
        jsr puz_tile_rect
        ldx u6
        lda puz_board,x
        bne +
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        jmp fill_rect
+       sta u7
        jsr fill_white
        jsr frame_round
        ; number
        lda u7
        ldx #0
        jsr utoa
        lda #0
        sta font
        lda #<numbuf
        sta tstr
        lda #>numbuf
        sta tstr+1
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
        adc #4
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jmp draw_text

; ---------------------------------------------------------------------
!zone puz_click
puz_click:
        ; which tile?
        ldx #0
-       stx u5
        jsr puz_tile_rect
        jsr mouse_in_rect
        bcc .hit
        ldx u5
        inx
        cpx #16
        bne -
        rts
.hit:   jsr puz_hole
        stx u4                  ; hole
        lda u5
        cmp u4
        beq .out
        ; same row?
        lda u5
        lsr
        lsr
        sta t0
        lda u4
        lsr
        lsr
        cmp t0
        bne .col
        ; slide along the row towards the hole
-       lda u4
        cmp u5
        beq .done
        bcc +
        lda #3                  ; hole is right of tile: tile left of hole moves right
        bne ++
+       lda #2
++      jsr puz_step
        jmp -
.col:   lda u5
        and #3
        sta t0
        lda u4
        and #3
        cmp t0
        bne .out
-       lda u4
        cmp u5
        beq .done
        bcc +
        lda #1                  ; hole below: tile above moves down
        bne ++
+       lda #0
++      jsr puz_step
        jmp -
.done:  jsr puz_solved
        bne .out
        jsr beep
        lda #12
        jsr wait_frames
        jsr beep
.out:   rts

; one move in direction A, redrawing the two squares
puz_step:
        jsr puz_move_dir
        jsr clip_push
        jsr clip_screen
        ldx puz_win
        jsr win_get_content
        ldx u4                  ; old hole now has a tile
        jsr puz_draw_tile
        jsr puz_hole
        stx u4
        jsr puz_draw_tile
        jsr clip_pop
        lda #2
        jmp wait_frames

; Z set if solved
puz_solved:
        ldx #14
-       txa
        clc
        adc #1
        cmp puz_board,x
        bne +
        dex
        bpl -
        lda #0
+       rts
