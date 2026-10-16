; =====================================================================
; jumptab.asm - the System's jump table, at JUMP_TABLE ($0810)
;
; Applications call the System only through these entries (jsr name),
; so a new System runs old applications.  Each entry is 3 bytes; their
; order is fixed.  New entries go at the end, into the reserved space.
; Parameters are passed in A, X, Y and the zero page registers listed
; in build/sysapi.asm (rx1..ry2 for rectangles, tx/ty/tstr for text,
; and so on).  tools/mkapi.py turns this file into build/sysapi.asm and
; docs/api.md, using the comment after each entry.
; =====================================================================
JUMP_TABLE = *
JT_SLOTS   = 128

; --- QuickDraw: rectangles and patterns
        jmp fill_rect           ; fill rx1..ry2 with the pattern set by set_pat_copy
        jmp fill_black          ; fill rx1..ry2 black
        jmp fill_white          ; fill rx1..ry2 white
        jmp invert_rect         ; invert rx1..ry2
        jmp frame_rect          ; 1 pixel frame around the inside of rx1..ry2
        jmp frame_round         ; black frame of rx1..ry2 with rounded corners
        jmp set_black           ; pattern black
        jmp set_white           ; pattern white
        jmp set_gray            ; pattern 50% grey
        jmp set_pat_copy        ; A/Y = 8 byte pattern, copy mode
        jmp rect_inset          ; A = pixels: shrink rx1..ry2 on all sides
        jmp rect_outset         ; A = pixels: grow rx1..ry2 on all sides
        jmp rect_visible        ; carry clear if rx1..ry2 meets the clip rect
        jmp content_rect        ; rect from content-relative A,X .. Y,t7 (uses wc_*)
; --- QuickDraw: clipping
        jmp clip_push           ; save the clip rect (preserves X, Y)
        jmp clip_pop            ; restore it (preserves X, Y)
        jmp clip_rect           ; clip rect = clip rect AND rx1..ry2; carry set if empty
        jmp clip_screen         ; clip rect = the whole screen
; --- QuickDraw: text and icons
        jmp draw_text           ; string tstr at tx,ty in font, mode tmode; sets twidth
        jmp draw_str            ; A/Y = string, otherwise as draw_text
        jmp text_width          ; twidth = width of tstr in font
        jmp draw_centred_at     ; A/Y = string, X = y in the content: centred across it
        jmp draw_icon           ; icon iptr at tx,ty, iflags = ICON_
        jmp wrap_draw           ; text q3 word wrapped at wr_x,wr_y, wr_w wide ('|' = new line); moves q3
; --- the pointer
        jmp hide_cursor         ; hide the pointer
        jmp show_cursor         ; show it again
        jmp set_cursor          ; A = CUR_ shape
; --- windows
        jmp win_alloc           ; X = free window id; carry set if none
        jmp win_open            ; X = window: add in front and draw
        jmp win_close           ; X = window: call M_CLOSE, remove, repaint behind
        jmp win_select          ; X = window: bring to the front
        jmp win_call            ; X = window, A = M_ method: call it with wc_* set
        jmp win_draw_frame      ; X = window: draw its frame and scroll bars
        jmp win_draw_content    ; X = window: call its M_DRAW, clipped
        jmp win_get_rect        ; X = window -> rx1..ry2 = frame rect
        jmp win_get_full        ; X = window -> rx1..ry2 with the shadow
        jmp win_get_content     ; X = window -> rx1..ry2 and wc_* = content rect
        jmp win_at_mouse        ; X = window under the pointer ($ff = desktop)
        jmp win_refresh         ; X = window: redraw its content, under any overlaps
        jmp win_set_rect        ; X = front window, rn_* = new rect
        jmp win_track           ; X = window, A = 0 vertical bar, else horizontal -> track rect
        jmp front_win           ; X = front window ($ff, Z set, if none)
        jmp z_front             ; X = window: move to the front of the list only
        jmp close_win           ; X = window: close unless it is a dialog
        jmp redraw_region       ; repaint desktop and windows inside rx1..ry2
        jmp mouse_in_rect       ; carry clear if the pointer is inside rx1..ry2
        jmp zoom_to_rect        ; zoom from zr_* out to rx1..ry2
; --- menus
        jmp menu_enable         ; X = menu*16 + item
        jmp menu_disable        ; X = menu*16 + item
        jmp menu_set            ; X = menu*16 + item, A = 0 disable, else enable
; --- alerts and dialogs
        jmp alert_note          ; A/Y = message ('|' = new line), OK button
        jmp alert_stop          ; A/Y = message, stop sign
        jmp dlg_open            ; open a dialog window (see dialog.asm)
        jmp dlg_close           ; close it
        jmp too_many_windows    ; the "too many windows" alert
; --- events and time
        jmp wait_frame          ; wait for the next frame
        jmp wait_frames         ; A = frames
        jmp wait_release        ; wait until the mouse button is up
        jmp wait_click_or_key   ; wait for a click or a key: A = the key (0: a click)
        jmp key_pending         ; A = 0 (Z set) if no key is waiting
        jmp beep                ; the System beep
        jmp random              ; A = random byte
; --- applications
        jmp launch_app          ; A/Y = file name, X = its length: replace this app
        jmp quit_app            ; back to the Finder
        jmp restart             ; restart
        jmp shut_down           ; shut down
; --- utilities
        jmp strcpy              ; copy string q0 to q1 (Y = length)
        jmp strcat              ; append string q0 to q1
        jmp strlen              ; A/Y = string -> A = length
        jmp utoa                ; A/X = number -> numbuf (A/Y = numbuf)
        jmp mul8                ; A * X -> A = low, X = high
        jmp fp_begin            ; before using the BASIC ROM's floating point
        jmp fp_end              ; after it
        jmp nop_method          ; does nothing (for unused window methods)
; --- QuickDraw: lines, ovals and the pen
        jmp set_mode            ; A = M_COPY, M_OR, M_XOR or M_BIC, after setting the pattern
        jmp plot                ; one pixel at A/X = x, Y = y
        jmp move_to             ; pen to A/X = x, Y = y
        jmp line_to             ; line from the pen to A/X = x, Y = y; the pen moves there
        jmp draw_line           ; line from rx1,ry1 to rx2,ry2
        jmp frame_oval          ; outline of the oval inside rx1..ry2
        jmp fill_oval           ; the oval inside rx1..ry2, filled
        jmp frame_circle        ; outline of a circle: centre rx1,ry1, radius A (to 127)
        jmp fill_circle         ; filled circle: centre rx1,ry1, radius A
        jmp frame_rrect         ; outline of rx1..ry2 with corners of radius A
        jmp fill_rrect          ; rx1..ry2 with corners of radius A, filled
; --- files on the network share (docs/fileservice.md); carry set on error, A = status
        jmp fs_info             ; A = volume: total KB, free KB and its name to (fs_rptr)
        jmp fs_list             ; folder q0: entries from fs_first, at most fs_max, to (fs_rptr)
        jmp fs_read             ; fs_len bytes at fs_off of file q0 to (fs_rptr)
        jmp fs_load             ; program file q0 to the address in its first two bytes
        jmp fs_write            ; fs_dlen bytes from (fs_dptr) to file q0, mode fs_mode
        jmp fs_delete           ; delete file or empty folder q0
        jmp fs_rename           ; rename or move q0 to q1
        jmp fs_copy             ; copy file q0 to q1
        jmp fs_mkdir            ; new folder q0
        jmp fs_stat             ; kind (1), size (4) and date (2) of q0 to (fs_rptr)
        jmp fs_volumes          ; the volumes: number, kind, connected, KB, free KB, name
        jmp fs_connect          ; A = volume: connect a network share
        jmp fs_disconnect       ; A = volume: disconnect it
; --- the WiC64's matrix unit (docs/npu.md); carry set on error, A = status
        jmp npu_run             ; program at (fs_dptr), fs_dlen bytes: results to (fs_rptr), fs_rlen bytes
        jmp wic_request         ; WiC64 command A, data from (fs_dptr): response to (fs_rptr)
        jmp npu_draw            ; program at (fs_dptr), fs_dlen bytes: its screen changes (SEND) into the bitmap

!if * > JUMP_TABLE + JT_SLOTS*3 { !error "jump table full" }
        !fill JUMP_TABLE + JT_SLOTS*3 - *, $60
