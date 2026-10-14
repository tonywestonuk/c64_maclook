; =====================================================================
; wm.asm - window manager
;
; Windows are drawn back to front, always clipped.  Anything that
; uncovers part of the screen calls redraw_region, which repaints the
; desktop and every window intersecting that rectangle.
; =====================================================================

MAXWIN  = 8
TITLE_H = 11            ; title bar rows y1..y1+10 (line at y1+10)
SB_W    = 10            ; scroll bar width incl. its dividing line

WF_CLOSE   = $01
WF_ZOOM    = $02
WF_GROW    = $04
WF_VSCROLL = $08
WF_HSCROLL = $10
WF_SHADOW  = $20
WF_DIALOG  = $40        ; double-bordered, no title bar
WF_NOTITLE = $80

P_NONE    = 0
P_CONTENT = 1
P_TITLE   = 2
P_CLOSE   = 3
P_ZOOM    = 4
P_GROW    = 5
P_UP      = 6
P_DOWN    = 7
P_PGUP    = 8
P_PGDN    = 9
P_THUMB   = 10

; class methods
M_DRAW  = 0
M_CLICK = 1
M_KEY   = 2
M_IDLE  = 3
M_CLOSE = 4
M_EDIT  = 5             ; key_char = EDIT_ command
M_RESIZE = 6            ; window changed size
M_SCROLL = 7            ; mouse down in a scroll bar, part in win_part_hit

; window classes.  System classes are below CL_APPBASE; classes from
; CL_APPBASE up are looked up in the application's class table.
CL_DIALOG  = 0
CL_CALC    = 1
CL_PUZZLE  = 2
CL_CLOCK   = 3
CL_NOTEPAD = 4
CL_CPANEL  = 5
CL_KEYCAPS = 6
CL_APPBASE = $10

class_table:            ; draw, click, key, idle, close, edit, resize, scroll
        !word dialog_draw, nop_method, nop_method, nop_method, nop_method, nop_method, nop_method, nop_method
        !word calc_draw, calc_click, calc_key, nop_method, calc_close, calc_edit, nop_method, nop_method
        !word puz_draw, puz_click, nop_method, nop_method, puz_close, nop_method, nop_method, nop_method
        !word clock_draw, nop_method, nop_method, clock_idle, clock_close, nop_method, nop_method, nop_method
        !word np_draw, np_click, np_key, np_idle, np_close, np_edit, nop_method, nop_method
        !word cp_draw, cp_click, nop_method, nop_method, cp_close, nop_method, nop_method, nop_method
        !word kc_draw, nop_method, kc_key, kc_idle, kc_close, nop_method, nop_method, nop_method

w_used:  !fill MAXWIN
w_x1l:   !fill MAXWIN
w_x1h:   !fill MAXWIN
w_y1:    !fill MAXWIN
w_x2l:   !fill MAXWIN
w_x2h:   !fill MAXWIN
w_y2:    !fill MAXWIN
w_flags: !fill MAXWIN
w_class: !fill MAXWIN
w_data:  !fill MAXWIN
w_titl:  !fill MAXWIN
w_tith:  !fill MAXWIN
w_zx1l:  !fill MAXWIN    ; saved rect for the zoom box
w_zx1h:  !fill MAXWIN
w_zy1:   !fill MAXWIN
w_zx2l:  !fill MAXWIN
w_zx2h:  !fill MAXWIN
w_zy2:   !fill MAXWIN
w_zoomed: !fill MAXWIN
w_scroll: !fill MAXWIN   ; vertical scroll offset in pixels
w_maxscr: !fill MAXWIN   ; largest scroll offset (0 = no scrolling)
w_view:   !fill MAXWIN   ; folder view mode

zlist:  !fill MAXWIN     ; window ids, front first
zcount: !byte 0

cur_win: !byte 0         ; window whose method is running
wc_x1:  !word 0          ; content rect of cur_win
wc_y1:  !byte 0
wc_x2:  !word 0
wc_y2:  !byte 0
rr_skip: !byte $ff       ; window redraw_region leaves out

; ---------------------------------------------------------------------
; win_alloc: X = free window id, carry set if none
; ---------------------------------------------------------------------
!zone win_alloc
win_alloc:
        ldx #0
-       lda w_used,x
        beq +
        inx
        cpx #MAXWIN
        bne -
        sec
        rts
+       lda #0
        sta w_scroll,x
        sta w_maxscr,x
        sta w_zoomed,x
        sta w_view,x
        sta w_data,x
        clc
        rts

; front window id -> X ($ff if none), Z set if none
front_win:
        ldx #$ff
        lda zcount
        beq +
        ldx zlist
+       cpx #$ff
        rts

; ---------------------------------------------------------------------
; Rectangles of a window
; ---------------------------------------------------------------------
win_get_rect:                   ; frame
        lda w_x1l,x
        sta rx1
        lda w_x1h,x
        sta rx1+1
        lda w_y1,x
        sta ry1
        lda w_x2l,x
        sta rx2
        lda w_x2h,x
        sta rx2+1
        lda w_y2,x
        sta ry2
        rts

win_get_full:                   ; frame + shadow
        jsr win_get_rect
        inc rx2
        bne +
        inc rx2+1
+       inc ry2
        rts

!zone win_get_content
win_get_content:                ; content -> rx1..ry2 and wc_*
        jsr win_get_rect
        lda w_flags,x
        and #WF_DIALOG
        beq .doc
        lda #4
        jsr rect_inset
        jmp .store
.doc:   inc rx1
        bne +
        inc rx1+1
+       lda rx2
        bne +
        dec rx2+1
+       dec rx2
        dec ry2
        lda w_flags,x
        bmi +                   ; WF_NOTITLE
        lda ry1
        clc
        adc #TITLE_H
        sta ry1
        jmp ++
+       inc ry1
++      lda w_flags,x
        and #WF_VSCROLL
        beq +
        sec
        lda rx2
        sbc #SB_W
        sta rx2
        bcs +
        dec rx2+1
+       lda w_flags,x
        and #WF_HSCROLL
        beq .store
        lda ry2
        sec
        sbc #SB_W
        sta ry2
.store: ldy #5
-       lda rx1,y
        sta wc_x1,y
        dey
        bpl -
        rts

; ---------------------------------------------------------------------
; win_call: X = window, A = method.  Sets cur_win and wc_* first.
; ---------------------------------------------------------------------
!zone win_call
win_call:
        stx cur_win
        sta .m
        jsr win_get_content
        ldx cur_win
        lda w_class,x
        cmp #CL_APPBASE
        bcs .app
        ldy #<class_table
        sty jvec
        ldy #>class_table
        sty jvec+1
        jmp .look
.app:   ldy APP_CLASSES
        sty jvec
        ldy APP_CLASSES+1
        sty jvec+1
.look:  and #$0f                ; entry = table + class*16 + method*2
        asl
        asl
        asl
        asl
        sta t0
        lda .m
        asl
        clc
        adc t0
        clc
        adc jvec
        sta jvec
        bcc +
        inc jvec+1
+       ldy #0
        lda (jvec),y
        tax
        iny
        lda (jvec),y
        sta jvec+1
        stx jvec
        lda .m
        ldx cur_win
        jmp (jvec)
.m:     !byte 0

; does nothing (for class tables)
nop_method:
        rts

; ---------------------------------------------------------------------
; Drawing
; ---------------------------------------------------------------------
wd_id:   !byte 0
wd_act:  !byte 0
wd_x1:   !word 0
wd_y1:   !byte 0
wd_x2:   !word 0
wd_y2:   !byte 0

; win_draw: X = window, frame + content, inside the current clip
!zone win_draw
win_draw:
        stx wd_id
        jsr clip_push
        jsr win_get_full
        jsr clip_rect
        bcs .out
        ldx wd_id
        jsr win_draw_frame
        ldx wd_id
        jsr win_draw_content
.out:   jmp clip_pop

; win_draw_content: X = window, white background then the class draws
!zone win_draw_content
win_draw_content:
        stx wd_id
        jsr clip_push
        jsr win_get_content
        jsr clip_rect
        bcs .out
        jsr fill_white
        ldx wd_id
        lda #M_DRAW
        jsr win_call
.out:   jmp clip_pop

; helpers: set rx1/rx2 to window x1+A .. x1+B etc.
wd_rx:  ; rx1 = wd_x1 + A, rx2 = wd_x1 + Y
        sty t1
        clc
        adc wd_x1
        sta rx1
        lda wd_x1+1
        adc #0
        sta rx1+1
        clc
        lda t1
        adc wd_x1
        sta rx2
        lda wd_x1+1
        adc #0
        sta rx2+1
        rts
wd_rxr: ; rx1 = wd_x2 - A, rx2 = wd_x2 - Y
        sty t1
        sta t0
        sec
        lda wd_x2
        sbc t0
        sta rx1
        lda wd_x2+1
        sbc #0
        sta rx1+1
        sec
        lda wd_x2
        sbc t1
        sta rx2
        lda wd_x2+1
        sbc #0
        sta rx2+1
        rts
wd_ry:  ; ry1 = wd_y1 + A, ry2 = wd_y1 + Y
        clc
        adc wd_y1
        sta ry1
        tya
        clc
        adc wd_y1
        sta ry2
        rts

!zone win_draw_frame
win_draw_frame:                 ; X = window
        stx wd_id
        lda #0
        sta wd_act
        lda zcount
        beq +
        cpx zlist
        bne +
        inc wd_act
+       jsr win_get_rect
        ldy #5
-       lda rx1,y
        sta wd_x1,y
        dey
        bpl -
        jsr set_black
        jsr frame_rect
        ldx wd_id
        lda w_flags,x
        and #WF_SHADOW
        beq .noshadow
        ; right shadow
        lda wd_x2
        clc
        adc #1
        sta rx1
        sta rx2
        lda wd_x2+1
        adc #0
        sta rx1+1
        sta rx2+1
        ldx wd_y1
        inx
        stx ry1
        ldx wd_y2
        inx
        stx ry2
        jsr fill_black
        ; bottom shadow
        lda #1
        ldy #0
        jsr wd_rx
        clc
        lda wd_x2
        adc #1
        sta rx2
        lda wd_x2+1
        adc #0
        sta rx2+1
        lda ry2
        sta ry1
        jsr fill_black
.noshadow:
        ldx wd_id
        lda w_flags,x
        and #WF_DIALOG
        beq .doc
        ; dialog: white ring, then a thick border inside
        jsr win_get_rect
        lda #1
        jsr rect_inset
        jsr fill_white
        jsr set_black
        jsr win_get_rect
        lda #2
        jsr rect_inset
        jsr frame_rect
        lda #1
        jsr rect_inset
        jsr frame_rect
        rts
.doc:   lda w_flags,x
        bpl .title
        jmp .sbars
.title: ; title bar interior
        lda #1
        ldy #0
        jsr wd_rx
        lda wd_x2
        sec
        sbc #1
        sta rx2
        lda wd_x2+1
        sbc #0
        sta rx2+1
        lda #1
        ldy #TITLE_H-2
        jsr wd_ry
        jsr fill_white
        lda wd_act
        bne .bf390
        jmp .notact
.bf390:
        ; stripes
        lda #2
        ldy #2
        jsr wd_rxr              ; rx2 = x2-2
        lda #2
        jsr .x1only             ; rx1 = x1+2
        lda #2
        ldy #TITLE_H-3
        jsr wd_ry
        lda wd_y1
        and #1
        bne +
        lda #<pat_even
        ldy #>pat_even
        jmp ++
+       lda #<pat_odd
        ldy #>pat_odd
++      jsr set_pat_copy
        jsr fill_rect
        ; close box
        ldx wd_id
        lda w_flags,x
        and #WF_CLOSE
        beq .noclose
        lda #7
        ldy #15
        jsr wd_rx
        lda #1
        ldy #TITLE_H-2
        jsr wd_ry
        jsr fill_white
        lda #8
        ldy #14
        jsr wd_rx
        lda #2
        ldy #TITLE_H-3
        jsr wd_ry
        jsr set_black
        jsr frame_rect
.noclose:
        ldx wd_id
        lda w_flags,x
        and #WF_ZOOM
        beq .notact
        lda #15
        ldy #7
        jsr wd_rxr
        lda #1
        ldy #TITLE_H-2
        jsr wd_ry
        jsr fill_white
        lda #14
        ldy #8
        jsr wd_rxr
        lda #2
        ldy #TITLE_H-3
        jsr wd_ry
        jsr set_black
        jsr frame_rect
        lda #14
        ldy #11
        jsr wd_rxr
        lda #2
        ldy #5
        jsr wd_ry
        jsr frame_rect
.notact:
        ; title text, centred
        ldx wd_id
        lda w_titl,x
        sta tstr
        lda w_tith,x
        sta tstr+1
        ora tstr
        bne .bf467
        jmp .line
.bf467:
        lda #0
        sta font
        jsr text_width
        ; tx = (x1 + x2 + 1 - w) / 2
        clc
        lda wd_x1
        adc wd_x2
        sta tx
        lda wd_x1+1
        adc wd_x2+1
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
        lda wd_act
        beq .ttext
        ; white gap behind the title
        sec
        lda tx
        sbc #4
        sta rx1
        lda tx+1
        sbc #0
        sta rx1+1
        clc
        lda tx
        adc twidth
        sta rx2
        lda tx+1
        adc twidth+1
        sta rx2+1
        clc
        lda rx2
        adc #2
        sta rx2
        bcc +
        inc rx2+1
+       lda #1
        ldy #TITLE_H-2
        jsr wd_ry
        jsr clip_push
        jsr rect_save
        lda #17
        ldy #17
        jsr wd_rxr
        lda #17
        jsr .x1only
        jsr clip_rect
        jsr rect_restore
        jsr fill_white
        jsr clip_pop
.ttext: lda wd_y1
        clc
        adc #2
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        ; keep the title between the close and zoom boxes
        jsr clip_push
        lda #17
        ldy #17
        jsr wd_rxr
        lda #17
        jsr .x1only
        lda #0
        sta ry1
        lda #199
        sta ry2
        jsr clip_rect
        jsr draw_text
        jsr clip_pop
.line:  ; line under the title bar
        lda #0
        ldy #0
        jsr wd_rx
        lda wd_x2
        sta rx2
        lda wd_x2+1
        sta rx2+1
        lda #TITLE_H-1
        ldy #TITLE_H-1
        jsr wd_ry
        jsr fill_black
.sbars: ldx wd_id
        lda w_flags,x
        and #WF_VSCROLL|WF_HSCROLL|WF_GROW
        bne +
        rts
+       jmp draw_scrollbars

.x1only:                        ; rx1 = wd_x1 + A
        clc
        adc wd_x1
        sta rx1
        lda wd_x1+1
        adc #0
        sta rx1+1
        rts

; ---------------------------------------------------------------------
; Scroll bars and grow box
; ---------------------------------------------------------------------
!zone draw_scrollbars
draw_scrollbars:
        ldx wd_id
        lda w_flags,x
        sta u6
        and #WF_VSCROLL
        bne .bf561
        jmp .nov
.bf561:
        ; dividing line and white bar
        lda #SB_W
        ldy #SB_W
        jsr wd_rxr
        lda wd_y1
        clc
        adc #TITLE_H
        sta ry1
        lda wd_y2
        sec
        sbc #1
        sta ry2
        jsr fill_black
        lda #SB_W-1
        ldy #1
        jsr wd_rxr
        jsr fill_white
        lda wd_act
        beq .nov
        ldx wd_id
        lda w_maxscr,x
        beq .nov
        ; arrows, grey track, thumb
        jsr sb_track_rect
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        jsr fill_rect
        jsr sb_track_rect       ; lines above and below the track
        dec ry1
        lda ry1
        sta ry2
        jsr fill_black
        jsr sb_track_rect
        inc ry2
        lda ry2
        sta ry1
        jsr fill_black
        ; up arrow
        lda #SB_W-1
        ldy #0
        jsr wd_rxr
        lda rx1
        sta tx
        lda rx1+1
        sta tx+1
        lda wd_y1
        clc
        adc #TITLE_H
        sta ty
        lda #0
        sta ty+1
        lda #ICON_PLAIN
        sta iflags
        lda #<icon_arrowup
        sta iptr
        lda #>icon_arrowup
        sta iptr+1
        jsr draw_icon
        ; down arrow above the grow box
        jsr sb_track_rect
        lda ry2
        clc
        adc #2
        sta ty
        lda #<icon_arrowdn
        sta iptr
        lda #>icon_arrowdn
        sta iptr+1
        jsr draw_icon
        ; thumb
        jsr sb_thumb_rect
        jsr fill_white
        jsr set_black
        jsr frame_rect
.nov:   lda u6
        and #WF_HSCROLL
        beq .noh
        lda #1
        ldy #0
        jsr wd_rx
        lda wd_x2
        sec
        sbc #1
        sta rx2
        lda wd_x2+1
        sbc #0
        sta rx2+1
        lda wd_y2
        sec
        sbc #SB_W
        sta ry1
        sta ry2
        jsr fill_black
.noh:   lda u6
        and #WF_GROW
        beq .nog
        ; grow box: line above it, icon when active
        lda #SB_W
        ldy #1
        jsr wd_rxr
        lda wd_y2
        sec
        sbc #SB_W
        sta ry1
        sta ry2
        jsr fill_black
        lda #SB_W-1
        ldy #1
        jsr wd_rxr
        inc ry1
        lda wd_y2
        sec
        sbc #1
        sta ry2
        jsr fill_white
        lda wd_act
        beq .nog
        lda rx1
        sta tx
        lda rx1+1
        sta tx+1
        lda ry1
        sta ty
        lda #0
        sta ty+1
        lda #ICON_PLAIN
        sta iflags
        lda #<icon_grow
        sta iptr
        lda #>icon_grow
        sta iptr+1
        jsr draw_icon
.nog:   rts

; track of the vertical scroll bar (between the arrows)
sb_track_rect:
        lda #SB_W-1
        ldy #1
        jsr wd_rxr
        lda wd_y1
        clc
        adc #TITLE_H+10
        sta ry1
        lda wd_y2
        sec
        sbc #SB_W+11
        sta ry2
        rts

; thumb position = track top + (track_len - 9) * scroll / maxscroll
!zone sb_thumb_rect
sb_thumb_rect:
        jsr sb_track_rect
        lda ry2
        sec
        sbc ry1
        sec
        sbc #8                  ; travel
        sta t0
        ldx wd_id
        lda w_scroll,x
        sta t1
        lda w_maxscr,x
        sta t2
        ; t3 = t0 * t1 / t2 (8 bit, via repeated subtraction of a 16 bit product)
        lda #0
        sta t4
        sta t5
        ldy t1
        beq .div
-       clc
        lda t4
        adc t0
        sta t4
        bcc +
        inc t5
+       dey
        bne -
.div:   lda #0
        sta t3
-       lda t4
        sec
        sbc t2
        tay
        lda t5
        sbc #0
        bcc +
        sta t5
        sty t4
        inc t3
        jmp -
+       lda ry1
        clc
        adc t3
        sta ry1
        clc
        adc #8
        sta ry2
        lda #SB_W
        ldy #0
        jmp wd_rxr

; ---------------------------------------------------------------------
; redraw_region: repaint desktop + windows inside rx1..ry2
; ---------------------------------------------------------------------
rr_i:   !byte 0
!zone redraw_region
redraw_region:
        jsr clip_push
        jsr clip_screen
        lda ry1
        cmp #DESK_Y1
        bcs +
        lda #DESK_Y1
        sta ry1
+       jsr clip_rect
        bcs .out
        jsr paint_desktop
        jsr hook_desk_draw
        ldx zcount
.w:     dex
        bmi .done
        stx rr_i
        lda zlist,x
        cmp rr_skip
        beq .next
        tax
        jsr win_get_full
        jsr rect_visible
        bcs .next
        ldx rr_i
        lda zlist,x
        tax
        jsr win_draw
.next:  ldx rr_i
        jmp .w
.done:  jsr draw_corners
.out:   jmp clip_pop

; redraw_old_new: repaint rect ro_* minus rect rn_* (what a moved or
; resized window uncovered), skipping window rr_skip.
ro_x1:  !word 0
ro_y1:  !byte 0
ro_x2:  !word 0
ro_y2:  !byte 0
rn_x1:  !word 0
rn_y1:  !byte 0
rn_x2:  !word 0
rn_y2:  !byte 0

!zone redraw_old_new
redraw_old_new:
        ; no overlap -> whole old rect
        ldx #5
-       lda rn_x1,x
        sta rx1,x
        dex
        bpl -
        jsr clip_push
        ldx #5
-       lda ro_x1,x
        sta clx1,x
        dex
        bpl -
        jsr rect_visible
        php
        jsr clip_pop
        plp
        bcc .overlap
        jsr .old
        jmp redraw_region
.overlap:
        ; top strip: old.y1 .. new.y1-1
        lda rn_y1
        cmp ro_y1
        beq +
        bcc +
        jsr .old
        ldx rn_y1
        dex
        stx ry2
        jsr redraw_region
+       ; bottom strip: new.y2+1 .. old.y2
        lda ro_y2
        cmp rn_y2
        beq +
        bcc +
        jsr .old
        ldx rn_y2
        inx
        stx ry1
        jsr redraw_region
+       ; middle rows: max(y1s) .. min(y2s)
        jsr .old
        lda rn_y1
        cmp ry1
        bcc +
        sta ry1
+       lda rn_y2
        cmp ry2
        bcs +
        sta ry2
+       lda ry2
        cmp ry1
        bcc .done
        sta .my2
        lda ry1
        sta .my1
        ; left strip: old.x1 .. new.x1-1
        lda ro_x1
        cmp rn_x1
        lda ro_x1+1
        sbc rn_x1+1
        bcs +
        sec
        lda rn_x1
        sbc #1
        sta rx2
        lda rn_x1+1
        sbc #0
        sta rx2+1
        jsr redraw_region
+       ; right strip: new.x2+1 .. old.x2
        lda rn_x2
        cmp ro_x2
        lda rn_x2+1
        sbc ro_x2+1
        bcs .done
        jsr .old
        lda .my1
        sta ry1
        lda .my2
        sta ry2
        clc
        lda rn_x2
        adc #1
        sta rx1
        lda rn_x2+1
        adc #0
        sta rx1+1
        jsr redraw_region
.done:  rts
.my1:   !byte 0
.my2:   !byte 0
.old:   ldx #5
-       lda ro_x1,x
        sta rx1,x
        dex
        bpl -
        rts

; ---------------------------------------------------------------------
; Z order
; ---------------------------------------------------------------------
; remove window X from zlist
!zone z_remove
z_remove:
        stx t0
        ldy #0
        ldx #0
-       cpx zcount
        beq +
        lda zlist,x
        inx
        cmp t0
        beq -
        sta zlist,y
        iny
        jmp -
+       sty zcount
        ldx t0
        rts

; insert window X at the front
z_front:
        stx t0
        ldy zcount
-       dey
        bmi +
        lda zlist,y
        sta zlist+1,y
        jmp -
+       lda t0
        sta zlist
        inc zcount
        ldx t0
        rts

; ---------------------------------------------------------------------
; win_open: X = filled-in window record.  zr_* = rect to zoom from
; (zr_on = 0 for none).
; ---------------------------------------------------------------------
wo_id:  !byte 0
!zone win_open
win_open:
        stx wo_id
        lda #1
        sta w_used,x
        lda zr_on
        beq +
        ldx wo_id
        jsr win_get_rect
        jsr zoom_to_rect
+       ldx wo_id
        jsr z_front
        ; deactivate the old front window
        lda zcount
        cmp #2
        bcc +
        ldx zlist+1
        jsr clip_push
        jsr clip_screen
        jsr win_get_full
        jsr clip_rect
        bcs ++
        ldx zlist+1
        jsr win_draw_frame
++      jsr clip_pop
+       jsr clip_push
        jsr clip_screen
        ldx wo_id
        jsr win_draw
        jsr clip_pop
        lda #0
        sta zr_on
        ldx wo_id
        rts

; ---------------------------------------------------------------------
; win_select: bring window X to the front
; ---------------------------------------------------------------------
ws_id:  !byte 0
!zone win_select
win_select:
        lda zcount
        beq +
        cpx zlist
        bne ++
+       rts
++      stx ws_id
        jsr z_remove
        jsr z_front
        ; old front (now second) becomes inactive
        ldx zlist+1
        jsr clip_push
        jsr clip_screen
        jsr win_get_full
        jsr clip_rect
        bcs +
        ldx zlist+1
        jsr win_draw_frame
+       jsr clip_pop
        jsr clip_push
        jsr clip_screen
        ldx ws_id
        jsr win_draw
        jmp clip_pop

; ---------------------------------------------------------------------
; win_close: close window X (zr_on/zr_* = rect to zoom to)
; ---------------------------------------------------------------------
wcl_id: !byte 0
wcl_rect: !fill 6
!zone win_close
win_close:
        stx wcl_id
        lda #M_CLOSE
        jsr win_call
        ldx wcl_id
        jsr win_get_full
        ldy #5
-       lda rx1,y
        sta wcl_rect,y
        dey
        bpl -
        ldx wcl_id
        jsr z_remove
        lda #0
        sta w_used,x
        lda #$ff
        sta rr_skip
        ldy #5
-       lda wcl_rect,y
        sta rx1,y
        dey
        bpl -
        jsr redraw_region
        lda zr_on
        beq +
        ldy #5
-       lda wcl_rect,y
        sta rx1,y
        dey
        bpl -
        jsr zoom_from_rect
+       lda #0
        sta zr_on
        ; new front window becomes active
        jsr front_win
        beq +
        jsr clip_push
        jsr clip_screen
        jsr win_get_full
        jsr clip_rect
        bcs ++
        jsr front_win
        jsr win_draw_frame
++      jsr clip_pop
+       rts

; ---------------------------------------------------------------------
; win_set_rect: X = window, rn_* = new rect.  Redraws what is needed.
; The window must be the front window.
; ---------------------------------------------------------------------
wsr_id: !byte 0
!zone win_set_rect
win_set_rect:
        stx wsr_id
        jsr win_get_full
        ldy #5
-       lda rx1,y
        sta ro_x1,y
        dey
        bpl -
        ldx wsr_id
        lda rn_x1
        sta w_x1l,x
        lda rn_x1+1
        sta w_x1h,x
        lda rn_y1
        sta w_y1,x
        lda rn_x2
        sta w_x2l,x
        lda rn_x2+1
        sta w_x2h,x
        lda rn_y2
        sta w_y2,x
        ; new full rect for the difference
        inc rn_x2
        bne +
        inc rn_x2+1
+       inc rn_y2
        lda wsr_id
        sta rr_skip
        jsr redraw_old_new
        lda #$ff
        sta rr_skip
        ldx wsr_id
        lda #M_RESIZE
        jsr win_call
        jsr clip_push
        jsr clip_screen
        ldx wsr_id
        jsr win_draw
        jmp clip_pop

; ---------------------------------------------------------------------
; Hit testing
; ---------------------------------------------------------------------
; win_at_mouse: X = window under the mouse ($ff = none)
!zone win_at_mouse
win_at_mouse:
        ldx #0
.l:     cpx zcount
        beq .none
        stx u6
        lda zlist,x
        tax
        jsr win_get_rect
        jsr mouse_in_rect
        bcc .hit
        ldx u6
        inx
        jmp .l
.hit:   ldx u6
        lda zlist,x
        tax
        rts
.none:  ldx #$ff
        rts

; carry clear if the mouse is inside rx1..ry2
mouse_in_rect:
        lda mouse_x
        cmp rx1
        lda mouse_x+1
        sbc rx1+1
        bcc .no
        lda rx2
        cmp mouse_x
        lda rx2+1
        sbc mouse_x+1
        bcc .no
        lda mouse_y
        cmp ry1
        bcc .no
        lda ry2
        cmp mouse_y
        bcc .no
        clc
        rts
.no:    sec
        rts

; win_part: X = window -> A = part code
wp_id:  !byte 0
!zone win_part
win_part:
        stx wp_id
        jsr win_get_rect
        ldy #5
-       lda rx1,y
        sta wd_x1,y
        dey
        bpl -
        lda w_flags,x
        and #WF_DIALOG|WF_NOTITLE
        bne .body
        lda wd_y1
        clc
        adc #TITLE_H-1
        cmp mouse_y
        bcc .body
        ; title bar.  Boxes only on the front window.
        lda zlist
        cmp wp_id
        bne .title
        lda w_flags,x
        and #WF_CLOSE
        beq +
        jsr close_box_rect
        jsr mouse_in_rect
        bcs +
        lda #P_CLOSE
        rts
+       ldx wp_id
        lda w_flags,x
        and #WF_ZOOM
        beq .title
        jsr zoom_box_rect
        jsr mouse_in_rect
        bcs .title
        lda #P_ZOOM
        rts
.title: lda #P_TITLE
        rts
.body:  ldx wp_id
        lda w_flags,x
        and #WF_GROW
        beq +
        lda #SB_W
        ldy #0
        jsr wd_rxr
        lda wd_y2
        sec
        sbc #SB_W
        sta ry1
        lda wd_y2
        sta ry2
        jsr mouse_in_rect
        bcs +
        lda #P_GROW
        rts
+       ldx wp_id
        lda w_flags,x
        and #WF_VSCROLL
        beq .content
        lda #SB_W
        ldy #0
        jsr wd_rxr
        lda wd_y1
        sta ry1
        lda wd_y2
        sta ry2
        jsr mouse_in_rect
        bcs .content
        ldx wp_id
        lda w_maxscr,x
        beq .none
        lda wd_y1
        clc
        adc #TITLE_H+10
        cmp mouse_y
        bcc +
        lda #P_UP
        rts
+       stx wd_id
        jsr sb_track_rect
        lda ry2
        cmp mouse_y
        bcs +
        lda #P_DOWN
        rts
+       jsr sb_thumb_rect
        lda mouse_y
        cmp ry1
        bcs +
        lda #P_PGUP
        rts
+       lda ry2
        cmp mouse_y
        bcs +
        lda #P_PGDN
        rts
+       lda #P_THUMB
        rts
.none:  lda #P_NONE
        rts
.content:
        lda #P_CONTENT
        rts

close_box_rect:                 ; uses wd_* of the window
        lda #7
        ldy #15
        jsr wd_rx
        lda #1
        ldy #TITLE_H-2
        jmp wd_ry
zoom_box_rect:
        lda #15
        ldy #7
        jsr wd_rxr
        lda #1
        ldy #TITLE_H-2
        jmp wd_ry

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
zr_on:  !byte 0
zr_x1:  !word 0
zr_y1:  !byte 0
zr_x2:  !word 0
zr_y2:  !byte 0
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
