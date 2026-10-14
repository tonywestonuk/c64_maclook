; =====================================================================
; brickles.asm - the game
;
; All game coordinates are local to the window's content area:
;   rows 0..10  status line, row 11 a line
;   rows 12..   playfield; bricks from BR_TOP, paddle at PAD_Y
; Ball position and velocity are 8.8 fixed point (high byte = pixel).
; =====================================================================

PF_W     = 216          ; content size
PF_H     = 160
PF_TOP   = 12
BR_COLS  = 12
BR_ROWS  = 6
BR_W     = 18
BR_H     = 7            ; pitch (6 pixel brick + gap)
BR_TOP   = 22
NBRICKS  = BR_COLS*BR_ROWS
PAD_Y    = 148
PAD_W    = 24           ; one sprite wide
PAD_H    = 4
BALL     = 4

ST_SERVE = 0
ST_PLAY  = 1
ST_OVER  = 2
ST_PAUSE = 3

CL_GAME  = CL_APPBASE+0

BA_ABOUT = 0
BA_NEW   = 1
BA_PAUSE = 2
BA_QUIT  = 3
BA_UNDO  = 4
BA_CUT   = 5
BA_COPY  = 6
BA_PASTE = 7
BA_CLEAR = 8
BA_SOUND = 9
BA_HIGH  = 10
BA_SLOW  = 11
BA_MED   = 12
BA_FAST  = 13

bk_high   = sys_pram+0  ; word, kept by the System between launches
bk_speed  = sys_pram+2  ; 0 medium, 1 slow, 2 fast
bk_mute   = sys_pram+3  ; 0 = sound on

bk_classes:             ; draw, click, key, idle, close, edit, resize, scroll
        !word bk_draw, bk_click, bk_key, bk_idle, bk_close, nop_method, nop_method, nop_method

bk_win:     !byte 0
bk_state:   !byte 0
bk_score:   !word 0
bk_balls:   !byte 0
bk_level:   !byte 0
bk_left:    !byte 0
bk_bricks:  !fill NBRICKS
bk_px:      !byte 0      ; paddle x
bk_opx:     !byte $ff    ; paddle as drawn
bk_bx:      !word 0      ; ball 8.8
bk_by:      !word 0
bk_vx:      !word 0
bk_vy:      !word 0
bk_obx:     !byte $ff    ; ball as drawn ($ff = not drawn)
bk_oby:     !byte 0
bk_last:    !byte 0      ; jiffy of the last step
bk_sndt:    !byte 0
bk_quitting: !byte 0
bk_live:    !byte 0      ; ball and paddle are sprites (else stamped in the bitmap)
bk_rowimg:  !byte BR_COLS*BR_W/8, 6, BR_COLS*BR_W   ; one row of bricks,
            !fill BR_COLS*BR_W/8*6                  ; in icon format
bk_span:    !fill BR_COLS*BR_W/8
bk_edge:    !fill BR_COLS*BR_W/8

SPR_BALL   = 2
SPR_PADDLE = 3
SPR_BITS   = (1<<SPR_BALL) | (1<<SPR_PADDLE)
SPR_DATA   = $c600         ; free sprite memory after the cursors
bk_spr_ball:   !byte $60,0,0, $f0,0,0, $f0,0,0, $60,0,0
bk_spr_paddle: !byte $7f,$ff,$fe, $ff,$ff,$ff, $ff,$ff,$ff, $7f,$ff,$fe
bk_buf:     !fill 48

; horizontal speed by where the ball hits the paddle
bk_vxlo:    !byte <-$200, <-$170, <-$100, <-$90, <$90, <$100, <$170, <$200
bk_vxhi:    !byte >-$200, >-$170, >-$100, >-$90, >$90, >$100, >$170, >$200
; vertical speed for medium, slow, fast
bk_vylo:    !byte <$1c0, <$150, <$240
bk_vyhi:    !byte >$1c0, >$150, >$240
; brick patterns per row
bk_patlo:   !byte <pat_black, <(patterns+2*8), <pat_gray, <(patterns+7*8), <pat_ltgray, <(patterns+3*8)
bk_pathi:   !byte >pat_black, >(patterns+2*8), >pat_gray, >(patterns+7*8), >pat_ltgray, >(patterns+3*8)

; ---------------------------------------------------------------------
; Start-up: the game window is in place before the System draws
; ---------------------------------------------------------------------
!zone bk_init
bk_init:
        lda #0
        sta bk_quitting
        jsr win_alloc
        stx bk_win
        +winrect 50, 20, 50+PF_W+1, 20+PF_H+11
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_GAME
        sta w_class,x
        lda #<str_bk_title
        sta w_titl,x
        lda #>str_bk_title
        sta w_tith,x
        lda #1
        sta w_used,x
        jsr z_front
        ; sprite shapes for the ball and paddle
        ldx #127
        lda #0
-       sta SPR_DATA,x
        dex
        bpl -
        ldx #11
-       lda bk_spr_ball,x
        sta SPR_DATA,x
        lda bk_spr_paddle,x
        sta SPR_DATA+64,x
        dex
        bpl -
        lda #(SPR_DATA-$c000)/64
        sta SPRPTR+SPR_BALL
        lda #(SPR_DATA-$c000)/64+1
        sta SPRPTR+SPR_PADDLE
        lda #0
        sta $d027+SPR_BALL
        sta $d027+SPR_PADDLE
        sta bk_live
        jmp bk_reset

; new game state, no drawing
bk_reset:
        lda #0
        sta bk_score
        sta bk_score+1
        sta bk_level
        lda #3
        sta bk_balls
        lda #(PF_W-PAD_W)/2
        sta bk_px
        lda #$ff
        sta bk_opx
        jsr bk_fill_bricks
        jmp bk_serve_state

bk_fill_bricks:
        ldx #NBRICKS-1
        lda #1
-       sta bk_bricks,x
        dex
        bpl -
        lda #NBRICKS
        sta bk_left
        rts

bk_serve_state:
        lda #ST_SERVE
        sta bk_state
        jmp bk_ball_on_paddle

bk_quit:                        ; the System is about to replace us
        lda #1
        sta bk_quitting
        jsr bk_sprites_off
        jmp show_cursor

; the close box quits (after the window is gone)
bk_close:
        jsr bk_sprites_off
        lda bk_quitting
        bne +
        lda #BA_QUIT
        sta pending_action
+       jmp show_cursor

; ---------------------------------------------------------------------
; Drawing
; ---------------------------------------------------------------------
; local rect A,X - Y,t7 -> screen rx..ry (uses wc_*)
bk_rect = content_rect

; clip to the game window's content (also sets wc_*)
bk_clip:
        jsr clip_push
        jsr clip_screen
        ldx bk_win
        jsr win_get_content
        jmp clip_rect

!zone bk_draw
bk_draw:                        ; M_DRAW (content is already white)
        jsr bk_status
        lda #PF_TOP-1
        sta t7
        lda #0
        ldx #PF_TOP-1
        ldy #PF_W-1
        jsr bk_rect
        jsr fill_black
        jsr bk_draw_bricks
        lda #$ff                ; nothing stamped any more
        sta bk_opx
        sta bk_obx
        lda bk_live             ; sprites show the ball and paddle when live
        bne +
        jsr bk_stamp
+       lda bk_state
        cmp #ST_OVER
        bne .bf218
        jmp bk_msg_over
.bf218:
        cmp #ST_SERVE
        bne +
        jmp bk_msg_serve
+       rts

; all the bricks, a row at a time
!zone bk_draw_bricks
bk_draw_bricks:
        lda #0
        sta bk_row
-       jsr bk_draw_row
        inc bk_row
        lda bk_row
        cmp #BR_ROWS
        bne -
        rts

; build row bk_row as a bitmap and blit it in one go
bk_draw_row:
        ldx #BR_COLS*BR_W/8-1
        lda #0
-       sta bk_span,x
        sta bk_edge,x
        dex
        bpl -
        ; which bricks are there
        lda bk_row
        asl
        adc bk_row
        asl
        asl                     ; first brick = row*12
        sta t5
        lda #0
        sta t6                  ; column
.br:    ldx t5
        lda bk_bricks,x
        beq .nb
        lda t6                  ; x1 = 18c
        asl
        sta t0
        asl
        asl
        asl
        clc
        adc t0
        sta t3
        clc
        adc #BR_W-2
        sta t4                  ; x2
        lda t3
        ldx t4
        ldy #0
        jsr bk_bits             ; span
        lda t3
        tax
        ldy #BR_COLS*BR_W/8
        jsr bk_bits             ; left edge
        lda t4
        tax
        ldy #BR_COLS*BR_W/8
        jsr bk_bits             ; right edge
.nb:    inc t5
        inc t6
        lda t6
        cmp #BR_COLS
        bne .br
        ; compose the 6 lines: edges black, inside the row's pattern
        ldy bk_row
        lda bk_patlo,y
        sta q2
        lda bk_pathi,y
        sta q2+1
        lda #0
        sta t5                  ; line
        lda #<(bk_rowimg+3)
        sta q3
        lda #>(bk_rowimg+3)
        sta q3+1
.ln:    lda t5
        beq .full
        cmp #5
        beq .full
        ; pattern row for this line (local y)
        lda bk_row
        asl
        asl
        asl
        sec
        sbc bk_row
        clc
        adc #BR_TOP
        adc t5
        and #7
        tay
        lda (q2),y
        sta t6
        ldy #0
-       lda bk_span,y
        and t6
        ora bk_edge,y
        sta (q3),y
        iny
        cpy #BR_COLS*BR_W/8
        bne -
        jmp .next
.full:  ldy #0
-       lda bk_span,y
        sta (q3),y
        iny
        cpy #BR_COLS*BR_W/8
        bne -
.next:  clc
        lda q3
        adc #BR_COLS*BR_W/8
        sta q3
        bcc +
        inc q3+1
+       inc t5
        lda t5
        cmp #6
        bne .ln
        ; blit (ORed onto the white background)
        lda wc_x1
        sta tx
        lda wc_x1+1
        sta tx+1
        lda bk_row
        asl
        asl
        asl
        sec
        sbc bk_row
        clc
        adc #BR_TOP
        adc wc_y1
        sta ty
        lda #0
        sta ty+1
        lda #<bk_rowimg
        sta iptr
        lda #>bk_rowimg
        sta iptr+1
        lda #ICON_PLAIN
        sta iflags
        jmp draw_icon

; set bits A..X (pixel columns) in bk_span+Y (Y = 0 span, 27 edges)
bk_bits:
        sta t0
        stx t1
        sty t2
        lsr
        lsr
        lsr
        clc
        adc t2
        sta t7                  ; first byte
        lda t1
        lsr
        lsr
        lsr
        clc
        adc t2
        sta t2                  ; last byte
        lda t0
        and #7
        tax
        lda lmask_tab,x
        ldx t7
        cpx t2
        bne +
        sta t0                  ; one byte: both masks
        lda t1
        and #7
        tax
        lda rmask_tab,x
        and t0
        ldx t7
        ora bk_span,x
        sta bk_span,x
        rts
+       ora bk_span,x
        sta bk_span,x
-       inx
        cpx t2
        beq +
        lda #$ff
        sta bk_span,x
        bne -
+       lda t1
        and #7
        tay
        lda rmask_tab,y
        ora bk_span,x
        sta bk_span,x
        rts

bk_msg_over:
        lda #0
        sta font
        lda #<str_bk_over
        ldy #>str_bk_over
        ldx #96
        jsr draw_centred_at
        lda #1
        sta font
        lda #<str_bk_again
        ldy #>str_bk_again
        ldx #110
        jmp draw_centred_at

bk_msg_serve:
        lda #1
        sta font
        lda #<str_bk_serve
        ldy #>str_bk_serve
        ldx #106
        jmp draw_centred_at

; erase the message line under the bricks
bk_msg_clear:
        lda #120
        sta t7
        lda #0
        ldx #94
        ldy #PF_W-1
        jsr bk_rect
        jmp fill_white

; brick X: draw it (or white if gone)
!zone bk_draw_brick
bk_draw_brick:
        stx t3
        txa
        ldy #0                  ; row = X / 12
-       cmp #BR_COLS
        bcc +
        sbc #BR_COLS
        iny
        bne -
+       sta t2                  ; column
        sty bk_row
        lda t2                  ; x1 = col*18 = 2c + 16c
        asl
        sta t0
        asl
        asl
        asl
        clc
        adc t0
        sta bk_x1
        lda bk_row              ; y1 = BR_TOP + row*7
        asl
        asl
        asl
        sec
        sbc bk_row
        clc
        adc #BR_TOP
        sta bk_y1
        clc
        adc #BR_H-2
        sta t7
        lda bk_x1
        clc
        adc #BR_W-2
        tay
        ldx bk_y1
        lda bk_x1
        jsr bk_rect
        ldx t3
        lda bk_bricks,x
        bne +
        jmp fill_white
+       jsr set_black
        jsr frame_rect
        lda #1
        jsr rect_inset
        ldy bk_row
        lda bk_patlo,y
        pha
        lda bk_pathi,y
        tay
        pla
        jsr set_pat_copy
        jmp fill_rect
bk_row: !byte 0
bk_x1:  !byte 0
bk_y1:  !byte 0

; ---------------------------------------------------------------------
; Ball and paddle: sprites while the game is live, otherwise stamped
; into the bitmap so menus and windows can cover them properly
; ---------------------------------------------------------------------
; draw the paddle and (unless the game is over) the ball into the bitmap
bk_stamp:
        lda bk_px
        sta bk_opx
        lda #PAD_Y+PAD_H-1
        sta t7
        lda bk_px
        clc
        adc #PAD_W-1
        tay
        ldx #PAD_Y
        lda bk_px
        jsr bk_rect
        jsr fill_black
        lda bk_state
        cmp #ST_OVER
        beq +
        lda bk_bx+1
        sta bk_obx
        lda bk_by+1
        sta bk_oby
        jsr bk_ball_rect
        jsr fill_black
+       rts

bk_ball_rect:
        lda bk_oby
        clc
        adc #BALL-1
        sta t7
        lda bk_obx
        clc
        adc #BALL-1
        tay
        ldx bk_oby
        lda bk_obx
        jmp bk_rect

; remove the stamps
!zone bk_unstamp
bk_unstamp:
        lda bk_opx
        cmp #$ff
        beq +
        lda #PAD_Y+PAD_H-1
        sta t7
        lda bk_opx
        clc
        adc #PAD_W-1
        tay
        ldx #PAD_Y
        lda bk_opx
        jsr bk_rect
        jsr fill_white
        lda #$ff
        sta bk_opx
+       lda bk_obx
        cmp #$ff
        beq .out
        jsr bk_ball_rect
        jsr fill_white
        ; repair any brick the ball overlapped
        lda bk_obx
        ldx bk_oby
        jsr .fix
        lda bk_obx
        clc
        adc #BALL-1
        ldx bk_oby
        jsr .fix
        lda bk_obx
        ldx bk_oby
        inx
        inx
        inx
        jsr .fix
        lda bk_obx
        clc
        adc #BALL-1
        ldx bk_oby
        inx
        inx
        inx
        jsr .fix
        lda #$ff
        sta bk_obx
.out:   rts
.fix:   jsr bk_brick_at
        cpx #$ff
        beq +
        lda bk_bricks,x
        beq +
        jmp bk_draw_brick
+       rts

; go live: stamps away, sprites on
bk_go_live:
        lda bk_live
        bne +
        jsr bk_unstamp
        lda #1
        sta bk_live
        jsr bk_place
        php
        sei
        lda $d015
        ora #SPR_BITS
        sta $d015
        plp
+       rts

; freeze: sprites off, stamps on (inside the clip)
bk_freeze:
        lda bk_live
        beq +
        jsr bk_sprites_off
        jsr bk_stamp
+       rts

bk_sprites_off:
        lda #0
        sta bk_live
        php
        sei
        lda $d015
        and #$ff-SPR_BITS
        sta $d015
        plp
        rts

; move the sprites to the ball and paddle (screen = content + local)
!zone bk_place
bk_place:
        lda #0
        sta t3                  ; x MSBs
        clc
        lda wc_x1
        adc bk_bx+1
        sta t0
        lda wc_x1+1
        adc #0
        sta t1
        clc
        lda t0
        adc #24
        sta $d000+2*SPR_BALL
        lda t1
        adc #0
        beq +
        lda #1<<SPR_BALL
        sta t3
+       lda wc_y1
        clc
        adc bk_by+1
        adc #50
        sta $d001+2*SPR_BALL
        clc
        lda wc_x1
        adc bk_px
        sta t0
        lda wc_x1+1
        adc #0
        sta t1
        clc
        lda t0
        adc #24
        sta $d000+2*SPR_PADDLE
        lda t1
        adc #0
        beq +
        lda t3
        ora #1<<SPR_PADDLE
        sta t3
+       lda wc_y1
        clc
        adc #PAD_Y+50
        sta $d001+2*SPR_PADDLE
        php
        sei
        lda $d010
        and #$ff-SPR_BITS
        ora t3
        sta $d010
        plp
        rts

; brick at local point (A, X) -> X = index ($ff = none)
!zone bk_brick_at
bk_brick_at:
        sta t0
        txa
        sec
        sbc #BR_TOP
        bcc .none
        ldy #0
-       cmp #BR_H
        bcc +
        sbc #BR_H
        iny
        bne -
+       cmp #BR_H-1             ; the gap row
        beq .none
        cpy #BR_ROWS
        bcs .none
        sty t1
        lda t0
        ldx #0
-       cmp #BR_W
        bcc +
        sbc #BR_W
        inx
        bne -
+       cmp #BR_W-1             ; the gap column
        beq .none
        cpx #BR_COLS
        bcs .none
        stx t2
        lda t1                  ; index = row*12 + col
        asl
        adc t1
        asl
        asl
        adc t2
        tax
        rts
.none:  ldx #$ff
        rts

; the status line
!zone bk_status
bk_status:
        lda #10
        sta t7
        lda #0
        ldx #0
        ldy #PF_W-1
        jsr bk_rect
        jsr fill_white
        lda #<bk_buf
        sta q1
        lda #>bk_buf
        sta q1+1
        lda #0
        sta bk_buf
        lda #<str_bk_score
        ldx #>str_bk_score
        jsr .cat
        lda bk_score
        ldx bk_score+1
        jsr .num
        lda #<str_bk_balls
        ldx #>str_bk_balls
        jsr .cat
        lda bk_balls
        ldx #0
        jsr .num
        lda #<str_bk_level
        ldx #>str_bk_level
        jsr .cat
        ldx bk_level
        inx
        txa
        ldx #0
        jsr .num
        lda #<str_bk_hi
        ldx #>str_bk_hi
        jsr .cat
        lda bk_high
        ldx bk_high+1
        jsr .num
        lda #1
        sta font
        lda #B_OR
        sta tmode
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
        lda #<bk_buf
        ldy #>bk_buf
        jmp draw_str
.cat:   sta q0
        stx q0+1
        lda #<bk_buf
        sta q1
        lda #>bk_buf
        sta q1+1
        jmp strcat
.num:   jsr utoa
        lda #<numbuf
        ldx #>numbuf
        jmp .cat

; redraw the status line from outside M_DRAW
bk_status_now:
        jsr bk_clip
        jsr bk_status
        jmp clip_pop

; ---------------------------------------------------------------------
; The game loop runs in M_IDLE, one step per frame, only while the
; game window is in front and the pointer is over it.
; ---------------------------------------------------------------------
!zone bk_idle
bk_idle:
        cpx zlist
        beq +
        jsr bk_freeze_clip          ; in the background: frozen
        jmp bk_show
+       lda jiffy
        cmp bk_last
        bne +
        rts
+       sta bk_last
        jsr bk_sound_tick
        jsr bk_clip
        jsr mouse_in_rect           ; rx..ry = content from win_get_content
        bcs .frozen                 ; pointer outside: frozen
        lda bk_state
        cmp #ST_PLAY
        beq .live
        cmp #ST_SERVE
        beq .live
.frozen:
        jsr bk_freeze
        jsr bk_show
        jmp clip_pop
.live:  jsr bk_go_live
        jsr hide_cursor             ; (the System shows it on every click)
        jsr bk_step
        lda bk_live
        beq +
        jsr bk_place
+       jmp clip_pop

bk_freeze_clip:
        lda bk_live
        beq +
        jsr bk_clip
        jsr bk_freeze
        jmp clip_pop
+       rts

bk_show = show_cursor

!zone bk_step
bk_step:
        ; paddle follows the mouse
        sec
        lda mouse_x
        sbc wc_x1
        sta t0
        lda mouse_x+1
        sbc wc_x1+1
        bne .pclamp
        lda t0
        sec
        sbc #PAD_W/2
        bcs +
.pclamp:
        lda #0
+       cmp #PF_W-PAD_W+1
        bcc +
        lda #PF_W-PAD_W
+       sta bk_px
        lda bk_state
        cmp #ST_SERVE
        bne +
        jmp bk_ball_on_paddle      ; the ball rides on the paddle
+       jmp bk_move

bk_ball_on_paddle:
        lda bk_px
        clc
        adc #PAD_W/2-BALL/2
        sta bk_bx+1
        lda #PAD_Y-BALL-1
        sta bk_by+1
        lda #0
        sta bk_bx
        sta bk_by
        rts

; move the ball one step and bounce it
!zone bk_move
bk_move:
        clc
        lda bk_bx
        adc bk_vx
        sta bk_bx
        lda bk_bx+1
        adc bk_vx+1
        sta bk_bx+1
        lda bk_vx+1             ; (keeps the carry)
        bpl .right
        bcs .xok
        lda #0                  ; left wall
        sta bk_bx
        sta bk_bx+1
        jsr bk_neg_vx
        jsr bk_blip_wall
        jmp .xok
.right: lda bk_bx+1
        cmp #PF_W-BALL+1
        bcc .xok
        lda #PF_W-BALL          ; right wall
        sta bk_bx+1
        lda #0
        sta bk_bx
        jsr bk_neg_vx
        jsr bk_blip_wall
.xok:   clc
        lda bk_by
        adc bk_vy
        sta bk_by
        lda bk_by+1
        adc bk_vy+1
        sta bk_by+1
        cmp #PF_TOP
        bcs +
        lda #PF_TOP             ; top wall
        sta bk_by+1
        jsr bk_vy_down
        jsr bk_blip_wall
+       ; paddle
        lda bk_vy+1
        bmi .nopad
        lda bk_by+1
        cmp #PAD_Y-BALL
        bcc .nopad
        cmp #PAD_Y+2
        bcs .nopad
        lda bk_bx+1
        clc
        adc #BALL
        cmp bk_px
        bcc .nopad
        beq .nopad
        lda bk_px
        clc
        adc #PAD_W
        cmp bk_bx+1
        bcc .nopad
        beq .nopad
        ; hit: angle from where it landed
        lda bk_bx+1
        clc
        adc #BALL/2
        sec
        sbc bk_px
        bcs +
        lda #0
+       lsr
        lsr
        cmp #8
        bcc +
        lda #7
+       tax
        lda bk_vxlo,x
        sta bk_vx
        lda bk_vxhi,x
        sta bk_vx+1
        jsr bk_vy_up
        lda #PAD_Y-BALL
        sta bk_by+1
        lda #$10
        jsr bk_blip
.nopad: ; bricks: test the centre of the ball
        lda bk_bx+1
        clc
        adc #BALL/2
        pha
        lda bk_by+1
        clc
        adc #BALL/2
        tax
        pla
        jsr bk_brick_at
        cpx #$ff
        beq .nobrick
        lda bk_bricks,x
        beq .nobrick
        jsr bk_hit_brick
.nobrick:
        ; fell out of the bottom?
        lda bk_by+1
        cmp #PF_H-BALL
        bcc +
        jmp bk_lost
+       rts

bk_neg_vx:
        sec
        lda #0
        sbc bk_vx
        sta bk_vx
        lda #0
        sbc bk_vx+1
        sta bk_vx+1
        rts
bk_neg_vy:
        sec
        lda #0
        sbc bk_vy
        sta bk_vy
        lda #0
        sbc bk_vy+1
        sta bk_vy+1
        rts
bk_vy_down:                     ; make vy positive
        lda bk_vy+1
        bmi bk_neg_vy
        rts
bk_vy_up:                       ; make vy negative
        lda bk_vy+1
        bpl bk_neg_vy
        rts

; brick X was hit
!zone bk_hit_brick
bk_hit_brick:
        lda #0
        sta bk_bricks,x
        stx u6
        jsr bk_draw_brick       ; now white
        jsr bk_neg_vy
        ; points: (6 - row) * 10
        lda #BR_ROWS
        sec
        sbc bk_row
        asl
        sta t0
        asl
        asl
        clc
        adc t0
        clc
        adc bk_score
        sta bk_score
        bcc +
        inc bk_score+1
+       lda bk_row              ; higher bricks, higher pitch
        eor #7
        asl
        asl
        adc #$18
        jsr bk_blip
        jsr bk_status
        dec bk_left
        bne .out
        ; cleared: next level, a bit faster
        inc bk_level
        jsr bk_fill_bricks
        jsr bk_draw_bricks
        jsr bk_serve_state
        jsr bk_status
        jmp bk_msg_serve
.out:   rts

; the ball went past the paddle
!zone bk_lost
bk_lost:
        lda #ST_SERVE
        sta bk_state            ; (stops bk_step drawing the ball)
        lda #$06
        jsr bk_blip
        lda #12
        sta bk_sndt
        dec bk_balls
        bne .more
        ; game over
        lda #ST_OVER
        sta bk_state
        lda bk_score            ; new high score?
        cmp bk_high
        lda bk_score+1
        sbc bk_high+1
        bcc +
        lda bk_score
        sta bk_high
        lda bk_score+1
        sta bk_high+1
+       jsr bk_status
        jsr bk_freeze
        jsr bk_show
        jmp bk_msg_over
.more:  jsr bk_status
        jsr bk_serve_state
        jmp bk_msg_serve

; ---------------------------------------------------------------------
; Clicks and keys
; ---------------------------------------------------------------------
bk_click:
        jsr wait_release
        ; fall through
bk_go:                          ; serve, resume, or start again
        lda bk_state
        cmp #ST_SERVE
        beq bk_launch
        cmp #ST_PAUSE
        bne +
        lda #ST_PLAY
        sta bk_state
        rts
+       cmp #ST_OVER
        bne +
        jmp bk_new_game
+       rts

bk_launch:
        jsr bk_clip
        jsr bk_msg_clear
        jsr clip_pop
        ldx bk_speed
        lda bk_vylo,x
        sta bk_vy
        lda bk_vyhi,x
        sta bk_vy+1
        ldx bk_level            ; each level is a little faster
        beq +
-       clc
        lda bk_vy
        adc #$18
        sta bk_vy
        bcc ++
        inc bk_vy+1
++      dex
        bne -
+       jsr bk_vy_up
        jsr random
        and #1
        tax
        lda .start,x
        tax
        lda bk_vxlo,x
        sta bk_vx
        lda bk_vxhi,x
        sta bk_vx+1
        lda #ST_PLAY
        sta bk_state
        rts
.start: !byte 2, 5

bk_key:
        lda key_char
        cmp #' '
        beq bk_go
        cmp #K_RETURN
        beq bk_go
        cmp #'p'
        bne .bf890
        jmp bk_pause
.bf890:
        rts

; ---------------------------------------------------------------------
; Sound: short blips on voice 2 (the System beeps on voice 1)
; ---------------------------------------------------------------------
bk_blip_wall:
        lda #$0c
; A = frequency high byte
bk_blip:
        ldx bk_mute
        bne +
        sta $d408
        lda #0
        sta $d407
        sta $d409
        lda #8
        sta $d40a
        lda #$00
        sta $d40c
        lda #$a0
        sta $d40d
        lda beep_vol
        asl
        ora #1
        sta $d418
        lda #$40
        sta $d40b
        lda #$41
        sta $d40b
        lda #3
        sta bk_sndt
+       rts

bk_sound_tick:
        lda bk_sndt
        beq +
        dec bk_sndt
        bne +
        lda #$40
        sta $d40b
+       rts

; ---------------------------------------------------------------------
; Menus
; ---------------------------------------------------------------------
bk_acts:
        !word bk_about, bk_new_game, bk_pause, quit_app
        !word nop_method, bk_edit, bk_edit, bk_edit, bk_edit
        !word bk_sound, bk_high_score, bk_set_speed, bk_set_speed, bk_set_speed

!zone bk_action
bk_action:
        pha
        jsr bk_freeze_clip
        pla
        asl
        tay
        lda bk_acts,y
        sta jvec
        lda bk_acts+1,y
        sta jvec+1
        jmp (jvec)

bk_new_game:
        jsr bk_reset
        ldx bk_win
        jsr win_select
        ldx bk_win
        jmp win_refresh

bk_pause:
        lda bk_state
        cmp #ST_PLAY
        bne +
        lda #ST_PAUSE
        sta bk_state
        jmp bk_show
+       cmp #ST_PAUSE
        bne +
        lda #ST_PLAY
        sta bk_state
+       rts

bk_edit:                        ; for desk accessories in front
        jsr front_win
        beq +
        lda cur_action
        sec
        sbc #BA_UNDO
        sta key_char
        lda #M_EDIT
        jmp win_call
+       rts

bk_sound:
        lda bk_mute
        eor #1
        sta bk_mute
        rts

bk_set_speed:
        lda cur_action
        sec
        sbc #BA_SLOW
        tax
        lda .map,x
        sta bk_speed
        rts
.map:   !byte 1, 0, 2

bk_high_score:
        lda #<str_bk_hsmsg
        sta q0
        lda #>str_bk_hsmsg
        sta q0+1
        lda #<bk_buf
        sta q1
        lda #>bk_buf
        sta q1+1
        jsr strcpy
        lda bk_high
        ldx bk_high+1
        jsr utoa
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
        lda #<bk_buf
        sta q1
        lda #>bk_buf
        sta q1+1
        jsr strcat
        lda #<str_bk_dot
        sta q0
        lda #>str_bk_dot
        sta q0+1
        lda #<bk_buf
        sta q1
        lda #>bk_buf
        sta q1+1
        jsr strcat
        lda #<bk_buf
        ldy #>bk_buf
        jmp alert_note

!zone bk_about
bk_about:
        lda #DLG_CUSTOM
        sta dlg_kind
        lda #<bk_about_draw
        sta dlg_custom
        lda #>bk_about_draw
        sta dlg_custom+1
        lda #84
        sta dlg_h
        lda #1
        sta dlg_x2h
        lda #44
        ldx #50
        ldy #<275
        jsr dlg_open
        bcs .out
        jsr wait_click_or_key
        jmp dlg_close
.out:   rts

bk_about_draw:
        lda #0
        sta font
        lda #<str_bk_title
        ldy #>str_bk_title
        ldx #6
        jsr draw_centred_at
        ; a little brick wall
        lda #0
        sta u5
-       lda u5
        asl
        asl
        asl
        asl
        clc
        adc #64
        sta t5
        clc
        adc #13
        tay
        lda #26
        sta t7
        ldx #21
        lda t5
        jsr content_rect
        ldx u5
        lda bk_patlo,x
        pha
        lda bk_pathi,x
        tay
        pla
        jsr set_pat_copy
        jsr fill_rect
        jsr set_black
        jsr frame_rect
        inc u5
        lda u5
        cmp #6
        bne -
        lda #1
        sta font
        lda #<str_bk_ab1
        ldy #>str_bk_ab1
        ldx #34
        jsr draw_centred_at
        lda #<str_bk_ab2
        ldy #>str_bk_ab2
        ldx #44
        jsr draw_centred_at
        lda #<str_bk_ab3
        ldy #>str_bk_ab3
        ldx #54
        jsr draw_centred_at
        lda #<str_bk_ab4
        ldy #>str_bk_ab4
        ldx #66
        jmp draw_centred_at

; enable / check items
!zone bk_update_menus
bk_update_menus:
        ; File: Pause only while playing; checked when paused
        lda menu_flags+16+1
        and #$ff-MF_CHECKED-MF_DISABLED
        ldx bk_state
        cpx #ST_PAUSE
        bne +
        ora #MF_CHECKED
        bne ++
+       cpx #ST_PLAY
        beq ++
        ora #MF_DISABLED
++      sta menu_flags+16+1
        ; Edit: for the Note Pad and Calculator
        lda #0                  ; Edit: nothing to edit in a game
        sta u1
        sta u2
        ldx #32+0
        jsr menu_disable
        lda u1
        ldx #32+2
        jsr menu_set
        lda u2
        ldx #32+3
        jsr menu_set
        lda u2
        ldx #32+4
        jsr menu_set
        lda u1
        ldx #32+5
        jsr menu_set
        ; Game: sound check mark
        lda menu_flags+48+0
        and #$ff-MF_CHECKED
        ldx bk_mute
        bne +
        ora #MF_CHECKED
+       sta menu_flags+48+0
        ; Speed
        ldx #0
-       lda menu_flags+64,x
        and #$ff-MF_CHECKED
        sta menu_flags+64,x
        inx
        cpx #3
        bne -
        ldx bk_speed
        lda .item,x
        tax
        lda menu_flags+64,x
        ora #MF_CHECKED
        sta menu_flags+64,x
        rts
.item:  !byte 1, 0, 2

; ---------------------------------------------------------------------
; Menus and text
; ---------------------------------------------------------------------
bk_menus:
        !word str_bk_file, str_bk_edit, str_bk_game, str_bk_speed
        !word bk_items_file, bk_items_edit, bk_items_game, bk_items_speed
bk_items_file:
        !byte 4
        +item str_bk_new, 'N', BA_NEW
        +item str_bk_pausei, 'P', BA_PAUSE
        +sep
        +item str_bk_quit, 'Q', BA_QUIT
bk_items_edit:
        !byte 6
        +item str_bk_undo, 'Z', BA_UNDO
        +sep
        +item str_bk_cut, 'X', BA_CUT
        +item str_bk_copy, 'C', BA_COPY
        +item str_bk_paste, 'V', BA_PASTE
        +item str_bk_clear, 0, BA_CLEAR
bk_items_game:
        !byte 3
        +item str_bk_soundi, 0, BA_SOUND
        +sep
        +item str_bk_highi, 0, BA_HIGH
bk_items_speed:
        !byte 3
        +item str_bk_slow, 0, BA_SLOW
        +item str_bk_med, 0, BA_MED
        +item str_bk_fast, 0, BA_FAST

str_bk_about:  !text "About Brickles", $13, 0
str_bk_title:  !text "Brickles", 0
str_bk_file:   !text "File", 0
str_bk_edit:   !text "Edit", 0
str_bk_game:   !text "Game", 0
str_bk_speed:  !text "Speed", 0
str_bk_new:    !text "New Game", 0
str_bk_pausei: !text "Pause", 0
str_bk_quit:   !text "Quit", 0
str_bk_undo:   !text "Undo", 0
str_bk_cut:    !text "Cut", 0
str_bk_copy:   !text "Copy", 0
str_bk_paste:  !text "Paste", 0
str_bk_clear:  !text "Clear", 0
str_bk_soundi: !text "Sound", 0
str_bk_highi:  !text "High Score", $13, 0
str_bk_slow:   !text "Slow", 0
str_bk_med:    !text "Medium", 0
str_bk_fast:   !text "Fast", 0
str_bk_score:  !text "Score ", 0
str_bk_balls:  !text "    Balls ", 0
str_bk_level:  !text "    Level ", 0
str_bk_hi:     !text "    High ", 0
str_bk_over:   !text "Game Over", 0
str_bk_again:  !text "Click to play again", 0
str_bk_serve:  !text "Click or press Space to serve", 0
str_bk_hsmsg:  !text "The high score is ", 0
str_bk_dot:    !text ".", 0
str_bk_ab1:    !text "A Breakout game for the Commodore 64 desktop.", 0
str_bk_ab2:    !text "Loaded from the 1541 in place of the Finder;", 0
str_bk_ab3:    !text "Quit (C= Q) brings the Finder back.", 0
str_bk_ab4:    !text "Click to continue.", 0
