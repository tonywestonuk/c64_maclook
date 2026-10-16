; =====================================================================
; basic_edit.asm - the Listing window: the program, edited a line at a
; time.  The line with the caret is plain text in ed_buf; leaving it
; tokenizes it back into the program (as QuickBASIC does), and it is
; then listed with its keywords in bold.
; =====================================================================

LH      = 10            ; line height
LS_TOP  = 3             ; the first line's top, in the content
LS_LEFT = 4
LS_VIS  = 16            ; lines in view
ED_MAX  = 160           ; the longest line, in characters
MAXLINES = 250

nlines:    !byte 0
ed_line:   !byte 0      ; the caret's line (nlines: the empty one after the end)
ed_top:    !byte 0      ; the first line in view
ed_col:    !byte 0
ed_len:    !byte 0
ed_dirty:  !byte 0      ; ed_buf differs from the program's line
ls_con:    !byte 0      ; the caret is drawn
ls_cx:     !word 0      ; where
ls_cy:     !byte 0
ls_ctime:  !byte 0
ls_hilite: !byte $ff    ; a line shown inverted (where an error was)
ls_quiet:  !byte 0      ; no drawing (pasting)
prog_rep:  !byte 0      ; prog_put: 1 replace, 0 insert
doc_dirty: !byte 0      ; changed since saved
ed_buf:    !fill ED_MAX+1

; ---------------------------------------------------------------------
; The program store, as BASIC V2 keeps it: a 0, then the lines ([link]
; [number][tokens][0]), the last a hidden one that ends the program
; (TK_XEND), then [0 0].  nlines doesn't count the hidden line.
; ---------------------------------------------------------------------
prog_base: !word 0      ; the first line
prog_end:  !word 0      ; the [0 0] after the last

!zone prog_new
prog_new:
        ldx #xend_line_end-xend_line-1
-       lda xend_line,x
        sta WS_START,x
        dex
        bpl -
        lda #<(WS_START+1)
        sta prog_base
        lda #>(WS_START+1)
        sta prog_base+1
        lda #<(WS_START+7)
        sta prog_end
        lda #>(WS_START+7)
        sta prog_end+1
        jsr relink
        lda #0
        sta nlines
        sta ed_line
        sta ed_top
        sta ed_col
        sta ed_len
        sta ed_buf
        sta ed_dirty
        sta doc_dirty
        lda #$ff
        sta ls_hilite
        rts
xend_line:
        !byte 0, 0, 0, $ff, $ff, TK_XEND, 0, 0, 0
xend_line_end:

; pa = the address of line A (the hidden last line if there are fewer)
!zone line_addr
line_addr:
        tax
        lda prog_base
        sta pa
        lda prog_base+1
        sta pa+1
.l:     txa
        beq .done
        ldy #1
        lda (pa),y
        beq .done               ; (the end)
        pha
        dey
        lda (pa),y
        sta pa
        pla
        sta pa+1
        dex
        jmp .l
.done:  rts

; A = the length of the line at pa
!zone line_len
line_len:
        ldy #4
-       lda (pa),y
        beq +
        iny
        bne -
+       iny
        tya
        rts

; relink: every line's link (and the numbers of the lines without
; their own, in between the others: never a multiple of 64)
!zone relink
relink: lda prog_base
        sta pb
        lda prog_base+1
        sta pb+1
        lda #0
        sta rl_n
        sta rl_n+1
        sta rl_i
.l:     lda pb                  ; at the end?
        cmp prog_end
        bne +
        lda pb+1
        cmp prog_end+1
        beq .out
+       lda rl_i                ; (not the hidden line's number)
        cmp nlines
        bcs .link
        ldy #2
        lda (pb),y
        and #63
        bne .auto
        lda (pb),y              ; its own: the next ones follow it
        sta rl_n
        iny
        lda (pb),y
        sta rl_n+1
        jmp .link
.auto:  inc rl_n
        bne +
        inc rl_n+1
+       lda rl_n
        and #63
        beq .auto
        ldy #2
        lda rl_n
        sta (pb),y
        iny
        lda rl_n+1
        sta (pb),y
.link:  ldy #4                  ; the next line: after its 0
-       lda (pb),y
        beq +
        iny
        bne -
+       iny
        tya
        clc
        adc pb
        sta rl_nx
        lda pb+1
        adc #0
        sta rl_nx+1
        ldy #0
        lda rl_nx
        sta (pb),y
        iny
        lda rl_nx+1
        sta (pb),y
        lda rl_nx
        sta pb
        lda rl_nx+1
        sta pb+1
        inc rl_i
        jmp .l
.out:   rts
rl_nx:  !word 0
rl_n:   !word 0
rl_i:   !byte 0

; prog_put: the line in cr_buf (cr_len long) replaces line A (prog_rep
; = 1) or goes in before it (prog_rep = 0).  Carry set if there is no
; room.
!zone prog_put
prog_put:
        pha
        jsr run_end             ; (a changed program can't go on)
        pla
        ldx no_relink           ; loading: always at the end, just before
        beq +                   ; the hidden line (6 bytes before prog_end)
        sec
        lda prog_end
        sbc #6
        sta pa
        lda prog_end+1
        sbc #0
        sta pa+1
        jmp ++
+       jsr line_addr
++
        lda #0
        ldy prog_rep
        beq +
        jsr line_len
+       sta za                  ; the old length
        lda cr_len              ; the new one
        sta zb
        ; room: prog_end + new - old must stay below WS_END - 256
        clc
        lda prog_end
        adc zb
        sta zw
        lda prog_end+1
        adc #0
        sta zw+1
        sec
        lda zw
        sbc za
        lda zw+1
        sbc #0
        cmp #>(WS_END-$100)
        bcc +
        rts
+       lda za                  ; the tail moves from pa+old to pa+new
        ldx zb
        jsr prog_shift
        ldy zb                  ; and the line goes in
        dey
-       lda cr_buf,y
        sta (pa),y
        dey
        bpl -
        lda prog_rep            ; (one more line)
        bne +
        inc nlines
+       lda no_relink           ; (loading: once at the end)
        bne +
        jsr relink
+       clc
        rts
no_relink: !byte 0

; delete line A
!zone prog_del
prog_del:
        pha
        jsr run_end
        pla
        cmp nlines
        bcs +
        jsr line_addr
        jsr line_len
        ldx #0
        jsr prog_shift
        dec nlines
        jmp relink
+       rts

; move the program after pa+A (to its end marker) to pa+X, and prog_end
; with it
!zone prog_shift
prog_shift:
        sta za
        stx zb
        clc
        lda pa
        adc za
        sta mv_src
        lda pa+1
        adc #0
        sta mv_src+1
        clc
        lda pa
        adc zb
        sta mv_dst
        lda pa+1
        adc #0
        sta mv_dst+1
        sec                     ; count = prog_end + 2 - src
        lda prog_end
        sbc mv_src
        sta mv_n
        lda prog_end+1
        sbc mv_src+1
        sta mv_n+1
        clc
        lda mv_n
        adc #2
        sta mv_n
        bcc +
        inc mv_n+1
+       jsr memmove
        sec                     ; prog_end += new - old
        lda zb
        sbc za
        sta zw
        lda #0
        sbc #0
        sta zw+1
        clc
        lda prog_end
        adc zw
        sta prog_end
        lda prog_end+1
        adc zw+1
        sta prog_end+1
        rts

zw:     !word 0

; memmove: mv_n bytes from mv_src to mv_dst, overlapping or not
mv_src: !word 0
mv_dst: !word 0
mv_n:   !word 0
!zone memmove
memmove:
        lda mv_n
        ora mv_n+1
        beq .rts
        lda mv_dst+1
        cmp mv_src+1
        bne +
        lda mv_dst
        cmp mv_src
+       beq .rts
        bcs .down               ; dst above src: from the end
        lda mv_src
        sta pb
        lda mv_src+1
        sta pb+1
        lda mv_dst
        sta pc
        lda mv_dst+1
        sta pc+1
        ldy #0
        ldx mv_n+1
        beq .part
.page:  lda (pb),y
        sta (pc),y
        iny
        bne .page
        inc pb+1
        inc pc+1
        dex
        bne .page
.part:  ldx mv_n
        beq .rts
-       lda (pb),y
        sta (pc),y
        iny
        dex
        bne -
.rts:   rts
.down:  clc                     ; pointers to the last page
        lda mv_src
        sta pb
        lda mv_src+1
        adc mv_n+1
        sta pb+1
        clc
        lda mv_dst
        sta pc
        lda mv_dst+1
        adc mv_n+1
        sta pc+1
        ldy mv_n                ; the odd bytes first
        beq .pages
-       dey
        lda (pb),y
        sta (pc),y
        tya
        bne -
.pages: ldx mv_n+1
        beq .rts
.page2: dec pb+1
        dec pc+1
        ldy #0
-       dey
        lda (pb),y
        sta (pc),y
        tya
        bne -
        dex
        bne .page2
        rts

; ---------------------------------------------------------------------
; The line being edited
; ---------------------------------------------------------------------
; ed_open: line A into ed_buf
!zone ed_open
ed_open:
        sta ed_line
        lda #0
        sta ed_dirty
        sta ed_len
        lda ed_line
        cmp nlines
        bcs .end
        jsr line_addr
        jsr detok
        ldx #0
-       cpx ls_len
        beq +
        cpx #ED_MAX
        beq +
        lda LS_BUF,x
        and #$7f
        sta ed_buf,x
        inx
        bne -
+       stx ed_len
.end:   ldx ed_len
        lda #0
        sta ed_buf,x
        lda ed_col
        cmp ed_len
        bcc +
        lda ed_len
        sta ed_col
+       rts

ed_enter:
        lda ed_line
        jsr ed_open
        jmp ls_show

; ed_commit: the line in ed_buf back into the program.  Carry set (and
; an alert) if it doesn't fit.
!zone ed_commit
ed_commit:
        lda ed_dirty
        beq .ok
        jsr run_end             ; a changed program can't go on
        jsr crunch
        bcs .err
        lda ed_line
        cmp nlines
        bcc .rep
        lda cr_buf+4            ; the empty line at the end: a new line,
        ora ed_keep             ; unless it's blank (Return keeps it)
        beq .clean
        lda nlines
        cmp #MAXLINES
        bcs .full
        lda #0
        sta prog_rep
        lda ed_line
        jsr prog_put
        bcs .full
        jmp .clean
.rep:   lda #1
        sta prog_rep
        lda ed_line
        jsr prog_put
        bcs .full
.clean: lda #0
        sta ed_dirty
        lda #1
        sta doc_dirty
.ok:    lda #0
        sta ed_keep
        clc
        rts
.full:  lda #<str_e_mem
        ldy #>str_e_mem
.err:   jsr alert_stop          ; A/Y = the message
        lda #0
        sta ed_keep
        sec
        rts
ed_keep: !byte 0

; ---------------------------------------------------------------------
; Keys
; ---------------------------------------------------------------------
!zone ls_key
ls_key:
        jsr ls_unhilite
        lda key_char
        cmp #K_RETURN
        bne +
        jmp ed_return
+       cmp #K_DEL
        bne +
        jmp ed_del
+       cmp #K_LEFT
        bne +
        jmp ed_left
+       cmp #K_RIGHT
        bne +
        jmp ed_right
+       cmp #K_UP
        bne +
        jmp ed_up
+       cmp #K_DOWN
        bne +
        jmp ed_down
+       cmp #32
        bcc .out
        cmp #127
        bcs .out
        jmp ed_insert
.out:   rts

; a character at the caret
!zone ed_insert
ed_insert:
        sta za
        ldx ed_len
        cpx #ED_MAX
        bcc +
        jmp beep
+       inx                     ; make room
-       lda ed_buf-1,x
        sta ed_buf,x
        dex
        cpx ed_col
        beq +
        bcs -
+       lda za
        ldx ed_col
        sta ed_buf,x
        inc ed_col
        inc ed_len
        lda #1
        sta ed_dirty
        lda ed_line
        jmp ls_line_shown

; Delete: the character before the caret, or join with the line above
!zone ed_del
ed_del:
        ldx ed_col
        beq .join
-       lda ed_buf,x
        sta ed_buf-1,x
        inx
        cpx ed_len
        bcc -
        beq -
        dec ed_col
        dec ed_len
        lda #1
        sta ed_dirty
        lda ed_line
        jmp ls_line_shown
.join:  lda ed_line
        bne +
        rts
+       ldx #0                  ; keep this line's text
-       lda ed_buf,x
        sta cr_buf,x
        beq +
        inx
        bne -
+       lda ed_line             ; it goes from the program
        cmp nlines
        bcs +
        jsr prog_del
        lda #1
        sta doc_dirty
+       lda #0                  ; onto the end of the line above
        sta ed_dirty
        lda #ED_MAX
        sta ed_col
        ldx ed_line
        dex
        txa
        jsr ed_open
        ldx ed_len
        ldy #0
-       lda cr_buf,y
        beq +
        cpx #ED_MAX
        bcs +
        sta ed_buf,x
        inx
        iny
        bne -
+       lda #0
        sta ed_buf,x
        stx ed_len
        lda #1
        sta ed_dirty
        jmp ls_from_line

; Return: the line splits at the caret; the new line is indented as
; this one
!zone ed_return
ed_return:
        ldx #0                  ; this line's indent
-       lda ed_buf,x
        cmp #' '
        bne +
        inx
        bne -
+       cpx ed_col
        bcc +
        ldx ed_col
+       stx er_ind
        ldx ed_col              ; the text after the caret to cr_buf
        ldy #0
-       lda ed_buf,x
        sta cr_buf,y
        beq +
        inx
        iny
        bne -
+       ldx ed_col              ; this line ends at the caret
        lda #0
        sta ed_buf,x
        stx ed_len
        lda #1
        sta ed_dirty
        ldx #0                  ; the new line: indent and the rest
-       lda cr_buf,x
        sta ls_tmp,x
        beq +
        inx
        bne -
+       lda ed_line
        cmp nlines
        bcc .mid
        lda #1                  ; at the end: even an empty line is kept
        sta ed_keep
        jsr ed_commit
        bcc +
        rts
+       lda ed_line
        cmp nlines              ; (a blank line at the end isn't kept)
        bcs +
        inc ed_line
+       jmp .new
.mid:   jsr ed_commit
        bcc +
        rts
+       inc ed_line             ; an empty line below, then fill it
        jsr cr_blank
        lda #0
        sta prog_rep
        lda ed_line
        jsr prog_put
        bcc +
        jmp ed_full
.new:   ldx #0                  ; ed_buf = indent + the rest
        lda #' '
-       cpx er_ind
        beq +
        sta ed_buf,x
        inx
        bne -
+       ldy #0
-       lda ls_tmp,y
        beq +
        cpx #ED_MAX
        bcs +
        sta ed_buf,x
        inx
        iny
        bne -
+       lda #0
        sta ed_buf,x
        stx ed_len
        lda er_ind
        sta ed_col
        lda #1
        sta ed_dirty
        sta doc_dirty
        lda ed_line
        sec
        sbc #1
        jmp ls_from_line

er_ind: !byte 0

ed_full:
        lda #<str_e_mem
        ldy #>str_e_mem
        jmp alert_stop

; cr_buf = a blank line
cr_blank:
        ldx #4
        lda #0
-       sta cr_buf,x
        dex
        bpl -
        inc cr_buf+2
        lda #5
        sta cr_len
        rts

ls_tmp = LS_BUF          ; (free while a line is split)

!zone ed_moves
ed_left:
        lda ed_col
        beq +
        dec ed_col
        jmp ls_caret_moved
+       lda ed_line
        beq .out
        lda #ED_MAX
        sta ed_col
        lda ed_line
        sec
        sbc #1
        jmp ed_goto
ed_right:
        lda ed_col
        cmp ed_len
        bcs +
        inc ed_col
        jmp ls_caret_moved
+       lda ed_line
        cmp nlines
        bcs .out
        lda #0
        sta ed_col
        lda ed_line
        clc
        adc #1
        jmp ed_goto
ed_up:
        lda ed_line
        beq .out
        sec
        sbc #1
        jmp ed_goto
ed_down:
        lda ed_line
        cmp nlines
        bcs .out
        adc #1
        jmp ed_goto
.out:   rts

; to line A, leaving this one (which is then listed as the program has it)
!zone ed_goto
ed_goto:
        sta eg_to
        jsr ed_commit
        bcs .out
        jsr ls_caret_off
        lda ed_line
        sta eg_from
        lda eg_to
        jsr ed_open
        lda eg_from
        jsr ls_line_shown       ; the old line, listed
        lda ed_line
        jmp ls_line_shown
.out:   rts
eg_to:   !byte 0
eg_from: !byte 0

; ---------------------------------------------------------------------
; Drawing
; ---------------------------------------------------------------------
; clip to the Listing's content, if it is in front; carry set if not
; (then nothing is drawn: it is redrawn when it comes to the front)
!zone ls_clip
ls_clip:
        lda ls_quiet
        bne .no
        ldx ls_win
        cpx #$ff
        beq .no
        cpx zlist
        bne .no
        jsr clip_push
        jsr clip_screen
        ldx ls_win
        jsr win_get_content
        jsr clip_rect
        clc
        rts
.no:    sec
        rts

; M_DRAW: everything (the content is white)
!zone ls_draw
ls_draw:
        lda #0
        sta ls_con
        lda ed_top
        sta ls_i
-       lda ls_i
        jsr ls_draw_line
        inc ls_i
        lda ls_i
        sec
        sbc ed_top
        cmp #LS_VIS
        bcc -
        rts
ls_i:   !byte 0
ls_j:   !byte 0

; line A changed: show it again (and make sure the caret is in view)
ls_line_shown:
        sta ls_ln
        jsr ls_show
        bcs ls_caret_moved      ; (all of it was drawn again)
        jsr ls_clip
        bcs ls_caret_moved
        jsr ls_caret_off
        lda ls_ln
        jsr ls_clear_line
        lda ls_ln
        jsr ls_draw_line
        jsr clip_pop
        jmp ls_caret_moved
ls_ln:  !byte 0

; lines A to the bottom changed
!zone ls_from_line
ls_from_line:
        sta ls_j
        jsr ls_show
        bcs ls_caret_moved
        jsr ls_bar
        jsr ls_clip
        bcs ls_caret_moved
        jsr ls_caret_off
        lda ls_j
        cmp ed_top
        bcs .l
        lda ed_top
        sta ls_j
.l:     lda ls_j
        sec
        sbc ed_top
        cmp #LS_VIS
        bcs +
        lda ls_j
        jsr ls_clear_line
        lda ls_j
        jsr ls_draw_line
        inc ls_j
        bne .l
+       jsr clip_pop
        ; fall through

; the caret moved: draw it now, and blink from there
ls_caret_moved:
        jsr ls_caret_off
        lda #0
        sta ls_con
        lda #0
        sta ls_ctime
        jmp ls_caret_on

; white behind line A (in view)
ls_clear_line:
        jsr ls_line_rect
        bcs +
        jmp fill_white
+       rts

; rx1..ry2 = line A's strip of the content; carry set if not in view
!zone ls_line_rect
ls_line_rect:
        jsr ls_line_y
        bcs +
        lda wc_x1
        sta rx1
        lda wc_x1+1
        sta rx1+1
        lda wc_x2
        sta rx2
        lda wc_x2+1
        sta rx2+1
        lda za
        sec
        sbc #1
        sta ry1
        clc
        adc #LH-1
        sta ry2
        clc
+       rts

; za = the screen y of line A's text; carry set if it isn't in view
!zone ls_line_y
ls_line_y:
        sec
        sbc ed_top
        bcc .no
        cmp #LS_VIS
        bcs .no
        tax
        lda #LS_TOP
        clc
-       dex
        bmi +
        adc #LH
        bcc -
+       adc wc_y1
        sta za
        clc
        rts
.no:    sec
        rts

; draw line A (clipped already, its place white)
!zone ls_draw_line
ls_draw_line:
        sta zc
        jsr ls_line_y
        bcc +
        rts
+       lda za
        sta ty
        lda #0
        sta ty+1
        clc
        lda wc_x1
        adc #LS_LEFT
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda zc
        cmp ed_line
        bne .listed
        lda #<ed_buf            ; the line being edited: as typed
        ldy #>ed_buf
        jsr draw_plain
        jmp .hil
.listed:
        cmp nlines
        bcs .out
        jsr line_addr
        jsr detok
        jsr draw_listed
.hil:   lda zc
        cmp ls_hilite
        bne .out
        lda zc                  ; (an error's line, inverted)
        jsr ls_line_rect
        bcs .out
        jmp invert_rect
.out:   rts

; ---------------------------------------------------------------------
; The caret: a line before the character at ed_col, blinking
; ---------------------------------------------------------------------
!zone ls_caret
ls_caret_on:
        lda ls_con
        bne .out
        jsr ls_clip
        bcs .out
        lda ed_line
        jsr ls_line_y
        bcs .pop
        lda za
        sta ls_cy
        ldx #0                  ; x: the width of the text before it
        stx zw
        stx zw+1
-       cpx ed_col
        beq +
        lda ed_buf,x
        jsr char_width
        clc
        adc zw
        sta zw
        bcc ++
        inc zw+1
++      inx
        bne -
+       clc
        lda wc_x1
        adc #LS_LEFT-1
        adc zw
        sta ls_cx
        lda wc_x1+1
        adc zw+1
        sta ls_cx+1
        lda #1
        sta ls_con
        jsr ls_caret_xor
.pop:   jsr clip_pop
.out:   rts

ls_caret_off:
        lda ls_con
        beq .out
        jsr ls_clip
        bcs .out
        lda #0
        sta ls_con
        jsr ls_caret_xor
        jmp clip_pop

ls_caret_xor:
        lda ls_cx
        sta rx1
        sta rx2
        lda ls_cx+1
        sta rx1+1
        sta rx2+1
        lda ls_cy
        sta ry1
        clc
        adc #7
        sta ry2
        jmp invert_rect

; M_IDLE: blink the caret while the Listing is in front
!zone ls_idle
ls_idle:
        cpx zlist
        bne .out
        lda jiffy
        cmp ls_last
        beq .out
        sta ls_last
        inc ls_ctime
        lda ls_ctime
        cmp caret_blink
        bcc .out
        lda #0
        sta ls_ctime
        lda ls_con
        beq +
        jmp ls_caret_off
+       jmp ls_caret_on
.out:   rts
ls_last: !byte 0

; ---------------------------------------------------------------------
; Scrolling
; ---------------------------------------------------------------------
; make the caret's line visible; carry set if the view moved (and was
; drawn again)
!zone ls_show
ls_show:
        lda ed_line
        cmp ed_top
        bcc .up
        sec
        sbc ed_top
        cmp #LS_VIS
        bcs .down
        clc
        rts
.up:    lda ed_line
        jmp .set
.down:  lda ed_line
        sec
        sbc #LS_VIS-1
.set:   sta ed_top
        jsr ls_redraw
        sec
        rts

; scroll bar range and position from nlines and ed_top
!zone ls_set_scroll
ls_set_scroll:
        ldx ls_win
        cpx #$ff
        beq .out
        lda nlines
        sec
        sbc #LS_VIS-1
        bcs +
        lda #0
+       cmp ed_top              ; never less than the view's top
        bcs +
        lda ed_top
+       sta w_maxscr,x
        lda ed_top
        sta w_scroll,x
.out:   rts

; the scroll bar again if its range or position changed
!zone ls_bar
ls_bar:
        ldx ls_win
        cpx #$ff
        beq .out
        lda w_maxscr,x
        sta bar_m
        lda w_scroll,x
        sta bar_s
        jsr ls_set_scroll
        ldx ls_win
        lda w_maxscr,x
        cmp bar_m
        bne +
        lda w_scroll,x
        cmp bar_s
        beq .out
+       jsr ls_clip
        bcs .out
        jsr clip_screen
        ldx ls_win
        jsr win_get_full
        jsr clip_rect
        ldx ls_win
        jsr win_draw_frame
        jmp clip_pop
.out:   rts
bar_m:  !byte 0
bar_s:  !byte 0

; the whole Listing again: its scroll bar and its lines
!zone ls_redraw
ls_redraw:
        jsr ls_set_scroll
        jsr ls_caret_off
        jsr ls_clip
        bcs .out
        jsr clip_screen
        ldx ls_win
        jsr win_get_full
        jsr clip_rect
        ldx ls_win
        jsr win_draw_frame
        ldx ls_win
        jsr win_get_content
        jsr clip_rect
        jsr fill_white
        jsr ls_draw
        jsr clip_pop
        jmp ls_caret_moved
.out:   rts

; after New or Open
ls_reset:
        lda #0
        sta ed_top
        sta ed_col
        jsr ed_open
        jmp ls_redraw

; M_SCROLL: the scroll bar's arrows, grey areas and thumb
!zone ls_scroll
ls_scroll:
        lda win_part_hit
        cmp #P_THUMB
        beq .thumb
        ldx #$ff
        cmp #P_UP
        beq .by
        ldx #1
        cmp #P_DOWN
        beq .by
        ldx #-LS_VIS+1
        cmp #P_PGUP
        beq .by
        ldx #LS_VIS-1
        cmp #P_PGDN
        bne .out
.by:    stx za
        ldx ls_win
        lda za
        bmi .neg
        clc
        adc ed_top
        bcs .max
        cmp w_maxscr,x
        bcc .set
.max:   lda w_maxscr,x
        jmp .set
.neg:   clc
        adc ed_top
        bcs .set
        lda #0
.set:   cmp ed_top
        beq .wait
        sta ed_top
        jsr ls_redraw
.wait:  lda #4
        jsr wait_frames
        lda mbtn
        beq .out
        jmp ls_scroll
.out:   rts
.thumb: ldx ls_win              ; the thumb: as far down as the pointer
        lda #0
        jsr win_track
        lda mouse_y
        sec
        sbc ry1
        bcs +
        lda #0
+       sta t0
        lda ry2
        sec
        sbc ry1
        sta t1
        lda t0
        cmp t1
        bcc +
        lda t1
        sta t0
+       ldx ls_win              ; ed_top = maxscr * t0 / t1
        lda w_maxscr,x
        ldx t0
        jsr mul8
        sta t2
        stx t3
        lda #0
        sta t4
-       lda t2
        sec
        sbc t1
        tay
        lda t3
        sbc #0
        bcc +
        sta t3
        sty t2
        inc t4
        bne -
+       lda t4
        cmp ed_top
        beq +
        sta ed_top
        jsr ls_redraw
+       lda mbtn
        bne .thumb
        rts

; ---------------------------------------------------------------------
; Clicks: the caret to the character under the pointer
; ---------------------------------------------------------------------
!zone ls_click
ls_click:
        jsr ls_unhilite
        lda mouse_y             ; which line
        sec
        sbc wc_y1
        sec
        sbc #LS_TOP-1
        bcs +
        lda #0
+       ldx #0
-       cmp #LH
        bcc +
        sbc #LH
        inx
        bne -
+       txa
        clc
        adc ed_top
        cmp nlines
        bcc +
        lda nlines
+       sta ck_line
        sec                     ; x in the text
        lda mouse_x
        sbc wc_x1
        sta zw
        lda mouse_x+1
        sbc wc_x1+1
        sta zw+1
        sec
        lda zw
        sbc #LS_LEFT
        sta zw
        bcs +
        dec zw+1
+       lda ck_line
        cmp ed_line
        beq +
        lda ck_line
        jsr ed_goto
        lda ck_line
        cmp ed_line             ; (couldn't leave the line)
        bne .out
+       ldx #0                  ; the column: half way across a character
-       cpx ed_len
        beq +
        lda zw+1
        bmi +
        lda ed_buf,x
        jsr char_width
        lsr
        sta za
        lda zw+1
        bne .next
        lda zw
        cmp za
        bcc +
.next:  lda ed_buf,x
        jsr char_width
        sta za
        sec
        lda zw
        sbc za
        sta zw
        bcs ++
        dec zw+1
++      inx
        bne -
+       stx ed_col
        jsr ls_caret_moved
        jmp wait_release
.out:   rts
ck_line: !byte 0

; the error's inverted line back to normal
!zone ls_unhilite
ls_unhilite:
        lda ls_hilite
        cmp #$ff
        beq +
        pha
        lda #$ff
        sta ls_hilite
        pla
        jmp ls_line_shown
+       rts

; close box: as Quit
ls_close:
        lda #BA_QUIT
        sta pending_action
        rts

; ---------------------------------------------------------------------
; Edit menu: whole lines (there is no selection)
; ---------------------------------------------------------------------
!zone ed_copy
ed_copy:
        ldx #0
-       lda ed_buf,x
        beq +
        sta clip_buf,x
        inx
        cpx #255
        bne -
+       lda #13                 ; a line, with its end
        sta clip_buf,x
        inx
        stx clip_len
        rts

ed_cut:
        jsr ed_copy
ed_clear:
        jsr run_end
        lda ed_line
        cmp nlines
        bcs +
        jsr prog_del
+       lda #1
        sta doc_dirty
        lda #0
        sta ed_col
        lda ed_line
        jsr ed_open
        lda ed_line
        jmp ls_from_line

; paste: the Clipboard typed in at the caret
!zone ed_paste
ed_paste:
        lda clip_len
        beq .out
        lda #1
        sta ls_quiet
        lda #0
        sta zp_i
-       ldx zp_i
        cpx clip_len
        beq +
        lda clip_buf,x
        cmp #13
        bne .chr
        jsr ed_return
        jmp .next
.chr:   cmp #10
        beq .next
        cmp #32
        bcc .next
        jsr ed_insert
.next:  inc zp_i
        bne -
+       lda #0
        sta ls_quiet
        jsr ls_show
        bcs .out
        jsr ls_redraw
.out:   rts
zp_i:   !byte 0
