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
        jsr obj_label
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
        cmp #4
        bne -
        rts

info_labels_lo: !byte <str_kind, <str_size, <str_where, <str_modified
info_labels_hi: !byte >str_kind, >str_size, >str_where, >str_modified

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
        lda o_type,y            ; kind
        tax
        lda kind_lo,x
        pha
        lda kind_hi,x
        tay
        pla
        rts
.size:  cpx #1
        bne .where
        lda o_type,y
        cmp #T_TRASH
        bcc .vsize
        cmp #T_APP
        bcc .dash               ; (the Trash, folders)
        lda o_kl,y              ; files: "nK"
        ldx o_kh,y
        jsr utoa
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
.k:     lda #<iv_buf
        sta q1
        lda #>iv_buf
        sta q1+1
        jsr strcpy
        lda #<str_k
        sta q0
        lda #>str_k
        sta q0+1
        jsr strcat
        lda #<iv_buf
        ldy #>iv_buf
        rts
.vsize: lda o_vol,y             ; volumes: their size
        asl
        asl
        tax
        ldy #0
-       lda vol_total,x
        sta ut_v,y
        inx
        iny
        cpy #4
        bne -
        jsr kb_str
        lda #<ut_buf
        ldy #>ut_buf
        rts
.where: cpx #2
        bne .date
        lda o_parent,y
        cmp #OBJ_TRASH
        beq +
        cmp #MAXOBJ
        bcc +
        lda #<str_desktop
        ldy #>str_desktop
        rts
+       tax
        jsr obj_label
        lda q1
        ldy q1+1
        rts
.date:  lda o_dl,y              ; day month year
        ora o_dh,y
        bne +
.dash:  lda #<str_dash
        ldy #>str_dash
        rts
+       lda o_dl,y
        and #31
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
        ldy u3                  ; month: bits 8-5
        lda o_dh,y
        lsr
        lda o_dl,y
        ror
        lsr
        lsr
        lsr
        lsr
        and #15
        sec
        sbc #1
        cmp #12
        bcc +
        lda #0
+       sta t0                  ; (5 bytes each)
        asl
        asl
        adc t0
        adc #<str_months
        sta q0
        lda #>str_months
        adc #0
        sta q0+1
        jsr strcat
        ldy u3                  ; year: 1980 + bits 15-9
        lda o_dh,y
        lsr
        clc
        adc #<1980
        pha
        lda #>1980
        adc #0
        tax
        pla
        jsr utoa
        lda #<str_space
        sta q0
        lda #>str_space
        sta q0+1
        jsr strcat
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
        jsr strcat
        lda #<iv_buf
        ldy #>iv_buf
        rts
iv_buf: !fill 24

kind_lo: !byte <str_k_disk, <str_k_share, <str_k_trash, <str_k_folder, <str_k_app, <str_k_doc, <str_k_text, <str_k_sys
kind_hi: !byte >str_k_disk, >str_k_share, >str_k_trash, >str_k_folder, >str_k_app, >str_k_doc, >str_k_text, >str_k_sys

; ---------------------------------------------------------------------
; Text windows: a text document (data 0) and the Clipboard (data 1)
; ---------------------------------------------------------------------
TEXTMAX = 470
!zone text_open
; text_open: X = a text document: read it, show it (one such window)
text_open:
        stx u3
        jsr obj_path
        bcc +
        rts
+       lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        lda #0
        ldx #3
-       sta fs_off,x
        dex
        bpl -
        lda #<(TEXTMAX-1)
        sta fs_len
        lda #>(TEXTMAX-1)
        sta fs_len+1
        lda #<text_buf
        sta fs_rptr
        lda #>text_buf
        sta fs_rptr+1
        lda #CUR_WATCH
        jsr set_cursor
        jsr fs_read
        php
        pha
        lda #CUR_ARROW
        jsr set_cursor
        pla
        plp
        bcc +
        jmp fs_alert
+       ; line ends become RETURNs (CR LF: one), other control codes spaces
        lda #<text_buf
        sta q0
        sta q1
        lda #>text_buf
        sta q0+1
        sta q1+1
        lda fs_rlen
        sta t0
        lda fs_rlen+1
        sta t1
        ldy #0
.c:     lda t0
        ora t1
        beq .end
        lda t0
        bne +
        dec t1
+       dec t0
        lda (q0),y
        inc q0
        bne +
        inc q0+1
+       cmp #13
        bne +
        lda t0                  ; CR before LF: drop it
        ora t1
        beq .ret
        lda (q0),y
        cmp #10
        beq .c
.ret:   lda #13
        bne .put
+       cmp #10
        beq .ret
        cmp #32
        bcs +
        lda #32
+       cmp #127
        bcc .put
        lda #"?"
.put:   sta (q1),y
        inc q1
        bne .c
        inc q1+1
        jmp .c
.end:   lda #0
        sta (q1),y
        ldx u3                  ; the title
        jsr obj_label
        lda q1
        sta q0
        lda q1+1
        sta q0+1
        lda #<text_title
        sta q1
        lda #>text_title
        sta q1+1
        jsr strcpy
        lda #0
        jmp text_window
clip_open:
        lda #1
text_window:
        sta u3
        ; already open?  Then it shows the new text
        ldx #0
-       lda w_used,x
        beq +
        lda w_class,x
        cmp #CL_TEXT
        bne +
        lda w_data,x
        cmp u3
        bne +
        stx u2
        jsr win_select
        ldx u2
        jsr win_draw_frame
        ldx u2
        jmp win_refresh
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
text_title_lo: !byte <text_title, <str_clipboard
text_title_hi: !byte >text_title, >str_clipboard

text_close:
        rts

!zone text_draw
text_draw:
        lda w_data,x
        bne .clip
        lda #<text_buf
        sta q3
        lda #>text_buf
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
