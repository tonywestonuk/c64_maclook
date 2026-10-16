; =====================================================================
; basic_tok.asm - tokenizing lines as BASIC V2 does, and listing them
;
; A line: [link 2][number 2][tokens][0], as the BASIC ROM wants it.
; Keywords are BASIC's tokens ($80-$cb) or ours ($cc on); numbers,
; names and anything else are kept as characters (names in capitals;
; the listing shows them in small letters).  Spaces are dropped, but a
; line's indent is kept.  After REM the rest of the line is kept as
; typed; so is DATA's, and a string's.  After NPU, the instruction's
; name follows in capitals.
;
; Line numbers are optional.  One typed as n is stored as n * 64, and
; so are the numbers after GOTO, GOSUB, THEN and RUN; lines without one
; get numbers in between (never a multiple of 64; see renumber).  So n
; can be 0 to 999.
; =====================================================================

TK_END     = $80
TK_DATA    = $83
TK_GOTO    = $89
TK_RUN     = $8a
TK_GOSUB   = $8d
TK_REM     = $8f
TK_ON      = $91
TK_PRINT   = $99
TK_TAB     = $a3
TK_TO      = $a4
TK_SPC     = $a6
TK_THEN    = $a7
TK_NOT     = $a8
TK_PLUS    = $aa
TK_MINUS   = $ab
TK_AND     = $af
TK_OR      = $b0
TK_GT      = $b1
TK_LT      = $b3
TK_SGN     = $b4        ; functions: SGN .. MID$
TK_MIDS    = $ca
TK_GO      = $cb

kw_x:   !text "CL", 'S'|$80, "PSE", 'T'|$80, "LIN", 'E'|$80
        !text "CIRCL", 'E'|$80, "BEE", 'P'|$80, "NP", 'U'|$80
        !text "EN", 'D'|$80, 0
op_tok: !text "+-*/^"           ; BASIC's operator tokens, $aa-$ae
        !byte 0, 0              ; (AND, OR)
        !text ">=<"             ; $b1-$b3

KW_ROM = $a09e          ; BASIC's keywords, read with the ROM banked in

; the ROMs in (for KW_ROM), interrupts off; and back (A kept)
rom_on: sei
        pha
        lda #$37
        sta $01
        pla
        rts
rom_off:
        pha
        lda #$35
        sta $01
        pla
        cli
        rts

; ---------------------------------------------------------------------
; crunch: ed_buf -> cr_buf (cr_len long).  Carry set (A/Y = a message)
; if it can't be done.
; ---------------------------------------------------------------------
cr_buf:  !fill 256
cr_len:  !byte 0
cr_y:    !byte 0        ; where the next byte goes
cr_ref:  !byte 0        ; the next number is a line number
cr_on:   !byte 0        ; in ON ... GOTO: so are the ones after commas
cr_x0:   !byte 0
cr_n:    !byte 0
cr_sp:   !byte 0

!zone crunch
crunch: tsx
        stx cr_sp
        lda #0
        sta cr_ref
        sta cr_on
        sta cr_buf              ; (the link: made later)
        sta cr_buf+1
        lda #1                  ; a line without its own number
        sta cr_buf+2
        lda #0
        sta cr_buf+3
        lda #4
        sta cr_y
        ldx #0                  ; the indent, kept
-       lda ed_buf,x
        cmp #' '
        bne +
        inx
        bne -
+       stx cr_x0
        jsr is_digit            ; a line number?
        bcs .indent
        jsr cr_uint
        lda zw                  ; 0-999
        cmp #<1000
        lda zw+1
        sbc #>1000
        bcs .big
        jsr zw_x64
        lda zw
        sta cr_buf+2
        lda zw+1
        sta cr_buf+3
-       lda ed_buf,x            ; (spaces after it don't count)
        cmp #' '
        bne .loop
        inx
        bne -
.indent:
        ldy #0
-       cpy cr_x0
        beq .loop
        lda #' '
        jsr cr_put
        iny
        bne -
.big:   lda #<str_e_lineno
        ldy #>str_e_lineno
        jmp cr_fail

.loop:  lda ed_buf,x
        bne +
        jmp .end
+       cmp #' '
        bne +
        inx
        bne .loop
+       cmp #'"'
        bne +
        jsr cr_string
        jmp .loop
+       cmp #$27                ; ' : a REM
        bne +
        lda #TK_REM
        jsr cr_put
        inx
        jmp .rest
+       cmp #'?'
        bne +
        lda #TK_PRINT
        jsr cr_put
        inx
        jmp .clear
+       cmp #':'
        bne +
        jsr cr_put
        inx
        lda #0
        sta cr_on
        jmp .clear
+       jsr is_digit
        bcc .num
        cmp #'.'
        beq .num
        jsr is_letter
        bcs +
        jmp .word
+       ldy #9                  ; an operator: its token
-       cmp op_tok,y
        beq +
        dey
        bpl -
        cmp #','                ; anything else as it is
        bne .raw
        jsr cr_put
        inx
        lda cr_on               ; ON x GOTO a, b, c
        beq .clear
        jmp .loop
.raw:   jsr cr_put
        inx
        jmp .clear
+       tya
        clc
        adc #TK_PLUS
        jsr cr_put
        inx
.clear: lda #0
        sta cr_ref
        jmp .loop

.num:   lda cr_ref
        beq .value
        jsr cr_uint             ; a line number: n * 64
        jsr zw_x64
        jsr cr_dec
        jmp .loop
.value: lda ed_buf,x            ; as typed: digits . E+-digits
        jsr is_digit
        bcc +
        cmp #'.'
        bne .clear
+       jsr cr_put
        inx
        jmp .value
        ; (E: in .word)

.word:  jsr cr_ident            ; cr_x0..x
        jsr kw_find             ; A = the token, carry clear
        bcc .bf208
        jmp .name
.bf208:
        cmp #X_FIRST            ; ours straight after THEN: a : between
        bcc +                   ; (BASIC runs what follows THEN itself)
        ldy cr_y
        pha
        lda cr_buf-1,y
        cmp #TK_THEN
        bne ++
        lda #':'
        jsr cr_put
++      pla
+       jsr cr_put
        cmp #TK_REM
        beq .rem
        cmp #TK_DATA
        beq .data
        cmp #TK_ON
        bne +
        sta cr_on
+       cmp #TK_GOTO
        beq .ref
        cmp #TK_GOSUB
        beq .ref
        cmp #TK_THEN
        beq .ref
        cmp #TK_RUN
        beq .ref
        cmp #TK_TO              ; GO TO
        bne +
        ldy cr_y
        lda cr_buf-2,y
        cmp #TK_GO
        beq .ref
+       cmp #TK_NPU
        bne .clr2
-       lda ed_buf,x            ; NPU: the instruction's name, in capitals
        cmp #' '
        bne .npul
        inx
        bne -
.npul:  lda ed_buf,x
        jsr is_letter
        bcs .clr2
        and #$df
        jsr cr_put
        inx
        bne .npul
.clr2:  jmp .clear
.ref:   lda #1
        sta cr_ref
        jmp .loop
.rem:   lda ed_buf,x            ; REM: the rest as it is
        cmp #' '
        bne .rest
        inx
.rest:  lda ed_buf,x
        beq .end
        jsr cr_put
        inx
        bne .rest
.data:  lda #0                  ; DATA: as it is, to a : outside quotes
        sta za
-       lda ed_buf,x
        beq .end
        cmp #'"'
        bne +
        lda za
        eor #1
        sta za
        lda #'"'
        bne ++
+       cmp #':'
        bne ++
        ldy za
        bne ++
        jmp .loop
++      jsr cr_put
        inx
        jmp -
.name:  ldy cr_x0               ; a name (or a number's E): in capitals
-       cpy cr_xe
        beq +
        lda ed_buf,y
        jsr upper
        jsr cr_put
        iny
        bne -
+       ldx cr_xe
        lda ed_buf-1,x          ; 1E-3: the sign after a number's E
        and #$df
        cmp #'E'
        bne +
        ldy cr_x0
        cpy #0
        beq +
        lda ed_buf-1,y
        jsr is_digit
        bcs +
        lda ed_buf,x
        cmp #'-'
        beq .sign
        cmp #'+'
        bne +
.sign:  jmp .loop               ; (the operator token, then the digits)
+       jmp .clear

.end:   lda #0
        jsr cr_put
        lda cr_y
        sta cr_len
        clc
        rts

; a string, quotes and all
cr_string:
        jsr cr_put
        inx
-       lda ed_buf,x
        beq +
        jsr cr_put
        inx
        cmp #'"'
        bne -
+       rts

; the line can't be made: A/Y = why
cr_fail:
        ldx cr_sp
        txs
        sec
        rts

; A to the end of cr_buf (A, X, Y kept)
!zone cr_put
cr_put: sty cp_y
        ldy cr_y
        cpy #250
        bcs +
        sta cr_buf,y
        inc cr_y
        ldy cp_y
        rts
+       lda #<str_e_long
        ldy #>str_e_long
        jmp cr_fail
cp_y:   !byte 0

; zw (0-999) * 64
zw_x64: ldy #6
-       asl zw
        rol zw+1
        dey
        bne -
        rts

; zw in decimal (X kept)
!zone cr_dec
cr_dec: stx cd_x
        lda zw
        ldx zw+1
        jsr utoa
        ldx #0
-       lda numbuf,x
        beq +
        jsr cr_put
        inx
        bne -
+       ldx cd_x
        rts
cd_x:   !byte 0

; zw = the decimal number at ed_buf,x (x moves past it)
!zone cr_uint
cr_uint:
        lda #0
        sta zw
        sta zw+1
.l:     lda ed_buf,x
        jsr is_digit
        bcs .out
        and #$0f
        pha
        lda zw                  ; zw = zw * 10 + digit
        asl
        sta za
        lda zw+1
        rol
        sta zb
        asl za
        rol zb
        clc
        lda za
        adc zw
        sta zw
        lda zb
        adc zw+1
        sta zw+1
        asl zw
        rol zw+1
        pla
        clc
        adc zw
        sta zw
        bcc +
        inc zw+1
+       inx
        bne .l
.out:   rts

; cr_ident: the word at ed_buf,x: cr_x0 = its start, cr_xe = x = after
; it (letters and digits, then perhaps $), cr_n = its length
!zone cr_ident
cr_ident:
        stx cr_x0
-       inx
        lda ed_buf,x
        jsr is_letter
        bcc -
        jsr is_digit
        bcc -
        cmp #'$'
        bne +
        inx
+       stx cr_xe
        txa
        sec
        sbc cr_x0
        sta cr_n
        rts
cr_xe:  !byte 0

; kw_find: is the word at cr_x0 (cr_n long) a keyword?  Carry clear and
; A = its token if so (TAB( and SPC( take their bracket too).  X kept
; (moved past the bracket).
!zone kw_find
kw_find:
        jsr rom_on
        lda #<KW_ROM
        sta pb
        lda #>KW_ROM
        sta pb+1
        lda #$80
        sta kf_t
        jsr .table
        jsr rom_off             ; (keeps the carry; interrupts back on)
        bcc .yes
        lda #<kw_x
        sta pb
        lda #>kw_x
        sta pb+1
        lda #X_FIRST
        sta kf_t
        jsr .table
        bcs .no
.yes:   lda kf_t
        cmp #TK_TAB             ; TAB(, SPC(: the bracket is theirs
        beq +
        cmp #TK_SPC
        bne .ok
+       lda ed_buf,x
        cmp #'('
        bne .nob
        inx
        stx cr_xe
.ok:    lda kf_t
        clc
        rts
.nob:   lda #<str_e_long        ; (TAB without its bracket: a name)
.no:    sec
        rts
; look in the table at pb (letters, the last with bit 7): carry clear,
; kf_t = the token, if it is there
.table: ldy #0
.next:  lda (pb),y
        beq .none
        sty kf_s                ; this entry starts here
        ldx cr_x0
.c:     lda ed_buf,x
        jsr upper
        sta kf_c
        lda (pb),y
        and #$7f
        cmp #'('                ; TAB( and SPC(: the word ends before (
        beq .end
        cmp kf_c
        bne .skip
        inx
        lda (pb),y
        iny
        asl
        bcc .c
        cpx cr_xe               ; the whole word?
        beq .found
        dey
.skip:  lda (pb),y              ; to the next entry
        iny
        asl
        bcc .skip
        inc kf_t
        jmp .next
.end:   cpx cr_xe
        bne .skip
.found: ldx cr_xe
        clc
        rts
.none:  ldx cr_xe
        sec
        rts
kf_t:   !byte 0
kf_s:   !byte 0
kf_c:   !byte 0

; character tests: carry clear if A is one (A kept)
is_digit:
        cmp #'0'
        bcc +
        cmp #'9'+1
        bcs +
        clc
        rts
+       sec
        rts
is_letter:
        pha
        and #$df
        cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        pla
        clc
        rts
+       pla
        sec
        rts
upper:  cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        and #$df
+       rts

; ---------------------------------------------------------------------
; detok: line pa listed into LS_BUF (ls_len long), with spaces where
; QuickBASIC puts them, the keywords' letters with bit 7 set, names in
; small letters
; ---------------------------------------------------------------------
ls_len:  !byte 0
dt_y:    !byte 0
dt_ps:   !byte 0        ; a space is due before the next thing
dt_val:  !byte 0        ; the last thing listed was a value
dt_fn:   !byte 0        ; .. a function (no space before its bracket)
dt_ref:  !byte 0        ; numbers are line numbers (/ 64)
dt_on:   !byte 0
dt_ind:  !byte 0

!zone detok
detok:  lda #0
        sta ls_len
        sta dt_ps
        sta dt_val
        sta dt_fn
        sta dt_ref
        sta dt_on
        ldy #2                  ; a number of its own (n * 64): n
        lda (pa),y
        and #63
        bne +
        lda (pa),y
        sta zw
        iny
        lda (pa),y
        sta zw+1
        ldx #6
-       lsr zw+1
        ror zw
        dex
        bne -
        jsr ls_zw
        lda #' '
        jsr ls_put
+       ldy #4
-       lda (pa),y              ; the indent
        cmp #' '
        bne +
        jsr ls_put
        iny
        bne -
+       lda ls_len
        sta dt_ind
.loop:  lda (pa),y
        bne +
        jmp .end
+       iny
        sty dt_y
        cmp #$80
        bcc .chr
        jmp .kw
.chr:   cmp #'"'
        bne +
        jsr .pend
        lda #'"'
-       jsr ls_put
        lda (pa),y
        beq .val
        iny
        cmp #'"'
        bne -
        jsr ls_put
.val:   sty dt_y
        lda #1
        sta dt_val
        lda #0
        sta dt_fn
        ldy dt_y
        jmp .loop
+       jsr is_digit
        bcc .num
        cmp #'.'
        beq .num
        jsr is_letter
        bcc .bf617
        jmp .other
.bf617:
        jsr .pend               ; a name: small letters
        dey
-       lda (pa),y
        jsr is_letter
        bcc +
        jsr is_digit
        bcs ++
+       ora #$20
        jsr .lpu
        iny
        bne -
++      cmp #'$'
        beq +
        cmp #'%'
        bne ++
+       jsr ls_put
        iny
++      sty dt_y
        lda #1
        sta dt_val
        sta dt_fn               ; (an array's bracket follows straight)
        jmp .loop
.num:   jsr .pend
        dey
        lda dt_ref
        beq .digits
        lda #0                  ; a line number: / 64
        sta zw
        sta zw+1
-       lda (pa),y
        jsr is_digit
        bcs +
        and #$0f
        pha
        jsr zw_x10
        pla
        clc
        adc zw
        sta zw
        bcc ++
        inc zw+1
++      iny
        bne -
+       sty dt_y
        ldx #6
-       lsr zw+1
        ror zw
        dex
        bne -
        jsr ls_zw
        ldy dt_y
        lda dt_on
        sta dt_ref
        jmp .val
.digits:
        lda (pa),y              ; digits . E and its sign
        jsr is_digit
        bcc +
        cmp #'.'
        beq +
        cmp #'E'
        beq .bf679
        jmp .val
.bf679:
        jsr ls_put
        iny
        lda (pa),y
        cmp #TK_MINUS
        bne ++
        lda #'-'
        bne +
++      cmp #TK_PLUS
        bne .digits
        lda #'+'
+       jsr ls_put
        iny
        bne .digits
.other: cmp #':'                ; (the : between THEN and ours: not shown)
        bne .o2
        lda (pa),y
        cmp #X_FIRST
        bcc .o1
        dey
        dey
        lda (pa),y
        iny
        iny
        cmp #TK_THEN
        bne .o1
        jmp .loop
.o1:    lda #':'
.o2:    cmp #','                ; punctuation
        beq +
        cmp #';'
        beq +
        cmp #':'
        bne .paren
        lda #0
        sta dt_on
        sta dt_ref
        lda #':'
+       jsr ls_put
        lda #1
        sta dt_ps
.nv:    lda #0
        sta dt_val
        sta dt_fn
        ldy dt_y
        jmp .loop
.paren: cmp #')'
        bne +
        jsr ls_put
        lda #0
        sta dt_ps
        lda #1
        sta dt_val
        lda #0
        sta dt_fn
        ldy dt_y
        jmp .loop
+       cmp #'('
        bne +
        ldx dt_fn
        bne ++
        jsr .pend
++      lda #0
        sta dt_ps
        lda #'('
        jsr ls_put
        jmp .nv
+       pha                     ; anything else
        jsr .pend
        pla
        jsr ls_put
        jmp .nv

.kw:    cmp #TK_PLUS            ; an operator
        bcc .word
        cmp #TK_LT+1
        bcs .word
        cmp #TK_AND
        beq .word
        cmp #TK_OR
        beq .word
        sec
        sbc #TK_PLUS
        tax
        lda op_tok,x
        ldx dt_val              ; after a value: spaces round it
        beq .unary
        pha
        jsr .space
        pla
        jsr ls_put
        cmp #'<'                ; <> <= >=
        beq .two
        cmp #'>'
        bne .op
.two:   ldy dt_y
        lda (pa),y
        cmp #TK_GT
        beq +
        cmp #TK_GT+1
        bne .op
+       sec
        sbc #TK_PLUS
        tax
        lda op_tok,x
        jsr ls_put
        inc dt_y
.op:    lda #1
        sta dt_ps
        jmp .nv
.unary: pha
        jsr .pend
        pla
        jsr ls_put
        jmp .nv
.word:  pha                     ; a keyword
        jsr .space
        pla
        pha
        jsr kw_put
        pla
        ldy dt_y
        cmp #TK_REM
        bne +
        lda #' '
        jsr ls_put
        jmp .rest
+       cmp #TK_DATA
        bne +
        lda #' '
        jsr ls_put
-       lda (pa),y              ; DATA: as it is, to a :
        bne .bf799
        jmp .end
.bf799:
        cmp #':'
        beq .nv0
        jsr ls_put
        iny
        bne -
.nv0:   sty dt_y
        jmp .nv
+       cmp #TK_NPU
        bne +
        lda #' '
        jsr ls_put
-       lda (pa),y              ; the instruction, in bold too
        jsr is_letter
        bcs ++
        ora #$80
        jsr ls_put
        iny
        bne -
++      sty dt_y
        lda #TK_NPU
+       ldx #0                  ; line numbers next?
        stx dt_ref
        cmp #TK_GOTO
        beq .ref
        cmp #TK_GOSUB
        beq .ref
        cmp #TK_THEN
        beq .ref
        cmp #TK_RUN
        beq .ref
        cmp #TK_ON
        bne +
        sta dt_on
+       cmp #TK_TO
        bne +
        ldx ls_len              ; (GO TO)
        lda LS_BUF-4,x
        cmp #'O'|$80
        bne +
.ref:   ldx #1
        stx dt_ref
+       ldx #0                  ; functions: ( straight after
        cmp #TK_SGN
        bcc +
        cmp #TK_MIDS+1
        bcs +
        inx
+       cmp #TK_TAB
        beq +
        cmp #TK_SPC
        bne ++
+       ldx #1
        stx dt_fn
        lda #0                  ; (their names end with the bracket)
        sta dt_ps
        sta dt_val
        ldy dt_y
        jmp .loop
++      stx dt_fn
        lda #1
        sta dt_ps
        lda #0
        sta dt_val
        ldy dt_y
        jmp .loop

.rest:  lda (pa),y              ; the rest of the line as it is
        beq .end
        jsr ls_put
        iny
        bne .rest
.end:   ldx ls_len              ; no spaces at the end
        beq +
        lda LS_BUF-1,x
        cmp #' '
        bne +
        dec ls_len
        bne .end
+       rts

; the space that is due, if any
.pend:  lda dt_ps
        beq +
        lda #0
        sta dt_ps
        lda #' '
        jmp ls_put
+       rts
; a space unless there is one already (or a bracket, or the indent)
.space: lda #0
        sta dt_ps
        ldx ls_len
        cpx dt_ind
        beq +
        lda LS_BUF-1,x
        cmp #' '
        beq +
        cmp #'('
        beq +
        lda #' '
        jmp ls_put
+       rts
; a letter of a name (keeps Y)
.lpu:   jmp ls_put

; zw = zw * 10
zw_x10: lda zw
        asl
        sta za
        lda zw+1
        rol
        sta zb
        asl za
        rol zb
        clc
        lda za
        adc zw
        sta zw
        lda zb
        adc zw+1
        sta zw+1
        asl zw
        rol zw+1
        rts

; zw in decimal to LS_BUF
ls_zw:  sty lz_y
        lda zw
        ldx zw+1
        jsr utoa
        ldx #0
-       lda numbuf,x
        beq +
        jsr ls_put
        inx
        bne -
+       ldy lz_y
        rts
lz_y:   !byte 0

; A to LS_BUF (as much as fits); A, X, Y kept
!zone ls_put
ls_put: stx lp_x
        ldx ls_len
        cpx #255
        bcs +
        sta LS_BUF,x
        inc ls_len
+       ldx lp_x
        rts
lp_x:   !byte 0

; keyword A's letters, with bit 7
!zone kw_put
kw_put: jsr rom_on
        ldx #<KW_ROM
        ldy #>KW_ROM
        sec
        sbc #$80
        cmp #X_FIRST-$80
        bcc +
        sbc #X_FIRST-$80
        ldx #<kw_x
        ldy #>kw_x
+       stx pb
        sty pb+1
        tax                     ; past X entries
        ldy #0
.skip:  txa
        beq .out
-       lda (pb),y
        iny
        asl
        bcc -
        dex
        jmp .skip
.out:   lda (pb),y
        pha
        ora #$80
        jsr ls_put
        iny
        pla
        bpl .out
        jmp rom_off

; ---------------------------------------------------------------------
; Drawing text in the small font
; ---------------------------------------------------------------------

!zone widths_init
widths_init:
        lda #1
        sta font
        lda #0
        sta dl_tmp+1
        lda #32
        sta za
-       lda za
        sta dl_tmp
        lda #<dl_tmp
        sta tstr
        lda #>dl_tmp
        sta tstr+1
        jsr text_width
        ldx za
        lda twidth
        sta wtab-32,x
        inc za
        bpl -
        rts

; A = the width of character A (bit 7: bold, one wider); X, Y kept
!zone char_width
char_width:
        sty cw_y
        cmp #$80
        and #$7f
        php
        sec
        sbc #32
        bcc .no
        tay
        lda wtab,y
        plp
        adc #0
        ldy cw_y
        rts
.no:    plp
        lda #0
        ldy cw_y
        rts
cw_y:   !byte 0

; draw_plain: the string A/Y at tx,ty
draw_plain:
        sta tstr
        sty tstr+1
        lda #1
        sta font
        lda #B_OR
        sta tmode
        jmp draw_text

; draw_listed: LS_BUF at tx,ty, its keywords in bold (the System font,
; a pixel higher so that the letters stand on the same line)
!zone draw_listed
draw_listed:
        lda #B_OR
        sta tmode
        ldx #0
.run:   stx dl_x
        cpx ls_len
        bne .bf1080
        jmp .out
.bf1080:
        lda LS_BUF,x            ; a run of plain or of bold letters
        and #$80
        sta dl_b
-       inx
        cpx ls_len
        beq +
        lda LS_BUF,x
        and #$80
        cmp dl_b
        beq -
+       stx dl_e
        lda LS_BUF,x            ; (ended with a 0 meanwhile)
        sta dl_c
        lda #0
        sta LS_BUF,x
        ldy dl_x                ; (bold: without bit 7, for the font)
        lda dl_b
        beq +
-       cpy dl_e
        beq +
        lda LS_BUF,y
        and #$7f
        sta LS_BUF,y
        iny
        bne -
+       clc
        lda #<LS_BUF
        adc dl_x
        sta tstr
        lda #>LS_BUF
        adc #0
        sta tstr+1
        lda #1                  ; plain: the small font
        ldx dl_b
        beq +
        lda #0                  ; bold: the System's, a pixel higher
        dec ty
+       sta font
        jsr draw_text
        lda dl_b
        beq +
        inc ty
        ldy dl_x                ; (bit 7 back)
-       cpy dl_e
        beq +
        lda LS_BUF,y
        ora #$80
        sta LS_BUF,y
        iny
        bne -
+       ldx dl_e
        lda dl_c
        sta LS_BUF,x
        clc
        lda tx
        adc twidth
        sta tx
        lda tx+1
        adc twidth+1
        sta tx+1
        ldx dl_e
        jmp .run
.out:   rts
dl_b:   !byte 0
dl_tmp: !fill 2
dl_x:   !byte 0
dl_e:   !byte 0
dl_c:   !byte 0
