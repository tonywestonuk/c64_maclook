; =====================================================================
; loader.asm - load files from the 1541 through the KERNAL
;
; The KERNAL is banked in only for the duration of the LOAD.  Our zero
; page use stays below $90, so the KERNAL's own variables ($90-$ff)
; are still intact from boot.  The raster IRQ keeps running through
; the KERNAL's vector, so the pointer moves while the drive works.
; =====================================================================

SETNAM = $ffbd
SETLFS = $ffba
LOAD   = $ffd5
LOAD_DEVICE = 8

ld_name: !word 0
ld_len:  !byte 0

; load_file: A/Y = name, X = length.  Loads to the address in the
; file's header.  Carry set on error (A = KERNAL error code).
!zone load_file
load_file:
        sta ld_name
        sty ld_name+1
        stx ld_len
        sei
        lda #<irq_k
        sta $0314
        lda #>irq_k
        sta $0315
        lda #$36                ; KERNAL + I/O
        sta $01
        cli
        lda ld_len
        ldx ld_name
        ldy ld_name+1
        jsr SETNAM
        lda #1
        ldx #LOAD_DEVICE
        ldy #1                  ; secondary address 1: use the file's address
        jsr SETLFS
        lda #0                  ; load, not verify
        jsr LOAD
        php
        sei
        ldx #$35                ; back to all RAM + I/O
        stx $01
        plp
        cli
        rts
