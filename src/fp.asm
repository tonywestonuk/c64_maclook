; =====================================================================
; fp.asm - borrowing the BASIC ROM's floating point routines.
;
; BASIC's zero page was saved at startup.  fp_enter swaps it back in
; and banks in the ROMs (interrupts off); fp_leave undoes that.  BASIC
; errors (overflow, division by zero) come back through the $0300
; vector to fp_error, which unwinds to the caller of the FP sequence
; with carry set.
; =====================================================================

MOVFM  = $bba2          ; FAC = mem(A/Y)
MOVMF  = $bbd4          ; mem(X/Y) = FAC
FADD   = $b867          ; FAC = mem(A/Y) + FAC
FSUB   = $b850          ; FAC = mem(A/Y) - FAC
FMULT  = $ba28          ; FAC = mem(A/Y) * FAC
FDIV   = $bb0f          ; FAC = mem(A/Y) / FAC
FOUT   = $bddd          ; FAC -> text at $0100
FIN    = $bcf3          ; text at TXTPTR -> FAC
CHRGOT = $0079
FAC_EXP = $61
TXTPTR = $7a

fp_sp:  !byte 0

; fp_begin: call as the first thing of a routine that does FP work.
; The routine's caller is where fp_error returns to.
!zone fp_begin
fp_begin:
        tsx                     ; stack: our return address, then the
        inx                     ; routine's return address
        inx
        stx fp_sp
        lda #<fp_error
        sta $0300
        lda #>fp_error
        sta $0301
        sei
        jsr zp_swap
        lda #$37
        sta $01
        rts

fp_end:
        lda #$35
        sta $01
        jsr zp_swap
        cli
        clc
        rts

fp_error:
        ldx fp_sp
        txs
        lda #$35
        sta $01
        jsr zp_swap
        cli
        sec
        rts

!zone zp_swap
zp_swap:
        ldx #2
-       lda $00,x
        ldy zp_basic,x
        sta zp_basic,x
        sty $00,x
        inx
        bne -
        rts
