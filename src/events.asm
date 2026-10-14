; =====================================================================
; events.asm - the event loop, and the hooks into the application
;
; An application (the Finder) is loaded at APP_BASE and starts with
; a table of entry points:
;
;   +0  jmp init            set up its data
;   +3  jmp action          A = menu action (below SYS_ACT)
;   +6  jmp update_menus    enable/disable/check its menu items
;   +9  jmp desk_draw       draw desktop icons inside the clip rect
;   +12 jmp desk_click      mouse down on the desktop
;   +15 jmp key             key typed with no window in front (A)
;   +18 jmp quit            about to restart or shut down
;   +21 !word classes       its window classes (CL_APPBASE upwards)
;   +23 !word menus         4 title pointers, then 4 item lists
;   +25 !word about         text for the first item of the C= menu
;   +27 !text "APP!"
; =====================================================================

APP_INIT      = APP_BASE+0
APP_ACTION    = APP_BASE+3
APP_UPDMENUS  = APP_BASE+6
APP_DESKDRAW  = APP_BASE+9
APP_DESKCLICK = APP_BASE+12
APP_KEY       = APP_BASE+15
APP_QUIT      = APP_BASE+18
APP_CLASSES   = APP_BASE+21
APP_MENUS     = APP_BASE+23
APP_ABOUT     = APP_BASE+25
APP_MAGIC     = APP_BASE+27

ACT_NONE    = $ff
SYS_ACT     = $40       ; actions from here up belong to the System

; Edit commands passed to a window's M_EDIT method in key_char
EDIT_UNDO   = 0
EDIT_CUT    = 1
EDIT_COPY   = 2
EDIT_PASTE  = 3
EDIT_CLEAR  = 4
EDIT_SELALL = 5

app_loaded: !byte 0
last_down:  !word 0
last_mx:    !word 0
last_my:    !byte 0

; guarded calls into the application
hook_desk_draw:
        lda app_loaded
        beq +
        jmp APP_DESKDRAW
+       rts
hook_desk_click:
        lda app_loaded
        beq +
        jmp APP_DESKCLICK
+       rts
hook_update_menus:
        lda app_loaded
        beq +
        jmp APP_UPDMENUS
+       rts
hook_key:
        ldx app_loaded
        beq +
        jmp APP_KEY
+       rts
hook_quit:
        lda app_loaded
        beq +
        jmp APP_QUIT
+       rts

; put the application's menus in the menu bar
!zone install_app_menus
install_app_menus:
        lda APP_MENUS
        sta q0
        lda APP_MENUS+1
        sta q0+1
        ldy #0
-       lda (q0),y
        sta menu_titles+2,y
        iny
        cpy #8
        bne -
        ldx #0
-       lda (q0),y
        sta menu_lists+2,x
        iny
        inx
        cpx #8
        bne -
        lda APP_ABOUT
        sta items_apple+1
        lda APP_ABOUT+1
        sta items_apple+2
        lda #0                  ; nothing disabled or checked from the last app
        ldx #NUM_MENUS*16-16-1
-       sta menu_flags+16,x
        dex
        bpl -
        rts

; ---------------------------------------------------------------------
; Event loop
; ---------------------------------------------------------------------
!zone main_loop
main_loop:
        lda pending_action
        cmp #ACT_NONE
        beq +
        ldx #ACT_NONE
        stx pending_action
        jsr do_action
+       jsr idle_tasks
        jsr new_press
        bcc .key
        jsr mouse_down
        jsr wait_release
        jmp main_loop
.key:   jsr get_key
        beq main_loop
        jsr key_down
        jmp main_loop

; every window gets an idle call (clock, caret)
idle_tasks:
        ldx #0
-       cpx zcount
        beq +
        stx .i
        lda zlist,x
        tax
        lda #M_IDLE
        jsr win_call
        ldx .i
        inx
        bne -
+       rts
.i:     !byte 0

!zone mouse_down
mouse_down:
        jsr show_cursor         ; a game may have hidden it
        ; double click?
        lda #0
        sta dbl_click
        sec
        lda press_jiffy         ; when it was pressed, not when we got to it
        sbc last_down
        sta t0
        lda press_jiffy+1
        sbc last_down+1
        bne +
        lda t0
        cmp dbl_time
        bcs +
        lda mouse_x
        sec
        sbc last_mx
        clc
        adc #4
        cmp #9
        bcs +
        lda mouse_y
        sec
        sbc last_my
        clc
        adc #4
        cmp #9
        bcs +
        inc dbl_click
+       lda press_jiffy
        sta last_down
        lda press_jiffy+1
        sta last_down+1
        lda mouse_x
        sta last_mx
        lda mouse_x+1
        sta last_mx+1
        lda mouse_y
        sta last_my
        ; where?
        lda mouse_y
        cmp #MENUBAR_LINE
        bcs .notmenu
        jsr menu_track
        jmp do_action
.notmenu:
        jsr win_at_mouse
        cpx #$ff
        bne .win
        jmp hook_desk_click
.win:   stx .w
        jsr win_part
        ldx .w
        cmp #P_TITLE
        bne +
        jmp win_drag
+       cpx zlist
        beq .front
        jmp win_select          ; first click activates
.front: cmp #P_CLOSE
        bne +
        jsr close_box_rect
        jsr track_box
        bcs .out
        ldx .w
        jmp close_win
+       cmp #P_ZOOM
        bne +
        jsr zoom_box_rect
        jsr track_box
        bcs .out
        ldx .w
        jmp win_zoom
+       cmp #P_GROW
        bne +
        jmp win_grow
+       cmp #P_CONTENT
        bne +
        lda #M_CLICK
        jmp win_call
+       cmp #P_UP
        bcc .out
        sta win_part_hit        ; scroll bar part, for the window's class
        lda #M_SCROLL
        jmp win_call
.out:   rts
.w:     !byte 0

; close window X (dialogs close themselves)
close_win:
        lda w_class,x
        cmp #CL_DIALOG
        beq +
        jmp win_close
+       rts

!zone key_down
key_down:                       ; A = key, X = modifiers
        sta key_char
        txa
        and #MOD_CMD
        beq .plain
        lda key_char
        jsr menu_key
        jmp do_action
.plain: jsr front_win
        beq .app
        lda #M_KEY              ; the method reads key_char
        jmp win_call
.app:   lda key_char
        jmp hook_key

; ---------------------------------------------------------------------
; Menu actions go to the application.  Actions from SYS_ACT up are
; kept for the System (none yet: desk accessories will be files).
; ---------------------------------------------------------------------
!zone do_action
do_action:
        cmp #ACT_NONE
        beq .out
        sta cur_action
        ldx #0
        stx zr_on
        cmp #SYS_ACT
        bcs .out
        ldx app_loaded
        beq .out
        jmp APP_ACTION
.out:   rts

too_many_windows:
        lda #<str_toomany
        ldy #>str_toomany
        jmp alert_stop
