; =====================================================================
; BASIC - a BASIC for the Commodore 64 desktop, after the Macintosh's
; Microsoft BASIC and QuickBASIC: a Listing window where the program is
; typed (line numbers are optional, keywords show in bold), and an
; Output window where it runs.
;
; The language is the C64's own BASIC V2, run by the BASIC ROM a slice
; at a time (basic_run.asm), so menus, windows and Stop work while a
; program runs, with statements of ours: CLS, PSET, LINE, CIRCLE, BEEP,
; and NPU for the WiC64's matrix unit (basic_npu.asm).
;
; Memory: BASIC needs more than one 8K block of code, so it starts at
; $5000, the second half of block 2.  That is the Shapes overlay's
; place, which BASIC never calls (it draws its own lines and circles);
; the System forgets the overlay when it loads an application.  The
; program and its variables, arrays and strings go after the code, up
; to $a000.
; =====================================================================
!cpu 6510
!to "build/basic.prg", cbm
!source "build/sysapi.asm"
!source "src/macros.asm"

BASIC_LOW = $5000

; the BASIC ROM, and our statements' tokens (basic_run.asm)
NEWSTT  = $a7ae         ; BASIC: the next statement
GONE    = $a7e4         ; .. this one
GONE2   = $a7e7         ; .. its token in A
CHRGET  = $0073
CHRGOT_ = $0079
ROM_ERR = $a437         ; error X
ERRTAB  = $a19e         ; the error messages
FRMNUM  = $ad8a         ; FAC = a number expression
GETBYT  = $b79e         ; X = a byte expression
CHKCOM  = $aefd
CHKOPN  = $aefa
CHKCLS  = $aef7
SNERR   = $af08
BAS_TXTPTR = $7a
BAS_CURLIN = $39

X_FIRST = $cc           ; our statements' tokens
TK_CLS    = $cc
TK_PSET   = $cd
TK_LINE   = $ce
TK_CIRCLE = $cf
TK_BEEP   = $d0
TK_NPU    = $d1
TK_XEND   = $d2         ; the hidden last line
X_LAST  = TK_XEND

OUT_ROWS = 16           ; the Output window's rows of text
OUT_COLS = 48           ; characters a row can hold, with its 0
OQ_MAX   = 128          ; PRINT's queue

; memory outside the application's file (BASIC never calls the Shapes
; overlay, so its oval table at $c700 is free too)
out_buf  = app_spare    ; the Output window's text (768 bytes)
oq_buf   = $c700        ; PRINT's queue
msg_buf  = $c780        ; an error's message (80)

; ---------------------------------------------------------------------
; Zero page: the System leaves $96-$fa alone, and so does BASIC (and
; the parts of the KERNAL it uses here)
; ---------------------------------------------------------------------
pa      = $e0           ; pointers (words)
pb      = $e2
pc      = $e4
pd      = $e6
pg      = pc            ; drawing: a byte of the bitmap
nl_out  = pc            ; NPU LOAD: where its bytes go
fl_p    = pd            ; Open: the text
fs_p    = pd            ; Save: the text
za      = $e8           ; scratch bytes
zb      = $e9
zc      = $ea
zd      = $eb

; ---------------------------------------------------------------------
; The part below APP_BASE, then the application's header there
; ---------------------------------------------------------------------
* = BASIC_LOW
!source "src/basic_npu.asm"
!source "src/basic_run.asm"
low_end:
!if low_end > APP_BASE {
        !error "BASIC's low part doesn't fit below APP_BASE"
}
        !fill APP_BASE - low_end, 0

* = APP_BASE

        jmp ba_init             ; entry points, see events.asm
        jmp ba_action
        jmp ba_update_menus
        jmp nop_method          ; nothing on the desktop
        jmp nop_method
        jmp nop_method
        jmp nop_method          ; quit
        !word ba_classes
        !word ba_menus
        !word str_ab_item
        !text "APP!"

; ---------------------------------------------------------------------
; Low memory the System doesn't use
; ---------------------------------------------------------------------
LS_BUF  = $0200         ; a line listed (keyword letters have bit 7 set)

WS_END  = $a000         ; the top of the workspace

; ---------------------------------------------------------------------
; Windows
; ---------------------------------------------------------------------
CL_LIST = CL_APPBASE+0
CL_OUT  = CL_APPBASE+1

ba_classes:             ; draw, click, key, idle, close, edit, resize, scroll
        !word ls_draw, ls_click, ls_key, ls_idle, ls_close, nop_method, nop_method, ls_scroll
        !word out_draw, out_click, out_key, out_idle, out_close, nop_method, nop_method, nop_method

; menu actions
BA_ABOUT  = 0
BA_NEW    = 1
BA_OPEN   = 2
BA_SAVE   = 3
BA_SAVEAS = 4
BA_QUIT   = 5
BA_UNDO   = 6
BA_CUT    = 7
BA_COPY   = 8
BA_PASTE  = 9
BA_CLEAR  = 10
BA_START  = 11
BA_STOP   = 12
BA_LIST   = 13
BA_OUT    = 14

ls_win:   !byte $ff     ; the Listing window ($ff: none)
out_win:  !byte $ff     ; the Output window

; ---------------------------------------------------------------------
; Start-up
; ---------------------------------------------------------------------
!zone ba_init
ba_init:
        jsr widths_init         ; the small font's widths
        jsr prog_new
        jsr doc_untitled
        ldx #0                  ; a document from the Finder?
        lda app_doc
        beq +
        jsr doc_take            ; doc_path = app_doc
        lda #0
        sta app_doc
        jsr file_load           ; (an error leaves an empty program)
+       lda #1                  ; (the System draws it after this)
        sta ls_quiet
        jsr ls_open
        jsr ed_enter
        lda #0
        sta ls_quiet
        rts

; ---------------------------------------------------------------------
; The windows
; ---------------------------------------------------------------------
!zone ls_open
ls_open:
        jsr win_alloc
        bcc +
        rts
+       stx ls_win
        +winrect 6, 16, 312, 196
        lda #WF_CLOSE|WF_VSCROLL|WF_SHADOW
        sta w_flags,x
        lda #CL_LIST
        sta w_class,x
        lda #<doc_title
        sta w_titl,x
        lda #>doc_title
        sta w_tith,x
        lda #0
        sta w_scroll,x
        sta w_maxscr,x
        lda #1
        sta w_used,x
        jsr ls_set_scroll
        ldx ls_win
        lda ls_quiet            ; (at the start: in the list, not drawn)
        beq +
        jmp z_front
+       jmp win_open

; the Output window, opened if need be and brought to the front
!zone out_front
out_front:
        ldx out_win
        cpx #$ff
        bne .sel
        jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx out_win
        +winrect 31, 20, 288, 196
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_OUT
        sta w_class,x
        lda #<str_output
        sta w_titl,x
        lda #>str_output
        sta w_tith,x
        lda #0
        sta w_scroll,x
        sta w_maxscr,x
        lda #1
        sta w_used,x
        jsr out_reset
        ldx out_win
        jmp win_open
.sel:   cpx zlist
        beq +
        jmp win_select
+       rts

; ---------------------------------------------------------------------
; Menus
; ---------------------------------------------------------------------
ba_acts:
        !word ba_about, ba_new, ba_open, ba_save, ba_saveas, ba_quit
        !word nop_method, ed_cut, ed_copy, ed_paste, ed_clear
        !word run_start, run_stop_menu, ba_show_list, ba_show_out

!zone ba_action
ba_action:
        asl
        tay
        lda ba_acts,y
        sta jvec
        lda ba_acts+1,y
        sta jvec+1
        jmp (jvec)

ba_show_list:
        ldx ls_win
        cpx #$ff
        bne +
        jsr ls_open
        jmp ed_enter
+       jmp win_select

ba_show_out:
        jmp out_front

; File > Quit, and the Listing's close box: save first?
!zone ba_quit
ba_quit:
        jsr ask_save
        bcs +
        jsr run_end
        jmp quit_app
+       rts

ba_new:
        jsr ask_save
        bcs +
        jsr run_end
        jsr prog_new
        jsr doc_untitled
        jmp ls_reset
+       rts

!zone ba_update_menus
ba_update_menus:
        ldx #32+0               ; Edit: no Undo
        jsr menu_disable
        lda run_state           ; Run: Start or Stop
        eor #1
        and #1
        ldx #48+0
        jsr menu_set
        lda run_state
        and #1
        ldx #48+1
        jmp menu_set

ba_menus:
        !word str_m_file, str_m_edit, str_m_run, str_m_windows
        !word items_file, items_edit, items_run, items_windows
items_file:
        !byte 6
        +item str_i_new, 'N', BA_NEW
        +item str_i_open, 'O', BA_OPEN
        +item str_i_save, 'S', BA_SAVE
        +item str_i_saveas, 0, BA_SAVEAS
        +sep
        +item str_i_quit, 'Q', BA_QUIT
items_edit:
        !byte 6
        +item str_i_undo, 'Z', BA_UNDO
        +sep
        +item str_i_cut, 'X', BA_CUT
        +item str_i_copy, 'C', BA_COPY
        +item str_i_paste, 'V', BA_PASTE
        +item str_i_clear, 0, BA_CLEAR
items_run:
        !byte 2
        +item str_i_start, 'R', BA_START
        +item str_i_stop, '.', BA_STOP
items_windows:
        !byte 2
        +item str_i_list, 'L', BA_LIST
        +item str_i_out, 'W', BA_OUT

; ---------------------------------------------------------------------
; About BASIC
; ---------------------------------------------------------------------
!zone ba_about
ba_about:
        lda #DLG_CUSTOM
        sta dlg_kind
        lda #<about_draw
        sta dlg_custom
        lda #>about_draw
        sta dlg_custom+1
        lda #92
        sta dlg_h
        lda #1
        sta dlg_x2h
        lda #34
        ldx #46
        ldy #<285
        jsr dlg_open
        bcs +
        jsr wait_click_or_key
        jmp dlg_close
+       rts

about_draw:
        lda #B_OR
        sta tmode
        lda #0
        sta font
        lda #<str_ab_name
        ldy #>str_ab_name
        ldx #6
        jsr draw_centred_at
        lda #1
        sta font
        lda #<str_ab1
        ldy #>str_ab1
        ldx #22
        jsr draw_centred_at
        lda #<str_ab2
        ldy #>str_ab2
        ldx #32
        jsr draw_centred_at
        lda #<str_ab3
        ldy #>str_ab3
        ldx #42
        jsr draw_centred_at
        jsr ws_free             ; "n bytes free"
        jsr utoa
        ldx #0
-       lda numbuf,x
        sta about_free,x
        beq +
        inx
        bne -
+       ldy #0
-       lda str_ab_free,y
        sta about_free,x
        beq +
        inx
        iny
        bne -
+       lda #<about_free
        ldy #>about_free
        ldx #56
        jsr draw_centred_at
        lda #<str_ab5
        ldy #>str_ab5
        ldx #74
        jmp draw_centred_at
about_free: !fill 24

!source "src/basic_edit.asm"
!source "src/basic_tok.asm"
!source "src/basic_out.asm"
!source "src/basic_file.asm"
!source "src/basic_str.asm"
wtab:    !fill 96                       ; the small font's widths

ba_end:
WS_START = ba_end
!if WS_START > $9000 {
        !error "BASIC leaves too little room for programs"
}
