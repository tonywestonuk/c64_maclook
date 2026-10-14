; =====================================================================
; menu.asm - menu bar and pull-down menus
; =====================================================================

MENUBAR_LINE = 11       ; black line under the menu bar
DESK_Y1      = 12       ; first desktop row
MAX_ITEMS    = 12
ITEM_H       = 11
SEP_H        = 5

MF_DISABLED = $80
MF_CHECKED  = $01

; per menu: title, item list
; menu 0 is the System's C= menu; the application fills in the rest
menu_titles:
        !word str_m_apple, str_none, str_none, str_none, str_none
menu_lists:
        !word items_apple, items_none, items_none, items_none, items_none

menu_tx:    !fill NUM_MENUS*2      ; title text x
menu_hx1:   !fill NUM_MENUS*2      ; highlight rect
menu_hx2:   !fill NUM_MENUS*2

; menu state while tracking
mn_cur:   !byte $ff             ; open menu
mn_item:  !byte $ff             ; highlighted item
mn_x1:    !word 0
mn_x2:    !word 0
mn_y2:    !byte 0
mn_count: !byte 0
mn_tops:  !fill MAX_ITEMS+1     ; top row of each item, plus end
mn_list:  !word 0

; ---------------------------------------------------------------------
; menu_init: lay out the titles
; ---------------------------------------------------------------------
!zone menu_init
menu_init:
        lda #0
        sta font
        lda #<10
        sta u0                  ; running x
        lda #>10
        sta u1
        ldx #0
.m:     stx u2
        txa
        asl
        tax
        lda u0
        sta menu_tx,x
        sec
        sbc #6
        sta menu_hx1,x
        lda u1
        sta menu_tx+1,x
        sbc #0
        sta menu_hx1+1,x
        lda menu_titles,x
        sta tstr
        lda menu_titles+1,x
        sta tstr+1
        jsr text_width
        ldx u2
        txa
        asl
        tax
        clc
        lda u0
        adc twidth
        sta u0
        lda u1
        adc twidth+1
        sta u1
        clc
        lda u0
        adc #4
        sta menu_hx2,x
        lda u1
        adc #0
        sta menu_hx2+1,x
        clc
        lda u0
        adc #13
        sta u0
        bcc +
        inc u1
+       ldx u2
        inx
        cpx #NUM_MENUS
        bne .m
        rts

; draw all titles (menu bar already white)
!zone menu_draw_titles
menu_draw_titles:
        lda #0
        sta font
        lda #B_OR
        sta tmode
        ldx #0
.t:     stx u2
        txa
        asl
        tax
        lda menu_tx,x
        sta tx
        lda menu_tx+1,x
        sta tx+1
        lda #2
        sta ty
        lda #0
        sta ty+1
        lda menu_titles,x
        ldy menu_titles+1,x
        jsr draw_str
        ldx u2
        inx
        cpx #NUM_MENUS
        bne .t
        ; the Commodore logo
        lda menu_tx
        sta tx
        lda menu_tx+1
        sta tx+1
        lda #1
        sta ty
        lda #0
        sta ty+1
        lda #ICON_PLAIN
        sta iflags
        lda #<icon_c64logo
        sta iptr
        lda #>icon_c64logo
        sta iptr+1
        jmp draw_icon

; invert title X
!zone menu_hilite
menu_hilite:
        txa
        asl
        tax
        lda menu_hx1,x
        sta rx1
        lda menu_hx1+1,x
        sta rx1+1
        lda menu_hx2,x
        sta rx2
        lda menu_hx2+1,x
        sta rx2+1
        lda #0
        sta ry1
        lda #MENUBAR_LINE-1
        sta ry2
        jsr clip_push
        jsr clip_screen
        jsr invert_rect
        jmp clip_pop

; ---------------------------------------------------------------------
; menu_open: X = menu.  Computes geometry, saves the area, draws it.
; ---------------------------------------------------------------------
!zone menu_open
menu_open:
        stx mn_cur
        jsr menu_hilite
        jsr clip_push
        jsr clip_screen
        lda mn_cur
        asl
        tax
        lda menu_lists,x
        sta mn_list
        sta q0
        lda menu_lists+1,x
        sta mn_list+1
        sta q0+1
        ldy #0
        lda (q0),y
        sta mn_count
        ; item tops and widest item
        lda #0
        sta font
        sta u4                  ; max width
        sta u5                  ; any shortcut
        lda #MENUBAR_LINE+1
        sta u3                  ; running y
        ldx #0
.it:    stx u2
        lda u3
        sta mn_tops,x
        jsr item_ptr            ; q1 -> item record
        ldy #0
        lda (q1),y
        iny
        ora (q1),y
        bne .text
        lda u3                  ; separator
        clc
        adc #SEP_H
        sta u3
        jmp .nexti
.text:  lda (q1),y
        sta tstr+1
        dey
        lda (q1),y
        sta tstr
        jsr text_width
        cmp u4
        bcc +
        sta u4
+       ldy #2
        lda (q1),y
        beq +
        sta u5
+       lda u3
        clc
        adc #ITEM_H
        sta u3
.nexti: ldx u2
        inx
        cpx mn_count
        bne .it
        lda u3
        sta mn_tops,x
        sta mn_y2               ; bottom frame line
        ; width = 14 + max + 8 (+ 22 for shortcuts)
        lda u4
        clc
        adc #22
        ldx u5
        beq +
        adc #22
+       sta u4
        ; x1 = highlight left, x2 = x1 + width
        lda mn_cur
        asl
        tax
        lda menu_hx1,x
        sta mn_x1
        lda menu_hx1+1,x
        sta mn_x1+1
        clc
        lda mn_x1
        adc u4
        sta mn_x2
        lda mn_x1+1
        adc #0
        sta mn_x2+1
        ; keep the shadow on screen: x2 <= 317
        lda mn_x2
        cmp #<318
        lda mn_x2+1
        sbc #>318
        bcc +
        sec
        lda mn_x2
        sbc #<317
        sta t0
        sec
        lda mn_x1
        sbc t0
        sta mn_x1
        lda mn_x1+1
        sbc #0
        sta mn_x1+1
        lda #<317
        sta mn_x2
        lda #>317
        sta mn_x2+1
+       ; save area under menu + shadow
        lda mn_x1+1
        lsr
        lda mn_x1
        ror
        lsr
        lsr
        sta sv_c1
        clc
        lda mn_x2
        adc #1
        sta t0
        lda mn_x2+1
        adc #0
        lsr
        lda t0
        ror
        lsr
        lsr
        sta sv_c2
        lda #MENUBAR_LINE
        sta sv_y1
        ldx mn_y2
        inx
        stx sv_y2
        jsr save_area
        ; box
        jsr mn_box_rect
        jsr fill_white
        jsr set_black
        jsr frame_rect
        ; shadow: right and bottom
        jsr mn_box_rect
        clc
        lda rx2
        adc #1
        sta rx1
        sta rx2
        lda rx2+1
        adc #0
        sta rx1+1
        sta rx2+1
        inc ry2
        lda #MENUBAR_LINE+2
        sta ry1
        jsr fill_black
        jsr mn_box_rect
        inc ry2
        lda ry2
        sta ry1
        clc
        lda rx1
        adc #2
        sta rx1
        bcc +
        inc rx1+1
+       inc rx2
        bne +
        inc rx2+1
+       jsr fill_black
        ; items
        ldx #0
-       stx u2
        jsr menu_draw_item
        ldx u2
        inx
        cpx mn_count
        bne -
        lda #$ff
        sta mn_item
        jmp clip_pop

mn_box_rect:
        lda mn_x1
        sta rx1
        lda mn_x1+1
        sta rx1+1
        lda mn_x2
        sta rx2
        lda mn_x2+1
        sta rx2+1
        lda #MENUBAR_LINE
        sta ry1
        lda mn_y2
        sta ry2
        rts

; q1 = item X of the open menu (records are 4 bytes after the count)
item_ptr:
        txa
        asl
        asl
        clc
        adc #1
        adc mn_list
        sta q1
        lda mn_list+1
        adc #0
        sta q1+1
        rts

; item rect for item X: rx1..ry2 (inside the frame)
item_rect:
        clc
        lda mn_x1
        adc #1
        sta rx1
        lda mn_x1+1
        adc #0
        sta rx1+1
        sec
        lda mn_x2
        sbc #1
        sta rx2
        lda mn_x2+1
        sbc #0
        sta rx2+1
        lda mn_tops,x
        sta ry1
        lda mn_tops+1,x
        sec
        sbc #1
        sta ry2
        rts

; flags for item X of the open menu -> A
item_flags:
        lda mn_cur
        asl
        asl
        asl
        asl
        stx t0
        ora t0
        tay
        lda menu_flags,y
        rts

!zone menu_draw_item
menu_draw_item:                 ; X = item
        stx u6
        jsr item_ptr
        ldy #0
        lda (q1),y
        iny
        ora (q1),y
        bne .text
        ; separator: dotted line
        ldx u6
        jsr item_rect
        lda ry1
        clc
        adc #2
        sta ry1
        sta ry2
        jsr set_gray
        jmp fill_rect
.text:  clc
        lda mn_x1
        adc #12
        sta tx
        lda mn_x1+1
        adc #0
        sta tx+1
        ldx u6
        lda mn_tops,x
        clc
        adc #1
        sta ty
        lda #0
        sta ty+1
        sta font
        lda #B_OR
        sta tmode
        ldy #1
        lda (q1),y
        sta tstr+1
        dey
        lda (q1),y
        sta tstr
        jsr draw_text
        ; check mark
        ldx u6
        jsr item_flags
        and #MF_CHECKED
        beq +
        clc
        lda mn_x1
        adc #3
        sta tx
        lda mn_x1+1
        adc #0
        sta tx+1
        lda #<str_check
        ldy #>str_check
        jsr draw_str
+       ; shortcut
        ldy #2
        lda (q1),y
        beq .nokey
        sta str_cmdkey+1
        lda #<str_cmdkey
        sta tstr
        lda #>str_cmdkey
        sta tstr+1
        jsr text_width
        sec
        lda mn_x2
        sbc #5
        sta tx
        lda mn_x2+1
        sbc #0
        sta tx+1
        sec
        lda tx
        sbc twidth
        sta tx
        lda tx+1
        sbc twidth+1
        sta tx+1
        jsr draw_text
.nokey: ; disabled: grey it out
        ldx u6
        jsr item_flags
        bpl +
        ldx u6
        jsr item_rect
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        lda #M_BIC
        sta rmode
        jsr fill_rect
+       rts

str_cmdkey: !byte $11,0,0
str_check:  !byte $12,0

; invert item X (if it is a real, enabled item)
!zone menu_invert_item
menu_invert_item:
        cpx #$ff
        beq +
        stx u6
        jsr item_rect
        jsr clip_push
        jsr clip_screen
        jsr invert_rect
        jsr clip_pop
        ldx u6
+       rts

!zone menu_close
menu_close:
        ldx mn_cur
        cpx #$ff
        beq +
        jsr restore_area
        ldx mn_cur
        jsr menu_hilite
        lda #$ff
        sta mn_cur
        sta mn_item
+       rts

; item under the mouse in the open menu -> X ($ff = none / disabled)
!zone item_at_mouse
item_at_mouse:
        ldx #$ff
        lda mouse_y
        cmp #MENUBAR_LINE+1
        bcc .out
        cmp mn_y2
        bcs .out
        lda mouse_x
        cmp mn_x1
        lda mouse_x+1
        sbc mn_x1+1
        bcc .out
        lda mn_x2
        cmp mouse_x
        lda mn_x2+1
        sbc mouse_x+1
        bcc .out
        ldx #0
-       lda mouse_y
        cmp mn_tops+1,x
        bcc .found
        inx
        cpx mn_count
        bne -
        ldx #$ff
        rts
.found: jsr item_ptr            ; separators and disabled items don't count
        ldy #0
        lda (q1),y
        iny
        ora (q1),y
        beq .none
        stx u6
        jsr item_flags
        ldx u6
        and #MF_DISABLED
        beq .out
.none:  ldx #$ff
.out:   rts

; title under the mouse -> X ($ff = none)
!zone title_at_mouse
title_at_mouse:
        ldx #$ff
        lda mouse_y
        cmp #MENUBAR_LINE
        bcs .out
        ldx #0
-       stx u6
        txa
        asl
        tay
        lda mouse_x
        cmp menu_hx1,y
        lda mouse_x+1
        sbc menu_hx1+1,y
        bcc .next
        lda menu_hx2,y
        cmp mouse_x
        lda menu_hx2+1,y
        sbc mouse_x+1
        bcs .hit
.next:  ldx u6
        inx
        cpx #NUM_MENUS
        bne -
        ldx #$ff
.out:   rts
.hit:   ldx u6
        rts

; ---------------------------------------------------------------------
; menu_track: called on a mouse-down in the menu bar.  Returns with
; A = action ($ff = none) after the button is released.
; ---------------------------------------------------------------------
!zone menu_track
menu_track:
        jsr hook_update_menus
        lda #$ff
        sta mn_cur
        sta mn_item
.loop:  jsr title_at_mouse
        cpx #$ff
        beq .intitle_none
        cpx mn_cur
        beq .items
        stx u7
        jsr menu_close
        ldx u7
        jsr menu_open
        jmp .wait
.intitle_none:
.items: lda mn_cur
        cmp #$ff
        beq .wait
        jsr item_at_mouse
        cpx mn_item
        beq .wait
        stx u7
        ldx mn_item
        jsr menu_invert_item
        ldx u7
        stx mn_item
        jsr menu_invert_item
.wait:  jsr wait_frame
        lda mbtn
        bne .loop
        ; released
        lda mn_item
        cmp #$ff
        beq .none
        ; blink the chosen item
        lda menu_blinks
        sta u7
        beq .blinked
-       ldx mn_item
        jsr menu_invert_item
        lda #3
        jsr wait_frames
        ldx mn_item
        jsr menu_invert_item
        lda #3
        jsr wait_frames
        dec u7
        bne -
.blinked:
        ldx mn_item
        jsr item_ptr
        ldy #3
        lda (q1),y
        pha
        jsr menu_close
        pla
        rts
.none:  jsr menu_close
        lda #$ff
        rts

; ---------------------------------------------------------------------
; menu_key: A = letter typed with Command.  Returns A = action or $ff.
; The menu title flashes like on the Mac.
; ---------------------------------------------------------------------
!zone menu_key
menu_key:
        cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        sbc #$1f                ; to upper case (carry is clear)
+       sta u7
        jsr hook_update_menus
        ldx #0
.m:     stx mn_cur
        txa
        asl
        tay
        lda menu_lists,y
        sta mn_list
        sta q0
        lda menu_lists+1,y
        sta mn_list+1
        sta q0+1
        ldy #0
        lda (q0),y
        sta mn_count
        ldx #0
.i:     jsr item_ptr
        ldy #2
        lda (q1),y
        cmp u7
        bne .ni
        stx u6
        jsr item_flags
        bmi .ni2
        ; found: flash title, return action
        ldx mn_cur
        jsr menu_hilite
        lda #6
        jsr wait_frames
        ldx mn_cur
        jsr menu_hilite
        ldx u6
        jsr item_ptr
        ldy #3
        lda (q1),y
        ldx #$ff
        stx mn_cur
        rts
.ni2:   ldx u6
.ni:    inx
        cpx mn_count
        bne .i
        ldx mn_cur
        inx
        cpx #NUM_MENUS
        bne .m
        lda #$ff
        sta mn_cur
        rts

; set/clear item flags: X = menu*16+item
menu_enable:
        lda menu_flags,x
        and #$ff-MF_DISABLED
        sta menu_flags,x
        rts
menu_disable:
        lda menu_flags,x
        ora #MF_DISABLED
        sta menu_flags,x
        rts
; A = 0 -> disable item X, else enable
menu_set:
        cmp #0
        beq menu_disable
        bne menu_enable
