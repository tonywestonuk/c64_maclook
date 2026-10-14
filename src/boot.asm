; =====================================================================
; boot.asm - start-up, loading the Finder, restart and shut down
; =====================================================================

str_finder_file: !text "FINDER"
FINDER_NAME_LEN = 6

!zone boot
boot:
        lda #0
        sta app_loaded
        jsr clip_screen
        +rect 0, 0, 319, 199
        jsr set_gray
        jsr fill_rect
        +txy 148, 88
        lda #<icon_happymac
        sta iptr
        lda #>icon_happymac
        sta iptr+1
        lda #0
        sta iflags
        jsr draw_icon
        jsr screen_on
        lda #60
        jsr wait_frames
        ; "Welcome to Commodore 64." stays up while the Finder loads
        +rect 70, 82, 249, 116
        jsr fill_white
        jsr set_black
        jsr frame_rect
        lda #2
        jsr rect_inset
        jsr frame_rect
        lda #1
        jsr rect_inset
        jsr frame_rect
        lda #0
        sta font
        lda #B_OR
        sta tmode
        lda #<str_welcome
        sta tstr
        lda #>str_welcome
        sta tstr+1
        jsr text_width
        lda #<320
        sec
        sbc twidth
        sta tx
        lda #>320
        sbc twidth+1
        lsr
        sta tx+1
        lda tx
        ror
        sta tx
        lda #95
        sta ty
        lda #0
        sta ty+1
        jsr draw_text
        lda #<str_finder_file
        ldy #>str_finder_file
        ldx #FINDER_NAME_LEN
        jsr load_app
start_app:                      ; hand over to the loaded application
        jsr APP_INIT
        jsr install_app_menus
        jsr menu_init
        jmp redraw_all

; load_app: A/Y = file name, X = length.  Loads an application to
; APP_BASE; if that fails, says so and falls back to the Finder.
app_name: !fill 16
app_namelen: !byte 0
!zone load_app
load_app:
        sta q0
        sty q0+1
        stx app_namelen
        ldy #0                  ; the name may live in the old application
-       lda (q0),y
        sta app_name,y
        iny
        cpy app_namelen
        bne -
        lda #0
        sta app_loaded
        lda #CUR_WATCH
        jsr set_cursor
.try:   lda #<app_name
        ldy #>app_name
        ldx app_namelen
        jsr load_file
        bcs .fail
        ldx #3                  ; check the application's signature
-       lda APP_MAGIC,x
        cmp str_appmagic,x
        bne .fail
        dex
        bpl -
        lda #1
        sta app_loaded
        lda #CUR_ARROW
        jmp set_cursor
.fail:  lda #CUR_ARROW
        jsr set_cursor
        lda #<str_noload
        ldy #>str_noload
        jsr alert_stop
        lda #CUR_WATCH
        jsr set_cursor
        ldx #0                  ; then try the Finder
-       lda str_finder_file,x
        sta app_name,x
        inx
        cpx #FINDER_NAME_LEN
        bne -
        stx app_namelen
        jmp .try

; launch_app: A/Y = file name, X = length.  Replaces the running
; application (like launching from the Finder before MultiFinder).
; Never returns.
!zone launch_app
launch_app:
        sta q0
        sty q0+1
        stx q1
        lda q0                  ; keep the name safe from close methods
        sta .n
        lda q0+1
        sta .n+1
        lda q1
        sta .l
        jsr hook_quit
        jsr close_all_quiet
        lda #0
        sta app_loaded
        lda #ACT_NONE
        sta pending_action
        ; empty menu bar and desktop while the disk works
        ldx #0
-       lda #<str_none
        sta menu_titles+2,x
        lda #>str_none
        sta menu_titles+3,x
        lda #<items_none
        sta menu_lists+2,x
        lda #>items_none
        sta menu_lists+3,x
        inx
        inx
        cpx #8
        bne -
        jsr menu_init
        jsr redraw_all
        lda .n
        ldy .n+1
        ldx .l
        jsr load_app
        ldx #$ff                ; the old application is gone: fresh stack
        txs
        jsr start_app
        jmp main_loop
.n:     !word 0
.l:     !byte 0

; quit_app: back to the Finder
quit_app:
        lda #<str_finder_file
        ldy #>str_finder_file
        ldx #FINDER_NAME_LEN
        jmp launch_app

str_appmagic: !text "APP!"

; close every window without redrawing
close_all_quiet:
-       lda zcount
        beq +
        ldx zlist
        lda #M_CLOSE
        jsr win_call
        ldx zlist
        lda #0
        sta w_used,x
        jsr z_remove
        jmp -
+       rts


; restart: the Finder is loaded again from the disk
!zone restart
restart:
        jsr hook_quit
        jsr close_all_quiet
        jsr clip_screen
        +rect 0, 0, 319, 199
        jsr fill_black
        lda #30
        jsr wait_frames
reboot:
        ldx #$ff                ; nothing of the old Finder stays on the stack
        txs
        lda #ACT_NONE
        sta pending_action
        jsr boot
        jmp main_loop

!zone shut_down
shut_down:
        jsr hook_quit
        jsr close_all_quiet
        lda #0
        sta app_loaded
        jsr clip_screen
        +rect 0, 0, 319, 199
        jsr fill_black
        lda #DLG_SHUTDOWN
        sta dlg_kind
        lda #64
        sta dlg_h
        lda #1
        sta dlg_nbtn
        lda #<str_restart
        sta dlg_btn
        lda #>str_restart
        sta dlg_btn+1
        lda #<50
        ldx #66
        ldy #<269
        jsr dlg_open
        jsr dialog_loop
        lda #<str_ok
        sta dlg_btn
        lda #>str_ok
        sta dlg_btn+1
        ldx dlg_win
        lda #0
        sta w_used,x
        jsr z_remove
        lda #80
        sta dlg_h
        jsr clip_screen
        +rect 0, 0, 319, 199
        jsr fill_black
        lda #30
        jsr wait_frames
        jmp reboot

shutdown_draw:
        lda #<icon_note
        sta iptr
        lda #>icon_note
        sta iptr+1
        clc
        lda wc_x1
        adc #10
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
        sta iflags
        jsr draw_icon
        lda #<str_switchoff
        sta q3
        lda #>str_switchoff
        sta q3+1
        clc
        lda wc_x1
        adc #42
        sta wr_x
        lda wc_x1+1
        adc #0
        sta wr_x+1
        lda wc_y1
        clc
        adc #6
        sta wr_y
        lda #160
        sta wr_w
        lda #11
        sta wr_lh
        lda #0
        sta font
        lda #B_OR
        sta tmode
        jsr wrap_draw
        ldx #0
        jsr draw_button
        ldx #0
        jsr dlg_btn_rect
        lda #3
        jsr rect_outset
        jsr frame_round
        lda #1
        jsr rect_inset
        jmp frame_round
