; =====================================================================
; finder.asm - the Finder: objects, folder windows, desktop icons,
; event loop, menu commands
; =====================================================================

MAXOBJ  = 24
DESKTOP = $fe
NOOBJ   = $ff
IB_H    = 14            ; info bar height in folder windows
CELL_W  = 56
CELL_H  = 36

T_DISK   = 0
T_TRASH  = 1
T_FOLDER = 2
T_APP    = 3
T_DOC    = 4
T_SYS    = 5

APP_README  = 0
APP_CLIP    = 1
APP_NONE    = 2
APP_BRICKLES = 3
APP_SHEET   = 4
APP_SHAPES  = 5

IC_DISK = 0
IC_TRASH = 1
IC_TRASHFULL = 2
IC_FOLDER = 3
IC_DOC = 4
IC_SYSTEM = 5
IC_FINDER = 6
IC_CLIPBOARD = 7
IC_SCRAPBOOK = 8
IC_BRICKLES = 9
IC_SHEET = 10
IC_SHAPES = 11

OBJ_DISK  = 0
OBJ_TRASH = 1

CL_FOLDER  = CL_APPBASE+0
CL_INFO    = CL_APPBASE+1
CL_TEXT    = CL_APPBASE+2

app_classes:            ; draw, click, key, idle, close, edit, resize, scroll
        !word folder_draw, folder_click, folder_key, nop_method, folder_close, folder_edit, folder_resize, folder_scroll_m
        !word info_draw, nop_method, nop_method, nop_method, info_close, nop_method, nop_method, nop_method
        !word text_draw, nop_method, nop_method, nop_method, text_close, nop_method, nop_method, nop_method

icon_table:
        !word icon_disk, icon_trash, icon_trashfull, icon_folder, icon_doc
        !word icon_system, icon_finder, icon_clipboard, icon_scrapbook
        !word icon_brickles, icon_sheet, icon_paint

; ---------------------------------------------------------------------
; Object table
; ---------------------------------------------------------------------
o_names:  !fill MAXOBJ*16
o_parent: !fill MAXOBJ
o_oldpar: !fill MAXOBJ
o_xl:     !fill MAXOBJ
o_xh:     !fill MAXOBJ
o_y:      !fill MAXOBJ
o_icon:   !fill MAXOBJ
o_type:   !fill MAXOBJ
o_app:    !fill MAXOBJ
o_size:   !fill MAXOBJ
o_win:    !fill MAXOBJ
o_flags:  !fill MAXOBJ
o_date:   !fill MAXOBJ
o_locked: !fill MAXOBJ

OF_SEL = 1
OF_HILITE = 2

; name, parent, x, y, icon, type, app, size (1541 blocks), date
!macro obj .name, .par, .x, .y, .icon, .type, .app, .size, .date {
        !word .name
        !byte .par
        !word .x
        !byte .y, .icon, .type, .app, .size, .date
}
OBJREC = 11
obj_init:
        +obj str_o_disk,    DESKTOP, 280, 16, IC_DISK, T_DISK, APP_NONE, 0, 0
        +obj str_o_trash,   DESKTOP, 284, 158, IC_TRASH, T_TRASH, APP_NONE, 0, 0
        +obj str_o_sysfold, OBJ_DISK, 18, 4, IC_FOLDER, T_FOLDER, APP_NONE, 0, 1
        +obj str_o_brickles, OBJ_DISK, 74, 4, IC_BRICKLES, T_APP, APP_BRICKLES, 15, 6
        +obj str_o_sheet,   OBJ_DISK, 130, 4, IC_SHEET, T_APP, APP_SHEET, 23, 6
        +obj str_o_readme,  OBJ_DISK, 186, 4, IC_DOC, T_DOC, APP_README, 6, 4
        +obj str_o_empty,   OBJ_DISK, 18, 40, IC_FOLDER, T_FOLDER, APP_NONE, 0, 4
        +obj str_o_shapes,  OBJ_DISK, 74, 40, IC_SHAPES, T_APP, APP_SHAPES, 7, 6
        +obj str_o_system,  2, 18, 4, IC_SYSTEM, T_SYS, APP_NONE, 70, 0
        +obj str_o_finder,  2, 74, 4, IC_FINDER, T_SYS, APP_NONE, 48, 0
        +obj str_o_clipf,   2, 130, 4, IC_CLIPBOARD, T_DOC, APP_CLIP, 2, 5
        +obj str_o_scrapf,  2, 18, 40, IC_SCRAPBOOK, T_SYS, APP_NONE, 40, 5
NUM_INIT_OBJ = (* - obj_init) / OBJREC

sel_obj:   !byte NOOBJ
last_obj:  !byte NOOBJ   ; object of the previous click (double clicks)
renaming:  !byte 0

; ---------------------------------------------------------------------
; finder_init: objects to their initial state
; ---------------------------------------------------------------------
!zone finder_init
finder_init:
        ldx #MAXOBJ-1
-       lda #NOOBJ
        sta o_parent,x
        sta o_win,x
        lda #0
        sta o_flags,x
        sta o_locked,x
        dex
        bpl -
        lda #<obj_init
        sta q2
        lda #>obj_init
        sta q2+1
        ldx #0
.o:     stx u0
        ldy #0
        lda (q2),y
        sta q0
        iny
        lda (q2),y
        sta q0+1
        jsr obj_name_ptr        ; q1 = name slot of X
        jsr strcpy
        ldx u0
        ldy #2
        lda (q2),y
        sta o_parent,x
        iny
        lda (q2),y
        sta o_xl,x
        iny
        lda (q2),y
        sta o_xh,x
        iny
        lda (q2),y
        sta o_y,x
        iny
        lda (q2),y
        sta o_icon,x
        iny
        lda (q2),y
        sta o_type,x
        iny
        lda (q2),y
        sta o_app,x
        iny
        lda (q2),y
        sta o_size,x
        iny
        lda (q2),y
        sta o_date,x
        clc
        lda q2
        adc #OBJREC
        sta q2
        bcc +
        inc q2+1
+       inx
        cpx #NUM_INIT_OBJ
        bne .o
        lda #NOOBJ
        sta sel_obj
        sta last_obj
        lda #0
        sta renaming
        rts

; X = object -> q1 = its name buffer (X preserved)
obj_name_ptr:
        txa
        asl
        asl
        asl
        asl
        clc
        adc #<o_names
        sta q1
        lda #>o_names
        adc #0
        sta q1+1
        txa
        lsr
        lsr
        lsr
        lsr
        clc
        adc q1+1
        sta q1+1
        rts

; X = object -> carry set if it is a container
is_container:
        lda o_type,x
        cmp #T_FOLDER+1
        rts                     ; carry clear for disk/trash/folder

; does the trash hold anything?  Z clear = yes
trash_full:
        ldx #MAXOBJ-1
-       lda o_parent,x
        cmp #OBJ_TRASH
        beq +
        dex
        bpl -
        lda #0
        rts
+       lda #1
        rts

; icon pointer for object X -> iptr
obj_icon_ptr:
        lda o_icon,x
        cpx #OBJ_TRASH
        bne +
        stx t0
        jsr trash_full          ; A = 0 empty, 1 full
        ldx t0
        clc
        adc #IC_TRASH
+       asl
        tay
        lda icon_table,y
        sta iptr
        lda icon_table+1,y
        sta iptr+1
        rts

; ---------------------------------------------------------------------
; Geometry: where an object's icon is on the screen
; ---------------------------------------------------------------------
ob_x:   !word 0          ; icon box (24x20) top-left
ob_y:   !word 0          ; (both signed: folders scroll)
ob_win: !byte 0
ic_x:   !word 0          ; image top-left
ic_y:   !word 0
lb_x1:  !word 0          ; label rect
lb_x2:  !word 0
lb_y1:  !word 0
lw:     !word 0
ob_id:  !byte 0

; obj_base: X = object.  Carry set if not visible (container closed).
!zone obj_base
obj_base:
        stx ob_id
        lda o_parent,x
        cmp #DESKTOP
        bne .folder
        lda o_xl,x
        sta ob_x
        lda o_xh,x
        sta ob_x+1
        lda o_y,x
        sta ob_y
        lda #0
        sta ob_y+1
        lda #$ff
        sta ob_win
        clc
        rts
.folder:
        cmp #MAXOBJ
        bcs .hidden
        tay
        lda o_win,y
        cmp #$ff
        beq .hidden
        sta ob_win
        tax
        jsr win_get_content
        ldx ob_id
        clc
        lda wc_x1
        adc o_xl,x
        sta ob_x
        lda wc_x1+1
        adc o_xh,x
        sta ob_x+1
        clc
        lda wc_y1
        adc #IB_H
        sta ob_y
        lda #0
        adc #0
        sta ob_y+1
        clc
        lda ob_y
        adc o_y,x
        sta ob_y
        bcc +
        inc ob_y+1
+       ldy ob_win
        sec
        lda ob_x
        sbc w_hscroll,y
        sta ob_x
        lda ob_x+1
        sbc #0
        sta ob_x+1
        sec
        lda ob_y
        sbc w_scroll,y
        sta ob_y
        lda ob_y+1
        sbc #0
        sta ob_y+1
        clc
        rts
.hidden:
        sec
        rts

; obj_geom: after obj_base, compute image and label positions
!zone obj_geom
obj_geom:
        ldx ob_id
        jsr obj_icon_ptr
        ldy #2
        lda (iptr),y            ; width in pixels
        sta t0
        lda #24
        sec
        sbc t0
        lsr
        clc
        adc ob_x
        sta ic_x
        lda ob_x+1
        adc #0
        sta ic_x+1
        ldy #1
        lda (iptr),y            ; height
        sta t0
        lda #20
        sec
        sbc t0
        clc
        adc ob_y
        sta ic_y
        lda ob_y+1
        adc #0
        sta ic_y+1
        ; label
        ldx ob_id
        jsr obj_name_ptr
        lda q1
        sta tstr
        lda q1+1
        sta tstr+1
        lda #1
        sta font
        jsr text_width
        lda twidth
        sta lw
        lda twidth+1
        sta lw+1
        ; lb_x1 = ob_x + 12 - lw/2 - 1
        lda lw+1
        lsr
        lda lw
        ror
        sta t0
        clc
        lda ob_x
        adc #11
        sta lb_x1
        lda ob_x+1
        adc #0
        sta lb_x1+1
        sec
        lda lb_x1
        sbc t0
        sta lb_x1
        lda lb_x1+1
        sbc #0
        sta lb_x1+1
        bpl +
        ldx ob_win              ; desktop labels stay on the screen
        bpl +
        lda #0
        sta lb_x1
        sta lb_x1+1
+       clc
        lda lb_x1
        adc lw
        sta lb_x2
        lda lb_x1+1
        adc lw+1
        sta lb_x2+1
        inc lb_x2
        bne +
        inc lb_x2+1
+       clc
        lda ob_y
        adc #21
        sta lb_y1
        lda ob_y+1
        adc #0
        sta lb_y1+1
        rts

; rx/ry = bounding rect of the object (after obj_geom), clamped to screen
!zone obj_bounds
obj_bounds:
        ; x1 = min(ob_x, lb_x1), x2 = max(ob_x+23, lb_x2), signed
        lda ob_x
        sta rx1
        lda ob_x+1
        sta rx1+1
        lda lb_x1
        cmp rx1
        lda lb_x1+1
        sbc rx1+1
        bvc +
        eor #$80
+       bpl +
        lda lb_x1
        sta rx1
        lda lb_x1+1
        sta rx1+1
+       clc
        lda ob_x
        adc #23
        sta rx2
        lda ob_x+1
        adc #0
        sta rx2+1
        lda rx2
        cmp lb_x2
        lda rx2+1
        sbc lb_x2+1
        bvc +
        eor #$80
+       bpl +
        lda lb_x2
        sta rx2
        lda lb_x2+1
        sta rx2+1
+       ; clamp to 0..319
        lda rx2+1
        bmi .off
        lda rx1+1
        bpl +
        lda #0
        sta rx1
        sta rx1+1
+       lda rx2
        cmp #<320
        lda rx2+1
        sbc #>320
        bcc +
        lda #<319
        sta rx2
        lda #>319
        sta rx2+1
+       ; y range ob_y .. ob_y+29, clamped
        lda ob_y+1
        bmi .ytop
        bne .off
        lda ob_y
        sta ry1
        jmp +
.ytop:  lda #0
        sta ry1
+       clc
        lda ob_y
        adc #29
        sta t0
        lda ob_y+1
        adc #0
        bmi .off
        bne .ybot
        lda t0
        cmp #200
        bcc +
.ybot:  lda #199
+       sta ry2
        clc
        rts
.off:   lda #0                  ; entirely off screen: empty rect
        sta ry1
        sta ry2
        sec
        rts

; ---------------------------------------------------------------------
; draw_obj: X = object, inside the current clip
; ---------------------------------------------------------------------
!zone draw_obj
draw_obj:
        jsr obj_base
        bcc .bf509
        jmp .out
.bf509:
        jsr obj_geom
        jsr obj_bounds
        jsr rect_visible
        bcc .bf513
        jmp .out
.bf513:
        ldx ob_id
        lda o_flags,x
        and #OF_SEL|OF_HILITE
        beq +
        lda #ICON_SEL
+       sta iflags
        lda o_win,x             ; open disks and folders look grey
        cmp #$ff
        beq +
        lda iflags
        ora #ICON_OPEN
        sta iflags
+
        lda ic_x
        sta tx
        lda ic_x+1
        sta tx+1
        lda ic_y
        sta ty
        lda ic_y+1
        sta ty+1
        jsr draw_icon
        ; label background
        jsr .labelrect
        ldx ob_id
        lda o_flags,x
        and #OF_SEL
        beq +
        jsr fill_black
        lda #B_BIC
        jmp ++
+       jsr fill_white
        lda #B_OR
++      sta tmode
        clc
        lda lb_x1
        adc #1
        sta tx
        lda lb_x1+1
        adc #0
        sta tx+1
        lda lb_y1
        sta ty
        lda lb_y1+1
        sta ty+1
        ldx ob_id
        jsr obj_name_ptr
        lda #1
        sta font
        lda q1
        ldy q1+1
        jsr draw_str
        ; renaming: show an insertion point after the name
        lda renaming
        beq .out
        ldx ob_id
        cpx sel_obj
        bne .out
        jsr .labelrect
        lda rx2
        sta rx1
        lda rx2+1
        sta rx1+1
        jsr invert_rect
.out:   rts
.labelrect:
        lda lb_x1
        sta rx1
        lda lb_x1+1
        sta rx1+1
        lda lb_x2
        sta rx2
        lda lb_x2+1
        sta rx2+1
        lda lb_y1
        sta t0
        lda lb_y1+1
        jsr clamp_y16
        sta ry1
        clc
        lda lb_y1
        adc #8
        sta t0
        lda lb_y1+1
        adc #0
        jsr clamp_y16
        sta ry2
        rts

; A = high, t0 = low byte of a signed y -> A = y clamped to 0..199
clamp_y16:
        bmi .zero
        bne .max
        lda t0
        cmp #200
        bcc .ok
.max:   lda #199
        rts
.zero:  lda #0
.ok:    rts

; redraw the screen area of object X
!zone redraw_obj
redraw_obj:
        cpx #MAXOBJ
        bcs .out
        lda o_parent,x
        cmp #NOOBJ
        beq .out
        jsr obj_base
        bcs .out
        jsr obj_geom
        jsr obj_bounds
        bcs .out
        jsr redraw_obj_rect
.out:   rts
redraw_obj_rect:                ; redraw rx..ry, limited to the container
        jsr limit_to_container
        bcs +
        jmp redraw_region
+       rts

; rx..ry = rx..ry AND the icon area of window ob_win (if any).
; Carry set if that is empty.
!zone limit_to_container
limit_to_container:
        ldx ob_win
        cpx #$ff
        beq .ok
        jsr clip_push
        ldy #5
-       lda rx1,y
        sta clx1,y
        dey
        bpl -
        ldx ob_win
        jsr win_get_content
        lda ry1
        clc
        adc #IB_H
        sta ry1
        jsr clip_rect
        php
        ldy #5
-       lda clx1,y
        sta rx1,y
        dey
        bpl -
        jsr clip_pop
        plp
        rts
.ok:    clc
        rts

; draw all desktop icons (inside the current clip)
!zone draw_desk_icons
draw_desk_icons:
        ldx #0
-       lda o_parent,x
        cmp #DESKTOP
        bne +
        stx u5
        jsr draw_obj
        ldx u5
+       inx
        cpx #MAXOBJ
        bne -
        rts

; ---------------------------------------------------------------------
; Hit testing: object of container A under the mouse -> X (NOOBJ)
; ---------------------------------------------------------------------
oam_c:  !byte 0
!zone obj_at_mouse
obj_at_mouse:
        sta oam_c
        ldx #MAXOBJ-1
.l:     stx u5
        lda o_parent,x
        cmp oam_c
        beq .bf691
        jmp .next
.bf691:
        jsr obj_base
        bcc .bf693
        jmp .next
.bf693:
        jsr obj_geom
        ; image box
        lda ic_x
        sta rx1
        lda ic_x+1
        sta rx1+1
        ldx ob_id
        jsr obj_icon_ptr
        ldy #2
        lda (iptr),y
        clc
        adc ic_x
        sta rx2
        lda ic_x+1
        adc #0
        sta rx2+1
        lda ic_y
        sta t0
        lda ic_y+1
        jsr clamp_y16
        sta ry1
        clc
        lda ob_y
        adc #19
        sta t0
        lda ob_y+1
        adc #0
        jsr clamp_y16
        sta ry2
        jsr mouse_in_rect
        bcc .hit
        ; label
        lda lb_x1
        sta rx1
        lda lb_x1+1
        sta rx1+1
        lda lb_x2
        sta rx2
        lda lb_x2+1
        sta rx2+1
        lda lb_y1
        sta t0
        lda lb_y1+1
        jsr clamp_y16
        sta ry1
        clc
        lda lb_y1
        adc #8
        sta t0
        lda lb_y1+1
        adc #0
        jsr clamp_y16
        sta ry2
        jsr mouse_in_rect
        bcc .hit
.next:  ldx u5
        dex
        bmi +
        jmp .l
+       ldx #NOOBJ
        rts
.hit:   ldx u5
        rts

; ---------------------------------------------------------------------
; Selection
; ---------------------------------------------------------------------
; select_obj: X = object (NOOBJ = deselect)
!zone select_obj
select_obj:
        cpx sel_obj
        beq .same
        stx u4
        jsr end_rename
        ldx sel_obj
        stx u3
        cpx #NOOBJ
        beq +
        lda o_flags,x
        and #$ff-OF_SEL
        sta o_flags,x
+       ldx u4
        stx sel_obj
        cpx #NOOBJ
        beq +
        lda o_flags,x
        ora #OF_SEL
        sta o_flags,x
+       ldx u3
        jsr redraw_obj
        ldx sel_obj
        jsr redraw_obj
.same:  rts

deselect:
        ldx #NOOBJ
        jmp select_obj

; ---------------------------------------------------------------------
; Folder windows
; ---------------------------------------------------------------------
; open_folder: X = container object
fo_obj: !byte 0
fo_win: !byte 0
!zone open_folder
open_folder:
        stx fo_obj
        lda o_win,x
        cmp #$ff
        beq +
        tax
        jmp win_select
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx fo_win
        ; default rect: staggered by object id
        ldy fo_obj
        lda fold_x1,y
        sta w_x1l,x
        lda #0
        sta w_x1h,x
        lda fold_y1,y
        sta w_y1,x
        clc
        lda fold_x1,y
        adc #250
        sta w_x2l,x
        lda #0
        adc #0
        sta w_x2h,x
        lda fold_y1,y
        clc
        adc fold_h,y
        sta w_y2,x
        lda #WF_CLOSE|WF_ZOOM|WF_GROW|WF_VSCROLL|WF_HSCROLL|WF_SHADOW
        sta w_flags,x
        lda #CL_FOLDER
        sta w_class,x
        lda fo_obj
        sta w_data,x
        tax
        jsr obj_name_ptr
        ldx fo_win
        lda q1
        sta w_titl,x
        lda q1+1
        sta w_tith,x
        ldy fo_obj
        txa
        sta o_win,y
        ; zoom from the icon
        ldx fo_obj
        jsr zoom_from_obj
        ldx fo_win
        stx wsr_id
        jsr folder_layout
        ldx fo_win
        jmp win_open

; staggered default positions, by object id (16 entries is enough)
fold_x1: !byte 24, 40, 50, 30, 30, 30, 30, 30, 60, 30, 30, 30, 30, 30, 30, 30
         !byte 40, 50, 60, 64, 40, 50, 60, 64
fold_y1: !byte 30, 60, 50, 30, 30, 30, 30, 30, 70, 30, 30, 30, 30, 30, 30, 30
         !byte 40, 50, 60, 70, 40, 50, 60, 70
fold_h:  !byte 148, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112
         !byte 112, 112, 112, 112, 112, 112, 112, 112

; zr_* = icon rect of object X (sets zr_on if visible)
!zone zoom_from_obj
zoom_from_obj:
        lda #0
        sta zr_on
        jsr obj_base
        bcs +
        lda ob_x+1              ; scrolled off the left
        bmi +
        lda ob_x
        sta zr_x1
        lda ob_x+1
        sta zr_x1+1
        clc
        lda ob_x
        adc #23
        sta zr_x2
        lda ob_x+1
        adc #0
        sta zr_x2+1
        lda ob_y+1
        bne +
        lda ob_y
        cmp #DESK_Y1
        bcc +
        sta zr_y1
        clc
        adc #19
        bcs +
        sta zr_y2
        lda #1
        sta zr_on
+       rts

wsr_id: !byte 0          ; window for folder_layout
; folder_layout: window wsr_id - compute the scroll ranges.
; fl_moved is set if a scroll position had to change.
fl_moved: !byte 0
fl_need:  !word 0
!zone folder_layout
folder_layout:
        lda #0
        sta fl_moved
        ldx wsr_id
        lda w_data,x
        sta u0
        jsr win_get_content
        ; visible height of the icon area
        lda wc_y2
        sec
        sbc wc_y1
        sec
        sbc #IB_H
        sta u1
        ; needed height = max(o_y + 34)
        lda #0
        sta u2
        ldx #MAXOBJ-1
-       lda o_parent,x
        cmp u0
        bne +
        lda o_y,x
        clc
        adc #32
        cmp u2
        bcc +
        sta u2
+       dex
        bpl -
        ldx wsr_id
        lda u2
        sec
        sbc u1
        bcs +
        lda #0
+       sta w_maxscr,x
        cmp w_scroll,x
        bcs +
        sta w_scroll,x
        inc fl_moved
+       ; needed width = max(right edge of icon or label) + 3
        lda #0
        sta fl_need
        sta fl_need+1
        ldx #MAXOBJ-1
.w:     stx u3
        lda o_parent,x
        cmp u0
        bne .wnext
        ; right edge from o_x = max(23, 12 + lw - lw/2)
        jsr obj_name_ptr
        lda q1
        sta tstr
        lda q1+1
        sta tstr+1
        lda #1
        sta font
        jsr text_width
        lda twidth+1
        lsr
        lda twidth
        ror
        sta t0
        sec
        lda twidth
        sbc t0
        clc
        adc #12+3
        cmp #23+3
        bcs +
        lda #23+3
+       ldx u3
        clc
        adc o_xl,x
        sta t0
        lda o_xh,x
        adc #0
        sta t1
        lda fl_need
        cmp t0
        lda fl_need+1
        sbc t1
        bcs .wnext
        lda t0
        sta fl_need
        lda t1
        sta fl_need+1
.wnext: ldx u3
        dex
        stx u3
        bpl .w
        ; hmax = needed - visible width, 0..255
        ldx wsr_id
        jsr win_get_content
        ldx wsr_id
        sec
        lda wc_x2
        sbc wc_x1
        sta t0
        lda wc_x2+1
        sbc wc_x1+1
        sta t1
        inc t0                  ; visible width
        bne +
        inc t1
+       sec
        lda fl_need
        sbc t0
        sta t0
        lda fl_need+1
        sbc t1
        bcs +
        lda #0
        sta t0
        beq ++
+       beq ++
        lda #255
        sta t0
++      lda t0
        sta w_hmax,x
        cmp w_hscroll,x
        bcs +
        sta w_hscroll,x
        inc fl_moved
+       rts

folder_close:
        ldy w_data,x
        lda #$ff
        sta o_win,y
        tya                     ; zoom back to the icon
        tax
        jmp zoom_from_obj

; M_DRAW
!zone folder_draw
folder_draw:
        lda w_data,x
        sta fd_f
        ; info bar: "n items   nnn blocks used   nnn blocks free"
        lda #1
        sta font
        lda #B_OR
        sta tmode
        jsr count_items
        sta u0
        ldx #0
        jsr utoa
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcpy
        lda #<str_items
        ldy #>str_items
        ldx u0
        dex
        bne +
        lda #<str_item
        ldy #>str_item
+       sta q0
        sty q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcat
        clc
        lda wc_x1
        adc #4
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #2
        sta ty
        lda #0
        sta ty+1
        lda #<fd_buf
        ldy #>fd_buf
        jsr draw_str
        ; the other two go only where they fit: free at the right after
        ; the item count, then used in the middle between them
        clc                     ; fd_le = end of the item count + gap
        lda wc_x1
        adc #4+8
        sta fd_le
        lda wc_x1+1
        adc #0
        sta fd_le+1
        clc
        lda fd_le
        adc twidth
        sta fd_le
        lda fd_le+1
        adc twidth+1
        sta fd_le+1
        jsr disk_used
        sta u0
        stx u1
        sec
        lda #<664
        sbc u0
        pha
        lda #>664
        sbc u1
        tax
        pla
        bcs +
        lda #0
        tax
+       jsr utoa
        jsr .kbuf
        lda #<str_avail
        sta q0
        lda #>str_avail
        sta q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcat
        lda #<fd_buf
        sta tstr
        lda #>fd_buf
        sta tstr+1
        jsr text_width
        sec
        lda wc_x2
        sbc #3
        sta tx
        lda wc_x2+1
        sbc #0
        sta tx+1
        sec
        lda tx
        sbc twidth
        sta tx
        sta fd_re
        lda tx+1
        sbc twidth+1
        sta tx+1
        sta fd_re+1
        lda tx                  ; tx < fd_le: no room
        cmp fd_le
        lda tx+1
        sbc fd_le+1
        bvc +
        eor #$80
+       bpl +
        jmp .line
+       jsr draw_text
        sec                     ; fd_re = start of free - gap
        lda fd_re
        sbc #8
        sta fd_re
        bcs +
        dec fd_re+1
+       lda u0
        ldx u1
        jsr utoa
        jsr .kbuf
        lda #<str_indisk
        sta q0
        lda #>str_indisk
        sta q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcat
        ; centre
        lda #<fd_buf
        sta tstr
        lda #>fd_buf
        sta tstr+1
        jsr text_width
        clc
        lda wc_x1
        adc wc_x2
        sta tx
        lda wc_x1+1
        adc wc_x2+1
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
        lda tx                  ; starts before fd_le: no room
        cmp fd_le
        lda tx+1
        sbc fd_le+1
        bvc +
        eor #$80
+       bmi .line
        clc                     ; ends after fd_re: no room
        lda tx
        adc twidth
        sta t0
        lda tx+1
        adc twidth+1
        sta t1
        lda fd_re
        cmp t0
        lda fd_re+1
        sbc t1
        bvc +
        eor #$80
+       bmi .line
        jsr draw_text
.line:
        ; double line
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
        adc #IB_H-4
        sta ry1
        sta ry2
        jsr fill_black
        inc ry1
        inc ry1
        inc ry2
        inc ry2
        jsr fill_black
        ; icons, clipped to the icon area
        jsr clip_push
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
        adc #IB_H
        sta ry1
        lda wc_y2
        sta ry2
        jsr clip_rect
        bcs .done
        ldx #0
-       lda o_parent,x
        cmp fd_f
        bne +
        stx u5
        jsr draw_obj
        ldx u5
+       inx
        cpx #MAXOBJ
        bne -
.done:  jmp clip_pop
.kbuf:  ; fd_buf = numbuf
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcpy
        rts
fd_f:   !byte 0
fd_le:  !word 0
fd_re:  !word 0
fd_buf: !fill 24

; count children of fd_f -> A
count_items:
        lda #0
        sta t0
        ldx #MAXOBJ-1
-       lda o_parent,x
        cmp fd_f
        bne +
        inc t0
+       dex
        bpl -
        lda t0
        rts

; blocks used on disk -> A/X
disk_used:
        lda #0
        sta t0
        sta t1
        ldx #MAXOBJ-1
-       lda o_parent,x
        cmp #NOOBJ
        beq +
        clc
        lda t0
        adc o_size,x
        sta t0
        bcc +
        inc t1
+       dex
        bpl -
        lda t0
        ldx t1
        rts

; M_KEY: typing renames the selected icon
folder_key:
        lda key_char
        jmp rename_key

; M_RESIZE: recompute the scroll range
folder_resize:
        stx wsr_id
        jmp folder_layout

; M_SCROLL: part in win_part_hit
folder_scroll_m:
        lda win_part_hit
        jmp scroll_track

; M_CLICK in a folder window
!zone folder_click
folder_click:
        lda w_data,x
        sta u0
        lda mouse_y
        sec
        sbc wc_y1
        cmp #IB_H
        bcc .none
        lda u0
        jsr obj_at_mouse
        cpx #NOOBJ
        beq .none
        jmp icon_click
.none:  lda #NOOBJ
        sta last_obj
        jmp deselect

; Edit menu in a folder: Select All selects the first item (single selection)
folder_edit:
        rts

; scroll the front folder window by A (signed).  fs_h = 0 scrolls
; vertically, W_H sideways.
fs_h:   !byte 0
!zone folder_scroll
folder_scroll:
        sta t0
        lda zlist
        clc
        adc fs_h
        tax
        lda w_scroll,x
        clc
        adc t0
        bit t0
        bmi .neg
        bcs .max
        cmp w_maxscr,x
        bcc .set
.max:   lda w_maxscr,x
        jmp .set
.neg:   bcs .set
        lda #0
.set:   cmp w_scroll,x
        beq .out
        sta w_scroll,x
        jsr clip_push
        jsr clip_screen
        ldx zlist
        jsr win_get_full
        jsr clip_rect
        ldx zlist
        jsr win_draw_frame
        ldx zlist
        jsr win_draw_content
        jsr clip_pop
.out:   rts

; mouse down in a scroll bar part A of the front window
!zone scroll_track
scroll_track:
        ldx #0
        cmp #P_LEFT             ; horizontal parts are the vertical ones + 5
        bcc +
        sbc #P_LEFT-P_UP
        ldx #W_H
+       stx fs_h
        sta u7
.loop:  lda u7
        cmp #P_UP
        bne +
        lda #-4
        jmp .go
+       cmp #P_DOWN
        bne +
        lda #4
        jmp .go
+       cmp #P_PGUP
        bne +
        lda #-32
        jmp .go
+       cmp #P_PGDN
        bne .thumb
        lda #32
.go:    jsr folder_scroll
        lda #3
        jsr wait_frames
        lda mbtn
        bne .loop
        jmp .done
.thumb: ; drag the thumb: scroll proportional to mouse position in the track
        ldx zlist
        lda fs_h
        jsr win_track
        lda fs_h
        bne .hthumb
        lda mouse_y
        sec
        sbc ry1
        bcs +
        lda #0
+       sta t0                  ; offset in track
        lda ry2
        sec
        sbc ry1
        sta t1                  ; track length
        jmp .scale
.hthumb:
        sec
        lda mouse_x
        sbc rx1
        sta t0
        lda mouse_x+1
        sbc rx1+1
        sta t2
        bcs +
        lda #0
        sta t0
        sta t2
+       sec
        lda rx2
        sbc rx1
        sta t1
        lda rx2+1
        sbc rx1+1
        beq +                   ; over 255 pixels: half scale
        lsr
        ror t1
        lsr t2
        ror t0
+       lda t2
        beq .scale
        lda t1
        sta t0
.scale: lda t0
        cmp t1
        bcc +
        lda t1
        sta t0
+       ; scroll = maxscr * t0 / t1
        lda t1
        sta .len
        lda zlist
        clc
        adc fs_h
        sta .w
        tax
        lda w_maxscr,x
        ldx t0
        jsr mul8
        sta t2
        stx t3
        lda #0
        sta t4
-       lda t2
        sec
        sbc .len
        tay
        lda t3
        sbc #0
        bcc +
        sta t3
        sty t2
        inc t4
        jmp -
+       ldx .w
        lda t4
        sec
        sbc w_scroll,x
        beq +
        jsr folder_scroll
+       jsr wait_frame
        lda mbtn
        beq .done
        jmp .thumb
.done:  lda #0
        sta fs_h
        rts
.len:   !byte 0
.w:     !byte 0

; ---------------------------------------------------------------------
; Clicking and dragging icons
; ---------------------------------------------------------------------
ick_obj: !byte 0
ick_mx:  !word 0
ick_my:  !byte 0
!zone icon_click
icon_click:
        stx ick_obj
        lda dbl_click
        beq +
        cpx last_obj
        bne +
        lda #NOOBJ
        sta last_obj
        jsr wait_release
        ldx ick_obj
        jmp open_obj
+       stx last_obj
        jsr select_obj
        lda mouse_x
        sta ick_mx
        lda mouse_x+1
        sta ick_mx+1
        lda mouse_y
        sta ick_my
.wait:  lda mbtn
        beq .out
        sec
        lda mouse_x
        sbc ick_mx
        clc
        adc #3
        cmp #7
        bcs .drag
        lda mouse_y
        sec
        sbc ick_my
        clc
        adc #3
        cmp #7
        bcs .drag
        jsr wait_frame
        jmp .wait
.drag:  ldx ick_obj
        jmp icon_drag
.out:   rts

dr_obj:  !byte 0
dr_gx:   !word 0         ; grab offset
dr_gy:   !word 0
dr_x:    !word 0         ; outline position (image top-left)
dr_y:    !word 0
dr_w:    !byte 0
dr_h:    !byte 0
dr_tgt:  !byte NOOBJ     ; highlighted drop target
dr_ox:   !byte 0         ; image offset inside the icon box
dr_oy:   !byte 0

!zone icon_drag
icon_drag:
        stx dr_obj
        jsr obj_base
        jsr obj_geom
        ldx dr_obj
        jsr obj_icon_ptr
        ldy #2
        lda (iptr),y
        sta dr_w
        dey
        lda (iptr),y
        sta dr_h
        sec
        lda ic_x
        sbc ob_x
        sta dr_ox
        sec
        lda ic_y
        sbc ob_y
        sta dr_oy
        sec
        lda ick_mx
        sbc ic_x
        sta dr_gx
        lda ick_mx+1
        sbc ic_x+1
        sta dr_gx+1
        sec
        lda ick_my
        sbc ic_y
        sta dr_gy
        lda #0
        sbc ic_y+1
        sta dr_gy+1
        lda #NOOBJ
        sta dr_tgt
        jsr dr_pos
        jsr dr_outline
.loop:  jsr wait_frame
        lda dr_x
        sta dr_px
        lda dr_x+1
        sta dr_px+1
        lda dr_y
        sta dr_py
        jsr dr_pos
        lda dr_x
        cmp dr_px
        bne .moved
        lda dr_x+1
        cmp dr_px+1
        bne .moved
        lda dr_y
        cmp dr_py
        beq .same
.moved: lda dr_x                ; erase at the old position
        sta dr_nx
        lda dr_x+1
        sta dr_nx+1
        lda dr_y
        sta dr_ny
        lda dr_px
        sta dr_x
        lda dr_px+1
        sta dr_x+1
        lda dr_py
        sta dr_y
        jsr dr_outline
        lda dr_nx
        sta dr_x
        lda dr_nx+1
        sta dr_x+1
        lda dr_ny
        sta dr_y
        jsr dr_check_target
        jsr dr_outline
.same:  lda mbtn
        bne .loop
        ; dropped
        jsr dr_outline
        ldx dr_tgt
        cpx #NOOBJ
        beq .notgt
        stx dr_tgt_save
        jsr unhilite
        lda #NOOBJ
        sta dr_tgt
        ldx dr_tgt_save
        jmp drop_into
.notgt: jmp drop_at

dr_nx:  !word 0
dr_ny:  !byte 0
dr_px:  !word 0
dr_py:  !byte 0
dr_tgt_save: !byte 0

; dr_x/dr_y from the mouse, kept on screen
dr_pos:
        sec
        lda mouse_x
        sbc dr_gx
        sta dr_x
        lda mouse_x+1
        sbc dr_gx+1
        sta dr_x+1
        bpl +
        lda #0
        sta dr_x
        sta dr_x+1
+       ; x + w <= 320
        clc
        lda dr_x
        adc dr_w
        sta t0
        lda dr_x+1
        adc #0
        sta t1
        lda t0
        cmp #<321
        lda t1
        sbc #>321
        bcc +
        sec
        lda #<320
        sbc dr_w
        sta dr_x
        lda #>320
        sbc #0
        sta dr_x+1
+       sec
        lda mouse_y
        sbc dr_gy
        sta t0
        lda #0
        sbc dr_gy+1
        bmi .top
        bne .bot
        lda t0
        cmp #DESK_Y1
        bcs +
.top:   lda #DESK_Y1
        sta t0
+       lda t0
        clc
        adc dr_h
        bcs .bot
        cmp #201
        bcc +
.bot:   lda #200
        sec
        sbc dr_h
        sta t0
+       lda t0
        sta dr_y
        rts

dr_outline:
        jsr clip_push
        jsr clip_screen
        lda #DESK_Y1
        sta cly1
        ldx dr_obj
        jsr obj_icon_ptr
        lda dr_x
        sta tx
        lda dr_x+1
        sta tx+1
        lda dr_y
        sta ty
        lda #0
        sta ty+1
        lda #ICON_OUTLINE
        sta iflags
        jsr draw_icon
        jmp clip_pop

; highlight the container under the pointer
!zone dr_check_target
dr_check_target:
        jsr find_target
        cpx dr_tgt
        beq .out
        stx u3
        ; erase the outline while icons are redrawn
        jsr dr_outline
        ldx dr_tgt
        jsr unhilite
        ldx u3
        stx dr_tgt
        cpx #NOOBJ
        beq +
        lda o_flags,x
        ora #OF_HILITE
        sta o_flags,x
        jsr redraw_obj
+       jsr dr_outline
.out:   rts

unhilite:
        cpx #NOOBJ
        beq +
        lda o_flags,x
        and #$ff-OF_HILITE
        sta o_flags,x
        jmp redraw_obj
+       rts

; container object under the mouse that dr_obj could be dropped into
!zone find_target
find_target:
        jsr win_at_mouse
        cpx #$ff
        bne .win
        lda #DESKTOP
        jmp .look
.win:   lda w_class,x
        cmp #CL_FOLDER
        bne .none
        stx u2
        jsr win_get_content
        jsr mouse_in_rect
        bcs .none
        ldx u2
        lda w_data,x
.look:  jsr obj_at_mouse
        cpx #NOOBJ
        beq .none
        cpx dr_obj
        beq .none
        jsr is_container
        bcs .none
        rts
.none:  ldx #NOOBJ
        rts

; ---------------------------------------------------------------------
; Dropping
; ---------------------------------------------------------------------
; drop into container X
!zone drop_into
drop_into:
        stx u4
        ldx dr_obj
        lda o_type,x
        cmp #T_DISK
        beq .disk
        cmp #T_TRASH
        beq .no
        ; no folder into itself or its own contents
        lda u4
        jsr obj_inside          ; is u4 inside dr_obj?
        bcc .no
        ldx dr_obj
        lda o_parent,x
        cmp u4
        beq .no                 ; already there
        ldx u4
        jsr free_slot           ; -> fs_x, fs_y
        ldx dr_obj
        lda u4
        jmp move_obj
.disk:  lda u4
        cmp #OBJ_TRASH
        bne .no
        lda #<str_noeject
        ldy #>str_noeject
        jmp alert_stop
.no:    rts

; carry clear if object A is X itself or inside X
!zone obj_inside
obj_inside:
        stx t5
        ldy #10
-       cmp t5
        beq .yes
        cmp #MAXOBJ
        bcs .no
        tax
        lda o_parent,x
        dey
        bne -
.no:    sec
        rts
.yes:   clc
        rts

; dropped on empty space
!zone drop_at
drop_at:
        ldx dr_obj
        lda o_type,x
        sta u5
        jsr win_at_mouse
        cpx #$ff
        bne .win
        ; desktop: position = icon box top-left
        sec
        lda dr_x
        sbc dr_ox
        sta fs_x
        lda dr_x+1
        sbc #0
        sta fs_x+1
        bpl +
        lda #0
        sta fs_x
        sta fs_x+1
+       lda dr_y
        sec
        sbc dr_oy
        cmp #DESK_Y1
        bcs +
        lda #DESK_Y1
+       cmp #170
        bcc +
        lda #170
+       sta fs_y
        lda fs_x
        cmp #<290
        lda fs_x+1
        sbc #>290
        bcc +
        lda #<290
        sta fs_x
        lda #>290
        sta fs_x+1
+       ldx dr_obj
        lda #DESKTOP
        jmp move_obj
.win:   lda w_class,x
        cmp #CL_FOLDER
        beq .bf1942
        jmp .no
.bf1942:
        lda u5                  ; disk and trash stay on the desktop
        cmp #T_FOLDER
        bcc .no
        stx u2
        jsr win_get_content
        jsr mouse_in_rect
        bcs .no
        ldx u2
        lda w_data,x
        sta u4
        lda u4
        ldx dr_obj
        jsr obj_inside
        bcc .no
        ; position relative to the icon area
        ldx u2
        sec
        lda dr_x
        sbc dr_ox
        sta t0
        lda dr_x+1
        sbc #0
        sta t1
        sec
        lda t0
        sbc wc_x1
        sta fs_x
        lda t1
        sbc wc_x1+1
        sta fs_x+1
        bpl +
        lda #0
        sta fs_x
        sta fs_x+1
+       clc
        lda fs_x
        adc w_hscroll,x
        sta fs_x
        bcc +
        inc fs_x+1
+       lda dr_y
        sec
        sbc dr_oy
        sec
        sbc wc_y1
        bcs +
        lda #0
+       sec
        sbc #IB_H
        bcs +
        lda #0
+       clc
        adc w_scroll,x
        sta fs_y
        ldx dr_obj
        lda u4
        jmp move_obj
.no:    rts

; ---------------------------------------------------------------------
; move_obj: X = object, A = new container, fs_x/fs_y = position
; ---------------------------------------------------------------------
fs_x:   !word 0
fs_y:   !byte 0
mo_obj: !byte 0
mo_old: !byte 0
mo_new: !byte 0
mo_rect: !fill 6
mo_trash: !byte 0

!zone move_obj
move_obj:
        stx mo_obj
        sta mo_new
        lda o_parent,x
        sta mo_old
        jsr trash_full
        sta mo_trash
        ; old area
        ldx mo_obj
        lda #0
        sta mo_rect+5           ; empty unless visible
        jsr obj_base
        bcs +
        jsr obj_geom
        jsr obj_bounds
        bcs +
        jsr limit_to_container
        bcs +
        ldx #5
-       lda rx1,x
        sta mo_rect,x
        dex
        bpl -
+       ldx mo_obj
        lda mo_new
        cmp #OBJ_TRASH
        bne +
        lda mo_old
        sta o_oldpar,x
+       lda mo_new
        sta o_parent,x
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
        ; repaint where it was
        lda mo_rect+5
        beq +
        ldx #5
-       lda mo_rect,x
        sta rx1,x
        dex
        bpl -
        jsr redraw_region
+       ldx mo_obj
        jsr redraw_obj
        lda mo_old
        cmp mo_new
        beq +
        jsr refresh_info_old
        lda mo_new
        jsr refresh_info
+       ; trash icon changes between empty and full
        jsr trash_full
        cmp mo_trash
        beq +
        ldx #OBJ_TRASH
        jsr redraw_obj
+       rts
refresh_info_old:
        lda mo_old
        ; fall through
; refresh_info: A = container - repaint its info bar, recompute scrolling
refresh_info:
        cmp #MAXOBJ
        bcs +
        tax
        lda o_win,x
        cmp #$ff
        beq +
        tax
        stx wsr_id
        jsr folder_layout
        ldx wsr_id
        jsr win_get_rect
        lda fl_moved            ; scrolled back: everything moved
        bne .all
        ldx wsr_id
        jsr win_get_content
        lda ry1
        clc
        adc #IB_H-1
        sta ry2
        jsr redraw_region
        ; scroll bars too
        ldx wsr_id
        jsr win_get_rect
        sec
        lda rx2
        sbc #SB_W
        sta rx1
        lda rx2+1
        sbc #0
        sta rx1+1
        jsr redraw_region
        ldx wsr_id
        jsr win_get_rect
        lda ry2
        sec
        sbc #SB_W
        sta ry1
.all:   jmp redraw_region
+       rts

; free_slot: X = container -> fs_x/fs_y = first free grid cell
fsl_c:  !byte 0
!zone free_slot
free_slot:
        stx fsl_c
        lda #4
        sta fs_y
.row:   lda #18
        sta fs_x
        lda #0
        sta fs_x+1
.col:   ldx #MAXOBJ-1
-       lda o_parent,x
        cmp fsl_c
        bne +
        lda o_xh,x
        bne +
        lda o_xl,x
        sec
        sbc fs_x
        clc
        adc #28
        cmp #56
        bcs +
        lda o_y,x
        sec
        sbc fs_y
        clc
        adc #18
        cmp #36
        bcc .taken
+       dex
        bpl -
        rts
.taken: lda fs_x
        clc
        adc #CELL_W
        sta fs_x
        cmp #18+CELL_W*4
        bcc .col
        lda fs_y
        clc
        adc #CELL_H
        sta fs_y
        cmp #200
        bcc .row
        lda #18
        sta fs_x
        lda #4
        sta fs_y
        rts

; ---------------------------------------------------------------------
; Opening things
; ---------------------------------------------------------------------
!zone open_obj
open_obj:
        lda o_type,x
        cmp #T_FOLDER+1
        bcs +
        jmp open_folder
+       cmp #T_SYS
        bne +
        lda #<str_sysfile
        ldy #>str_sysfile
        jmp alert_note
+       lda o_app,x
        asl
        tay
        lda app_open,y
        sta jvec
        lda app_open+1,y
        sta jvec+1
        jsr zoom_from_obj
        jmp (jvec)
.v:     !word 0

app_open:
        !word readme_open, clip_open, nop_method, brickles_launch, sheet_launch
        !word shapes_launch


; Brickles and the Spreadsheet are real applications: the System
; replaces the Finder with them
brickles_launch:
        lda #<str_brickles_file
        ldy #>str_brickles_file
        ldx #str_sheet_file-str_brickles_file
        bne app_launch
sheet_launch:
        lda #<str_sheet_file
        ldy #>str_sheet_file
        ldx #str_shapes_file-str_sheet_file
        bne app_launch
shapes_launch:
        lda #<str_shapes_file
        ldy #>str_shapes_file
        ldx #str_files_end-str_shapes_file
app_launch:
        sta u0
        sty u1
        stx u2
        lda zr_on               ; zoom from the icon to the whole screen
        beq +
        +rect 0, DESK_Y1, 319, 199
        jsr zoom_to_rect
+       lda u0
        ldy u1
        ldx u2
        jmp launch_app
str_brickles_file: !text "Brickles.app"
str_sheet_file:    !text "Spreadsheet.app"
str_shapes_file:   !text "Shapes.app"
str_files_end:

; ---------------------------------------------------------------------
; Renaming: typing while an icon is selected replaces its name
; ---------------------------------------------------------------------
!zone rename_key
rename_key:                     ; A = key
        ldx sel_obj
        cpx #NOOBJ
        beq .out
        cpx #OBJ_TRASH
        beq .out
        sta u4
        cmp #K_RETURN
        beq end_rename_now
        ldx sel_obj
        jsr obj_base
        bcs .out
        jsr obj_geom
        jsr obj_bounds
        jsr limit_to_container
        ldx #5
-       lda rx1,x
        sta mo_rect,x
        dex
        bpl -
        ldx sel_obj
        jsr obj_name_ptr
        lda renaming
        bne +
        lda #1
        sta renaming
        ldy #0
        tya
        sta (q1),y
+       ldy #0                  ; find the end of the name
-       lda (q1),y
        beq +
        iny
        bne -
+       lda u4
        cmp #K_DEL
        bne .add
        cpy #0
        beq .redraw
        dey
        lda #0
        sta (q1),y
        jmp .redraw
.add:   cmp #32
        bcc .out
        cmp #127
        bcs .out
        cpy #15
        bcs .out
        sta (q1),y
        iny
        lda #0
        sta (q1),y
.redraw:
        ldx #5
-       lda mo_rect,x
        sta rx1,x
        dex
        bpl -
        jsr redraw_region
        ldx sel_obj
        jsr redraw_obj
.out:   rts

end_rename_now:
end_rename:
        lda renaming
        beq +
        lda #0
        sta renaming
        ldx sel_obj
        jsr obj_name_ptr        ; empty name -> "untitled"
        ldy #0
        lda (q1),y
        bne ++
        lda #<str_untitled
        sta q0
        lda #>str_untitled
        sta q0+1
        jsr strcpy
++      ldx sel_obj
        jsr redraw_obj
+       rts

; ---------------------------------------------------------------------
; Menu commands
; ---------------------------------------------------------------------
ACT_ABOUT     = 0
ACT_NEWFOLDER = 1
ACT_OPEN      = 2
ACT_PRINT     = 3
ACT_CLOSE     = 4
ACT_INFO      = 5
ACT_DUP       = 6
ACT_PUTBACK   = 7
ACT_EJECT     = 8
ACT_UNDO      = 9
ACT_CUT       = 10
ACT_COPY      = 11
ACT_PASTE     = 12
ACT_CLEAR     = 13
ACT_SELALL    = 14
ACT_SHOWCLIP  = 15
ACT_VICON     = 16
ACT_VSMALL    = 17
ACT_VNAME     = 18
ACT_VDATE     = 19
ACT_VSIZE     = 20
ACT_VKIND     = 21
ACT_CLEANUP   = 22
ACT_EMPTY     = 23
ACT_ERASE     = 24
ACT_STARTUP   = 25
ACT_RESTART   = 26
ACT_SHUTDOWN  = 27

action_table:
        !word about_box
        !word new_folder, act_open, nop_method, act_close, get_info, act_dup, put_back, act_eject
        !word nop_method, act_edit, act_edit, act_edit, act_edit, act_edit, clip_open
        !word act_view, act_view, act_view, act_view, act_view, act_view
        !word clean_up, empty_trash, erase_disk, set_startup, restart, shut_down

; app_action: A = one of the actions above (called by the System)
!zone app_action
app_action:
        asl
        tay
        lda action_table,y
        sta jvec
        lda action_table+1,y
        sta jvec+1
        lda cur_action
        jmp (jvec)

act_open:
        ldx sel_obj
        cpx #NOOBJ
        beq +
        jmp open_obj
+       rts

act_close:
        jsr front_win
        beq +
        jmp close_win
+       rts

act_edit:                       ; route to the front window
        jsr front_win
        beq +
        lda cur_action
        sec
        sbc #ACT_UNDO           ; -> EDIT_ command
        sta key_char
        lda #M_EDIT
        jmp win_call
+       rts

act_view:
        jsr front_win
        beq +
        lda w_class,x
        cmp #CL_FOLDER
        bne +
        lda cur_action
        sec
        sbc #ACT_VICON
        sta w_view,x
+       rts

act_eject:
        lda #<str_noeject
        ldy #>str_noeject
        jmp alert_stop

; New Folder: in the front folder window (or on the disk)
!zone new_folder
new_folder:
        jsr new_obj
        bcs .out
        stx nf_obj
        ldy #OBJ_DISK
        jsr front_win
        cpx #$ff
        beq +
        lda w_class,x
        cmp #CL_FOLDER
        bne +
        ldy w_data,x
+       sty nf_par
        ldx nf_obj
        lda #T_FOLDER
        sta o_type,x
        lda #IC_FOLDER
        sta o_icon,x
        lda #APP_NONE
        sta o_app,x
        lda #0
        sta o_size,x
        lda #6
        sta o_date,x
        jsr obj_name_ptr
        lda #<str_o_empty
        sta q0
        lda #>str_o_empty
        sta q0+1
        jsr strcpy
        ldx nf_par
        jsr free_slot
        ldx nf_obj
        lda nf_par
        sta o_parent,x
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
        jsr select_obj
        lda nf_par
        jsr refresh_info
.out:   rts

nf_par: !byte 0
nf_obj: !byte 0

; new_obj: X = free object slot (carry set if none)
new_obj:
        ldx #0
-       lda o_parent,x
        cmp #NOOBJ
        beq +
        inx
        cpx #MAXOBJ
        bne -
        sec
        rts
+       lda #0
        sta o_flags,x
        sta o_locked,x
        lda #$ff
        sta o_win,x
        clc
        rts

; Duplicate: "Copy of <name>" next to it
!zone act_dup
act_dup:
        ldx sel_obj
        cpx #NOOBJ
        bne .bf2380
        jmp .out
.bf2380:
        lda o_type,x
        cmp #T_APP
        bcs .bf2383
        jmp .out
.bf2383:
        jsr new_obj
        bcc .bf2385
        jmp .out
.bf2385:
        stx nf_obj
        ldy sel_obj
        lda o_parent,y
        sta o_parent,x
        sta nf_par
        lda o_icon,y
        sta o_icon,x
        lda o_type,y
        sta o_type,x
        lda o_app,y
        sta o_app,x
        lda o_size,y
        sta o_size,x
        lda #6
        sta o_date,x
        jsr obj_name_ptr
        lda #<str_copyof
        sta q0
        lda #>str_copyof
        sta q0+1
        jsr strcpy
        ldx sel_obj
        jsr obj_name_ptr
        lda q1
        sta q0
        lda q1+1
        sta q0+1
        ldx nf_obj
        jsr obj_name_ptr
        jsr strcat
        ldx nf_obj                  ; truncate to 15
        jsr obj_name_ptr
        ldy #15
        lda #0
        sta (q1),y
        lda nf_par
        cmp #DESKTOP
        bne +
        ldy sel_obj
        lda o_xl,y
        sec
        sbc #30
        sta fs_x
        lda o_xh,y
        sbc #0
        sta fs_x+1
        lda o_y,y
        clc
        adc #8
        sta fs_y
        jmp ++
+       ldx nf_par
        jsr free_slot
++      ldx nf_obj
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
        jsr select_obj
        lda nf_par
        jsr refresh_info
.out:   rts

; Put Back: from the trash to where it came from
!zone put_back
put_back:
        ldx sel_obj
        cpx #NOOBJ
        beq .out
        lda o_parent,x
        cmp #OBJ_TRASH
        bne .out
        lda o_oldpar,x
        sta u4
        cmp #DESKTOP
        beq .desk
        tax
        jsr free_slot
        jmp .go
.desk:  lda #<200
        sta fs_x
        lda #>200
        sta fs_x+1
        lda #60
        sta fs_y
.go:    ldx sel_obj
        lda u4
        jmp move_obj
.out:   rts

; Clean Up: snap the icons of the front folder to the grid
!zone clean_up
clean_up:
        jsr front_win
        bne .bf2482
        jmp .out
.bf2482:
        lda w_class,x
        cmp #CL_FOLDER
        beq .bf2485
        jmp .out
.bf2485:
        stx u6
        lda w_data,x
        sta u4
        jsr win_get_content
        ; columns that fit
        sec
        lda wc_x2
        sbc wc_x1
        sec
        sbc #18
        ldx #0
-       cmp #CELL_W
        bcc +
        sbc #CELL_W
        inx
        bne -
+       cpx #0
        bne +
        inx
+       stx u5
        lda #0
        sta u3                  ; column
        lda #18
        sta fs_x
        lda #4
        sta fs_y
        ldx #0
.l:     lda o_parent,x
        cmp u4
        bne .n
        lda fs_x
        sta o_xl,x
        lda #0
        sta o_xh,x
        lda fs_y
        sta o_y,x
        lda fs_x
        clc
        adc #CELL_W
        sta fs_x
        inc u3
        lda u3
        cmp u5
        bcc .n
        lda #0
        sta u3
        lda #18
        sta fs_x
        lda fs_y
        clc
        adc #CELL_H
        sta fs_y
.n:     inx
        cpx #MAXOBJ
        bne .l
        ldx u6
        stx wsr_id
        jsr folder_layout
        ldx u6
        jsr win_get_content
        jmp redraw_region
.out:   rts

; Empty Trash: everything inside the trash goes away
!zone empty_trash
empty_trash:
        jsr trash_full
        beq .out
        ldx #MAXOBJ-1
.l:     stx et_i
        cpx #OBJ_TRASH
        beq .n
        lda o_parent,x
        cmp #NOOBJ
        beq .n
        lda #OBJ_TRASH
        jsr obj_inside_rev      ; is X inside the trash?
        bcs .n
        ldx et_i
        lda o_win,x             ; close its window
        cmp #$ff
        beq +
        tax
        jsr win_close
        ldx et_i
+       lda #NOOBJ
        sta o_parent,x
        cpx sel_obj
        bne .n
        lda #NOOBJ
        sta sel_obj
.n:     ldx et_i
        dex
        bpl .l
        ldx #OBJ_TRASH
        jsr redraw_obj
        lda #OBJ_TRASH
        jsr refresh_info
        ldx #OBJ_TRASH
        lda o_win,x
        cmp #$ff
        beq .out
        tax
        jsr win_get_content
        jmp redraw_region
.out:   rts

et_i:   !byte 0

; carry clear if object X is inside container A (not X itself)
obj_inside_rev:
        sta t5
        lda o_parent,x
        ldy #10
-       cmp t5
        beq +
        cmp #MAXOBJ
        bcs ++
        tax
        lda o_parent,x
        dey
        bne -
++      sec
        rts
+       clc
        rts

erase_disk:
        lda #<str_erase
        ldy #>str_erase
        jmp alert_stop
set_startup:
        lda #<str_startup
        ldy #>str_startup
        jmp alert_note

; ---------------------------------------------------------------------
; update_menus: enable/disable items for the current state
; ---------------------------------------------------------------------
MN_APPLE   = 0*16
MN_FILE    = 1*16
MN_EDIT    = 2*16
MN_VIEW    = 3*16
MN_SPECIAL = 4*16

!zone update_menus
update_menus:
        jsr end_rename
        ; File
        lda #0
        ldx sel_obj
        cpx #NOOBJ
        beq +
        lda #1
+       sta u0                  ; something selected
        ldx #MN_FILE+1           ; Open
        jsr menu_set
        lda u0
        ldx #MN_FILE+5           ; Get Info
        jsr menu_set
        lda #0                  ; Duplicate: applications and documents
        ldx sel_obj
        cpx #NOOBJ
        beq +
        ldy o_type,x
        cpy #T_APP
        bcc +
        lda #1
+       ldx #MN_FILE+6
        jsr menu_set
        lda #0                  ; Put Back: something in the trash
        ldx sel_obj
        cpx #NOOBJ
        beq +
        ldy o_parent,x
        cpy #OBJ_TRASH
        bne +
        lda #1
+       ldx #MN_FILE+7
        jsr menu_set
        lda zcount              ; Close: any window
        ldx #MN_FILE+3
        jsr menu_set
        ldx #MN_FILE+2           ; Print
        jsr menu_disable
        ; Edit: nothing in the Finder's own windows uses it (yet)
        lda #0
        sta u1
        sta u2
        lda u1
        ldx #MN_EDIT+2           ; Cut
        jsr menu_set
        lda u2
        ldx #MN_EDIT+3           ; Copy
        jsr menu_set
        lda u2
        ldx #MN_EDIT+4           ; Paste
        jsr menu_set
        lda u1
        ldx #MN_EDIT+5           ; Clear
        jsr menu_set
        lda u1
        ldx #MN_EDIT+6           ; Select All
        jsr menu_set
        ldx #MN_EDIT+0           ; Undo
        jsr menu_disable
        ; View: folder in front, check its view
        lda #$ff
        sta u3
        jsr front_win
        cpx #$ff
        beq +
        lda w_class,x
        cmp #CL_FOLDER
        bne +
        lda w_view,x
        sta u3
+       ldx #0
.v:     lda menu_flags+MN_VIEW,x
        and #$ff-MF_CHECKED-MF_DISABLED
        ldy u3
        cpy #$ff
        bne +
        ora #MF_DISABLED
        jmp ++
+       cpx u3
        bne ++
        ora #MF_CHECKED
++      sta menu_flags+MN_VIEW,x
        inx
        cpx #6
        bne .v
        ; Special
        jsr trash_full
        ldx #MN_SPECIAL+1        ; Empty Trash
        jsr menu_set
        lda #0
        ldy u3
        cpy #$ff
        beq +
        lda #1
+       ldx #MN_SPECIAL+0        ; Clean Up
        jmp menu_set
