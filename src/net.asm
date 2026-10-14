; =====================================================================
; net.asm - the WiC64 on the user port, and the network file service
;
; The System's files live on a network share that the WiC64 offers
; (docs/fileservice.md).  The transfer protocol is the WiC64's own:
; PB0-PB7 ($dd01) carry the data, PA2 ($dd00 bit 2) is high while the
; C64 sends and low while it receives, and the WiC64 answers every byte
; on FLAG2 (bit 4 of $dd0d).
;
; All calls return carry clear and A = 0 on success, or carry set and
; A = the status (16.. from the file service, FS_NOWIC64 if the WiC64
; did not answer).  Paths are in q0 (and q1 for the destination of a
; rename or copy); the other parameters are the fs_ variables in
; public.asm.
; =====================================================================

NET_REQ = $0600         ; request payload being built (256 bytes)
NET_PATH_MAX = 120

FS_INFO   = $80         ; file service commands
FS_LIST   = $81
FS_READ   = $82
FS_WRITE  = $83
FS_DELETE = $84
FS_RENAME = $85
FS_MKDIR  = $86
FS_STAT   = $87
FS_COPY   = $88

FS_OK        = 0        ; status codes
FS_NOTFOUND  = 16
FS_EXISTS    = 17
FS_NOTEMPTY  = 18
FS_WRONGKIND = 19
FS_BADREQ    = 20
FS_NOSHARE   = 21
FS_IOERR     = 22
FS_FULL      = 23
FS_DENIED    = 24
FS_NOWIC64   = $ff      ; the WiC64 did not answer

FSW_REPLACE = 0         ; fs_write modes
FSW_AT      = 1
FSW_APPEND  = 2

nt_c:    !fill 3        ; timeout counter
nr_cmd:  !byte 0
nr_n:    !byte 0        ; request bytes in NET_REQ
nr_size: !word 0
nr_prg:  !byte 0        ; 1: the first two bytes of the response are its address

; ---------------------------------------------------------------------
; The user port
; ---------------------------------------------------------------------
; wait for FLAG2 from the WiC64; carry set after about four seconds
!zone net_wait
net_wait:
        lda #$10
        bit $dd0d
        bne .ok
        lda #0
        sta nt_c
        sta nt_c+1
        lda #4
        sta nt_c+2
-       lda #$10
        bit $dd0d
        bne .ok
        dec nt_c
        bne -
        dec nt_c+1
        bne -
        dec nt_c+2
        bne -
        sec
        rts
.ok:    clc
        rts

; A -> the WiC64 (carry set on timeout)
net_put:
        sta $dd01
        jmp net_wait

; the WiC64 -> A (carry set on timeout)
net_get:
        jsr net_wait
        bcs +
        lda $dd01
+       rts

; ---------------------------------------------------------------------
; net_request: send command A with X bytes of NET_REQ, then fs_dlen
; bytes from (fs_dptr), and receive the response: the status in
; fs_status, the payload to (fs_rptr), at most fs_rmax bytes (the rest
; is read and dropped), its length in fs_rlen.
; ---------------------------------------------------------------------
!zone net_request
net_request:
        sta nr_cmd
        stx nr_n
        lda $dd0d               ; no stale FLAG2
        lda $dd02               ; PA2 is an output, high: we send
        ora #$04
        sta $dd02
        lda $dd00
        ora #$04
        sta $dd00
        lda #$ff
        sta $dd03               ; port B out
        lda #"R"
        jsr net_put
        bcs .fail
        lda nr_cmd
        jsr net_put
        bcs .fail
        clc                     ; size = request bytes + data
        lda nr_n
        adc fs_dlen
        jsr net_put
        bcs .fail
        lda #0
        adc fs_dlen+1
        jsr net_put
        bcs .fail
        ldy #0
-       cpy nr_n
        beq +
        lda NET_REQ,y
        jsr net_put
        bcs .fail
        iny
        bne -
+       lda fs_dptr             ; the data
        sta p4
        lda fs_dptr+1
        sta p4+1
        lda fs_dlen
        sta nr_size
        lda fs_dlen+1
        sta nr_size+1
        ldy #0
.data:  lda nr_size
        ora nr_size+1
        beq .turn
        lda (p4),y
        jsr net_put
        bcs .fail
        iny
        bne +
        inc p4+1
+       lda nr_size
        bne +
        dec nr_size+1
+       dec nr_size
        jmp .data
.fail:  jmp .nowic
.turn:  lda #0                  ; the data is sent once only
        sta fs_dlen
        sta fs_dlen+1
        sta $dd03               ; port B in
        lda $dd00               ; PA2 low: we receive
        and #$fb
        sta $dd00
        jsr net_wait            ; the WiC64 has turned round
        bcc .bf166
        jmp .nowic
.bf166:
        lda $dd01               ; ready for the first byte
        jsr net_get             ; status, size
        bcs .nowic
        sta fs_status
        jsr net_get
        bcs .nowic
        sta nr_size
        jsr net_get
        bcs .nowic
        sta nr_size+1
        lda fs_rptr
        sta p4
        lda fs_rptr+1
        sta p4+1
        lda #0
        sta fs_rlen
        sta fs_rlen+1
        lda nr_prg              ; a program: its first two bytes say where
        beq .recv
        lda #0
        sta nr_prg
        jsr .count
        beq .recv
        jsr net_get
        bcs .nowic
        sta p4
        jsr .count
        beq .recv
        jsr net_get
        bcs .nowic
        sta p4+1
.recv:  jsr .count              ; the payload
        beq .done
        jsr net_get
        bcs .nowic
        ldx fs_rlen+1           ; room left?
        cpx fs_rmax+1
        bcc .keep
        bne .recv
        ldx fs_rlen
        cpx fs_rmax
        bcs .recv
.keep:  ldy #0
        sta (p4),y
        inc p4
        bne +
        inc p4+1
+       inc fs_rlen
        bne .recv
        inc fs_rlen+1
        jmp .recv
.done:  lda fs_status
        cmp #1                  ; carry set unless 0
        rts
.nowic: lda #0
        sta $dd03
        lda #FS_NOWIC64
        sta fs_status
        sec
        rts
; one byte less to come; Z set if there were none
.count: lda nr_size
        ora nr_size+1
        beq +
        lda nr_size
        bne ++
        dec nr_size+1
++      dec nr_size
        lda #1                  ; (Z clear)
+       rts

; ---------------------------------------------------------------------
; Building requests in NET_REQ
; ---------------------------------------------------------------------
; append the string at (q0) at X; X = the new end
!zone nr_path
nr_path0:
        ldy #0
-       lda (q0),y
        beq +
        sta NET_REQ,x
        inx
        iny
        cpy #NET_PATH_MAX
        bne -
+       rts
nr_path1:
        ldy #0
-       lda (q1),y
        beq +
        sta NET_REQ,x
        inx
        iny
        cpy #NET_PATH_MAX
        bne -
+       rts
; fs_off and fs_len at X
nr_offset:
        ldy #0
-       lda fs_off,y
        sta NET_REQ,x
        inx
        iny
        cpy #4
        bne -
        rts
; no data, no payload kept
nr_none:
        lda #0
        sta fs_dlen
        sta fs_dlen+1
        sta fs_rmax
        sta fs_rmax+1
        rts

; ---------------------------------------------------------------------
; The calls
; ---------------------------------------------------------------------
; fs_info: total and free KB and the share's name to (fs_rptr), fs_rmax
fs_info:
        lda #0
        sta fs_dlen
        sta fs_dlen+1
        ldx #0
        lda #FS_INFO
        jmp net_request

; fs_list: folder q0, entries from fs_first, at most fs_max of them, to
; (fs_rptr) (at most fs_rmax bytes)
fs_list:
        lda fs_first
        sta NET_REQ
        lda fs_first+1
        sta NET_REQ+1
        lda fs_max
        sta NET_REQ+2
        ldx #3
        jsr nr_path0
        lda #0
        sta fs_dlen
        sta fs_dlen+1
        lda #FS_LIST
        jmp net_request

; fs_read: fs_len bytes at fs_off of file q0 to (fs_rptr)
fs_read:
        lda fs_len
        sta fs_rmax
        lda fs_len+1
        sta fs_rmax+1
        ldx #0
        jsr nr_offset
        lda fs_len
        sta NET_REQ,x
        lda fs_len+1
        sta NET_REQ+1,x
        inx
        inx
        jsr nr_path0
        lda #0
        sta fs_dlen
        sta fs_dlen+1
        lda #FS_READ
        jmp net_request

; fs_load: the program file q0, to the address in its first two bytes
fs_load:
        lda #0
        ldx #3
-       sta fs_off,x
        dex
        bpl -
        lda #$ff
        sta fs_len
        sta fs_len+1
        lda #1
        sta nr_prg
        jmp fs_read

; fs_write: fs_dlen bytes from (fs_dptr) to file q0, mode fs_mode
; (FSW_REPLACE, FSW_AT fs_off, FSW_APPEND)
fs_write:
        ldx #0
        jsr nr_offset
        lda fs_mode
        sta NET_REQ+4
        ldx #6
        jsr nr_path0
        txa
        sec
        sbc #6
        sta NET_REQ+5           ; path length
        lda #0
        sta fs_rmax
        sta fs_rmax+1
        lda #FS_WRITE
        jmp net_request

; fs_delete, fs_mkdir: path q0
fs_delete:
        lda #FS_DELETE
        bne fs_onepath
fs_mkdir:
        lda #FS_MKDIR
fs_onepath:
        pha
        jsr nr_none
        ldx #0
        jsr nr_path0
        pla
        jmp net_request

; fs_stat: path q0 -> kind (1) and size (4) to (fs_rptr)
fs_stat:
        jsr nr_none
        lda #5
        sta fs_rmax
        ldx #0
        jsr nr_path0
        lda #FS_STAT
        jmp net_request

; fs_rename, fs_copy: q0 to q1
fs_rename:
        lda #FS_RENAME
        bne fs_twopaths
fs_copy:
        lda #FS_COPY
fs_twopaths:
        pha
        jsr nr_none
        ldx #1
        jsr nr_path0
        dex
        stx NET_REQ             ; length of the first path
        inx
        jsr nr_path1
        pla
        jmp net_request
