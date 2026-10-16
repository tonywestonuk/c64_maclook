; =====================================================================
; basic_file.asm - programs as text files: Open, Save, Save As, and
; the dialogs that ask for a name or about unsaved changes
;
; A program is saved as its listing, one line to a CR.  The Finder
; opens a .bas document by starting BASIC with its path in app_doc.
; =====================================================================

doc_path:  !fill 128    ; "0:Folder/Name.bas" ("" while untitled)
doc_title: !fill 32     ; "Name"

; doc_path = app_doc, and the title from it
!zone doc_take
doc_take:
        ldx #0
-       lda app_doc,x
        sta doc_path,x
        beq +
        inx
        cpx #127
        bne -
        lda #0
        sta doc_path,x
+       jmp doc_set_title

doc_untitled:
        lda #0
        sta doc_path
        ldx #0
-       lda str_untitled,x
        sta doc_title,x
        beq +
        inx
        bne -
+       rts

; the title: the path's last name, without .bas
!zone doc_set_title
doc_set_title:
        ldx #0                  ; after the last / or :
        ldy #0
-       lda doc_path,x
        beq +
        inx
        cmp #'/'
        beq ++
        cmp #':'
        bne -
++      txa
        tay
        jmp -
+       ldx #0
-       lda doc_path,y
        beq +
        cmp #'.'
        beq +
        sta doc_title,x
        iny
        inx
        cpx #31
        bne -
+       lda #0
        sta doc_title,x
        rts

; ---------------------------------------------------------------------
; File > Open..., Save, Save As...
; ---------------------------------------------------------------------
!zone ba_open
ba_open:
        jsr ask_save
        bcs .out
        lda #0
        sta nd_buf
        lda #<str_openq
        ldy #>str_openq
        jsr name_dialog
        bcs .out
        jsr run_end
        jsr path_from_name      ; pd_buf = the path
        ldx #0
-       lda pd_buf,x
        sta doc_path,x
        beq +
        inx
        bne -
+       jsr doc_set_title
        jsr file_load
        jsr ls_reset
        jmp ls_title
.out:   rts

ba_save:
        lda doc_path
        beq ba_saveas
        jmp file_save

!zone ba_saveas
ba_saveas:
        ldx #0                  ; the name so far
-       lda doc_title,x
        sta nd_buf,x
        beq +
        inx
        bne -
+       lda #<str_saveq
        ldy #>str_saveq
        jsr name_dialog
        bcs .out
        jsr path_from_name
        ldx #0
-       lda pd_buf,x
        sta doc_path,x
        beq +
        inx
        bne -
+       jsr doc_set_title
        jsr ls_title
        jmp file_save
.out:   sec
        rts

; the Listing's title bar again
ls_title:
        ldx ls_win
        cpx #$ff
        beq +
        jsr clip_push
        jsr clip_screen
        ldx ls_win
        jsr win_get_full
        jsr clip_rect
        ldx ls_win
        jsr win_draw_frame
        jsr clip_pop
+       rts

; pd_buf = the path for the name in nd_buf: in the document's folder
; (or on the startup disk), with .bas on the end
!zone path_from_name
path_from_name:
        ldx #0                  ; a whole path ("1:...") as it is
-       lda nd_buf,x
        beq .rel
        cmp #':'
        beq .abs
        inx
        bne -
.abs:   ldx #0
-       lda nd_buf,x
        sta pd_buf,x
        beq .ext
        inx
        bne -
.rel:   ldx #0                  ; the document's folder: up to its last / or :
        ldy #0
-       lda doc_path,x
        beq +
        inx
        cmp #'/'
        beq ++
        cmp #':'
        bne -
++      txa
        tay
        jmp -
+       cpy #0
        bne +
        lda #'0'                ; untitled: the startup disk
        sta pd_buf
        lda #':'
        sta pd_buf+1
        ldx #2
        jmp .name
+       ldx #0
-       lda doc_path,x
        sta pd_buf,x
        inx
        dey
        bne -
.name:  ldy #0
-       lda nd_buf,y
        sta pd_buf,x
        beq .ext
        inx
        iny
        bne -
.ext:   ldx #0                  ; ends in .bas?
-       lda pd_buf,x
        beq +
        inx
        bne -
+       cpx #4
        bcc .add
        lda pd_buf-4,x
        cmp #'.'
        bne .add
        lda pd_buf-3,x
        and #$df
        cmp #'B'
        bne .add
        lda pd_buf-2,x
        and #$df
        cmp #'A'
        bne .add
        lda pd_buf-1,x
        and #$df
        cmp #'S'
        beq .out
.add:   ldy #0
-       lda str_dotbas,y
        sta pd_buf,x
        beq .out
        inx
        iny
        bne -
.out:   rts
pd_buf: !fill 128

; ---------------------------------------------------------------------
; Loading: the file into the top of the workspace, then a line at a
; time into the program
; ---------------------------------------------------------------------
!zone file_load
file_load:
        jsr prog_new
        lda #<doc_path
        sta q0
        lda #>doc_path
        sta q0+1
        lda #0
        sta fs_off
        sta fs_off+1
        sta fs_off+2
        sta fs_off+3
        sec                     ; as much as there is room for
        lda #<WS_END
        sbc #<(WS_START+512)
        sta fs_len
        lda #>WS_END
        sbc #>(WS_START+512)
        sta fs_len+1
        lda #<(WS_START+512)
        sta fs_rptr
        lda #>(WS_START+512)
        sta fs_rptr+1
        jsr fs_read
        bcc +
        jmp file_error
+       lda fs_rlen             ; the text, moved to the top
        sta mv_n
        lda fs_rlen+1
        sta mv_n+1
        lda #<(WS_START+512)
        sta mv_src
        lda #>(WS_START+512)
        sta mv_src+1
        sec
        lda #<WS_END
        sbc fs_rlen
        sta mv_dst
        sta fl_p
        lda #>WS_END
        sbc fs_rlen+1
        sta mv_dst+1
        sta fl_p+1
        jsr memmove
        lda #1                  ; (the lines are linked at the end)
        sta no_relink
.line:  lda fl_p                ; the end?
        cmp #<WS_END
        bne +
        lda fl_p+1
        cmp #>WS_END
        bne +
        jmp .done
+       ldx #0                  ; the next line to ed_buf
.chr:   lda fl_p
        cmp #<WS_END
        bne +
        lda fl_p+1
        cmp #>WS_END
        bne +
        lda #0
        beq .eol
+       ldy #0
        lda (fl_p),y
        inc fl_p
        bne +
        inc fl_p+1
+       cmp #13
        beq .eol
        cmp #10
        beq .eol
        cmp #9                  ; tabs: spaces
        bne +
        lda #' '
+       cmp #32
        bcc .chr
        cmp #127
        bcs .chr
        cpx #ED_MAX
        bcs .chr
        sta ed_buf,x
        inx
        jmp .chr
.eol:   sta fl_term
        lda #0
        sta ed_buf,x
        stx ed_len
        lda fl_term             ; (the LF of a CR LF: nothing)
        cmp #10
        bne +
        lda fl_prev
        cmp #13
        bne +
        cpx #0
        beq .skip
+       clc                     ; room for the line and its names?
        lda prog_end
        adc #<300
        sta za
        lda prog_end+1
        adc #>300
        cmp fl_p+1
        bcs .mem
        jsr crunch
        bcs .err
        lda nlines
        cmp #MAXLINES
        bcs .mem
        lda #0
        sta prog_rep
        lda nlines
        jsr prog_put
        bcs .mem
.skip:  lda fl_term
        sta fl_prev
        jmp .line
.done:  lda #0
        sta no_relink
        jsr relink              ; (links and numbers, once)
        lda #0
        sta ed_dirty
        sta doc_dirty
        sta ed_top
        sta ed_col
        jsr ed_open             ; (line 0, to edit)
        clc
        rts
.mem:   lda #<str_e_mem
        ldy #>str_e_mem
.err:   jsr alert_stop
        lda #0
        sta ed_dirty
        sta no_relink
        jsr relink
        lda #0
        jsr ed_open
        sec
        rts
fl_term: !byte 0
fl_prev: !byte 0

; a file call failed: say why (A = the status)
!zone file_error
file_error:
        ldx #fe_end-fe_codes-1
-       cmp fe_codes,x
        beq +
        dex
        bpl -
        ldx #fe_end-fe_codes
+       txa
        asl
        tax
        lda fe_msgs,x
        ldy fe_msgs+1,x
        jsr alert_stop
        sec
        rts
fe_codes: !byte FS_NOTFOUND, FS_NOWIC64, FS_FULL, FS_DENIED, FS_NOSHARE
fe_end:
fe_msgs:  !word str_fe_notfound, str_fe_nowic, str_fe_full, str_fe_denied
          !word str_fe_noshare, str_fe_other

; ---------------------------------------------------------------------
; Saving: the listing, line by line, above the program; then written
; ---------------------------------------------------------------------
!zone file_save
file_save:
        jsr ed_commit
        bcc +
        rts
+       clc
        lda prog_end
        adc #1
        sta fs_dptr
        sta fs_p
        lda prog_end+1
        adc #0
        sta fs_dptr+1
        sta fs_p+1
        lda #0
        sta fs_i
.line:  lda fs_i
        cmp nlines
        beq .write
        jsr line_addr
        jsr detok
        clc                     ; room?
        lda fs_p
        adc ls_len
        lda fs_p+1
        adc #1
        cmp #>WS_END
        bcs .mem
        ldx #0
        ldy #0
-       cpx ls_len
        beq +
        lda LS_BUF,x
        and #$7f
        sta (fs_p),y
        iny
        inx
        bne -
+       lda #13
        sta (fs_p),y
        iny
        tya
        clc
        adc fs_p
        sta fs_p
        bcc +
        inc fs_p+1
+       inc fs_i
        jmp .line
.write: sec
        lda fs_p
        sbc fs_dptr
        sta fs_dlen
        lda fs_p+1
        sbc fs_dptr+1
        sta fs_dlen+1
        lda #FSW_REPLACE
        sta fs_mode
        lda #0
        sta fs_off
        sta fs_off+1
        sta fs_off+2
        sta fs_off+3
        lda #<doc_path
        sta q0
        lda #>doc_path
        sta q0+1
        jsr fs_write
        bcc +
        jmp file_error
+       lda #0
        sta doc_dirty
        clc
        rts
.mem:   lda #<str_e_mem
        ldy #>str_e_mem
        jsr alert_stop
        sec
        rts
fs_i:   !byte 0

; ---------------------------------------------------------------------
; Unsaved changes: Save, Don't Save, or Cancel (carry set)
; ---------------------------------------------------------------------
!zone ask_save
ask_save:
        jsr ed_commit
        bcs .cancel
        lda doc_dirty
        bne +
        clc
        rts
+       ldx #0                  ; Save changes to "name"?
        ldy #0
-       lda str_askq1,y
        beq +
        sta msg_buf,x
        inx
        iny
        bne -
+       ldy #0
-       lda doc_title,y
        beq +
        sta msg_buf,x
        inx
        iny
        bne -
+       ldy #0
-       lda str_askq2,y
        sta msg_buf,x
        beq +
        inx
        iny
        bne -
+       lda #<msg_buf
        sta ad_msg
        lda #>msg_buf
        sta ad_msg+1
        lda #0
        sta ad_field
        lda #3
        sta ad_nbtn
        lda #<btn_yes
        sta ad_btns
        lda #>btn_yes
        sta ad_btns+1
        jsr app_dialog
        cmp #1                  ; No
        beq .no
        cmp #0
        bne .cancel
        jmp ba_save             ; Yes (carry set if that fails)
.no:    clc
        rts
.cancel:
        sec
        rts
btn_yes:    !word str_b_yes, str_b_no, str_b_cancel
btn_ok:     !word str_b_ok, str_b_cancel

; name_dialog: A/Y = the question; nd_buf = the answer (it starts with
; what is there).  Carry set if cancelled.
!zone name_dialog
name_dialog:
        sta ad_msg
        sty ad_msg+1
        lda nd_buf              ; (a name to start with is selected)
        sta nd_sel
        lda #1
        sta ad_field
        lda #2
        sta ad_nbtn
        lda #<btn_ok
        sta ad_btns
        lda #>btn_ok
        sta ad_btns+1
        jsr app_dialog
        cmp #0
        bne +
        lda nd_buf              ; (an empty name is a cancel)
        beq +
        clc
        rts
+       sec
        rts
nd_buf: !fill 41
nd_sel: !byte 0
ND_MAX = 40

; ---------------------------------------------------------------------
; app_dialog: ad_msg, a text field (ad_field), ad_nbtn buttons named at
; ad_btns (button 0, the default, on the right).  A = the button.
; ---------------------------------------------------------------------
ad_msg:   !word 0
ad_field: !byte 0
ad_nbtn:  !byte 0
ad_btns:  !word 0
ad_res:   !byte 0
AD_W = 240
AD_H = 76

!zone app_dialog
app_dialog:
        lda #DLG_CUSTOM
        sta dlg_kind
        lda #<ad_draw
        sta dlg_custom
        lda #>ad_draw
        sta dlg_custom+1
        lda #AD_H
        sta dlg_h
        lda #>(40+AD_W-1)
        sta dlg_x2h
        lda #40
        ldx #50
        ldy #<(40+AD_W-1)
        jsr dlg_open
        bcc .loop
        lda ad_nbtn             ; no window: as Cancel
        sec
        sbc #1
        rts
.loop:  jsr wait_click_or_key
        cmp #0
        bne .bf585
        jmp .click
.bf585:
        cmp #K_RETURN
        bne +
        lda #0
        bne .bf587
        jmp .done
.bf587:
+       cmp #K_ESC
        bne +
        lda ad_nbtn
        sec
        sbc #1
        beq .bf597
        jmp .done
.bf597:
+       ldx ad_field
        beq .loop
        ldx nd_sel              ; the name is selected: the key replaces it
        beq +
        ldx #0
        stx nd_sel
        stx nd_buf
        cmp #K_DEL
        bne +
        jmp .field
+       cmp #K_DEL
        bne +
        ldx #0
-       lda nd_buf,x
        beq ++
        inx
        bne -
++      txa
        beq .loop
        lda #0
        sta nd_buf-1,x
        jmp .field
+       cmp #32
        bcc .loop
        cmp #127
        bcs .loop
        cmp #'/'                ; (a name, not a path... but : is allowed)
        beq .loop
        tay
        ldx #0
-       lda nd_buf,x
        beq +
        inx
        bne -
+       cpx #ND_MAX
        bcs .loop
        tya
        sta nd_buf,x
        lda #0
        sta nd_buf+1,x
.field: jsr clip_push
        jsr clip_screen
        ldx dlg_win
        jsr win_get_content
        jsr clip_rect
        jsr ad_draw_field
        jsr clip_pop
        jmp .loop
.click: ldx #0                  ; a button?
-       stx ad_res
        jsr ad_btn_rect
        jsr mouse_in_rect
        bcc +
        ldx ad_res
        inx
        cpx ad_nbtn
        bne -
        jmp .loop
+       lda ad_res
.done:  sta ad_res
        jsr dlg_close
        lda ad_res
        rts

; M_DRAW: the message, the field, the buttons
ad_draw:
        lda #B_OR
        sta tmode
        lda #0
        sta font
        clc
        lda wc_x1
        adc #12
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
        lda ad_msg
        sta tstr
        lda ad_msg+1
        sta tstr+1
        jsr draw_text
        lda ad_field
        beq +
        jsr ad_draw_field
+       ldx #0
-       stx ad_i
        jsr ad_btn_rect
        jsr set_black
        jsr frame_round
        ldx ad_i
        bne +
        lda #3                  ; the default: a thick outline
        jsr rect_outset
        jsr frame_round
        lda #1
        jsr rect_inset
        jsr frame_round
        lda #2
        jsr rect_inset
        ldx ad_i
+       lda ad_btns             ; its name, in the middle
        sta pb
        lda ad_btns+1
        sta pb+1
        lda ad_i
        asl
        tay
        lda (pb),y
        sta tstr
        iny
        lda (pb),y
        sta tstr+1
        lda #0
        sta font
        jsr text_width
        lda twidth              ; tx = the middle - the width / 2
        lsr
        sta za
        clc
        lda rx1
        adc rx2
        sta tx
        lda rx1+1
        adc rx2+1
        lsr
        sta tx+1
        ror tx
        sec
        lda tx
        sbc za
        sta tx
        lda tx+1
        sbc #0
        sta tx+1
        lda ry1
        clc
        adc #3
        sta ty
        lda #0
        sta ty+1
        jsr draw_text
        ldx ad_i
        inx
        cpx ad_nbtn
        beq +
        jmp -
+       rts
ad_i:   !byte 0

; the text field, with what is typed and a caret
ad_draw_field:
        +rect 0, 0, 0, 0
        clc
        lda wc_x1
        adc #12
        sta rx1
        lda wc_x1+1
        adc #0
        sta rx1+1
        sec
        lda wc_x2
        sbc #12
        sta rx2
        lda wc_x2+1
        sbc #0
        sta rx2+1
        lda wc_y1
        clc
        adc #24
        sta ry1
        adc #14
        sta ry2
        jsr fill_white
        jsr set_black
        jsr frame_rect
        lda rx1
        clc
        adc #3
        sta tx
        lda rx1+1
        adc #0
        sta tx+1
        lda ry1
        clc
        adc #3
        sta ty
        lda #0
        sta ty+1
        lda #<nd_buf
        ldy #>nd_buf
        jsr draw_plain
        lda nd_sel              ; selected: inverted, no caret
        beq +
        lda tx
        sta rx1
        lda tx+1
        sta rx1+1
        clc
        lda tx
        adc twidth
        sta rx2
        lda tx+1
        adc twidth+1
        sta rx2+1
        lda ty
        sta ry1
        clc
        adc #8
        sta ry2
        jmp invert_rect
+       clc                     ; the caret after it
        lda tx
        adc twidth
        sta rx1
        sta rx2
        lda tx+1
        adc twidth+1
        sta rx1+1
        sta rx2+1
        lda ty
        sta ry1
        clc
        adc #8
        sta ry2
        jmp fill_black

; rx1..ry2 = button X (0 on the right), from dlg_win's content
ad_btn_rect:
        stx za
        ldx dlg_win
        jsr win_get_content
        sec                     ; x2 = wc_x2 - 12 - 64 * i
        lda wc_x2
        sbc #12
        sta rx2
        lda wc_x2+1
        sbc #0
        sta rx2+1
        ldx za
-       dex
        bmi +
        sec
        lda rx2
        sbc #64
        sta rx2
        bcs -
        dec rx2+1
        jmp -
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
