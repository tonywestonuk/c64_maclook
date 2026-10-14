; =====================================================================
; boot.asm - start-up, loading the Finder, restart and shut down
; =====================================================================

str_finder_file: !text "System Folder/Finder.sys"
FINDER_NAME_LEN = * - str_finder_file

!zone boot
boot:
        lda #0
        sta app_loaded
        jsr clip_screen         ; a grey screen (also behind any trouble
        +rect 0, 0, 319, 199    ;   loading the Interface overlay)
        jsr set_gray
        jsr fill_rect
        jsr boot_screen         ; happy C64 and welcome (Interface overlay)
        lda #<str_finder_file
        ldy #>str_finder_file
        ldx #FINDER_NAME_LEN
        jsr load_app
start_app:                      ; hand over to the loaded application
        jsr APP_INIT
        jsr install_app_menus
        jsr menu_init
        jmp redraw_all

; load_app: A/Y = path on the share, X = length.  Loads an application
; to APP_BASE; if that fails, says so and falls back to the Finder.
APP_NAME_MAX = 100
app_name: !fill APP_NAME_MAX+1
app_namelen: !byte 0
!zone load_app
load_app:
        sta q0
        sty q0+1
        cpx #APP_NAME_MAX
        bcc +
        ldx #APP_NAME_MAX
+       stx app_namelen
        ldy #0                  ; the name may live in the old application
-       cpy app_namelen
        beq +
        lda (q0),y
        sta app_name,y
        iny
        bne -
+       lda #0
        sta app_name,y
        lda #0
        sta app_loaded
        lda #CUR_WATCH
        jsr set_cursor
.try:   lda #<app_name
        sta q0
        lda #>app_name
        sta q0+1
        jsr fs_load
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
        lda #0
        sta app_name,x
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
        jsr ovl_reset           ; (and no overlay is running)
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
        jsr ovl_reset
        lda #ACT_NONE
        sta pending_action
        jsr boot
        jmp main_loop

