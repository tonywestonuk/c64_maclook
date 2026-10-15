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
FS_VOLUMES = $89
FS_CONNECT = $8a
FS_DISCONNECT = $8b

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
nr_burst: !byte 0       ; 1: the response is screen changes, in a burst (npu_draw)

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
        lda nr_burst
        beq +
        jmp nr_burst_recv
+       jsr net_get             ; status, size
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
        sta nr_burst
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
; npu_draw's response, in a burst: read after read, without waiting for
; FLAG2 (the WiC64 has each byte on the port before the next read, the
; quickest being 7 cycles later).  Status, size, then runs of bytes for
; the bitmap: offset (2; bit 15 set: 8 apart, along a pixel row), count,
; the bytes.  A run that would go outside the bitmap is not written; the
; rest is read and dropped, and the status is FS_IOERR.
; ---------------------------------------------------------------------
nb_hi:  !byte 0
nb_n:   !byte 0

!zone nr_burst_recv
nr_burst_recv:
        lda #0
        sta nr_burst
        lda $dd01               ; status
        sta fs_status
        lda $dd01               ; size
        sta nr_size
        lda $dd01
        sta nr_size+1
.run:   lda nr_size+1           ; a header left?
        bne .head
        lda nr_size
        bne +
        jmp .done
+       cmp #3
        bcs .head
        jmp .drop
.head:  lda $dd01               ; offset
        sta p4
        lda $dd01
        sta nb_hi
        lda $dd01               ; count
        sta nb_n
        sec                     ; the header is read
        lda nr_size
        sbc #3
        sta nr_size
        bcs +
        dec nr_size+1
+       sec                     ; are the bytes there?
        lda nr_size
        sbc nb_n
        tax
        lda nr_size+1
        sbc #0
        bcc .drop
        stx nr_size             ; (they will be)
        sta nr_size+1
        ldx nb_n
        beq .run
        dex                     ; the run's last byte: offset + (count - 1) * step
        stx t0
        lda #0
        sta t1
        bit nb_hi
        bpl +
        cpx #32                 ; (8 apart: at most 32)
        bcs .bad
        txa
        asl
        asl
        asl
        sta t0
        rol t1
+       lda nb_hi
        and #$1f
        sta p4+1
        clc
        lda p4
        adc t0
        lda p4+1
        adc t1
        cmp #>8000              ; below 8000?
        bcc .ok
        bne .bad
        clc
        lda p4
        adc t0
        cmp #<8000
        bcs .bad
.ok:    lda p4+1                ; in the bitmap
        ora #>BITMAP
        sta p4+1
        ldx nb_n
        ldy #0
        bit nb_hi
        bmi .eight
-       lda $dd01
        sta (p4),y
        iny
        dex
        bne -
        jmp .run
.eight: lda $dd01
        sta (p4),y
        tya
        clc
        adc #8
        tay
        dex
        bne .eight
        jmp .run
.bad:   clc                     ; not written: its bytes are dropped too
        lda nr_size
        adc nb_n
        sta nr_size
        bcc .drop
        inc nr_size+1
.drop:  lda nr_size             ; read what is left, and drop it
        ora nr_size+1
        beq .err
        lda $dd01
        lda nr_size
        bne +
        dec nr_size+1
+       dec nr_size
        jmp .drop
.err:   lda #FS_IOERR
        sta fs_status
.done:  lda fs_status
        cmp #1                  ; carry set unless 0
        rts

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
; fs_info: A = volume: total and free KB and its name to (fs_rptr), fs_rmax
fs_info:
        sta NET_REQ
        lda #0
        sta fs_dlen
        sta fs_dlen+1
        ldx #1
        lda #FS_INFO
        jmp net_request

; fs_volumes: the list of volumes to (fs_rptr), fs_rmax
fs_volumes:
        lda #0
        sta fs_dlen
        sta fs_dlen+1
        tax
        lda #FS_VOLUMES
        jmp net_request

; fs_connect, fs_disconnect: A = volume
fs_connect:
        ldx #FS_CONNECT
        bne +
fs_disconnect:
        ldx #FS_DISCONNECT
+       sta NET_REQ
        txa
        pha
        jsr nr_none
        ldx #1
        pla
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

; fs_stat: path q0 -> kind (1), size (4) and date (2) to (fs_rptr)
fs_stat:
        jsr nr_none
        lda #7
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

; ---------------------------------------------------------------------
; The WiC64's matrix unit (docs/npu.md): a program of instructions on
; its 32 matrix registers, run on the ESP32; it can keep scripts there
; ---------------------------------------------------------------------
NPU_COMMAND = $90       ; the WiC64 command
NPU_BURST   = $91       ; .. its response sent in a burst (npu_draw)

NPU_END     = $00       ; instructions
NPU_LOAD    = $01       ; r rows cols format data
NPU_STORE   = $02       ; r format -> rows cols data
NPU_FILL    = $03       ; r rows cols k
NPU_IDENT   = $04       ; r n
NPU_RANGE   = $05       ; r rows cols start step
NPU_COPY    = $06       ; d a
NPU_TRANSP  = $07       ; d a
NPU_JOIN    = $08       ; d a b how
NPU_FREE    = $09       ; r
NPU_RESET   = $0a
NPU_DEFINE  = $0b       ; s length(2) bytes: keep a script
NPU_RUN     = $0c       ; s: run it
NPU_CLOCK   = $0d       ; r: seconds since the last CLOCK
NPU_ADD     = $10       ; d a b
NPU_SUB     = $11       ; d a b
NPU_EMUL    = $12       ; d a b
NPU_EDIV    = $13       ; d a b
NPU_MUL     = $14       ; d a b
NPU_SCALE   = $15       ; d a k
NPU_OFFSET  = $16       ; d a k
NPU_APPLY   = $17       ; d a function
NPU_SOFTMAX = $18       ; d a
NPU_SUM     = $19       ; d a how
NPU_ARGMAX  = $1a       ; d a
NPU_PICK    = $1b       ; d a b row: elements of a, numbered by row of b
NPU_ROTATE  = $20       ; r axis angle
NPU_PROJECT = $21       ; d a k
NPU_TURN    = $22       ; d axis a i: rotation by element i of a (radians)
NPU_SCREEN  = $30       ; x(2) y(2) w(2) h(2): where to draw on the screen
NPU_CLEAR   = $31       ; white
NPU_LINES   = $32       ; p e m: lines between points, where mask m > 0
NPU_SEND    = $33       ; -> the bytes of the screen that changed
NPU_ALL     = 255       ; LINES: no mask

NPU_S16     = $00       ; formats (+ fraction bits)
NPU_S8      = $10
NPU_U8      = $20

NPU_X       = 0         ; ROTATE axes
NPU_Y       = 1
NPU_Z       = 2
NPU_PLANE   = 3

NPU_BESIDE  = 0         ; JOIN
NPU_BELOW   = 1

NPU_NEG     = 0         ; APPLY functions
NPU_ABS     = 1
NPU_RELU    = 2
NPU_SIGMOID = 3
NPU_TANH    = 4
NPU_SQRT    = 5
NPU_EXP     = 6
NPU_LOG     = 7
NPU_SIN     = 8
NPU_COS     = 9
NPU_ROUND   = 10
NPU_FLOOR   = 11
NPU_SQUARE  = 12
NPU_STEP    = 13        ; 1 above 0, else 0

NPU_BADPROG = 20        ; status codes
NPU_EMPTY   = 32
NPU_SIZES   = 33
NPU_MEMORY  = 34
NPU_TOOMUCH = 35

; npu_run: the program at (fs_dptr), fs_dlen bytes; the results to
; (fs_rptr), at most fs_rmax bytes, their length in fs_rlen
; npu_draw: as npu_run, for a program whose results are changes to the
; screen (SEND): they are received in a burst, straight into the bitmap
npu_draw:
        lda #1
        sta nr_burst
        lda #NPU_BURST
        bne wic_request
npu_run:
        lda #NPU_COMMAND
; wic_request: WiC64 command A, with fs_dlen bytes from (fs_dptr); the
; response to (fs_rptr), at most fs_rmax bytes
wic_request:
        ldx #0
        jmp net_request
