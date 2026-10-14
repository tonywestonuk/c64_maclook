; =====================================================================
; util.asm - macros and small helpers
; =====================================================================

; ---------------------------------------------------------------------
; utoa: A = low, X = high -> decimal string in numbuf, A/Y = numbuf
; ---------------------------------------------------------------------
numbuf: !fill 8
u_val:  !word 0
u_dig:  !byte 0
u_on:   !byte 0
pow_lo: !byte <10000, <1000, <100, <10, <1
pow_hi: !byte >10000, >1000, >100, >10, >1

!zone utoa
utoa:
        sta u_val
        stx u_val+1
        lda #0
        sta u_on
        ldy #0
        ldx #0
.pow:   lda #0
        sta u_dig
.sub:   sec
        lda u_val
        sbc pow_lo,x
        sta t0
        lda u_val+1
        sbc pow_hi,x
        bcc .digit
        sta u_val+1
        lda t0
        sta u_val
        inc u_dig
        jmp .sub
.digit: lda u_dig
        ora u_on
        bne .emit
        cpx #4
        bne .skip
.emit:  lda u_dig
        ora #'0'
        sta numbuf,y
        iny
        lda #1
        sta u_on
.skip:  inx
        cpx #5
        bne .pow
        lda #0
        sta numbuf,y
        lda #<numbuf
        ldy #>numbuf
        rts

; two decimal digits of A (0..99) -> numbuf (always two digits)
!zone utoa2
utoa2:
        ldx #'0'
-       cmp #10
        bcc +
        sbc #10
        inx
        bne -
+       ora #'0'
        stx numbuf
        sta numbuf+1
        lda #0
        sta numbuf+2
        lda #<numbuf
        ldy #>numbuf
        rts

; ---------------------------------------------------------------------
; strings: q0 = source, q1 = destination
; ---------------------------------------------------------------------
; strcpy: copy including the terminator, Y = length on return
!zone strcpy
strcpy:
        ldy #0
-       lda (q0),y
        sta (q1),y
        beq +
        iny
        bne -
+       rts

; strcat: append q0 to q1
strcat:
        ldy #0
-       lda (q1),y
        beq +
        iny
        bne -
+       tya
        clc
        adc q1
        sta q1
        bcc strcpy
        inc q1+1
        jmp strcpy

; strlen: A/Y = string -> A = length
strlen:
        sta q0
        sty q0+1
        ldy #0
-       lda (q0),y
        beq +
        iny
        bne -
+       tya
        rts

; mul8: A * X -> A (low) / X (high)
!zone mul8
mul8:
        sta t0
        stx t1
        lda #0
        sta t2
        ldx #8
-       lsr t1
        bcc +
        clc
        adc t0
+       ror
        ror t2
        dex
        bne -
        tax
        lda t2
        rts
