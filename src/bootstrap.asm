; =====================================================================
; BOOT - loads SYSTEM from the network share through the WiC64
;
; One block, for a floppy or the Datasette: LOAD it and RUN it.  It
; copies its loader to $c000 (SYSTEM goes where BOOT is), reads
; "System Folder/System.sys" with the file service's read command, puts
; it where its first two bytes say, and jumps into it.  Failures end in
; BASIC's own messages: ?DEVICE NOT PRESENT if the WiC64 does not
; answer, ?FILE NOT FOUND if SYSTEM is not on the share.
; =====================================================================
!cpu 6510
!to "build/boot.prg", cbm

LOADER = $c000
ERROR  = $a437          ; BASIC: print error X and return to READY
ptr    = $fb            ; (free until SYSTEM uses them for the mouse)
count  = $fd

* = $0801
        !byte $0b,$08,$0a,$00,$9e       ; 10 SYS 2061
        !text "2061"
        !byte 0,0,0

        ldx #loader_end-loader
-       lda loader-1,x
        sta LOADER-1,x
        dex
        bne -
        jmp LOADER

loader:
!pseudopc LOADER {
        lda $dd0d               ; no stale FLAG2
        lda $dd02               ; PA2 out, high: we send
        ora #$04
        sta $dd02
        lda $dd00
        ora #$04
        sta $dd00
        ldx #$ff
        stx $dd03
        inx
-       lda request,x
        sta $dd01
        jsr wait
        inx
        cpx #request_end-request
        bne -
        lda #0                  ; PA2 low: we receive
        sta $dd03
        lda $dd00
        and #$fb
        sta $dd00
        jsr wait
        lda $dd01               ; ready
        jsr get                 ; status
        beq +
        ldx #4                  ; ?FILE NOT FOUND
        jmp ERROR
+       jsr get                 ; size
        sta count
        jsr get
        sta count+1
        jsr get                 ; load address
        sta ptr
        jsr get
        sta ptr+1
        lda count               ; less the address
        sec
        sbc #2
        sta count
        bcs +
        dec count+1
+       ldy #0
.next:  lda count
        ora count+1
        beq .done
        jsr get
        sta (ptr),y
        inc ptr
        bne +
        inc ptr+1
+       lda count
        bne +
        dec count+1
+       dec count
        jmp .next
.done:  jmp $080d               ; SYSTEM

; the next byte
get:    jsr wait
        lda $dd01
        rts

; wait for FLAG2; after about two seconds, ?DEVICE NOT PRESENT
wait:   lda #0
        sta tc
        sta tc+1
-       lda #$10
        bit $dd0d
        bne +
        dec tc
        bne -
        dec tc+1
        bne -
        lda #0
        sta $dd03
        ldx #5                  ; ?DEVICE NOT PRESENT
        jmp ERROR
+       rts

tc:     !byte 0, 0              ; timeout counter

request:
        !text "R"
        !byte $82                       ; file service: read
        !word request_end-payload       ; payload size
payload:
        !byte 0, 0, 0, 0                ; from offset 0
        !byte $ff, $ff                  ; as much as there is
        !text "System Folder/System.sys"
request_end:
}
loader_end:

!if * > $0801 + 254 {
        !error "BOOT is more than one block"
}
