; =====================================================================
; basic_npu.asm - NPU statements: the WiC64's matrix unit (docs/npu.md)
;
;   NPU LOAD r, A [, n]    array A into register r: A(i, j) is row i,
;                          column j (a one-dimensional array is a row);
;                          only the first n columns if n is given; the
;                          fixed-point format is chosen to fit
;   NPU STORE r, A [, f]   register r back into A (f fraction bits, 8)
;   NPU DEFINE s ... NPU END   the NPU statements between them are kept
;                          as script s instead of being run
;   NPU DRAW s             run script s; what it SENDs is drawn in the
;                          Output window (NPU SCREEN x, y, w, h: a part
;                          of it; the whole of it otherwise)
;   NPU <instruction> operands   any other instruction, as in npu.md,
;                          with numbers for axes and functions
;
; They run inside BASIC: the ROM works out the operands, and the
; requests go to the WiC64 through the System (sys_call).  The first
; NPU statement of a run empties the matrix unit (RESET).
; =====================================================================

QINT    = $bc9b         ; FAC to a 32 bit integer at $62-$65 (high first)
MOVFM_  = $bba2
MOVMF_  = $bbd4
FMULT_  = $ba28
GIVAYF  = $b391

npu_fresh:  !byte 0     ; nothing sent yet this run
npu_mode:   !byte 0     ; 1: in DEFINE (the script is in npu_def)
npu_dlen:   !byte 0
npu_placed: !byte 0     ; the WiC64 knows where the window is
npu_sx:     !byte 0     ; NPU SCREEN: the part of the content
npu_sy:     !byte 0
npu_sw:     !byte 0
npu_sh:     !byte 0
npu_full:   !byte 1     ; .. all of it
npu_ins:    !fill 24    ; an instruction being put together
npu_n:      !byte 0
npu_code:   !byte 0
no_i:       !byte 0
npu_def = cr_buf        ; DEFINE's script ([DEFINE s length] first)
NPU_DEF_MAX = 250

npu_begin:
        lda #1
        sta npu_fresh
        sta npu_full
        lda #0
        sta npu_mode
npu_unplaced:
        lda #0
        sta npu_placed
        rts

; the instructions: length, name, code, operands (r a byte, k a 16.16
; number, w a 16 bit number, a an angle in radians), 0; codes from $f0
; are done here
NS_LOAD   = $f0
NS_STORE  = $f1
NS_DEFINE = $f2
NS_END    = $f3
NS_SCREEN = $f4
NS_DRAW   = $f5
npu_names:
        !byte 4
        !text "LOAD"
        !byte NS_LOAD, 0
        !byte 5
        !text "STORE"
        !byte NS_STORE, 0
        !byte 4
        !text "FILL"
        !byte NPU_FILL
        !text "rrrk", 0
        !byte 5
        !text "IDENT"
        !byte NPU_IDENT
        !text "rr", 0
        !byte 5
        !text "RANGE"
        !byte NPU_RANGE
        !text "rrrkk", 0
        !byte 4
        !text "COPY"
        !byte NPU_COPY
        !text "rr", 0
        !byte 6
        !text "TRANSP"
        !byte NPU_TRANSP
        !text "rr", 0
        !byte 4
        !text "JOIN"
        !byte NPU_JOIN
        !text "rrrr", 0
        !byte 4
        !text "FREE"
        !byte NPU_FREE
        !text "r", 0
        !byte 5
        !text "RESET"
        !byte NPU_RESET, 0
        !byte 6
        !text "DEFINE"
        !byte NS_DEFINE, 0
        !byte 3
        !text "RUN"
        !byte NPU_RUN
        !text "r", 0
        !byte 5
        !text "CLOCK"
        !byte NPU_CLOCK
        !text "r", 0
        !byte 3
        !text "ADD"
        !byte NPU_ADD
        !text "rrr", 0
        !byte 3
        !text "SUB"
        !byte NPU_SUB
        !text "rrr", 0
        !byte 4
        !text "EMUL"
        !byte NPU_EMUL
        !text "rrr", 0
        !byte 4
        !text "EDIV"
        !byte NPU_EDIV
        !text "rrr", 0
        !byte 3
        !text "MUL"
        !byte NPU_MUL
        !text "rrr", 0
        !byte 5
        !text "SCALE"
        !byte NPU_SCALE
        !text "rrk", 0
        !byte 6
        !text "OFFSET"
        !byte NPU_OFFSET
        !text "rrk", 0
        !byte 5
        !text "APPLY"
        !byte NPU_APPLY
        !text "rrr", 0
        !byte 7
        !text "SOFTMAX"
        !byte NPU_SOFTMAX
        !text "rr", 0
        !byte 3
        !text "SUM"
        !byte NPU_SUM
        !text "rrr", 0
        !byte 6
        !text "ARGMAX"
        !byte NPU_ARGMAX
        !text "rr", 0
        !byte 4
        !text "PICK"
        !byte NPU_PICK
        !text "rrrr", 0
        !byte 6
        !text "ROTATE"
        !byte NPU_ROTATE
        !text "rra", 0
        !byte 7
        !text "PROJECT"
        !byte NPU_PROJECT
        !text "rrk", 0
        !byte 4
        !text "TURN"
        !byte NPU_TURN
        !text "rrrr", 0
        !byte 6
        !text "SCREEN"
        !byte NS_SCREEN, 0
        !byte 5
        !text "CLEAR"
        !byte NPU_CLEAR, 0
        !byte 5
        !text "LINES"
        !byte NPU_LINES
        !text "rrr", 0
        !byte 4
        !text "SEND"
        !byte NPU_SEND, 0
        !byte 3
        !text "END"
        !byte NS_END, 0
        !byte 4
        !text "DRAW"
        !byte NS_DRAW
        !text "r", 0
        !byte 0

; ---------------------------------------------------------------------
; NPU <instruction> ... (inside BASIC: TXTPTR at the name)
; ---------------------------------------------------------------------
!zone st_npu
st_npu: jsr npu_name            ; A = the code, pb = its operands
        sta npu_code
        lda npu_fresh           ; the first of this run: a clean start
        beq +
        lda #0
        sta npu_fresh
        lda #NPU_RESET
        sta npu_ins
        lda #1
        sta npu_n
        jsr npu_send
+       lda npu_code
        cmp #NS_LOAD
        bne +
        jmp npu_load
+       cmp #NS_STORE
        bne +
        jmp npu_store
+       cmp #NS_DEFINE
        bne +
        jmp npu_define
+       cmp #NS_END
        bne +
        jmp npu_enddef
+       cmp #NS_SCREEN
        bne +
        jmp npu_screen
+       cmp #NS_DRAW
        bne +
        jmp npu_draw_s
+       sta npu_ins             ; the code, then each operand
        lda #1
        sta npu_n
        lda #0
        sta no_i
.op:    ldy no_i
        lda (pb),y
        beq .done
        cpy #0
        beq +
        jsr CHKCOM
        ldy no_i
        lda (pb),y
+       inc no_i
        cmp #'r'
        bne +
        jsr GETBYT
        txa
        jsr npu_put
        jmp .op
+       cmp #'k'
        bne +
        jsr FRMNUM
        jsr npu_k
        jmp .op
+       cmp #'w'
        bne +
        jsr get_int
        jsr npu_put
        txa
        jsr npu_put
        jmp .op
+       jsr FRMNUM              ; a: radians -> 65536ths of a turn
        lda #<fp_rad2u
        ldy #>fp_rad2u
        jsr FMULT_
        jsr QINT
        lda $65
        jsr npu_put
        lda $64
        jsr npu_put
        jmp .op
.done:  ; run now, or keep for the script
        lda npu_mode
        bne +
        jmp npu_send
+       ldx #0
-       cpx npu_n
        beq +
        lda npu_ins,x
        jsr def_put
        inx
        bne -
+       rts

fp_rad2u: !byte $8e, $22, $f9, $83, $6e         ; 65536 / 2 pi

; A to the script being defined
def_put:
        ldy npu_dlen
        cpy #NPU_DEF_MAX
        bcs +
        sta npu_def+4,y
        inc npu_dlen
        rts
+       ldx #<str_e_npubig
        ldy #>str_e_npubig
        jmp our_error

; A to npu_ins (X, Y kept)
npu_put:
        sty np_y
        ldy npu_n
        sta npu_ins,y
        inc npu_n
        ldy np_y
        rts
np_y:   !byte 0

; a 16.16 number from FAC: 4 bytes, low first
!zone npu_k
npu_k:  lda FAC_EXP             ; * 65536
        beq +
        clc
        adc #16
        sta FAC_EXP
+       jsr QINT
        ldx #3
-       lda $62,x
        jsr npu_put
        dex
        bpl -
        rts

; the instruction's name (capitals, after NPU): A = its code, pb = its
; operands; TXTPTR after the name
!zone npu_name
npu_name:
        ldy #0
-       lda (BAS_TXTPTR),y
        cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        iny
        bne -
+       sty nn_len
        tya
        beq .syn
        lda #<npu_names
        sta pb
        lda #>npu_names
        sta pb+1
.next:  ldy #0
        lda (pb),y
        beq .syn
        cmp nn_len
        bne .skip
        ldy #0
-       lda (BAS_TXTPTR),y      ; the text's letter y, the table's y + 1
        iny
        cmp (pb),y
        bne .skip
        cpy nn_len
        bne -
        iny                     ; found: the code, then the operands
        lda (pb),y
        sta za
        iny
        tya
        clc
        adc pb
        sta pb
        bcc +
        inc pb+1
+       clc                     ; TXTPTR after the name
        lda BAS_TXTPTR
        adc nn_len
        sta BAS_TXTPTR
        bcc +
        inc BAS_TXTPTR+1
+       jsr CHRGOT_
        lda za
        rts
.skip:  ldy #0                  ; length + letters + code + operands + 0
        lda (pb),y
        clc
        adc #2
        tay
-       lda (pb),y
        beq +
        iny
        bne -
+       iny
        tya
        clc
        adc pb
        sta pb
        bcc .next
        inc pb+1
        bne .next
.syn:   jmp SNERR
nn_len: !byte 0

; ---------------------------------------------------------------------
; Sending (through the System); errors stop the program with the
; WiC64's message
; ---------------------------------------------------------------------
npu_send:
        lda #<npu_ins
        ldx #>npu_ins
        ldy npu_n
npu_send_ax:
        sta fs_dptr
        stx fs_dptr+1
        sty fs_dlen
        lda #0
        sta fs_dlen+1
npu_send_n:
        lda #0
        sta fs_rmax
        sta fs_rmax+1
        lda #<npu_run
        ldx #>npu_run
npu_sys:                        ; the System routine A/X, carry set on error
        sta sc_vec
        stx sc_vec+1
        jsr net_call
        bcs npu_fail
        rts

; a failed request: A = the status
!zone npu_fail
npu_fail:
        cmp #FS_NOWIC64
        bne +
        ldx #<str_e_nowic
        ldy #>str_e_nowic
        jmp our_error
+       lda #<npu_msg           ; the WiC64's message ($2A)
        sta fs_rptr
        lda #>npu_msg
        sta fs_rptr+1
        lda #60
        sta fs_rmax
        lda #0
        sta fs_rmax+1
        sta fs_dlen
        sta fs_dlen+1
        sta fs_rlen
        lda #<wic_request
        sta sc_vec
        lda #>wic_request
        sta sc_vec+1
        lda #$2a
        jsr net_call
        ldx #0                  ; "WiC64: " and the message
-       lda str_e_wic,x
        beq +
        sta npu_err,x
        inx
        bne -
+       ldy #0
-       cpy fs_rlen
        beq +
        lda npu_msg,y
        sta npu_err,x
        inx
        iny
        cpx #78
        bne -
+       lda #0
        sta npu_err,x
        ldx #<npu_err
        ldy #>npu_err
        jmp our_error
npu_msg: !fill 61
npu_err: !fill 80

; ---------------------------------------------------------------------
; DEFINE s ... END
; ---------------------------------------------------------------------
npu_define:
        lda npu_mode
        bne npu_syn
        jsr GETBYT
        stx npu_def+1
        lda #NPU_DEFINE
        sta npu_def
        lda #1
        sta npu_mode
        lda #0
        sta npu_dlen
        rts
npu_syn:
        jmp SNERR

npu_enddef:
        lda npu_mode
        beq npu_syn
        lda #0
        sta npu_mode
        lda npu_dlen
        sta npu_def+2
        lda #0
        sta npu_def+3
        lda npu_dlen
        clc
        adc #4
        tay
        lda #<npu_def
        ldx #>npu_def
        jmp npu_send_ax

; ---------------------------------------------------------------------
; SCREEN x, y, w, h (in the Output window's content)
; ---------------------------------------------------------------------
npu_screen:
        jsr GETBYT
        stx npu_sx
        jsr CHKCOM
        jsr GETBYT
        stx npu_sy
        jsr CHKCOM
        jsr GETBYT
        stx npu_sw
        jsr CHKCOM
        jsr GETBYT
        stx npu_sh
        lda #0
        sta npu_full
        sta npu_placed
        rts

; ---------------------------------------------------------------------
; DRAW s: SCREEN first if the WiC64 doesn't know where the window is,
; then RUN s; its SEND comes back in a burst into the screen
; ---------------------------------------------------------------------
!zone npu_draw_s
npu_draw_s:
        lda npu_mode
        bne npu_syn
        jsr need_front
        jsr GETBYT
        stx nd_s
        lda #0
        sta npu_n
        lda npu_placed
        bne .run
        lda #NPU_SCREEN
        jsr npu_put
        lda npu_full
        beq +
        lda #0                  ; the whole content
        sta npu_sx
        sta npu_sy
        sec
        lda out_x2
        sbc out_x1
        clc
        adc #1
        sta npu_sw
        lda out_y2
        sec
        sbc out_y1
        clc
        adc #1
        sta npu_sh
+       clc
        lda out_x1
        adc npu_sx
        jsr npu_put
        lda out_x1+1
        adc #0
        jsr npu_put
        clc
        lda out_y1
        adc npu_sy
        jsr npu_put
        lda #0
        jsr npu_put
        lda npu_sw              ; (256 wide: 0 and 1)
        jsr npu_put
        lda npu_sw
        bne +
        lda #1
        bne ++
+       lda #0
++      jsr npu_put
        lda npu_sh
        jsr npu_put
        lda #0
        jsr npu_put
.run:   lda #NPU_RUN
        jsr npu_put
        lda nd_s
        jsr npu_put
        lda #<npu_ins
        sta fs_dptr
        lda #>npu_ins
        sta fs_dptr+1
        lda npu_n
        sta fs_dlen
        lda #0
        sta fs_dlen+1
        sta fs_rmax
        sta fs_rmax+1
        lda #<npu_draw
        sta sc_vec
        lda #>npu_draw
        sta sc_vec+1
        jsr net_call
        bcs +
        lda #1
        sta npu_placed
        rts
+       cmp #FS_IOERR           ; a burst that made no sense: the window
        bne +                   ; white again, and it starts again
        lda #0
        sta npu_placed
        lda #<win_refresh
        sta sc_vec
        lda #>win_refresh
        sta sc_vec+1
        ldx out_win
        jmp sys_call
+       jmp npu_fail
nd_s:   !byte 0

; ---------------------------------------------------------------------
; Arrays: BASIC's own (DIM).  An array: [name 2][size 2][dimensions 1]
; [the dimensions' sizes, 2 bytes each, high first, the last one first]
; then the elements, 5 bytes each, the first subscript changing fastest.
; ---------------------------------------------------------------------
; the array named at TXTPTR: pa = its first element, na_rows x na_cols
!zone npu_array
npu_array:
        ldy #0                  ; its name: one or two letters (or digits)
        lda (BAS_TXTPTR),y
        cmp #'A'
        bcs .bf629
        jmp .syn
.bf629:
        cmp #'Z'+1
        bcc .bf631
        jmp .syn
.bf631:
        sta na_n1
        lda #0
        sta na_n2
-       jsr CHRGET              ; (more letters don't count)
        bcc +                   ; (a digit)
        cmp #'A'
        bcc ++
        cmp #'Z'+1
        bcs ++
+       ldx na_n2
        bne -
        sta na_n2
        jmp -
++      ldx #0
        cmp #'$'
        beq .syn
        cmp #'%'                ; whole numbers: BASIC marks the name
        bne +
        lda na_n1
        ora #$80
        sta na_n1
        lda na_n2
        ora #$80
        sta na_n2
        jsr CHRGET
        ldx #1
+       stx na_int
        lda $2f                 ; look for it from ARYTAB to STREND
        sta pa
        lda $30
        sta pa+1
.l:     lda pa
        cmp $31
        lda pa+1
        sbc $32
        bcs .none
        ldy #0
        lda (pa),y
        cmp na_n1
        bne .next
        iny
        lda (pa),y
        cmp na_n2
        beq .found
.next:  ldy #2
        lda (pa),y
        tax
        iny
        lda (pa),y
        tay
        txa
        clc
        adc pa
        sta pa
        tya
        adc pa+1
        sta pa+1
        jmp .l
.none:  ldx #<str_e_noarray
        ldy #>str_e_noarray
        jmp our_error
.syn:   jmp SNERR
.found: ldy #4
        lda (pa),y              ; dimensions
        cmp #1
        beq .one
        cmp #2
        bne .big
        ldy #5                  ; the second dimension's size (columns)
        lda (pa),y
        bne .big
        iny
        lda (pa),y
        sta na_cols
        iny                     ; the first's (rows)
        lda (pa),y
        bne .big
        iny
        lda (pa),y
        sta na_rows
        lda #9
        bne .elems
.one:   lda #1
        sta na_rows
        ldy #5
        lda (pa),y
        bne .big
        iny
        lda (pa),y
        sta na_cols
        lda #7
.elems: jmp pa_add
.big:   ldx #<str_e_npubig
        ldy #>str_e_npubig
        jmp our_error
na_n1:   !byte 0
na_n2:   !byte 0
na_rows: !byte 0
na_cols: !byte 0
na_int:  !byte 0        ; 1: whole numbers (2 bytes each, high first)

; pb = element (row na_i, column na_j): pa + (i + j * rows) * 5
!zone na_elem
na_elem:
        lda na_i                ; i + j * rows
        sta zw
        lda #0
        sta zw+1
        ldx na_j
        beq +
-       clc
        lda zw
        adc na_rows
        sta zw
        bcc ++
        inc zw+1
++      dex
        bne -
+       lda na_int              ; * 2 for whole numbers
        beq +
        asl zw
        rol zw+1
        jmp ++
+       lda zw                  ; * 5
        sta zc
        lda zw+1
        sta zd
        asl zw
        rol zw+1
        asl zw
        rol zw+1
        clc
        lda zw
        adc zc
        sta zw
        lda zw+1
        adc zd
        sta zw+1
++      clc
        lda pa
        adc zw
        sta pb
        lda pa+1
        adc zw+1
        sta pb+1
        rts
na_i:   !byte 0
na_j:   !byte 0

; the next element, row by row: carry set when there are no more
na_next:
        inc na_j
        lda na_j
        cmp na_cols
        bcc +
        lda #0
        sta na_j
        inc na_i
        lda na_i
        cmp na_rows
        bcc +
        rts
+       clc
        rts

; ---------------------------------------------------------------------
; LOAD r, A: rows x columns of 16 bit numbers, with as many fraction
; bits as the largest of them allows
; ---------------------------------------------------------------------
!zone npu_load
npu_load:
        jsr GETBYT
        stx nl_reg
        jsr CHKCOM
        jsr npu_array
        jsr CHRGOT_             ; [, columns]: only the first so many
        cmp #','
        bne +
        jsr CHRGET
        jsr GETBYT
        txa
        bne .bf798
        jmp .bad
.bf798:
        cpx na_cols
        beq ++
        bcc .bf801
        jmp .bad
.bf801:
++      stx na_cols
+       lda #0                  ; the largest exponent: the fraction bits
        sta nl_e
        sta na_i
        sta na_j
        sta nl_f
        lda na_int              ; (whole numbers: none)
        bne .put
-       jsr na_elem
        ldy #0
        lda (pb),y
        cmp nl_e
        bcc +
        sta nl_e
+       jsr na_next
        bcc -
        lda #15
        ldx nl_e
        beq +
        lda #143
        sec
        sbc nl_e
        bcs ++
        ldx #15                 ; too big for 16 bits: OVERFLOW
        jmp ROM_ERR
++      cmp #16
        bcc +
        lda #15
+       sta nl_f
.put:   lda npu_mode            ; room above the arrays for the request
        bne +
        jsr npu_room
+       lda $31                 ; where it goes: above the arrays
        sta nl_out
        lda $32
        sta nl_out+1
        lda #0
        sta nl_len
        sta nl_len+1
        lda #NPU_LOAD
        jsr nl_put
        lda nl_reg
        jsr nl_put
        lda na_rows
        jsr nl_put
        lda na_cols
        jsr nl_put
        lda nl_f
        ora #NPU_S16
        jsr nl_put
        lda #0
        sta na_i
        sta na_j
-       jsr na_elem             ; each: the element * 2^f, as a whole number
        lda na_int
        beq +
        ldy #1                  ; (a whole number already)
        lda (pb),y
        jsr nl_put
        ldy #0
        lda (pb),y
        jsr nl_put
        jmp .nxt
+       lda pb
        ldy pb+1
        jsr MOVFM_
        lda FAC_EXP
        beq +
        clc
        adc nl_f
        sta FAC_EXP
+       jsr AYINT_
        lda $65
        jsr nl_put
        lda $64
        jsr nl_put
.nxt:   jsr na_next
        bcc -
        lda npu_mode            ; for a script: there already
        beq +
        rts
+       sec                     ; send it
        lda nl_out
        sbc nl_len
        sta fs_dptr
        lda nl_out+1
        sbc nl_len+1
        sta fs_dptr+1
        lda nl_len
        sta fs_dlen
        lda nl_len+1
        sta fs_dlen+1
        jmp npu_send_n

.bad:   ldx #14                 ; ILLEGAL QUANTITY
        jmp ROM_ERR

; room between the arrays and the strings for rows x columns x 2 + 5
; bytes (BASIC's garbage collected first if there isn't)
!zone npu_room
npu_room:
        lda na_rows
        sta zw
        lda #0
        sta zw+1
        ldx na_cols             ; rows * columns
        dex
        beq +
-       clc
        lda zw
        adc na_rows
        sta zw
        bcc ++
        inc zw+1
++      dex
        bne -
+       asl zw                  ; * 2 + 5
        rol zw+1
        lda zw
        clc
        adc #5
        sta zw
        bcc +
        inc zw+1
+       jsr .free
        bcc .ok
        jsr $b526               ; GARBAG
        jsr .free
        bcc .ok
        ldx #16                 ; OUT OF MEMORY
        jmp ROM_ERR
.ok:    rts
; carry clear if FRETOP - STREND >= zw
.free:  sec
        lda $33
        sbc $31
        tax
        lda $34
        sbc $32
        tay
        txa
        cmp zw
        tya
        sbc zw+1
        bcc +
        clc
        rts
+       sec
        rts

; a byte of the LOAD: to the script, or above the arrays (if it fits)
!zone nl_put
nl_put: ldx npu_mode
        beq +
        jmp def_put
+       ldy #0
        sta (nl_out),y
        inc nl_out
        bne +
        inc nl_out+1
+       inc nl_len
        bne +
        inc nl_len+1
+       lda nl_out              ; still below the strings?
        cmp $33
        lda nl_out+1
        sbc $34
        bcs +
        rts
+       ldx #16                 ; OUT OF MEMORY
        jmp ROM_ERR
nl_reg:  !byte 0
nl_e:    !byte 0
nl_f:    !byte 0
nl_len:  !word 0

; ---------------------------------------------------------------------
; STORE r, A [, f]: the register back into the array
; ---------------------------------------------------------------------
!zone npu_store
npu_store:
        lda npu_mode
        beq +
        jmp SNERR
+       jsr GETBYT
        stx nl_reg
        jsr CHKCOM
        jsr npu_array
        lda #8
        sta nl_f
        jsr CHRGOT_
        cmp #','
        bne +
        jsr CHRGET
        jsr GETBYT
        cpx #16
        bcc ++
        ldx #14                 ; ILLEGAL QUANTITY
        jmp ROM_ERR
++      stx nl_f
+       jsr npu_room            ; (room for the answer)
        lda #NPU_STORE          ; STORE r, S16 + f
        sta npu_ins
        lda nl_reg
        sta npu_ins+1
        lda nl_f
        sta npu_ins+2
        lda #<npu_ins
        sta fs_dptr
        lda #>npu_ins
        sta fs_dptr+1
        lda #3
        sta fs_dlen
        lda #0
        sta fs_dlen+1
        lda $31                 ; the answer above the arrays
        sta fs_rptr
        sta nl_out
        lda $32
        sta fs_rptr+1
        sta nl_out+1
        sec
        lda $33
        sbc $31
        sta fs_rmax
        lda $34
        sbc $32
        sta fs_rmax+1
        lda #<npu_run
        ldx #>npu_run
        jsr npu_sys
        ldy #0                  ; rows, columns: as the array's
        lda (nl_out),y
        cmp na_rows
        bne .size
        iny
        lda (nl_out),y
        cmp na_cols
        bne .size
        lda #2
        clc
        adc nl_out
        sta nl_out
        bcc +
        inc nl_out+1
+       lda #0
        sta na_i
        sta na_j
-       jsr na_elem             ; each: signed 16 bits / 2^f
        lda na_int
        beq .flt
        ldy #0                  ; whole numbers: shifted down, high first
        lda (nl_out),y
        sta zc
        iny
        lda (nl_out),y
        ldx nl_f
        beq .sh
.shl:   cmp #$80
        ror
        ror zc
        dex
        bne .shl
.sh:    ldy #0
        sta (pb),y
        iny
        lda zc
        sta (pb),y
        jmp .on
.flt:   ldy #1
        lda (nl_out),y
        pha
        dey
        lda (nl_out),y
        tay
        pla
        jsr GIVAYF
        lda FAC_EXP
        beq +
        sec
        sbc nl_f
        beq ++                  ; (too small: 0)
        bcs +++
++      lda #0
+++     sta FAC_EXP
+       ldx pb
        ldy pb+1
        jsr MOVMF_
.on:    lda #2
        clc
        adc nl_out
        sta nl_out
        bcc +
        inc nl_out+1
+       jsr na_next
        bcc -
        rts
.size:  ldx #<str_e_npubig
        ldy #>str_e_npubig
        jmp our_error
