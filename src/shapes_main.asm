; =====================================================================
; SHAPES - a QuickDraw demonstration for the Commodore 64 desktop.
;
; An application like Brickles: the System loads it from drive 8 to
; APP_BASE.  It draws lines, ovals, circles and round rects with the
; System's QuickDraw calls, using only the published API.
; =====================================================================
!cpu 6510
!to "build/shapes.prg", cbm
!source "build/sysapi.asm"
!source "src/macros.asm"

* = APP_BASE
        jmp sh_init             ; entry points, see events.asm
        jmp sh_action
        jmp sh_update_menus
        jmp nop_method          ; nothing on the desktop
        jmp nop_method
        jmp nop_method
        jmp sh_quit
        !word sh_classes
        !word sh_menus
        !word str_sh_about
        !text "APP!"

CL_SHAPES = CL_APPBASE+0

SA_ABOUT  = 0           ; menu actions
SA_QUIT   = 1
SA_PAGE   = 2           ; + page
SA_PEN    = 10          ; + pen
SA_INVERT = 15

PAGES     = 6
PENS      = 4

sh_classes:             ; draw, click, key, idle, close, edit, resize, scroll
        !word sh_draw, sh_click, nop_method, nop_method, sh_close, nop_method, nop_method, nop_method

sh_win:     !byte 0
sh_page:    !byte 0     ; what the window shows
sh_pen:     !byte 0     ; pattern for filled shapes
sh_xor:     !byte 0     ; 1 = filled shapes invert
sh_quitting: !byte 0

sh_init:
        lda #0
        sta sh_quitting
        jsr win_alloc
        stx sh_win
        +winrect 31, 20, 288, 196      ; content 256 wide: offsets are bytes
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_SHAPES
        sta w_class,x
        lda #<str_sh_title
        sta w_titl,x
        lda #>str_sh_title
        sta w_tith,x
        lda #1
        sta w_used,x
        jmp z_front

sh_quit:
        lda #1
        sta sh_quitting
        rts

; the close box quits
sh_close:
        lda sh_quitting
        bne +
        lda #SA_QUIT
        sta pending_action
+       rts

; a click shows the next page
sh_click:
        ldx sh_page
        inx
        cpx #PAGES
        bcc +
        ldx #0
+       txa
        clc
        adc #SA_PAGE
        ; fall through

; ---------------------------------------------------------------------
; Menus
; ---------------------------------------------------------------------
!zone sh_action
sh_action:
        cmp #SA_ABOUT
        bne +
        lda #<str_sh_info
        ldy #>str_sh_info
        jmp alert_note
+       cmp #SA_QUIT
        bne +
        jmp quit_app
+       cmp #SA_INVERT
        bne +
        lda sh_xor
        eor #1
        sta sh_xor
        jmp .redraw
+       cmp #SA_PEN
        bcc +
        sbc #SA_PEN
        sta sh_pen
        jmp .redraw
+       sec
        sbc #SA_PAGE
        sta sh_page
.redraw:
        ldx sh_win
        jmp win_refresh

sh_update_menus:
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
        ldx #PAGES-1            ; Shapes: tick the page
-       lda menu_flags+48,x
        and #$ff-MF_CHECKED
        cpx sh_page
        bne +
        ora #MF_CHECKED
+       sta menu_flags+48,x
        dex
        bpl -
        ldx #PENS-1             ; Pen: tick the pattern
-       lda menu_flags+64,x
        and #$ff-MF_CHECKED
        cpx sh_pen
        bne +
        ora #MF_CHECKED
+       sta menu_flags+64,x
        dex
        bpl -
        lda menu_flags+64+PENS+1
        and #$ff-MF_CHECKED
        ldx sh_xor
        beq +
        ora #MF_CHECKED
+       sta menu_flags+64+PENS+1
        rts

; ---------------------------------------------------------------------
; Drawing helpers.  Coordinates are relative to the content.
; ---------------------------------------------------------------------
; A, Y = content x, y -> A/X = screen x, Y = screen y
sh_pt:
        clc
        adc wc_x1
        pha
        lda wc_x1+1
        adc #0
        tax
        tya
        clc
        adc wc_y1
        tay
        pla
        rts

; rect: A,X = left, top; Y,t7 = right, bottom (content_rect)
; circle centre: A, X (and t7 unused)
sh_centre:
        ldy #0
        sty t7
        jmp content_rect

; the pen's pattern and mode for filled shapes
sh_set_pen:
        ldx sh_pen
        lda sh_pen_lo,x
        ldy sh_pen_hi,x
        jsr set_pat_copy
        lda sh_xor
        beq +
        lda #M_XOR
        jmp set_mode
+       rts
sh_pen_lo: !byte <pat_black, <pat_gray, <pat_ltgray, <(patterns+5*8)
sh_pen_hi: !byte >pat_black, >pat_gray, >pat_ltgray, >(patterns+5*8)

; ---------------------------------------------------------------------
; M_DRAW
; ---------------------------------------------------------------------
sh_draw:
        lda sh_page
        asl
        tay
        lda sh_pages,y
        sta jvec
        lda sh_pages+1,y
        sta jvec+1
        jmp (jvec)
sh_pages:
        !word sh_sampler, sh_lines, sh_ovals, sh_circles, sh_rrects, sh_random

; --- Sampler: a bit of everything ------------------------------------
sh_sampler:
        ; a fan of lines
        jsr set_black
        lda #0
        sta u0
-       jsr sh_fan_origin       ; to the top edge
        lda u0
        clc
        adc #4
        ldy #4
        jsr sh_pt
        jsr line_to
        jsr sh_fan_origin       ; and down the right
        lda #68
        ldy u0
        iny
        iny
        iny
        iny
        jsr sh_pt
        jsr line_to
        lda u0
        clc
        adc #8
        sta u0
        cmp #65
        bcc -
        ; ovals: framed, and filled grey
        lda #36
        sta t7
        lda #76
        ldx #4
        ldy #124
        jsr content_rect
        jsr set_black
        jsr frame_oval
        lda #74
        sta t7
        lda #76
        ldx #42
        ldy #124
        jsr content_rect
        jsr set_gray
        jsr fill_oval
        jsr set_black
        jsr frame_oval
        ; circles inside each other
        lda #6
        sta u0
-       lda #160
        ldx #38
        jsr sh_centre
        lda u0
        jsr frame_circle
        lda u0
        clc
        adc #6
        sta u0
        cmp #31
        bcc -
        ; two filled circles, inverting where they overlap
        jsr set_black
        lda #M_XOR
        jsr set_mode
        lda #208
        ldx #28
        jsr sh_centre
        lda #20
        jsr fill_circle
        lda #228
        ldx #48
        jsr sh_centre
        lda #20
        jsr fill_circle
        ; round rects
        lda #118
        sta t7
        lda #4
        ldx #84
        ldy #68
        jsr content_rect
        jsr set_black
        lda #8
        jsr frame_rrect
        lda #158
        sta t7
        lda #4
        ldx #124
        ldy #68
        jsr content_rect
        lda #<pat_ltgray
        ldy #>pat_ltgray
        jsr set_pat_copy
        lda #12
        jsr fill_rrect
        jsr set_black
        lda #12
        jsr frame_rrect
        ; patterned circles
        lda #0
        sta u0
-       ldx u0
        lda sh_pc_x,x
        pha
        lda sh_pc_y,x
        tax
        pla
        jsr sh_centre
        ldx u0
        lda sh_pc_lo,x
        ldy sh_pc_hi,x
        jsr set_pat_copy
        lda #14
        jsr fill_circle
        jsr set_black
        lda #14
        jsr frame_circle
        inc u0
        lda u0
        cmp #6
        bcc -
        ; a star: every second point of five
        jsr set_black
        ldx #0
        jsr sh_star_pt
        jsr move_to
        lda #0
        sta u0
-       lda u0
        clc
        adc #2
        cmp #5
        bcc +
        sbc #5
+       sta u0
        tax
        jsr sh_star_pt
        jsr line_to
        lda u0
        bne -
        rts
sh_fan_origin:
        lda #4
        ldy #70
        jsr sh_pt
        jmp move_to
sh_pc_x:  !byte 92, 124, 156, 92, 124, 156
sh_pc_y:  !byte 100, 100, 100, 138, 138, 138
sh_pc_lo: !byte <(patterns+0*8), <(patterns+2*8), <(patterns+3*8), <(patterns+5*8), <(patterns+7*8), <pat_gray
sh_pc_hi: !byte >(patterns+0*8), >(patterns+2*8), >(patterns+3*8), >(patterns+5*8), >(patterns+7*8), >pat_gray
; star point X (0..4) -> A/X/Y screen
sh_star_pt:
        lda sh_star_x,x
        ldy sh_star_y,x
        jmp sh_pt
sh_star_x: !byte 214, 246, 234, 194, 182
sh_star_y: !byte 90, 113, 151, 151, 113

; --- Lines: fans from two corners ------------------------------------------
sh_lines:
        jsr sh_set_pen
        lda #0
        sta u0
-       lda #0                  ; top left to the bottom edge
        ldy #0
        jsr sh_pt
        jsr move_to
        lda u0
        ldy #163
        jsr sh_pt
        jsr line_to
        lda #255                ; bottom right to the top edge
        ldy #163
        jsr sh_pt
        jsr move_to
        lda u0
        ldy #0
        jsr sh_pt
        jsr line_to
        lda u0
        clc
        adc #12
        sta u0
        bcc -
        rts

; --- Ovals: inside each other -------------------------------------------
sh_ovals:
        lda #0
        sta u0                  ; step
-       lda u0                  ; (12k, 8k) - (255 - 12k, 163 - 8k)
        asl
        asl
        asl
        sta u1                  ; 8k
        lda #163
        sec
        sbc u1
        sta t7
        lda u1
        lsr
        clc
        adc u1
        sta u2                  ; 12k
        lda #255
        sec
        sbc u2
        tay
        lda u2
        ldx u1
        jsr content_rect
        lda u0
        and #1
        beq +
        jsr set_white
        jmp ++
+       jsr sh_set_pen
++      jsr fill_oval
        jsr set_black
        jsr frame_oval
        inc u0
        lda u0
        cmp #10
        bcc -
        rts

; --- Circles: a grid -----------------------------------------------------
sh_circles:
        lda #0
        sta u0                  ; column
        sta u1                  ; row
.c:     ldx u0
        lda sh_cx,x
        ldx u1
        pha
        lda sh_cy,x
        tax
        pla
        jsr sh_centre
        jsr sh_set_pen
        lda u0
        clc
        adc u1
        asl
        asl
        adc #8
        pha
        jsr fill_circle
        jsr set_black
        pla
        jsr frame_circle
        inc u0
        lda u0
        cmp #4
        bcc .c
        lda #0
        sta u0
        inc u1
        lda u1
        cmp #3
        bcc .c
        rts
sh_cx: !byte 32, 96, 160, 224
sh_cy: !byte 28, 82, 136

; --- Round rects: bigger and bigger corners -------------------------------
sh_rrects:
        lda #0
        sta u0
-       ldx u0
        lda sh_rr_y2,x
        sta t7
        ldy sh_rr_x2,x
        lda sh_rr_x1,x
        pha
        lda sh_rr_y1,x
        tax
        pla
        jsr content_rect
        jsr sh_set_pen
        ldx u0
        lda sh_rr_r,x
        jsr fill_rrect
        jsr set_black
        ldx u0
        lda sh_rr_r,x
        jsr frame_rrect
        inc u0
        lda u0
        cmp #6
        bcc -
        rts
sh_rr_x1: !byte 4, 88, 172, 4, 88, 172
sh_rr_x2: !byte 80, 164, 250, 80, 164, 250
sh_rr_y1: !byte 8, 8, 8, 86, 86, 86
sh_rr_y2: !byte 76, 76, 76, 156, 156, 156
sh_rr_r:  !byte 0, 4, 8, 14, 22, 36

; --- Random: shapes anywhere, in random patterns ---------------------------
!zone sh_random
sh_random:
        lda #30
        sta u0
.r:     jsr random              ; a rect inside the content
        and #127
        sta u1
        jsr random
        and #127
        clc
        adc u1
        sta u1                  ; x1 0..254
        jsr random
        and #63
        clc
        adc #12
        clc
        adc u1
        bcc +
        lda #255
+       tay                     ; x2
        jsr random
        and #127
        sta u2                  ; y1 0..127
        jsr random
        and #31
        clc
        adc #10
        adc u2
        sta t7                  ; y2
        lda u1
        ldx u2
        jsr content_rect
        jsr random              ; pattern
        and #7
        asl
        asl
        asl
        clc
        adc #<patterns
        pha
        lda #>patterns
        adc #0
        tay
        pla
        jsr set_pat_copy
        lda sh_xor
        beq +
        lda #M_XOR
        jsr set_mode
+       jsr random              ; kind
        and #3
        beq .oval
        cmp #1
        beq .rrect
        cmp #2
        beq .circle
        jsr fill_rect
        jsr set_black
        jsr frame_rect
        jmp .next
.oval:  jsr fill_oval
        jsr set_black
        jsr frame_oval
        jmp .next
.rrect: lda #8
        jsr fill_rrect
        jsr set_black
        lda #8
        jsr frame_rrect
        jmp .next
.circle:
        jsr random
        and #15
        clc
        adc #6
        pha
        jsr fill_circle
        jsr set_black
        pla
        jsr frame_circle
.next:  dec u0
        beq .bf594
        jmp .r
.bf594:
        rts

; ---------------------------------------------------------------------
; Menus and text
; ---------------------------------------------------------------------
sh_menus:
        !word str_sh_file, str_sh_edit, str_sh_shapes, str_sh_pen
        !word sh_items_file, sh_items_edit, sh_items_shapes, sh_items_pen
sh_items_file:
        !byte 1
        +item str_sh_quit, 'Q', SA_QUIT
sh_items_edit:
        !byte 6
        +item str_sh_undo, 'Z', ACT_NONE
        +sep
        +item str_sh_cut, 'X', ACT_NONE
        +item str_sh_copy, 'C', ACT_NONE
        +item str_sh_paste, 'V', ACT_NONE
        +item str_sh_clear, 0, ACT_NONE
sh_items_shapes:
        !byte PAGES
        +item str_sh_sampler, 'S', SA_PAGE+0
        +item str_sh_lines, 'L', SA_PAGE+1
        +item str_sh_ovals, 'O', SA_PAGE+2
        +item str_sh_circles, 'C', SA_PAGE+3
        +item str_sh_rrects, 'R', SA_PAGE+4
        +item str_sh_random, 'N', SA_PAGE+5
sh_items_pen:
        !byte PENS+2
        +item str_sh_black, 0, SA_PEN+0
        +item str_sh_gray, 0, SA_PEN+1
        +item str_sh_ltgray, 0, SA_PEN+2
        +item str_sh_weave, 0, SA_PEN+3
        +sep
        +item str_sh_invert, 'I', SA_INVERT

str_sh_about:   !text "About Shapes", $13, 0
str_sh_info:    !text "Shapes|QuickDraw lines, ovals, circles and round rects, drawn through the System's jump table. Click the window for the next picture.", 0
str_sh_title:   !text "Shapes", 0
str_sh_file:    !text "File", 0
str_sh_edit:    !text "Edit", 0
str_sh_shapes:  !text "Shapes", 0
str_sh_pen:     !text "Pen", 0
str_sh_quit:    !text "Quit", 0
str_sh_undo:    !text "Undo", 0
str_sh_cut:     !text "Cut", 0
str_sh_copy:    !text "Copy", 0
str_sh_paste:   !text "Paste", 0
str_sh_clear:   !text "Clear", 0
str_sh_sampler: !text "Sampler", 0
str_sh_lines:   !text "Lines", 0
str_sh_ovals:   !text "Ovals", 0
str_sh_circles: !text "Circles", 0
str_sh_rrects:  !text "Round Rects", 0
str_sh_random:  !text "Random", 0
str_sh_black:   !text "Black", 0
str_sh_gray:    !text "Grey", 0
str_sh_ltgray:  !text "Light Grey", 0
str_sh_weave:   !text "Weave", 0
str_sh_invert:  !text "Invert", 0

sh_end:
!if sh_end > PAGE_BASE {
        !error "SHAPES is bigger than its 8K block"
}
