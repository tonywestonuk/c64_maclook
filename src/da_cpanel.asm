; =====================================================================
; da_cpanel.asm - Control Panel and Key Caps
; =====================================================================

cp_win:  !byte $ff
cp_pat:  !fill 8          ; pattern being edited
cp_idx:  !byte 0          ; stock pattern shown

!zone cp_open
cp_open:
        lda #CL_CPANEL
        jsr da_find
        bcs +
        jmp win_select
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx cp_win
        +winrect 34, 36, 34+250, 36+122
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_CPANEL
        sta w_class,x
        lda #<str_o_cpanel
        sta w_titl,x
        lda #>str_o_cpanel
        sta w_tith,x
        ldx #7
-       lda desk_pat,x
        sta cp_pat,x
        dex
        bpl -
        ldx cp_win
        jmp win_open

cp_close:
        lda #$ff
        sta cp_win
        rts

; rect helper: rx/ry = content origin + (A, X) .. + (Y, t7)
cp_rect:
        sta t4
        stx t5
        sty t6
        clc
        lda wc_x1
        adc t4
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        clc
        lda wc_x1
        adc t6
        sta rx2
        lda wc_x1+1
        adc #0
        sta rx2+1
        lda wc_y1
        clc
        adc t5
        sta ry1
        lda wc_y1
        clc
        adc t7
        sta ry2
        rts

; text A/Y at content (X, t7) in the small font
cp_text:
        stx t4
        sta tstr
        sty tstr+1
        clc
        lda wc_x1
        adc t4
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc t7
        sta ty
        lda #0
        sta ty+1
        lda #1
        sta font
        lda #B_OR
        sta tmode
        jmp draw_text

!zone cp_draw
cp_draw:
        ; dividing line between the columns
        lda #106
        sta t7
        lda #112
        ldx #2
        ldy #112
        jsr cp_rect
        jsr fill_black
        ; labels
        lda #3
        sta t7
        lda #<str_cp_pattern
        ldy #>str_cp_pattern
        ldx #8
        jsr cp_text
        lda #74
        sta t7
        lda #<str_cp_volume
        ldy #>str_cp_volume
        ldx #8
        jsr cp_text
        jsr cp_draw_fat
        jsr cp_draw_preview
        ; arrows under the preview
        lda #67
        sta t7
        lda #58
        ldx #57
        ldy #72
        jsr cp_rect
        lda #<str_lt
        sta tstr
        lda #>str_lt
        sta tstr+1
        jsr push_button
        lda #67
        sta t7
        lda #82
        ldx #57
        ldy #96
        jsr cp_rect
        lda #<str_gt
        sta tstr
        lda #>str_gt
        sta tstr+1
        jsr push_button
        jsr cp_draw_volume
        ; radio groups
        ldx #0
-       stx u5
        jsr cp_draw_group
        ldx u5
        inx
        cpx #3
        bne -
        rts

; fat bits editor at (8,14), 8x8 cells of 5 pixels
!zone cp_draw_fat
cp_draw_fat:
        lda #54
        sta t7
        lda #8
        ldx #14
        ldy #48
        jsr cp_rect
        jsr fill_white
        jsr set_black
        jsr frame_rect
        lda #0
        sta u6                  ; bit index 0..63
-       jsr cp_cell
        inc u6
        lda u6
        cmp #64
        bne -
        rts

; draw cell u6 of the fat bits editor
cp_cell:
        lda u6
        and #7
        sta t0
        asl
        asl
        clc
        adc t0                  ; *5
        clc
        adc #9
        sta u4
        lda u6
        lsr
        lsr
        lsr
        sta t0
        asl
        asl
        clc
        adc t0
        clc
        adc #15
        tax
        clc
        adc #3
        sta t7
        lda u4
        clc
        adc #3
        tay
        lda u4
        jsr cp_rect
        ; bit set?
        lda u6
        lsr
        lsr
        lsr
        tax
        lda u6
        and #7
        tay
        lda cp_pat,x
        and bit_tab,y
        bne +
        jmp fill_white
+       jmp fill_black

cp_draw_preview:
        lda #54
        sta t7
        lda #56
        ldx #14
        ldy #96
        jsr cp_rect
        lda #<cp_pat
        ldy #>cp_pat
        jsr set_pat_copy
        jsr fill_rect
        jsr set_black
        jmp frame_rect

; volume slider: 8 stops at x = 12 + 11*i, y = 86
!zone cp_draw_volume
cp_draw_volume:
        lda #94
        sta t7
        lda #8
        ldx #83
        ldy #100
        jsr cp_rect
        jsr fill_white
        lda #88
        sta t7
        lda #12
        ldx #88
        ldy #89
        jsr cp_rect
        jsr fill_black
        ldx #0
-       stx u4
        txa
        asl
        asl
        asl
        clc
        adc u4
        adc u4
        adc u4
        adc #12
        sta u6
        lda #90
        sta t7
        lda u6
        ldx #86
        ldy u6
        jsr cp_rect
        jsr fill_black
        ldx u4
        inx
        cpx #8
        bne -
        ; knob
        lda beep_vol
        asl
        asl
        asl
        clc
        adc beep_vol
        adc beep_vol
        adc beep_vol
        adc #10
        sta u6
        lda #93
        sta t7
        lda u6
        clc
        adc #4
        tay
        lda u6
        ldx #84
        jsr cp_rect
        jsr fill_white
        jsr set_black
        jmp frame_rect

; ---------------------------------------------------------------------
; radio button groups: label, y, count, variable, values, option labels
; ---------------------------------------------------------------------
cpg_label: !word str_cp_blink, str_cp_menu, str_cp_dbl
cpg_y:     !byte 3, 40, 77
cpg_n:     !byte 3, 4, 3
cpg_var:   !word np_blink, menu_blinks, dbl_time
cpg_vals:  !byte 50, 30, 12, 0
           !byte 0, 1, 2, 3
           !byte 36, 24, 14, 0
cpg_opts:  !word str_slow, str_med, str_fast, 0
           !word str_off, str_1, str_2, str_3
           !word str_slow, str_med, str_fast, 0
cpg_cur:   !byte 0

!zone cp_draw_group
cp_draw_group:                  ; X = group
        stx cpg_cur
        txa
        asl
        tay
        lda cpg_y,x
        sta t7
        lda cpg_label,y
        pha
        lda cpg_label+1,y
        tay
        pla
        ldx #120
        jsr cp_text
        lda #0
        sta u3
-       jsr cp_draw_radio
        inc u3
        ldx cpg_cur
        lda u3
        cmp cpg_n,x
        bne -
        rts

; option u3 of group cpg_cur: radio at x = 124 + 30*i, y = label y + 12
cp_radio_pos:
        lda u3
        asl
        asl
        asl
        asl
        sec
        sbc u3
        asl                     ; *30
        clc
        adc #124
        sta u4                  ; x
        ldx cpg_cur
        lda cpg_y,x
        clc
        adc #12
        sta u7                  ; y
        rts

cp_draw_radio:
        jsr cp_radio_pos
        ; current value?
        lda cpg_cur
        asl
        tay
        lda cpg_var,y
        sta q2
        lda cpg_var+1,y
        sta q2+1
        lda cpg_cur
        asl
        asl
        clc
        adc u3
        tax
        ldy #0
        lda (q2),y
        cmp cpg_vals,x
        php
        clc
        lda wc_x1
        adc u4
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc u7
        sta ty
        lda #0
        sta ty+1
        lda #<icon_radio
        ldy #>icon_radio
        plp
        bne +
        lda #<icon_radioon
        ldy #>icon_radioon
+       sta iptr
        sty iptr+1
        lda #0
        sta iflags
        jsr draw_icon
        ; option label
        lda cpg_cur
        asl
        asl
        clc
        adc u3
        asl
        tay
        lda cpg_opts,y
        ldx cpg_opts+1,y
        stx t3
        ora t3
        beq +
        lda u7
        sta t7
        lda u4
        clc
        adc #9
        tax
        lda cpg_opts,y
        ldy t3
        jmp cp_text
+       rts

; ---------------------------------------------------------------------
!zone cp_click
cp_click:
        ; fat bits?
        lda #54
        sta t7
        lda #9
        ldx #15
        ldy #48
        jsr cp_rect
        jsr mouse_in_rect
        bcs .notfat
        jmp cp_click_fat
.notfat:
        ; preview: set the desktop
        lda #54
        sta t7
        lda #56
        ldx #14
        ldy #96
        jsr cp_rect
        jsr mouse_in_rect
        bcs +
        jmp cp_set_desktop
+       ; arrows
        lda #67
        sta t7
        lda #58
        ldx #57
        ldy #72
        jsr cp_rect
        jsr mouse_in_rect
        bcs +
        jsr track_box
        bcc .bf472
        jmp .out
.bf472:
        lda #$ff
        jmp cp_cycle
+       lda #67
        sta t7
        lda #82
        ldx #57
        ldy #96
        jsr cp_rect
        jsr mouse_in_rect
        bcs +
        jsr track_box
        bcs .out
        lda #1
        jmp cp_cycle
+       ; volume
        lda #94
        sta t7
        lda #8
        ldx #83
        ldy #100
        jsr cp_rect
        jsr mouse_in_rect
        bcs +
        jmp cp_click_volume
+       ; radio buttons
        ldx #0
.g:     stx cpg_cur
        lda #0
        sta u3
.o:     jsr cp_radio_pos
        lda u7
        clc
        adc #6
        sta t7
        lda u4
        clc
        adc #6
        tay
        ldx u7
        lda u4
        jsr cp_rect
        jsr mouse_in_rect
        bcs .no
        ; set the variable
        lda cpg_cur
        asl
        tay
        lda cpg_var,y
        sta q2
        lda cpg_var+1,y
        sta q2+1
        lda cpg_cur
        asl
        asl
        clc
        adc u3
        tax
        lda cpg_vals,x
        ldy #0
        sta (q2),y
        jsr clip_push
        jsr clip_screen
        ldx cpg_cur
        jsr cp_draw_group_radios
        jmp clip_pop
.no:    inc u3
        ldx cpg_cur
        lda u3
        cmp cpg_n,x
        bne .o
        inx
        cpx #3
        bne .g
.out:   rts

cp_draw_group_radios:
        stx cpg_cur
        lda #0
        sta u3
-       jsr cp_draw_radio
        inc u3
        ldx cpg_cur
        lda u3
        cmp cpg_n,x
        bne -
        rts

; toggle a fat bit; keep painting while the button is held
!zone cp_click_fat
cp_click_fat:
        jsr .cell_at_mouse
        bcs .out
        ; paint colour = opposite of the first cell
        lda cp_pat,x
        and bit_tab,y
        sta u5                  ; 0 = paint black
.loop:  jsr .cell_at_mouse
        bcs .next
        lda u5
        bne .clr
        lda cp_pat,x
        ora bit_tab,y
        jmp .st
.clr:   lda bit_tab,y
        eor #$ff
        and cp_pat,x
.st:    cmp cp_pat,x
        beq .next
        sta cp_pat,x
        jsr clip_push
        jsr clip_screen
        jsr cp_cell
        jsr cp_draw_preview
        jsr clip_pop
.next:  jsr wait_frame
        lda mbtn
        bne .loop
.out:   rts
.cell_at_mouse:                 ; X = row, Y = column, u6 = index
        sec
        lda mouse_x
        sbc wc_x1
        sec
        sbc #9
        bcc .none
        ldx #0
-       cmp #5
        bcc +
        sbc #5
        inx
        bne -
+       cpx #8
        bcs .none
        stx t0
        lda mouse_y
        sec
        sbc wc_y1
        sec
        sbc #15
        bcc .none
        ldy #0
-       cmp #5
        bcc +
        sbc #5
        iny
        bne -
+       cpy #8
        bcs .none
        tya
        asl
        asl
        asl
        ora t0
        sta u6
        tya
        tax
        ldy t0
        clc
        rts
.none:  sec
        rts

; next/previous stock pattern
cp_cycle:
        clc
        adc cp_idx
        bpl +
        lda #NUM_PATTERNS-1
+       cmp #NUM_PATTERNS
        bcc +
        lda #0
+       sta cp_idx
        asl
        asl
        asl
        tax
        ldy #0
-       lda patterns,x
        sta cp_pat,y
        inx
        iny
        cpy #8
        bne -
        jsr clip_push
        jsr clip_screen
        jsr cp_draw_fat
        jsr cp_draw_preview
        jmp clip_pop

; copy the pattern to the desktop and repaint it
cp_set_desktop:
        jsr wait_release
        ldx #7
-       lda cp_pat,x
        sta desk_pat,x
        dex
        bpl -
        lda #CUR_WATCH
        jsr set_cursor
        +rect 0, DESK_Y1, 319, 199
        jsr redraw_region
        lda #CUR_ARROW
        jmp set_cursor

; volume: nearest stop
cp_click_volume:
        sec
        lda mouse_x
        sbc wc_x1
        sec
        sbc #7
        bcs +
        lda #0
+       ldx #0
-       cmp #11
        bcc +
        sbc #11
        inx
        bne -
+       cpx #8
        bcc +
        ldx #7
+       stx beep_vol
        jsr clip_push
        jsr clip_screen
        jsr cp_draw_volume
        jsr clip_pop
        jsr beep
        jmp wait_release

str_cp_pattern: !text "Desktop Pattern", 0
str_cp_volume:  !text "Speaker Volume", 0
str_cp_blink:   !text "Rate of Insertion Point Blinking", 0
str_cp_menu:    !text "Menu Blinking", 0
str_cp_dbl:     !text "Double-Click Speed", 0
str_slow:       !text "Slow", 0
str_med:        !text "Med", 0
str_fast:       !text "Fast", 0
str_off:        !text "Off", 0
str_1:          !text "1", 0
str_2:          !text "2", 0
str_3:          !text "3", 0
str_lt:         !text "<", 0
str_gt:         !text ">", 0

; =====================================================================
; Key Caps
; =====================================================================
kc_win:  !byte $ff
kc_buf:  !fill 32
kc_hi:   !byte $ff        ; highlighted key
kc_time: !byte 0

kc_rows: !text "1234567890-=", 0
         !text "QWERTYUIOP[]", 0
         !text "ASDFGHJKL;'", 0
         !text "ZXCVBNM,./", 0
kc_rowx: !byte 6, 12, 15, 21
kc_ch:   !byte 0, 0

!zone kc_open
kc_open:
        lda #CL_KEYCAPS
        jsr da_find
        bcs +
        jmp win_select
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx kc_win
        +winrect 50, 100, 50+165, 100+96
        lda #0
        sta kc_buf
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_KEYCAPS
        sta w_class,x
        lda #<str_o_keycaps
        sta w_titl,x
        lda #>str_o_keycaps
        sta w_tith,x
        lda #$ff
        sta kc_hi
        ldx kc_win
        jmp win_open

kc_close:
        lda #$ff
        sta kc_win
        rts

; key number X (0..44, 45 = space) -> rect, kc_ch = label
!zone kc_key_rect
kc_key_rect:
        cpx #45
        bne +
        lda #84
        sta t7
        lda #42
        ldx #74
        ldy #118
        jsr cp_rect
        lda #' '
        sta kc_ch
        rts
+       ; find row
        stx t2
        ldy #0                  ; row
        lda #0                  ; first key of row
        sta t3
.r:     lda kc_rowlen,y
        clc
        adc t3
        cmp t2
        beq +
        bcs .found
+       sta t3
        iny
        bne .r
.found: lda t2
        sec
        sbc t3                  ; column
        sta t4
        lda kc_rowoff,y         ; label
        clc
        adc t4
        tax
        lda kc_rows,x
        sta kc_ch
        lda t4                  ; x = rowx + 12*col
        asl
        adc t4
        asl
        asl
        clc
        adc kc_rowx,y
        sta t5
        tya                     ; y = 26 + 12*row
        sta t6
        asl
        adc t6
        asl
        asl
        adc #26
        tax
        clc
        adc #10
        sta t7
        lda t5
        clc
        adc #10
        tay
        lda t5
        jmp cp_rect
kc_rowlen: !byte 12, 12, 11, 10
kc_rowoff: !byte 0, 13, 26, 38

!zone kc_draw
kc_draw:
        ; text box
        lda #16
        sta t7
        lda #4
        ldx #4
        ldy #159
        jsr cp_rect
        jsr set_black
        jsr frame_rect
        jsr kc_draw_text
        ldx #0
-       stx u5
        jsr kc_draw_key
        ldx u5
        inx
        cpx #46
        bne -
        rts

kc_draw_text:
        lda #15
        sta t7
        lda #5
        ldx #5
        ldy #158
        jsr cp_rect
        jsr fill_white
        lda #0
        sta font
        lda #<kc_buf
        sta tstr
        lda #>kc_buf
        sta tstr+1
        clc
        lda wc_x1
        adc #8
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #6
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jmp draw_text

kc_draw_key:
        stx u6
        jsr kc_key_rect
        jsr fill_white
        jsr frame_round
        lda #1
        sta font
        lda #<kc_ch
        sta tstr
        lda #>kc_ch
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
        adc #2
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jsr draw_text
        ldx u6
        cpx kc_hi
        bne +
        jsr kc_key_rect
        lda #1
        jsr rect_inset
        jsr invert_rect
+       rts

; a key was typed: highlight it, add it to the text
!zone kc_key
kc_key:
        lda key_char
        cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        and #$df
+       sta u4
        ; find the key
        ldx #45
        cmp #' '
        beq .found
        ldx #0
-       stx u5
        jsr kc_key_rect
        lda kc_ch
        cmp u4
        beq +
        ldx u5
        inx
        cpx #45
        bne -
        jmp .text
+       ldx u5
.found: stx u5
        jsr kc_unhilite
        ldx u5
        stx kc_hi
        lda #10
        sta kc_time
        jsr clip_push
        jsr clip_screen
        ldx kc_win
        jsr win_get_content
        ldx u5
        jsr kc_key_rect
        lda #1
        jsr rect_inset
        jsr invert_rect
        jsr clip_pop
.text:  lda key_char
        cmp #32
        bcc .out
        cmp #127
        bcs .out
        ; append, scrolling when full
        ldx #0
-       lda kc_buf,x
        beq +
        inx
        bne -
+       cpx #24
        bcc +
        ldy #0
-       lda kc_buf+1,y
        sta kc_buf,y
        iny
        cpy #24
        bne -
        dex
+       lda key_char
        sta kc_buf,x
        lda #0
        sta kc_buf+1,x
        jsr clip_push
        jsr clip_screen
        ldx kc_win
        jsr win_get_content
        jsr kc_draw_text
        jmp clip_pop
.out:   rts

kc_idle:
        lda kc_time
        beq +
        dec kc_time
        bne +
        jmp kc_unhilite
+       rts

kc_unhilite:
        ldx kc_hi
        bmi +
        lda #$ff
        sta kc_hi
        stx u6
        jsr clip_push
        jsr clip_screen
        ldx kc_win
        jsr win_get_content
        ldx u6
        jsr kc_key_rect
        lda #1
        jsr rect_inset
        jsr invert_rect
        jsr clip_pop
+       rts
