; =====================================================================
; POLYHEDRON - a solid turned in 3D, and drawn, by the WiC64.
;
; The solid lives on the WiC64 (docs/npu.md).  At the start the C64
; sends a script for a frame, which the WiC64 keeps; when a solid is
; chosen, its corners, its faces' normals, the faces' distances from the
; centre and its edges.  Each frame it then sends just "RUN 0" (with the
; window's place on the screen when that has changed, and the speeds or
; Hide Back Edges when they have), and the WiC64's ESP32 runs the
; script: it moves the angles on by the time since the last frame, turns
; the corners about three axes, puts them in perspective, works out
; which faces point at the eye, draws the edges (those of the faces in
; front, unless the back ones are shown) on its copy of the screen, and
; sends back the bytes that changed.  They come in a burst (npu_draw),
; straight into the bitmap: the C64 draws nothing.  The solids are made
; by tools/solids.py.
; =====================================================================
!cpu 6510
!to "build/polyhedron.prg", cbm
!source "build/sysapi.asm"
!source "src/macros.asm"

* = APP_BASE
        jmp ph_init             ; entry points, see events.asm
        jmp ph_action
        jmp ph_update_menus
        jmp nop_method          ; nothing on the desktop
        jmp nop_method
        jmp nop_method
        jmp ph_quit
        !word ph_classes
        !word ph_menus
        !word str_ph_about
        !text "APP!"

CL_POLYHEDRON = CL_APPBASE+0

PA_ABOUT  = 0           ; menu actions
PA_QUIT   = 1
PA_HIDE   = 2
PA_SOLID  = 3           ; + solid
PA_SPEED  = 10          ; + speed

SPEEDS    = 4           ; slow, medium, fast, stopped
STOPPED   = 3

CW        = 256         ; the content
CH        = 164
CX        = 128         ; the centre, in the content
CY        = 82
DIST      = 400         ; the eye's distance (as in tools/solids.py)

ph_classes:             ; draw, click, key, idle, close, edit, resize, scroll
        !word ph_draw, nop_method, ph_key, ph_idle, ph_close, nop_method, nop_method, nop_method

ph_win:     !byte 0
ph_quitting: !byte 0
ph_solid:   !byte 4     ; the icosahedron
ph_hide:    !byte 1     ; 1 = only the edges of the faces in front
ph_speed:   !byte 1
ph_go_speed: !byte 1    ; the speed to go on at after a stop
ph_started: !byte 0     ; the script is on the WiC64
ph_ready:   !byte 0     ; the solid is
ph_placed:  !byte 0     ; it knows where the window is, and what it shows
ph_sent_speed: !byte $ff        ; the speed it has ($ff: none yet)
ph_sent_hide: !byte $ff         ; Hide Back Edges, as it has it
ph_dirty:   !byte 1     ; draw a frame even when stopped
ph_last:    !byte 0     ; jiffy of the last frame
ph_frames:  !word 0     ; frames drawn (for measuring)

; per speed, the turns about z, x and y, in radians a second (8.8)
ph_speeds:  !word 154, 115, 77          ; slow: 0.6, 0.45, 0.3
            !word 358, 269, 179         ; medium: 1.4, 1.05, 0.7
            !word 819, 614, 410         ; fast: 3.2, 2.4, 1.6
            !word 0, 0, 0               ; stopped

ph_init:
        lda #0
        sta ph_quitting
        sta ph_started
        sta ph_ready
        sta ph_placed
        lda #$ff
        sta ph_sent_speed
        sta ph_sent_hide
        lda #1
        sta ph_dirty
        jsr win_alloc
        stx ph_win
        +winrect 31, 20, 288, 196       ; content 256 x 164
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_POLYHEDRON
        sta w_class,x
        jsr ph_title
        lda #1
        sta w_used,x
        jmp z_front

ph_quit:
        lda #1
        sta ph_quitting
        rts

; the close box quits
ph_close:
        lda ph_quitting
        bne +
        lda #PA_QUIT
        sta pending_action
+       rts

; the window's title: the solid's name (X = the window)
ph_title:
        ldy ph_solid
        lda sd_name_lo,y
        sta w_titl,x
        lda sd_name_hi,y
        sta w_tith,x
        rts

; ---------------------------------------------------------------------
; Menus and keys
; ---------------------------------------------------------------------
!zone ph_action
ph_action:
        cmp #PA_ABOUT
        bne +
        jmp ph_about
+       cmp #PA_QUIT
        bne +
        jmp quit_app
+       cmp #PA_HIDE
        bne +
        lda ph_hide
        eor #1
        sta ph_hide
        jmp .dirty
+       cmp #PA_SPEED
        bcs .speed
        sec                     ; a solid
        sbc #PA_SOLID
        cmp ph_solid
        beq .done
        sta ph_solid
        lda #0
        sta ph_ready
        ldx ph_win
        jsr ph_title
        jsr win_draw_frame
        jmp .dirty
.speed: sbc #PA_SPEED
        sta ph_speed
        cmp #STOPPED
        beq .dirty
        sta ph_go_speed
.dirty: lda #1
        sta ph_dirty
.done:  rts

; keys: the cursor keys for the next or previous solid, H hides or shows
; the back edges, space stops and goes
!zone ph_key
ph_key:
        lda key_char
        cmp #K_DOWN
        beq .next
        cmp #K_RIGHT
        beq .next
        cmp #K_UP
        beq .prev
        cmp #K_LEFT
        beq .prev
        cmp #'h'
        bne +
        lda #PA_HIDE
        jmp ph_action
+       cmp #' '
        bne .no
        lda ph_speed
        cmp #STOPPED
        bne +
        lda ph_go_speed
        jmp ++
+       lda #STOPPED
++      clc
        adc #PA_SPEED
        jmp ph_action
.next:  ldx ph_solid
        inx
        cpx #SOLIDS
        bcc .go
        ldx #0
        beq .go
.prev:  ldx ph_solid
        dex
        bpl .go
        ldx #SOLIDS-1
.go:    txa
        clc
        adc #PA_SOLID
        jmp ph_action
.no:    rts

ph_update_menus:
        ldx #0                  ; Edit: nothing to edit
-       txa
        pha
        ora #32
        tax
        jsr menu_disable
        pla
        tax
        inx
        cpx #6
        bne -
        ldx #SOLIDS-1           ; Solid: tick the solid
-       lda menu_flags+48,x
        and #$ff-MF_CHECKED
        cpx ph_solid
        bne +
        ora #MF_CHECKED
+       sta menu_flags+48,x
        dex
        bpl -
        lda menu_flags+48+SOLIDS+1      ; and Hide Back Edges
        and #$ff-MF_CHECKED
        ldx ph_hide
        beq +
        ora #MF_CHECKED
+       sta menu_flags+48+SOLIDS+1
        ldx #SPEEDS-1           ; Speed: tick the speed
-       lda menu_flags+64,x
        and #$ff-MF_CHECKED
        cpx ph_speed
        bne +
        ora #MF_CHECKED
+       sta menu_flags+64,x
        dex
        bpl -
        rts

; ---------------------------------------------------------------------
; About Polyhedron
; ---------------------------------------------------------------------
ph_about:
        lda #DLG_CUSTOM
        sta dlg_kind
        lda #<ph_about_draw
        sta dlg_custom
        lda #>ph_about_draw
        sta dlg_custom+1
        lda #92
        sta dlg_h
        lda #0
        sta dlg_x2h
        lda #40
        ldx #40
        ldy #248
        jsr dlg_open
        bcs +
        jsr wait_click_or_key
        jmp dlg_close
+       rts

ph_about_draw:
        lda #0
        sta font
        lda #<str_ph_name
        ldy #>str_ph_name
        ldx #6
        jsr draw_centred_at
        lda #1
        sta font
        lda #<str_ph_info1
        ldy #>str_ph_info1
        ldx #26
        jsr draw_centred_at
        lda #<str_ph_info2
        ldy #>str_ph_info2
        ldx #36
        jsr draw_centred_at
        lda #<str_ph_info3
        ldy #>str_ph_info3
        ldx #46
        jsr draw_centred_at
        lda #<str_ph_info4
        ldy #>str_ph_info4
        ldx #56
        jsr draw_centred_at
        lda #<str_ph_info5
        ldy #>str_ph_info5
        ldx #72
        jmp draw_centred_at

; ---------------------------------------------------------------------
; M_DRAW: the System has just made the content white (the window was
; opened, moved or uncovered): the next frame tells the WiC64 where the
; window is and that it's white, and it sends the whole solid again
; ---------------------------------------------------------------------
ph_draw:
        lda #0
        sta ph_placed
        lda #1
        sta ph_dirty
        rts

; ---------------------------------------------------------------------
; M_IDLE: a frame, at most one a jiffy, while the window is in front
; ---------------------------------------------------------------------
!zone ph_idle
ph_idle:
        cpx zlist
        bne .rts
        lda jiffy
        cmp ph_last
        beq .rts
        lda ph_speed
        cmp #STOPPED
        bne .go
        lda ph_dirty
        beq .rts
.go:    lda jiffy
        sta ph_last
        lda #0
        sta ph_dirty
        jsr ph_prepare          ; the script and the solid
        bcs .fail
        jsr ph_frame
        bcs .fail
        inc ph_frames
        bne .rts
        inc ph_frames+1
.rts:   rts
.fail:  jmp ph_failed

; ---------------------------------------------------------------------
; Talking to the matrix unit
; ---------------------------------------------------------------------
; whatever the WiC64 doesn't have yet: the script (with the centre and
; the starting angles), the solid (corners, normals, distances, edges).
; Carry set on an error, A = the status.
!zone ph_prepare
ph_prepare:
        lda ph_started
        bne +
        lda #>(ph_start_end-ph_start_prog)
        sta fs_dlen+1
        lda #<ph_start_prog
        ldx #>ph_start_prog
        ldy #<(ph_start_end-ph_start_prog)
        jsr ph_run
        bcs .rts
        lda #1
        sta ph_started
+       lda ph_ready
        bne .ok
        ldy ph_solid
        lda sd_len_hi,y
        sta fs_dlen+1
        lda sd_len_lo,y
        sta t0
        lda sd_prog_lo,y
        ldx sd_prog_hi,y
        ldy t0
        jsr ph_run
        bcs .rts
        lda #1
        sta ph_ready
.ok:    clc
.rts:   rts

; run the program at A/X, Y + 256 * fs_dlen+1 bytes; no results
ph_run:
        sta fs_dptr
        stx fs_dptr+1
        sty fs_dlen
        lda #0
        sta fs_rmax
        sta fs_rmax+1
        jmp npu_run

; a frame: the request is what has changed, then RUN 0; the changes to
; the screen come back in a burst, into the bitmap
!zone ph_frame
ph_frame:
        lda ph_placed           ; SCREEN: where the content is (it's white)
        bne .placed
        ldx ph_win
        jsr win_get_content     ; (wc_*)
        ldy #0
        ldx #0
-       lda ph_screen_prog,x
        sta ph_req,y
        iny
        inx
        cpx #9
        bne -
        lda wc_x1
        sta ph_req-8,y
        lda wc_x1+1
        sta ph_req-7,y
        lda wc_y1
        sta ph_req-6,y
        jmp .hide
.placed:
        ldy #0
.hide:  lda ph_hide             ; Hide Back Edges: LOAD 20, 0 to hide, else 1
        cmp ph_sent_hide
        beq +
        ldx #0
-       lda ph_wire_prog,x
        sta ph_req,y
        iny
        inx
        cpx #6
        bne -
        lda ph_hide
        eor #1
        sta ph_req-1,y
+       lda ph_speed            ; the speeds: LOAD 14
        cmp ph_sent_speed
        beq +
        ldx #0
-       lda ph_speed_prog,x     ; the instruction ..
        sta ph_req,y
        iny
        inx
        cpx #5
        bne -
        lda ph_speed            ; .. and the 6 bytes for this speed
        sta t0
        asl
        adc t0
        asl
        tax
        lda #6
        sta t1
-       lda ph_speeds,x
        sta ph_req,y
        iny
        inx
        dec t1
        bne -
+       lda #NPU_RUN            ; and the frame
        sta ph_req,y
        iny
        lda #0
        sta ph_req,y
        iny
        sty fs_dlen
        lda #0
        sta fs_dlen+1
        lda #<ph_req
        sta fs_dptr
        lda #>ph_req
        sta fs_dptr+1
        jsr npu_draw
        bcs .rts
        lda #1                  ; the WiC64 has it all now
        sta ph_placed
        lda ph_hide
        sta ph_sent_hide
        lda ph_speed
        sta ph_sent_speed
        clc
.rts:   rts

; something went wrong: start again from the beginning, and say what
; went wrong unless it was just a burst that made no sense
!zone ph_failed
ph_failed:
        ldx #0
        stx ph_started
        stx ph_ready
        ldx #$ff
        stx ph_sent_speed
        stx ph_sent_hide
        cmp #FS_IOERR
        bne +
        ldx ph_win              ; (the window white again: everything anew)
        jmp win_refresh
+       cmp #FS_NOWIC64
        bne +
        lda #<str_ph_nowic64
        ldy #>str_ph_nowic64
        jsr alert_stop
        lda #PA_QUIT
        sta pending_action
        rts
+       lda #<ph_msg            ; the WiC64's message ($2A)
        sta fs_rptr
        lda #>ph_msg
        sta fs_rptr+1
        lda #MSG_MAX
        sta fs_rmax
        lda #0
        sta fs_rmax+1
        sta fs_dlen
        sta fs_dlen+1
        sta ph_msg
        lda #$2a
        jsr wic_request
        ldx fs_rlen
        lda #0
        sta ph_msg,x
        lda #<ph_msg
        ldy #>ph_msg
        jsr alert_stop          ; (closing it redraws the window: everything anew)
        lda #STOPPED
        sta ph_speed
        rts

; ---------------------------------------------------------------------
; The programs (docs/npu.md)
; ---------------------------------------------------------------------
; At the start: the centre, (0 0 1) to pick out z, the starting angles,
; no speeds yet, Hide Back Edges, and the script for a frame
ph_start_prog:
        !byte NPU_LOAD, 3, 2, 1, NPU_S16        ; 3: the centre
        !word CX, CY
        !byte NPU_LOAD, 12, 1, 3, NPU_S8        ; 12: (0 0 1), for the z row
        !byte 0, 0, 1
        !byte NPU_LOAD, 17, 1, 3, NPU_S16+8     ; 17: the angles (radians)
        !word 0, 154, 51                        ; (0, 0.6, 0.2)
        !byte NPU_LOAD, 14, 1, 3, NPU_S16+8     ; 14: the speeds
        !word 0, 0, 0
        !byte NPU_LOAD, 20, 1, 1, NPU_U8, 0     ; 20: 1 to show the back edges
        !byte NPU_DEFINE, 0, <(ph_script_end-ph_script), >(ph_script_end-ph_script)
; script 0, a frame: kept and run by the WiC64
ph_script:
        !byte NPU_CLOCK, 15                     ; 15: seconds since the last frame
        !byte NPU_EMUL, 16, 14, 15              ; the angles move on by
        !byte NPU_ADD, 17, 17, 16               ; the speeds (14) x the time
        !byte NPU_TURN, 1, NPU_Z, 17, 0         ; turn about z, then x, then y
        !byte NPU_TURN, 8, NPU_X, 17, 1
        !byte NPU_TURN, 9, NPU_Y, 17, 2
        !byte NPU_MUL, 10, 8, 1
        !byte NPU_MUL, 10, 9, 10                ; 10: the whole turn
        !byte NPU_MUL, 2, 10, 0                 ; 2: the corners turned (3 x v)
        !byte NPU_PROJECT, 2, 2                 ; .. seen in perspective (2 x v)
        !32 DIST * 65536
        !byte NPU_ADD, 2, 2, 3                  ; .. in the middle of the window
        !byte NPU_MUL, 11, 12, 10               ; 11: the normals' z, turned (1 x f)
        !byte NPU_MUL, 11, 11, 4
        !byte NPU_ADD, 11, 11, 13               ; + distance / DIST: negative faces us
        !byte NPU_APPLY, 11, 11, NPU_NEG
        !byte NPU_APPLY, 11, 11, NPU_STEP       ; 1 for the faces in front
        !byte NPU_PICK, 18, 11, 5, 2            ; 18: for each edge, the faces
        !byte NPU_PICK, 19, 11, 5, 3            ; in front either side of it ..
        !byte NPU_ADD, 18, 18, 19
        !byte NPU_ADD, 18, 18, 20               ; .. (+ 1 to show them all)
        !byte NPU_CLEAR                         ; draw them
        !byte NPU_LINES, 2, 5, 18
        !byte NPU_SEND                          ; -> what changed on the screen
ph_script_end:
ph_start_end:

; the parts of a frame's request
ph_screen_prog:                                 ; SCREEN: the content (x, y patched)
        !byte NPU_SCREEN
        !word 0, 0, CW, CH
ph_wire_prog:                                   ; Hide Back Edges (the value patched)
        !byte NPU_LOAD, 20, 1, 1, NPU_U8, 0
ph_speed_prog:                                  ; the speeds (then 6 bytes)
        !byte NPU_LOAD, 14, 1, 3, NPU_S16+8

; ---------------------------------------------------------------------
; Menus and text
; ---------------------------------------------------------------------
ph_menus:
        !word str_ph_file, str_ph_edit, str_ph_solid, str_ph_speed
        !word ph_items_file, ph_items_edit, ph_items_solid, ph_items_speed
ph_items_file:
        !byte 1
        +item str_ph_quit, 'Q', PA_QUIT
ph_items_edit:
        !byte 6
        +item str_ph_undo, 'Z', ACT_NONE
        +sep
        +item str_ph_cut, 'X', ACT_NONE
        +item str_ph_copy, 'C', ACT_NONE
        +item str_ph_paste, 'V', ACT_NONE
        +item str_ph_clear, 0, ACT_NONE
ph_items_solid:
        !byte SOLIDS+2
        +item str_sd_0, '1', PA_SOLID+0
        +item str_sd_1, '2', PA_SOLID+1
        +item str_sd_2, '3', PA_SOLID+2
        +item str_sd_3, '4', PA_SOLID+3
        +item str_sd_4, '5', PA_SOLID+4
        +item str_sd_5, '6', PA_SOLID+5
        +sep
        +item str_ph_hide, 'H', PA_HIDE
ph_items_speed:
        !byte SPEEDS
        +item str_ph_slow, 'S', PA_SPEED+0
        +item str_ph_medium, 'M', PA_SPEED+1
        +item str_ph_fast, 'F', PA_SPEED+2
        +item str_ph_stop, '.', PA_SPEED+3

str_ph_about:   !text "About Polyhedron", $13, 0
str_ph_name:    !text "Polyhedron", 0
str_ph_info1:   !text "The WiC64 keeps the solid and a script.", 0
str_ph_info2:   !text "Each frame the C64 sends RUN 0: the ESP32", 0
str_ph_info3:   !text "turns the solid, draws it, and sends back", 0
str_ph_info4:   !text "what changed, straight into the screen.", 0
str_ph_info5:   !text "Click to continue.", 0
str_ph_nowic64: !text "Polyhedron needs a WiC64: it turns|and draws the solid.", 0
str_ph_file:    !text "File", 0
str_ph_edit:    !text "Edit", 0
str_ph_solid:   !text "Solid", 0
str_ph_speed:   !text "Speed", 0
str_ph_quit:    !text "Quit", 0
str_ph_undo:    !text "Undo", 0
str_ph_cut:     !text "Cut", 0
str_ph_copy:    !text "Copy", 0
str_ph_paste:   !text "Paste", 0
str_ph_clear:   !text "Clear", 0
str_ph_hide:    !text "Hide Back Edges", 0
str_ph_slow:    !text "Slow", 0
str_ph_medium:  !text "Medium", 0
str_ph_fast:    !text "Fast", 0
str_ph_stop:    !text "Stopped", 0

!source "build/solids.asm"

MSG_MAX = 79
ph_req:         !fill 32        ; a frame's request
ph_msg:         !fill MSG_MAX+1

ph_end:
!if ph_end > PAGE_BASE {
        !error "POLYHEDRON is bigger than its 8K block"
}
