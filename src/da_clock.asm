; =====================================================================
; da_clock.asm - Alarm Clock desk accessory (CIA time-of-day clock)
; =====================================================================

clock_win:  !byte $ff
clock_sec:  !byte $ff     ; last seconds shown
clock_str:  !fill 14
clock_date: !text "Tuesday, October 6, 1987", 0

!zone clock_open
clock_open:
        lda #CL_CLOCK
        jsr da_find
        bcs +
        jmp win_select
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx clock_win
        +winrect 170, 24, 296, 64
        lda #WF_CLOSE|WF_SHADOW
        sta w_flags,x
        lda #CL_CLOCK
        sta w_class,x
        lda #<str_o_clock
        sta w_titl,x
        lda #>str_o_clock
        sta w_tith,x
        lda #$ff
        sta clock_sec
        ldx clock_win
        jmp win_open

clock_close:
        lda #$ff
        sta clock_win
        rts

; read the TOD clock into clock_str: "10:09:41 AM"
!zone clock_read
clock_read:
        lda $dc0b               ; hours latch the clock
        sta t0
        lda $dc0a
        sta t1
        lda $dc09
        sta t2
        lda $dc08               ; unlatch
        lda t2
        sta clock_sec
        ldx #0
        lda t0
        and #$10
        beq +
        lda #'1'
        sta clock_str,x
        inx
+       lda t0
        and #$0f
        ora #'0'
        sta clock_str,x
        inx
        lda #':'
        sta clock_str,x
        inx
        lda t1
        jsr .bcd
        lda #':'
        sta clock_str,x
        inx
        lda t2
        jsr .bcd
        lda #' '
        sta clock_str,x
        inx
        lda #'A'
        bit t0
        bpl +
        lda #'P'
+       sta clock_str,x
        inx
        lda #'M'
        sta clock_str,x
        inx
        lda #0
        sta clock_str,x
        rts
.bcd:   pha
        lsr
        lsr
        lsr
        lsr
        ora #'0'
        sta clock_str,x
        inx
        pla
        and #$0f
        ora #'0'
        sta clock_str,x
        inx
        rts

!zone clock_draw
clock_draw:
        jsr clock_read
        lda #0
        sta font
        lda #<clock_str
        ldy #>clock_str
        ldx #3
        jsr draw_centred_at
        lda #1
        sta font
        lda #<clock_date
        ldy #>clock_date
        ldx #16
        jmp draw_centred_at

; once a second, redraw
clock_idle:
        lda $dc09
        cmp clock_sec
        beq +
        sta clock_sec
        jsr win_get_content
        lda ry1
        clc
        adc #13
        sta ry2
        jmp redraw_region
+       rts
