; =====================================================================
; public.asm - the System's public data
;
; This block sits at a fixed address right after the jump table, so
; applications can use it without being rebuilt when the System changes.
; New entries go at the end; nothing here may move or change size.
; tools/mkapi.py publishes every label in this file in build/sysapi.asm.
; =====================================================================

MAXWIN    = 8           ; windows
NUM_MENUS = 5           ; the C= menu and four application menus

sys_version: !byte 1    ; API version

; --- events --------------------------------------------------------
pending_action: !byte ACT_NONE  ; menu action the event loop runs next
key_char:   !byte 0     ; the key for M_KEY and the app's key entry;
                        ; the EDIT_ command for M_EDIT
cur_action: !byte 0     ; the menu action being run
dbl_click:  !byte 0     ; 1 when the last mouse down was a double click
win_part_hit: !byte 0   ; scroll bar part (P_UP ...) for M_SCROLL

; --- settings ------------------------------------------------------
dbl_time:   !byte 24    ; double-click time, frames
caret_blink: !byte 30   ; insertion point blink, frames
menu_blinks: !byte 3    ; times a chosen menu item flashes
beep_vol:   !byte 5     ; 0..7
desk_pat:   !byte $aa,$55,$aa,$55,$aa,$55,$aa,$55

; --- kept by the System while applications come and go ----------------
sys_pram:   !fill 16

; --- the Clipboard: clip_len bytes of text at clip_buf ----------------
clip_len:   !byte 0
clip_buf = $0500

; --- a document for the application being started ---------------------
; The Finder puts the path of a document opened with an application
; here ("0:Folder/Name.bas", 0 = none); the application takes it.
app_doc = $0700

; --- BASIC's zero page ------------------------------------------------
; The System's zero page and BASIC's overlap: this is BASIC's ($02-$ff)
; while the System's is in use (fp_begin swaps them)
basic_zp = $0400

; --- spare memory for applications ------------------------------------
; The Interface overlay ($4000) stays below app_spare: the rest of its
; region is free for an application's data (768 bytes, not loaded with
; it).  An application that never calls the Shapes overlay's routines
; (plot, lines, ovals ...) may also use their region, $5000-$5fff (the
; System forgets the overlay when an application loads), and the oval
; table at $c700-$c7ff.
app_spare = $4d00

; --- utoa's result -------------------------------------------------
numbuf:     !fill 8

; --- windows: each array has one entry per window id ----------------
w_used:  !fill MAXWIN
w_x1l:   !fill MAXWIN   ; frame rect (x 16 bit, y 8 bit)
w_x1h:   !fill MAXWIN
w_y1:    !fill MAXWIN
w_x2l:   !fill MAXWIN
w_x2h:   !fill MAXWIN
w_y2:    !fill MAXWIN
w_flags: !fill MAXWIN   ; WF_
w_class: !fill MAXWIN   ; CL_
w_data:  !fill MAXWIN   ; free for the window's owner
w_titl:  !fill MAXWIN   ; title string (0 = none)
w_tith:  !fill MAXWIN
w_zx1l:  !fill MAXWIN   ; saved rect for the zoom box
w_zx1h:  !fill MAXWIN
w_zy1:   !fill MAXWIN
w_zx2l:  !fill MAXWIN
w_zx2h:  !fill MAXWIN
w_zy2:   !fill MAXWIN
w_zoomed: !fill MAXWIN
w_scroll: !fill MAXWIN  ; vertical scroll offset in pixels
w_maxscr: !fill MAXWIN  ; largest vertical offset (0 = no scrolling)
w_hscroll: !fill MAXWIN ; the same sideways
w_hmax:   !fill MAXWIN
W_H = w_hscroll - w_scroll      ; w_scroll,x+W_H = w_hscroll,x etc.
!if w_hmax - w_maxscr != W_H { !error "w_hmax" }
w_view:   !fill MAXWIN  ; free for the window's owner (the Finder's view)

zlist:   !fill MAXWIN   ; window ids, front first
zcount:  !byte 0

cur_win: !byte 0        ; window whose method is running
wc_x1:   !word 0        ; its content rect
wc_y1:   !byte 0
wc_x2:   !word 0
wc_y2:   !byte 0

; --- zoom_to_rect's small rect (an icon) -----------------------------
zr_on:   !byte 0        ; 0 = no zoom
zr_x1:   !word 0
zr_y1:   !byte 0
zr_x2:   !word 0
zr_y2:   !byte 0

; --- dialogs (dlg_open, alerts) --------------------------------------
DLG_ALERT    = 0        ; dlg_kind
DLG_CUSTOM   = 1        ; drawn by dlg_custom (applications)
DLG_SHUTDOWN = 2
dlg_kind:  !byte 0      ; DLG_
dlg_msg:   !word 0
dlg_icon:  !word 0
dlg_nbtn:  !byte 1
dlg_btn:   !word str_ok, str_cancel     ; button 0 = default (rightmost)
dlg_win:   !byte 0
dlg_result: !byte 0
dlg_custom: !word 0     ; draw routine for DLG_CUSTOM
dlg_x2h:   !byte 1      ; dlg_open: high byte of x2
dlg_h:     !byte 80     ; dlg_open: height

; --- wrap_draw's parameters and result -------------------------------
wr_x:    !word 0        ; top left
wr_y:    !byte 0
wr_w:    !byte 0        ; width
wr_lh:   !byte 0        ; line height
wr_cx:   !word 0        ; result: just after the last character
wr_cy:   !byte 0
wr_draw: !byte 1        ; 0 = only measure

; --- menus ---------------------------------------------------------
menu_flags: !fill NUM_MENUS*16  ; MF_ flags, 16 per menu

; --- QuickDraw tables ----------------------------------------------
lmask_tab: !byte $ff,$7f,$3f,$1f,$0f,$07,$03,$01
rmask_tab: !byte $80,$c0,$e0,$f0,$f8,$fc,$fe,$ff
bit_tab:   !byte $80,$40,$20,$10,$08,$04,$02,$01
pat_black: !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
pat_white: !byte $00,$00,$00,$00,$00,$00,$00,$00
pat_gray:  !byte $aa,$55,$aa,$55,$aa,$55,$aa,$55
pat_ltgray: !byte $88,$22,$88,$22,$88,$22,$88,$22
pat_even:  !byte $ff,$00,$ff,$00,$ff,$00,$ff,$00
pat_odd:   !byte $00,$ff,$00,$ff,$00,$ff,$00,$ff
!source "build/patterns.asm"

; --- the pen (move_to, line_to) ----------------------------------------
pn_x:      !word 0
pn_y:      !byte 0

; --- the file calls (fs_*): parameters and results --------------------
fs_off:    !fill 4      ; position in the file
fs_len:    !word 0      ; bytes to read
fs_mode:   !byte 0      ; fs_write: FSW_REPLACE, FSW_AT or FSW_APPEND
fs_first:  !word 0      ; fs_list: first entry
fs_max:    !byte 0      ; fs_list: most entries
fs_rptr:   !word 0      ; where results go
fs_rmax:   !word 0      ; room there (more is dropped)
fs_rlen:   !word 0      ; result: bytes received
fs_dptr:   !word 0      ; fs_write: the data
fs_dlen:   !word 0      ; fs_write: its length
fs_status: !byte 0      ; result: status of the last call

public_end:
