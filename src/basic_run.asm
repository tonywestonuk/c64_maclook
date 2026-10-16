; =====================================================================
; basic_run.asm - running a program with the C64's own BASIC
;
; The program is kept in BASIC V2's format, so the BASIC ROM runs it:
; its statements, expressions, variables, strings and arrays.  BASIC's
; zero page and the System's overlap, so they are swapped (basic_zp
; holds whichever isn't in use), and the ROMs are banked in while BASIC
; runs.  It runs in slices from the Output window's idle call:
;
;   - every statement passes through IGONE ($0308): there the slice
;     ends when its time is up, our statements (NPU, PSET ...) run,
;     and END, STOP and the hidden last line end the program;
;   - PRINT's characters (CHROUT) are queued and drawn between slices;
;     INPUT's (CHRIN) wait for a line typed in the Output window;
;   - errors come through IERROR ($0300).
;
; A slice ends with BASIC's part of the stack (its FOR and GOSUB entries,
; and any calls in progress) copied out; the next one copies it back.
; Interrupts stay on: with the KERNAL banked in they come through $0314,
; where the System's interrupt routine is run with its own $70-$7f and
; $fb-$fe swapped back in for it.
; =====================================================================

RS_STOP = 0
RS_RUN  = 1
W_NONE  = 0             ; run_wait: what the program waits for
W_INPUT = 1             ; a line typed in the Output window
W_FRONT = 2             ; the Output window in front (to draw)
SLICE   = 8             ; frames a slice may take
E_OURS  = 128           ; error: the message is already in msg_buf
SB_BUF  = $c600         ; BASIC's stack while it isn't running (256)

run_state: !byte RS_STOP
run_wait:  !byte W_NONE
resume:    !word 0      ; where BASIC carries on
sys_sp:    !byte 0      ; the stack pointer when the slice started
sb_len:    !byte 0
frames:    !byte 0      ; counted by the interrupt while BASIC runs
slice_end: !byte 0
sys_irq:   !word 0      ; the System's interrupt routine
st_txt:    !word 0      ; the statement being run (to run it again)
st_sp:     !byte 0
err_code:  !byte 0
err_num:   !word 0      ; the line number it was in
err_idx:   !byte 0

; ---------------------------------------------------------------------
; Run > Start
; ---------------------------------------------------------------------
!zone run_start
run_start:
        jsr ed_commit
        bcc +
        rts
+       jsr run_end
        jsr out_front
        lda out_win
        cmp #$ff
        bne +
        rts
+       jsr out_cls
        jsr npu_begin
        ; BASIC's memory: the program, then variables, arrays, strings
        lda prog_base
        sta basic_zp+$2b        ; TXTTAB
        ldx prog_base+1
        stx basic_zp+$2c
        sec                     ; DATPTR and TXTPTR: the 0 before it
        sbc #1
        sta basic_zp+$41
        sta basic_zp+BAS_TXTPTR
        bcs +
        dex
+       stx basic_zp+$42
        stx basic_zp+BAS_TXTPTR+1
        clc                     ; VARTAB = ARYTAB = STREND: after its end
        lda prog_end
        adc #2
        sta basic_zp+$2d
        sta basic_zp+$2f
        sta basic_zp+$31
        lda prog_end+1
        adc #0
        sta basic_zp+$2e
        sta basic_zp+$30
        sta basic_zp+$32
        lda #<WS_END            ; FRETOP = MEMSIZ: the top
        sta basic_zp+$33
        sta basic_zp+$37
        lda #>WS_END
        sta basic_zp+$34
        sta basic_zp+$38
        lda #$19                ; no temporary strings
        sta basic_zp+$16
        lda #0
        sta basic_zp+$3e        ; (no CONT)
        sta basic_zp+$10
        sta basic_zp+$13        ; (the screen for I/O)
        sta sb_len
        sta in_state
        sta oq_len
        sta inkey_c
        sta err_code
        lda #<run_begin
        sta resume
        lda #>run_begin
        sta resume+1
        jsr hooks_on
        lda #RS_RUN
        sta run_state
        rts

; the vectors BASIC and the KERNAL go through
!zone hooks_on
hooks_on:
        sei
        lda $fffe               ; (RAM: the System's interrupt routine)
        sta sys_irq
        lda $ffff
        sta sys_irq+1
        ldx #hk_end-hk_vec-1
-       ldy hk_off,x
        lda hk_vec,x
        sta $0300,y
        dex
        bpl -
        cli
        rts
hk_off: !byte $08, $09, $14, $15, $24, $25, $26, $27, $28, $29, $2a, $2b
        !byte $22, $23, $2c, $2d
hk_vec: !word igone, irq_b, chrin, chrout, stop_k, getin, k_rts, k_rts
hk_end:

; the program stops (and can't go on)
run_end:
        lda #RS_STOP
        sta run_state
        lda #W_NONE
        sta run_wait
        sta in_state
        rts

; Run > Stop
run_stop_menu:
        lda run_state
        beq +
        jsr run_end
        jmp beep
+       rts

; ---------------------------------------------------------------------
; Switching between the System and BASIC
; ---------------------------------------------------------------------
; swap $02-$95 and $fb-$fe with basic_zp (interrupts must be off)
!zone zswap
zswap:  ldx #$94                 ; ($02-$95, two at a time)
-       lda $01,x
        ldy basic_zp+1,x
        sty $01,x
        sta basic_zp+1,x
        lda $00,x
        ldy basic_zp,x
        sty $00,x
        sta basic_zp,x
        dex
        dex
        bne -
        ldx #3
-       lda $fb,x
        ldy basic_zp+$fb,x
        sty $fb,x
        sta basic_zp+$fb,x
        dex
        bpl -
        lda $01ff               ; (INPUT and READ put a comma at $01ff: the
        ldy bas_1ff             ; top of the System's stack)
        sty $01ff
        sta bas_1ff
        rts
bas_1ff: !byte 0

to_basic:
        sei
        jsr zswap
        lda #$37
        sta $01
        lda basic_zp+$74        ; TI: the System's jiffies
        sta $a2
        lda basic_zp+$75
        sta $a1
        lda #0
        sta $a0
        cli
        rts
to_system:
        sei
        lda #$35
        sta $01
        jsr zswap
        cli
        rts

; sys_call: from BASIC, the System routine at sc_vec (A, X, Y and carry
; passed on, and back)
sc_vec: !word 0
sc_a:   !byte 0
sc_p:   !byte 0
sc_x:   !byte 0
sc_y:   !byte 0
!zone sys_call
sys_call:
        sta sc_a
        php
        pla
        sta sc_p
        stx sc_x
        sty sc_y
        jsr to_system
        lda sc_p
        pha
        lda sc_a
        ldx sc_x
        ldy sc_y
        plp
        jsr .go
        php
        sta sc_a
        pla
        sta sc_p
        stx sc_x
        sty sc_y
        jsr to_basic
        lda sc_p
        pha
        lda sc_a
        ldx sc_x
        ldy sc_y
        plp
        rts
.go:    jmp (sc_vec)

; net_call: as sys_call, for the System's WiC64 routines (npu_run,
; npu_draw, wic_request), which only use $02-$03, $12-$13 and $80-$83 of
; the zero page (and the interrupt $70-$7f and $fb-$fe): only those are
; swapped, which is quicker
!zone net_call
net_call:
        sta sc_a
        php
        pla
        sta sc_p
        stx sc_x
        sty sc_y
        sei
        lda #$35
        sta $01
        jsr .swap
        cli
        lda sc_p
        pha
        lda sc_a
        ldx sc_x
        ldy sc_y
        plp
        jsr .go
        php
        sta sc_a
        pla
        sta sc_p
        stx sc_x
        sty sc_y
        sei
        jsr .swap
        lda #$37
        sta $01
        cli
        lda sc_p
        pha
        lda sc_a
        ldx sc_x
        ldy sc_y
        plp
        rts
.go:    jmp (sc_vec)
.swap:  ldy #nc_end-nc_zp-1
-       ldx nc_zp,y
        lda $00,x
        pha
        lda basic_zp,x
        sta $00,x
        pla
        sta basic_zp,x
        dey
        bpl -
        rts
nc_zp:  !byte $02, $03, $12, $13, $80, $81, $82, $83, $fb, $fc, $fd, $fe
        !for z, $70, $7f { !byte z }
nc_end:

; the interrupt while BASIC runs (from the KERNAL's, A X Y pushed): the
; System's routine, with its own $70-$7f and $fb-$fe
!zone irq_b
irq_b:  jsr .swap
        lda #>.back             ; as if it had interrupted us
        pha
        lda #<.back
        pha
        php
        jmp (sys_irq)
.back:  jsr .swap
        inc frames
        lda basic_zp+$74        ; TI: the System's jiffies
        sta $a2
        lda basic_zp+$75
        sta $a1
        lda #0
        sta $a0
        pla
        tay
        pla
        tax
        pla
        rti
.swap:  ldx #15
-       lda $70,x
        ldy basic_zp+$70,x
        sty $70,x
        sta basic_zp+$70,x
        dex
        bpl -
        ldx #3
-       lda $fb,x
        ldy basic_zp+$fb,x
        sty $fb,x
        sta basic_zp+$fb,x
        dex
        bpl -
        rts

; ---------------------------------------------------------------------
; A slice (from the Output window's idle call)
; ---------------------------------------------------------------------
!zone run_slice
run_slice:
        lda run_state
        bne +
        rts
+       jsr out_place           ; where the window is now
        jsr out_flush           ; what was printed (if it's in front)
        lda run_wait
        beq .go
        cmp #W_INPUT
        bne +
        lda in_state            ; typed yet?
        cmp #IS_READY
        bne .out
        beq .clear
+       lda oq_len              ; W_FRONT: drawn now?
        bne .out
        lda out_win
        cmp zlist
        bne .out
.clear: lda #W_NONE
        sta run_wait
.go:    sei                     ; BASIC's stack back below ours (an
        tsx                     ; interrupt now would land on it)
        stx sys_sp
        txa
        sec
        sbc sb_len
        tax
        ldy #0
-       cpy sb_len
        beq +
        lda SB_BUF,y
        sta $0101,x
        inx
        iny
        bne -
+       lda sys_sp
        sec
        sbc sb_len
        tax
        txs
        lda frames
        clc
        adc #SLICE
        sta slice_end
        lda #<ierror
        sta $0300
        lda #>ierror
        sta $0301
        jsr to_basic
        jmp (resume)
.out:   rts

; the first statement (BASIC's stack starts with a 0: FOR's search stops)
run_begin:
        lda #0
        pha
        jmp NEWSTT

; yield: back to the desktop; BASIC carries on at resume later.  (Not
; called: jumped to, from anywhere in BASIC.)
!zone yield
yield:  jsr to_system
        tsx                     ; BASIC's part of the stack, kept
        stx za
        lda sys_sp
        sec
        sbc za
        sta sb_len
        ldy #0
-       cpy sb_len
        beq +
        lda $0101,x
        sta SB_BUF,y
        inx
        iny
        bne -
+       ldx sys_sp
        txs
        jsr out_flush
        bcc +
        lda run_wait            ; not in front: wait for it
        bne +
        lda #W_FRONT
        sta run_wait
+       rts

; the program has ended (END, STOP, the last line, an error)
!zone prog_done
prog_done:
        jsr to_system
        ldx sys_sp
        txs
        jsr run_end
        jsr out_flush
        lda err_code
        beq +
        jsr show_error
+       rts

; ---------------------------------------------------------------------
; Hooks (BASIC's zero page in, ROMs in)
; ---------------------------------------------------------------------
; IGONE: each statement
!zone igone
igone:  lda frames              ; time up?
        sec
        sbc slice_end
        bmi +
        lda #<igone             ; (this statement, next slice)
        sta resume
        lda #>igone
        sta resume+1
        jmp yield
+       tsx                     ; (to run it again)
        stx st_sp
        lda BAS_TXTPTR
        sta st_txt
        lda BAS_TXTPTR+1
        sta st_txt+1
        jsr CHRGET
        cmp #X_FIRST
        bcs .ours
        cmp #$80                ; END
        beq .end
        cmp #$90                ; STOP
        beq .end
        cmp #$84                ; RUN, LOAD, OPEN ...: not here
        bcc .std
        cmp #$a3
        bcs .std
        ldx #bad_end-bad_toks-1
-       cmp bad_toks,x
        beq .bad
        dex
        bpl -
.std:   jsr CHRGOT_
        jmp GONE2
.end:   lda #0
        sta err_code
        jmp prog_done
.bad:   ldx #<str_e_notnow
        ldy #>str_e_notnow
        jmp our_error
.ours:  cmp #X_LAST+1
        bcs .syn
        cmp #TK_XEND
        beq .end
        sbc #X_FIRST-1          ; (carry clear: one less)
        asl
        tax
        lda #>(NEWSTT-1)        ; then the next statement
        pha
        lda #<(NEWSTT-1)
        pha
        lda x_table+1,x
        pha
        lda x_table,x
        pha
        jmp CHRGET
.syn:   jmp SNERR
bad_toks: !byte $8a, $93, $94, $95, $9a, $9b, $9c, $9d, $9f, $a0, $a2, $98, $84
bad_end:
x_table: !word st_cls-1, st_pset-1, st_line-1, st_circle-1, st_beep-1, st_npu-1

; run this statement again later (A = what to wait for)
st_again:
        sta run_wait
        ldx st_sp               ; (nothing of the statement's on the stack)
        txs
        lda st_txt
        sta BAS_TXTPTR
        lda st_txt+1
        sta BAS_TXTPTR+1
        lda #<igone
        sta resume
        lda #>igone
        sta resume+1
        jmp yield

; drawing needs the Output window in front, and the text before it drawn
need_front:
        lda oq_len
        bne +
        lda out_win
        cmp zlist
        bne +
        rts
+       lda #W_FRONT
        jmp st_again

; IERROR: BASIC's error X; its message (lower case but the first letter)
!zone ierror
ierror: stx err_code
        lda BAS_CURLIN
        sta err_num
        lda BAS_CURLIN+1
        sta err_num+1
        cpx #E_OURS
        beq .done
        lda #<ERRTAB            ; the X'th message
        sta pa
        lda #>ERRTAB
        sta pa+1
        ldy #0
.skip:  dex
        beq .copy
-       lda (pa),y              ; past one message
        inc pa
        bne +
        inc pa+1
+       asl
        bcc -
        bcs .skip
.copy:  lda (pa),y
        pha
        and #$7f
        cpy #0
        beq +
        jsr lower
+       sta msg_buf,y
        iny
        pla
        bpl .copy
        ldx #0                  ; " error"
-       lda str_error,x
        sta msg_buf,y
        beq .done
        inx
        iny
        bne -
.done:  jmp prog_done

; our own error: the message X/Y
our_error:
        stx pa
        sty pa+1
        ldy #0
-       lda (pa),y
        sta msg_buf,y
        beq +
        iny
        bne -
+       ldx #E_OURS
        jmp ROM_ERR

lower:  cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        ora #$20
+       rts

; CHROUT: PRINT's characters, queued (the column kept for TAB and ,)
!zone chrout
chrout: sta co_c
        stx co_x
        sty co_y
        ldx oq_len
        cpx #OQ_MAX
        bcs .full
        sta oq_buf,x
        inc oq_len
        cmp #13
        bne +
        lda #0
        sta $d3
        beq ++
+       cmp #$93                ; (clear: column 0)
        bne +
        lda #0
        sta $d3
        beq ++
+       cmp #$1d                ; (cursor right: TAB, SPC and ,)
        beq +
        cmp #32
        bcc ++
+       inc $d3
++      ldx co_x
        ldy co_y
        lda co_c
        clc
        rts
.full:  lda #<.again            ; drawn first
        sta resume
        lda #>.again
        sta resume+1
        jmp yield
.again: lda co_c
        ldx co_x
        ldy co_y
        jmp chrout
co_c:   !byte 0
co_x:   !byte 0
co_y:   !byte 0

; CHRIN: INPUT's line: the program waits until it has been typed
IS_NONE  = 0
IS_TYPE  = 1
IS_READY = 2
in_state: !byte IS_NONE
in_pos:   !byte 0
!zone chrin
chrin:  stx co_x
        sty co_y
.again: lda in_state            ; (back here when the line is typed)
        cmp #IS_READY
        beq .give
        lda #IS_TYPE            ; wait for it
        sta in_state
        lda #0
        sta in_len
        sta in_pos
        lda #W_INPUT
        sta run_wait
        lda #<.again
        sta resume
        lda #>.again
        sta resume+1
        jmp yield
.give:  ldx in_pos
        cpx in_len
        bcs .cr
        lda IN_BUF,x
        inc in_pos
        bne .out
.cr:    lda #IS_NONE
        sta in_state
        lda #13
.out:   ldx co_x
        ldy co_y
        clc
        rts

; GETIN: GET's key (0 if none)
getin:  lda inkey_c
        pha
        lda #0
        sta inkey_c
        pla
        clc
        rts
inkey_c: !byte 0

; STOP: never (Run > Stop does it between slices)
stop_k: lda #1
k_rts:  rts

; ---------------------------------------------------------------------
; After an error: say so, and show the line
; ---------------------------------------------------------------------
!zone show_error
show_error:
        ldx #0                  ; "Message in line n."
-       lda msg_buf,x
        beq +
        inx
        bne -
+       stx za
        jsr err_line_no         ; A = the line's index ($ff: none)
        sta err_idx
        cmp #$ff
        beq .nonum
        ldx za
        ldy #0
-       lda str_inline,y
        beq +
        sta msg_buf,x
        inx
        iny
        bne -
+       stx za
        lda err_idx
        jsr line_label          ; numbuf = how the listing names it
        ldx za
        ldy #0
-       lda numbuf,y
        sta msg_buf,x
        beq +
        inx
        iny
        bne -
+       lda #'.'
        sta msg_buf,x
        inx
        lda #0
        sta msg_buf,x
.nonum: lda #<msg_buf
        ldy #>msg_buf
        jsr alert_stop
        lda err_idx
        cmp #$ff
        beq +
        jmp show_line
+       rts

; A = the index of the line numbered err_num ($ff if none)
!zone err_line_no
err_line_no:
        ldx #0
.l:     cpx nlines
        beq .none
        stx zb
        txa
        jsr line_addr
        ldx zb
        ldy #2
        lda (pa),y
        cmp err_num
        bne +
        iny
        lda (pa),y
        cmp err_num+1
        beq .yes
+       inx
        bne .l
.none:  lda #$ff
        rts
.yes:   txa
        rts

; numbuf = line A's name: its own number, or its place in the listing
!zone line_label
line_label:
        sta zb
        jsr line_addr
        ldy #2                  ; a number of its own: n * 64
        lda (pa),y
        and #63
        bne +
        lda (pa),y
        sta zw
        iny
        lda (pa),y
        ldx #6
-       lsr
        ror zw
        dex
        bne -
        tax
        lda zw
        jmp utoa
+       lda zb
        clc
        adc #1
        ldx #0
        jmp utoa

; the Listing in front with line err_idx inverted and the caret on it
!zone show_line
show_line:
        jsr ed_commit
        lda err_idx
        sta ls_hilite
        lda #0
        sta ed_col
        lda err_idx
        jsr ed_open
        ldx ls_win
        cpx #$ff
        beq +
        cpx zlist
        beq ++
        jsr win_select
        jmp ls_show
++      jmp ls_redraw
+       jsr ls_open
        jmp ls_show
