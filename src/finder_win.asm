; =====================================================================
; finder_win.asm - the Finder's About box, Get Info and text windows
; =====================================================================

; ---------------------------------------------------------------------
; About the Finder
; ---------------------------------------------------------------------
!zone about_box
about_box:
        lda #DLG_CUSTOM
        sta dlg_kind
        lda #<about_draw
        sta dlg_custom
        lda #>about_draw
        sta dlg_custom+1
        lda #110
        sta dlg_h
        lda #1
        sta dlg_x2h
        lda #40
        ldx #40
        ldy #<279
        jsr dlg_open
        bcs .out
        jsr wait_click_or_key
        jmp dlg_close
.out:   rts

about_draw:
        ; title
        lda #0
        sta font
        lda #B_OR
        sta tmode
        lda #<str_about1
        ldy #>str_about1
        ldx #4
        jsr draw_centred_at
        ; picture: hills under a sky
        jsr about_picture
        lda #1
        sta font
        lda #<str_about2
        ldy #>str_about2
        ldx #64
        jsr draw_centred_at
        lda #<str_about3
        ldy #>str_about3
        ldx #74
        jsr draw_centred_at
        lda #<str_about4
        ldy #>str_about4
        ldx #84
        jsr draw_centred_at
        lda #<str_about5
        ldy #>str_about5
        ldx #94
        jmp draw_centred_at

; a little landscape (rolling hills) like the Finder's About box
!zone about_picture
about_picture:
        ; frame
        clc
        lda wc_x1
        adc #40
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        sec
        lda wc_x2
        sbc #40
        sta rx2
        lda wc_x2+1
        sbc #0
        sta rx2+1
        lda wc_y1
        clc
        adc #16
        sta ry1
        clc
        adc #42
        sta ry2
        jsr set_black
        jsr frame_rect
        lda rx2
        sta .x2
        lda rx2+1
        sta .x2+1
        ; hills: columns of grey/black from a height table
        lda rx1
        sta u0
        lda rx1+1
        sta u1
        lda ry2
        sta u3
        ldx #0
.col:   stx u2
        inc u0
        bne +
        inc u1
+       lda u0
        cmp .x2
        lda u1
        sbc .x2+1
        bcs .sun
        ; height = hill1[x] (far) then hill2[x] (near)
        lda u0
        sta rx1
        lda u1
        sta rx1+1
        txa
        and #63
        tay
        lda hill_far,y
        jsr .column_pat
        lda u2
        clc
        adc #23
        and #63
        tay
        lda hill_near,y
        jsr .column_blk
        ldx u2
        inx
        bne .col
.sun:   rts
.x2:    !word 0
.column_pat:
        sta t0
        lda u3
        sec
        sbc t0
        sta ry1
        lda u3
        sec
        sbc #1
        sta ry2
        lda rx1
        sta rx2
        lda rx1+1
        sta rx2+1
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        jmp fill_rect
.column_blk:
        sta t0
        lda u3
        sec
        sbc t0
        sta ry1
        lda u3
        sec
        sbc #1
        sta ry2
        lda rx1
        sta rx2
        lda rx1+1
        sta rx2+1
        jmp fill_black

hill_far:
        !for i, 0, 63 { !byte 18 + int(7.0*sin(float(i)*6.2832/64.0) + 4.0*sin(float(i)*6.2832*3.0/64.0)) }
hill_near:
        !for i, 0, 63 { !byte 9 + int(5.0*sin(float(i)*6.2832*2.0/64.0 + 1.0)) }


; ---------------------------------------------------------------------
; Get Info
; ---------------------------------------------------------------------
!zone get_info
get_info:
        ldx sel_obj
        cpx #NOOBJ
        bne +
        rts
+       stx u3
        jsr win_alloc
        bcc +
        jmp too_many_windows
+       lda #70
        sta w_x1l,x
        lda #0
        sta w_x1h,x
        sta w_x2h,x
        lda #250
        sta w_x2l,x
        lda #40
        sta w_y1,x
        lda #160
        sta w_y2,x
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_INFO
        sta w_class,x
        lda u3
        sta w_data,x
        lda #<str_info
        sta w_titl,x
        lda #>str_info
        sta w_tith,x
        stx u2
        ldx u3
        jsr zoom_from_obj
        ldx u2
        jmp win_open

info_close:
        rts

!zone info_draw
info_draw:
        lda w_data,x
        sta u3
        tax
        jsr obj_icon_ptr
        clc
        lda wc_x1
        adc #8
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #4
        sta ty
        lda #0
        sta ty+1
        sta iflags
        jsr draw_icon
        ; name in the system font
        ldx u3
        jsr obj_name_ptr
        lda #0
        sta font
        lda #B_OR
        sta tmode
        clc
        lda wc_x1
        adc #40
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #9
        sta ty
        lda q1
        ldy q1+1
        jsr draw_str
        ; line
        lda wc_x1
        sta rx1
        lda wc_x1+1
        sta rx1+1
        lda wc_x2
        sta rx2
        lda wc_x2+1
        sta rx2+1
        lda wc_y1
        clc
        adc #27
        sta ry1
        sta ry2
        jsr fill_black
        ; fields
        lda #1
        sta font
        lda #0
        sta u4                  ; line
-       ldx u4
        lda info_labels_lo,x
        ldy info_labels_hi,x
        ldx #6
        jsr info_text
        ldx u4
        jsr info_value          ; A/Y = value string
        ldx #50
        jsr info_text
        inc u4
        lda u4
        cmp #5
        bne -
        ; locked box
        clc
        lda wc_x1
        adc #6
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        clc
        lda rx1
        adc #6
        sta rx2
        lda rx1+1
        adc #0
        sta rx2+1
        lda wc_y2
        sec
        sbc #10
        sta ry1
        clc
        adc #6
        sta ry2
        jsr set_black
        jsr frame_rect
        lda #<str_locked
        sta tstr
        lda #>str_locked
        sta tstr+1
        clc
        lda rx2
        adc #4
        sta tx
        lda rx2+1
        adc #0
        sta tx+1
        lda ry1
        sta ty
        lda #0
        sta ty+1
        jmp draw_text

info_labels_lo: !byte <str_kind, <str_size, <str_where, <str_created, <str_modified
info_labels_hi: !byte >str_kind, >str_size, >str_where, >str_created, >str_modified

; draw A/Y at content x offset X, line u4
info_text:
        sta tstr
        sty tstr+1
        stx t0
        clc
        lda wc_x1
        adc t0
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda u4
        asl
        asl
        asl
        clc
        adc u4
        adc wc_y1
        adc #32
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jmp draw_text

; value of info line X for object u3 -> A/Y
!zone info_value
info_value:
        ldy u3
        cpx #0
        bne .size
        ; kind
        lda o_type,y
        tax
        lda kind_lo,x
        pha
        lda kind_hi,x
        tay
        pla
        rts
.size:  cpx #1
        bne .where
        lda o_size,y
        ldx #0
        jsr utoa
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
        lda #<iv_buf
        sta q1
        lda #>iv_buf
        sta q1+1
        jsr strcpy
        lda #<str_kondisk
        sta q0
        lda #>str_kondisk
        sta q0+1
        jsr strcat
        lda #<iv_buf
        ldy #>iv_buf
        rts
.where: cpx #2
        bne .date
        lda o_parent,y
        cmp #MAXOBJ
        bcc +
        lda #<str_desktop
        ldy #>str_desktop
        rts
+       tax
        jsr obj_name_ptr
        lda q1
        ldy q1+1
        rts
.date:  lda o_date,y
        tax
        lda date_lo,x
        pha
        lda date_hi,x
        tay
        pla
        rts
iv_buf: !fill 20

kind_lo: !byte <str_k_disk, <str_k_trash, <str_k_folder, <str_k_app, <str_k_doc, <str_k_sys
kind_hi: !byte >str_k_disk, >str_k_trash, >str_k_folder, >str_k_app, >str_k_doc, >str_k_sys
date_lo: !byte <str_d0, <str_d1, <str_d2, <str_d3, <str_d4, <str_d5, <str_d6
date_hi: !byte >str_d0, >str_d1, >str_d2, >str_d3, >str_d4, >str_d5, >str_d6

; ---------------------------------------------------------------------
; Text windows: Read Me (data 0) and the Clipboard (data 1)
; ---------------------------------------------------------------------
!zone text_open
readme_open:
        lda #0
        beq text_open
clip_open:
        lda #1
text_open:
        sta u3
        ; already open?
        ldx #0
-       lda w_used,x
        beq +
        lda w_class,x
        cmp #CL_TEXT
        bne +
        lda w_data,x
        cmp u3
        bne +
        jmp win_select
+       inx
        cpx #MAXWIN
        bne -
        jsr win_alloc
        bcc +
        jmp too_many_windows
+       lda u3
        sta w_data,x
        tay
        lda text_x1,y
        sta w_x1l,x
        lda text_x2,y
        sta w_x2l,x
        lda #0
        sta w_x1h,x
        sta w_x2h,x
        lda text_y1,y
        sta w_y1,x
        lda text_y2,y
        sta w_y2,x
        lda text_title_lo,y
        sta w_titl,x
        lda text_title_hi,y
        sta w_tith,x
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_TEXT
        sta w_class,x
        jmp win_open

text_x1: !byte 24, 60
text_x2: !byte 250, 255
text_y1: !byte 22, 120
text_y2: !byte 178, 185
text_title_lo: !byte <str_o_readme, <str_clipboard
text_title_hi: !byte >str_o_readme, >str_clipboard

text_close:
        rts

!zone text_draw
text_draw:
        lda w_data,x
        bne .clip
        lda #<str_readme_text
        sta q3
        lda #>str_readme_text
        sta q3+1
        jmp .draw
.clip:  lda clip_len
        bne +
        lda #<str_clipempty
        sta q3
        lda #>str_clipempty
        sta q3+1
        jmp .draw
+       lda #<clip_buf
        sta q3
        lda #>clip_buf
        sta q3+1
.draw:  clc
        lda wc_x1
        adc #5
        sta wr_x
        lda wc_x1+1
        adc #0
        sta wr_x+1
        lda wc_y1
        clc
        adc #4
        sta wr_y
        sec
        lda wc_x2
        sbc wc_x1
        sec
        sbc #9
        sta wr_w
        lda #9
        sta wr_lh
        lda #1
        sta font
        lda #B_OR
        sta tmode
        jmp wrap_draw

