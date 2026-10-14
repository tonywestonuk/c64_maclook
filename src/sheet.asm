; =====================================================================
; sheet.asm - the spreadsheet
;
; Cells A1..G24.  Each cell has the text as typed (up to 15 characters),
; a type (empty, text, number, formula), a value (5 byte BASIC float),
; a format, and the string shown in the grid.  Formulas:
;
;   =expr   with + - * / ( ), numbers, cell references like B4, and
;           SUM / AVG / MIN / MAX / COUNT over a range like B4:D8
;
; Recalculation and formatting run with BASIC's zero page swapped in
; (fp_begin .. fp_end), so that code only uses absolute memory and the
; zero page bytes BASIC leaves free: $fb-$fe.
; =====================================================================

COLS    = 7
ROWS    = 24
NCELLS  = COLS*ROWS
CW      = 40            ; cell width
CH      = 10            ; cell height
RHW     = 20            ; row header width
FBH     = 15            ; formula bar height (line at FBH-1)
CHH     = 10            ; column header height
GT      = FBH+CHH       ; top of the grid
VROWS   = 14            ; visible rows
MAXTOP  = ROWS-VROWS
TEXTLEN = 15

T_EMPTY = 0
T_TEXT  = 1
T_NUM   = 2
T_FORM  = 3

F_ERR   = $01
F_FMT   = $30
FMT_GEN = $00
FMT_FIX = $10
FMT_INT = $20
FMT_CUR = $30

CL_SHEET = CL_APPBASE+0

SA_ABOUT = 0
SA_NEW   = 1
SA_QUIT  = 2
SA_UNDO  = 3
SA_CUT   = 4
SA_COPY  = 5
SA_PASTE = 6
SA_CLEAR = 7
SA_GEN   = 8
SA_FIX   = 9
SA_INT   = 10
SA_CUR   = 11
SA_CALC  = 12
SA_SHOWF = 13

SP_TXT  = $fb           ; pointers usable with BASIC's zero page in
SP_DST  = $fd

INT_    = $bccc         ; FAC = INT(FAC)
FCOMP   = $bc5b         ; compare FAC with mem(A/Y): A = 0 / 1 (FAC>) / $ff
GIVAYF  = $b391         ; FAC = signed int A (high) / Y (low)
FAC_SGN = $66


ss_classes:             ; draw, click, key, idle, close, edit, resize, scroll
        !word ss_draw, ss_click, ss_key, ss_idle, ss_close, nop_method, nop_method, ss_scroll

ss_win:     !byte 0
ss_sel:     !byte 0      ; selected cell
ss_top:     !byte 0      ; first visible row
ss_editing: !byte 0
ss_edit:    !fill 16     ; formula bar text while editing
ss_showf:   !byte 0      ; show formulas instead of values
ss_caret:   !byte 0
ss_ctime:   !byte 0
ss_quitting: !byte 0

; ---------------------------------------------------------------------
; Start-up
; ---------------------------------------------------------------------
!zone ss_init
ss_init:
        lda #0
        sta ss_editing
        sta ss_showf
        sta ss_top
        sta ss_sel
        sta ss_caret
        sta ss_pending
        jsr ss_tables
        jsr ss_load_sample
        lda #$ff                ; classify every cell, recalculate
        jsr ss_compute
        jsr win_alloc
        stx ss_win
        +winrect 2, 14, 317, 197
        lda #WF_CLOSE|WF_VSCROLL|WF_SHADOW
        sta w_flags,x
        lda #CL_SHEET
        sta w_class,x
        lda #<str_ss_title
        sta w_titl,x
        lda #>str_ss_title
        sta w_tith,x
        lda #MAXTOP
        sta w_maxscr,x
        lda #0
        sta w_scroll,x
        lda #1
        sta w_used,x
        jmp z_front

; address tables and empty cells
!zone ss_tables
ss_tables:
        lda #<ss_text
        sta q0
        lda #>ss_text
        sta q0+1
        lda #<ss_val
        sta q1
        lda #>ss_val
        sta q1+1
        lda #<ss_disp
        sta q2
        lda #>ss_disp
        sta q2+1
        ldx #0
.l:     lda q0
        sta ss_tlo,x
        lda q0+1
        sta ss_thi,x
        lda q1
        sta ss_vlo,x
        lda q1+1
        sta ss_vhi,x
        lda q2
        sta ss_dlo,x
        lda q2+1
        sta ss_dhi,x
        ldy #0
        tya
        sta ss_type,x
        sta ss_flags,x
        sta ss_dirty,x
        sta (q0),y
        sta (q2),y
        lda #16
        jsr .add0
        lda #5
        jsr .add1
        lda #12
        jsr .add2
        inx
        cpx #NCELLS
        bne .l
        rts
.add0:  clc
        adc q0
        sta q0
        bcc +
        inc q0+1
+       rts
.add1:  clc
        adc q1
        sta q1
        bcc +
        inc q1+1
+       rts
.add2:  clc
        adc q2
        sta q2
        bcc +
        inc q2+1
+       rts

; the sample worksheet: col, row (1-based), format, text
!macro cell .c, .r, .f, .t {
        !byte (.r-1)*COLS + .c, .f
        !text .t, 0
}
ss_sample:
        +cell 0, 1, FMT_GEN, "Budget 1987"
        +cell 0, 3, FMT_GEN, "Item"
        +cell 1, 3, FMT_GEN, "Jan"
        +cell 2, 3, FMT_GEN, "Feb"
        +cell 3, 3, FMT_GEN, "Mar"
        +cell 4, 3, FMT_GEN, "Total"
        +cell 5, 3, FMT_GEN, "Average"
        +cell 0, 4, FMT_GEN, "Rent"
        +cell 1, 4, FMT_FIX, "400"
        +cell 2, 4, FMT_FIX, "400"
        +cell 3, 4, FMT_FIX, "400"
        +cell 0, 5, FMT_GEN, "Food"
        +cell 1, 5, FMT_FIX, "120"
        +cell 2, 5, FMT_FIX, "135.5"
        +cell 3, 5, FMT_FIX, "110"
        +cell 0, 6, FMT_GEN, "Disks"
        +cell 1, 6, FMT_FIX, "30"
        +cell 2, 6, FMT_FIX, "45"
        +cell 3, 6, FMT_FIX, "19.95"
        +cell 0, 7, FMT_GEN, "Software"
        +cell 1, 7, FMT_FIX, "80"
        +cell 2, 7, FMT_FIX, "0"
        +cell 3, 7, FMT_FIX, "59.9"
        +cell 0, 8, FMT_GEN, "Mags"
        +cell 1, 8, FMT_FIX, "4.5"
        +cell 2, 8, FMT_FIX, "4.5"
        +cell 3, 8, FMT_FIX, "4.5"
        +cell 4, 4, FMT_FIX, "=SUM(B4:D4)"
        +cell 4, 5, FMT_FIX, "=SUM(B5:D5)"
        +cell 4, 6, FMT_FIX, "=SUM(B6:D6)"
        +cell 4, 7, FMT_FIX, "=SUM(B7:D7)"
        +cell 4, 8, FMT_FIX, "=SUM(B8:D8)"
        +cell 5, 4, FMT_FIX, "=AVG(B4:D4)"
        +cell 5, 5, FMT_FIX, "=AVG(B5:D5)"
        +cell 5, 6, FMT_FIX, "=AVG(B6:D6)"
        +cell 5, 7, FMT_FIX, "=AVG(B7:D7)"
        +cell 5, 8, FMT_FIX, "=AVG(B8:D8)"
        +cell 0, 10, FMT_GEN, "Total"
        +cell 1, 10, FMT_CUR, "=SUM(B4:B8)"
        +cell 2, 10, FMT_CUR, "=SUM(C4:C8)"
        +cell 3, 10, FMT_CUR, "=SUM(D4:D8)"
        +cell 4, 10, FMT_CUR, "=SUM(E4:E8)"
        +cell 0, 12, FMT_GEN, "Income"
        +cell 1, 12, FMT_CUR, "700"
        +cell 2, 12, FMT_CUR, "700"
        +cell 3, 12, FMT_CUR, "700"
        +cell 4, 12, FMT_CUR, "=SUM(B12:D12)"
        +cell 0, 13, FMT_GEN, "Left"
        +cell 1, 13, FMT_CUR, "=B12-B10"
        +cell 2, 13, FMT_CUR, "=C12-C10"
        +cell 3, 13, FMT_CUR, "=D12-D10"
        +cell 4, 13, FMT_CUR, "=E12-E10"
        +cell 0, 15, FMT_GEN, "Biggest"
        +cell 1, 15, FMT_FIX, "=MAX(B4:D8)"
        +cell 0, 16, FMT_GEN, "Smallest"
        +cell 1, 16, FMT_FIX, "=MIN(B4:D8)"
        +cell 0, 17, FMT_GEN, "Entries"
        +cell 1, 17, FMT_GEN, "=COUNT(B4:D8)"
        !byte $ff

!zone ss_load_sample
ss_load_sample:
        lda #<ss_sample
        sta q0
        lda #>ss_sample
        sta q0+1
.e:     ldy #0
        lda (q0),y
        cmp #$ff
        beq .done
        tax
        iny
        lda (q0),y
        sta ss_flags,x
        lda ss_tlo,x
        sta q1
        lda ss_thi,x
        sta q1+1
        clc
        lda q0
        adc #2
        sta q0
        bcc +
        inc q0+1
+       jsr strcpy              ; q0 -> q1, Y = length
        iny
        tya
        clc
        adc q0
        sta q0
        bcc .e
        inc q0+1
        jmp .e
.done:  rts

; ---------------------------------------------------------------------
; Calculation (BASIC's zero page and ROMs are active in here)
; A = cell to classify again ($ff = all, $fe = none), then recalculate
; every formula and reformat every number.
; ---------------------------------------------------------------------
ss_reparse: !byte 0
ss_pass:    !byte 0
ss_changed: !byte 0
ss_i:       !byte 0
ss_ci:      !byte 0
ss_cur:     !byte 0
ss_errsp:   !byte 0
ss_pi:      !byte 0
ss_vsp:     !byte 0
ss_vstk:    !fill 5*10
ss_tmp:     !fill 5
ss_c100:    !fill 5
ss_chalf:   !fill 5
str_c100:   !text "100", 0
str_chalf:  !text ".5", 0

!zone ss_compute
ss_compute:
        sta ss_reparse
        lda #CUR_WATCH
        jsr set_cursor
        jsr fp_begin
        lda #<ss_err
        sta $0300
        lda #>ss_err
        sta $0301
        ; constants
        lda #<str_c100
        ldy #>str_c100
        jsr ss_fin_str
        ldx #<ss_c100
        ldy #>ss_c100
        jsr MOVMF
        lda #<str_chalf
        ldy #>str_chalf
        jsr ss_fin_str
        ldx #<ss_chalf
        ldy #>ss_chalf
        jsr MOVMF
        ; classify
        lda ss_reparse
        cmp #$fe
        beq .calc
        cmp #$ff
        bne .one
        ldx #0
-       stx ss_i
        jsr ss_classify_safe
        bcc +
        ldx ss_i                ; (a number too big: keep it as text)
        lda #T_TEXT
        sta ss_type,x
+       ldx ss_i
        inx
        cpx #NCELLS
        bne -
        jmp .calc
.one:   tax
        jsr ss_classify_safe
.calc:  lda #8                  ; until nothing changes (or a loop)
        sta ss_pass
.pass:  lda #0
        sta ss_changed
        ldx #0
.c:     lda ss_type,x
        cmp #T_FORM
        bne .n
        stx ss_i
        jsr ss_eval_cell
        ldx ss_i
        bcc .ok
        lda ss_flags,x
        and #F_ERR
        bne .n
        lda ss_flags,x
        ora #F_ERR
        sta ss_flags,x
        inc ss_changed
        jmp .n
.ok:    lda ss_flags,x
        and #F_ERR
        beq .n
        lda ss_flags,x
        and #$ff-F_ERR
        sta ss_flags,x
        inc ss_changed
.n:     inx
        cpx #NCELLS
        bne .c
        lda ss_changed
        beq .done
        dec ss_pass
        bne .pass
.done:  jsr ss_format_all
        jsr fp_end
        lda #CUR_ARROW
        jmp set_cursor

; FAC = number in the string A/Y
ss_fin_str:
        sta TXTPTR
        sty TXTPTR+1
        jsr CHRGOT
        jmp FIN

; errors (ours, and BASIC's through $0300) unwind to the caller of the
; routine that set ss_errsp
ss_err:
        ldx ss_errsp
        txs
        sec
        rts

; work out what kind of cell X is (carry set if a number overflowed)
ss_classify_safe:
        stx ss_ci
        tsx
        stx ss_errsp
        jsr ss_classify
        clc
        rts

!zone ss_classify
ss_classify:
        ldx ss_ci
        lda ss_tlo,x
        sta SP_TXT
        lda ss_thi,x
        sta SP_TXT+1
        ldy #0
        lda (SP_TXT),y
        bne +
        lda #T_EMPTY
        jmp .set
+       cmp #'='
        bne +
        lda #T_FORM
        jmp .set
+       ; only number characters, with at least one digit?
        lda #0
        sta ss_tmp
-       lda (SP_TXT),y
        beq .chk
        cmp #' '
        beq .nc
        cmp #'.'
        beq .nc
        cmp #'-'
        beq .nc
        cmp #'+'
        beq .nc
        cmp #'E'
        beq .nc
        cmp #'0'
        bcc .text
        cmp #'9'+1
        bcs .text
        inc ss_tmp
.nc:    iny
        bne -
.chk:   lda ss_tmp
        beq .text
        lda SP_TXT
        ldy SP_TXT+1
        jsr ss_fin_str
        ldy #0                  ; FIN must have used it all
        lda (TXTPTR),y
        bne .text
        ldx ss_ci
        lda ss_vlo,x
        ldy ss_vhi,x
        tax
        jsr MOVMF
        lda #T_NUM
        jmp .set
.text:  lda #T_TEXT
.set:   ldx ss_ci
        sta ss_type,x
        lda ss_flags,x
        and #$ff-F_ERR
        sta ss_flags,x
        rts

; evaluate formula cell X.  Carry set on error.
!zone ss_eval_cell
ss_eval_cell:
        stx ss_cur
        tsx
        stx ss_errsp
        ldx ss_cur
        clc
        lda ss_tlo,x
        adc #1                  ; skip the '='
        sta SP_TXT
        lda ss_thi,x
        adc #0
        sta SP_TXT+1
        lda #0
        sta ss_pi
        sta ss_vsp
        jsr ss_expr
        jsr ss_peek
        cmp #0
        beq +
        jmp ss_err              ; something left over
+       ldx #<ss_tmp
        ldy #>ss_tmp
        jsr MOVMF
        ldx ss_cur
        lda ss_vlo,x
        sta SP_DST
        lda ss_vhi,x
        sta SP_DST+1
        ldy #4
-       lda ss_tmp,y
        cmp (SP_DST),y
        bne .diff
        dey
        bpl -
        clc
        rts
.diff:  ldy #4
-       lda ss_tmp,y
        sta (SP_DST),y
        dey
        bpl -
        inc ss_changed
        clc
        rts

; next non-space character, upper case -> A (0 at the end)
ss_peek:
        ldy ss_pi
-       lda (SP_TXT),y
        cmp #' '
        bne +
        iny
        bne -
+       sty ss_pi
        cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        and #$df
+       rts

ss_next:
        inc ss_pi
        rts

; value stack: push FAC / pop -> A/Y = address of the popped value
ss_push:
        lda ss_vsp
        cmp #5*9
        bcc +
        jmp ss_err
+       clc
        adc #<ss_vstk
        tax
        lda #>ss_vstk
        adc #0
        tay
        jsr MOVMF
        lda ss_vsp
        clc
        adc #5
        sta ss_vsp
        rts
ss_pop:
        lda ss_vsp
        sec
        sbc #5
        sta ss_vsp
        clc
        adc #<ss_vstk
        pha
        lda #>ss_vstk
        adc #0
        tay
        pla
        rts

; expr := term {(+|-) term}
!zone ss_expr
ss_expr:
        jsr ss_term
.l:     jsr ss_peek
        cmp #'+'
        beq .add
        cmp #'-'
        beq .sub
        rts
.add:   jsr ss_next
        jsr ss_push
        jsr ss_term
        jsr ss_pop
        jsr FADD
        jmp .l
.sub:   jsr ss_next
        jsr ss_push
        jsr ss_term
        jsr ss_pop
        jsr FSUB                ; left - right
        jmp .l

; term := factor {(*|/) factor}
!zone ss_term
ss_term:
        jsr ss_factor
.l:     jsr ss_peek
        cmp #'*'
        beq .mul
        cmp #'/'
        beq .div
        rts
.mul:   jsr ss_next
        jsr ss_push
        jsr ss_factor
        jsr ss_pop
        jsr FMULT
        jmp .l
.div:   jsr ss_next
        jsr ss_push
        jsr ss_factor
        lda FAC_EXP             ; dividing by zero
        bne +
        jmp ss_err
+       jsr ss_pop
        jsr FDIV                ; left / right
        jmp .l

; factor := number | cell | function(range) | (expr) | -factor
!zone ss_factor
ss_factor:
        jsr ss_peek
        cmp #'-'
        bne +
        jsr ss_next
        jsr ss_factor
        lda FAC_EXP
        beq ++
        lda FAC_SGN
        eor #$ff
        sta FAC_SGN
++      rts
+       cmp #'+'
        bne +
        jsr ss_next
        jmp ss_factor
+       cmp #'('
        bne +
        jsr ss_next
        jsr ss_expr
        jsr ss_peek
        cmp #')'
        bne .bad
        jmp ss_next
+       cmp #'.'
        beq .num
        cmp #'0'
        bcc .bad
        cmp #'9'+1
        bcc .num
        cmp #'A'
        bcc .bad
        cmp #'Z'+1
        bcs .bad
        ; a letter: a cell if a digit follows, else a function
        iny
        lda (SP_TXT),y
        cmp #'0'
        bcc .func
        cmp #'9'+1
        bcs .func
        jsr ss_cellref
        jmp ss_load_cell
.func:  jmp ss_function
.num:   clc
        lda SP_TXT
        adc ss_pi
        sta TXTPTR
        lda SP_TXT+1
        adc #0
        sta TXTPTR+1
        jsr CHRGOT
        jsr FIN
        sec
        lda TXTPTR
        sbc SP_TXT
        sta ss_pi
        rts
.bad:   jmp ss_err

; cell reference at the parse position -> X = cell, ss_c / ss_r
ss_c:   !byte 0
ss_r:   !byte 0
!zone ss_cellref
ss_cellref:
        jsr ss_peek
        sec
        sbc #'A'
        cmp #COLS
        bcs .bad
        sta ss_c
        jsr ss_next
        lda #0
        sta ss_r
        ldy ss_pi
-       lda (SP_TXT),y
        cmp #'0'
        bcc +
        cmp #'9'+1
        bcs +
        and #$0f
        pha
        lda ss_r                ; r = r*10 + digit
        asl
        asl
        adc ss_r
        asl
        sta ss_r
        pla
        clc
        adc ss_r
        sta ss_r
        iny
        bne -
+       sty ss_pi
        lda ss_r
        beq .bad
        cmp #ROWS+1
        bcs .bad
        dec ss_r                ; 0-based
        lda ss_r                ; cell = row*7 + col
        asl
        asl
        asl
        sec
        sbc ss_r
        clc
        adc ss_c
        tax
        rts
.bad:   jmp ss_err

; FAC = value of cell X (text and empty cells count as 0)
ss_load_cell:
        lda ss_type,x
        cmp #T_NUM
        bcc .zero
        lda ss_flags,x
        and #F_ERR
        beq +
        jmp ss_err
+       lda ss_vlo,x
        ldy ss_vhi,x
        jmp MOVFM
.zero:  lda #0
        sta FAC_EXP
        rts

; SUM / AVG / MIN / MAX / COUNT ( range )
ss_fname:  !fill 8
ss_fn:     !byte 0
ss_c1:     !byte 0
ss_r1:     !byte 0
ss_c2:     !byte 0
ss_r2:     !byte 0
ss_count:  !byte 0
ss_first:  !byte 0
ss_cc:     !byte 0
ss_rr:     !byte 0
ss_fnames: !text "SUM",0,0,0,0,0, "AVG",0,0,0,0,0, "AVERAGE",0, "MIN",0,0,0,0,0
           !text "MAX",0,0,0,0,0, "COUNT",0,0,0
SS_NFN = 6
ss_fncode: !byte 0, 1, 1, 2, 3, 4

!zone ss_function
ss_function:
        ; name (letters)
        ldx #0
-       jsr ss_peek
        cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        cpx #7
        bcs .bad
        sta ss_fname,x
        inx
        jsr ss_next
        jmp -
+       lda #0
        sta ss_fname,x
        ; look it up
        ldx #0
.find:  stx ss_fn
        txa
        asl
        asl
        asl
        tay
        ldx #0
-       lda ss_fnames,y
        cmp ss_fname,x
        bne .nextfn
        cmp #0
        beq .found
        iny
        inx
        bne -
.nextfn:
        ldx ss_fn
        inx
        cpx #SS_NFN
        bne .find
.bad:   jmp ss_err
.found: ldx ss_fn
        lda ss_fncode,x
        sta ss_fn
        jsr ss_peek
        cmp #'('
        bne .bad
        jsr ss_next
        jsr ss_cellref
        lda ss_c
        sta ss_c1
        sta ss_c2
        lda ss_r
        sta ss_r1
        sta ss_r2
        jsr ss_peek
        cmp #':'
        bne +
        jsr ss_next
        jsr ss_cellref
        lda ss_c
        sta ss_c2
        lda ss_r
        sta ss_r2
+       jsr ss_peek
        cmp #')'
        bne .bad
        jsr ss_next
        ; put the corners in order
        lda ss_c1
        cmp ss_c2
        bcc +
        ldx ss_c2
        sta ss_c2
        stx ss_c1
+       lda ss_r1
        cmp ss_r2
        bcc +
        ldx ss_r2
        sta ss_r2
        stx ss_r1
+       lda #0
        sta FAC_EXP
        sta ss_count
        lda #1
        sta ss_first
        lda ss_r1
        sta ss_rr
.row:   lda ss_c1
        sta ss_cc
.col:   lda ss_rr               ; cell = row*7 + col
        asl
        asl
        asl
        sec
        sbc ss_rr
        clc
        adc ss_cc
        tax
        lda ss_type,x
        cmp #T_NUM
        bcc .skip
        lda ss_flags,x
        and #F_ERR
        beq +
        jmp ss_err
+       inc ss_count
        lda ss_fn
        cmp #2
        bcs .minmax
        lda ss_vlo,x            ; SUM and AVG
        ldy ss_vhi,x
        jsr FADD
        jmp .skip
.minmax:
        cmp #4
        beq .skip               ; COUNT
        lda ss_first
        beq +
        lda #0
        sta ss_first
        lda ss_vlo,x
        ldy ss_vhi,x
        jsr MOVFM
        jmp .skip
+       stx ss_i2
        lda ss_vlo,x
        ldy ss_vhi,x
        jsr FCOMP               ; A = 1 if FAC > cell, $ff if FAC < cell
        ldx ss_fn
        cpx #2
        bne .max
        cmp #1                  ; MIN: take the cell if FAC is bigger
        bne .skip
        beq .take
.max:   cmp #$ff                ; MAX: take the cell if FAC is smaller
        bne .skip
.take:  ldx ss_i2
        lda ss_vlo,x
        ldy ss_vhi,x
        jsr MOVFM
.skip:  inc ss_cc
        lda ss_cc
        cmp ss_c2
        bne .bf918
        jmp .col
.bf918:
        bcs .bf919
        jmp .col
.bf919:
        inc ss_rr
        lda ss_rr
        cmp ss_r2
        bne .bf923
        jmp .row
.bf923:
        bcs .bf924
        jmp .row
.bf924:
        ; finish
        lda ss_fn
        cmp #1
        bne .notavg
        lda ss_count
        beq .zero
        jsr ss_push             ; sum / count
        ldy ss_count
        lda #0
        jsr GIVAYF
        jsr ss_pop
        jmp FDIV
.notavg:
        cmp #4
        bne +
        ldy ss_count
        lda #0
        jmp GIVAYF
+       rts
.zero:  lda #0
        sta FAC_EXP
        rts
ss_i2:  !byte 0

; ---------------------------------------------------------------------
; Formatting: every number's display string, marking cells that changed
; ---------------------------------------------------------------------
ss_dbuf:  !fill 16
ss_fi:    !byte 0
ss_ff:    !byte 0
ss_neg:   !byte 0
ss_nd:    !byte 0
ss_nt:    !byte 0
ss_npad:  !byte 0
ss_ni:    !byte 0
str_err:  !text "#ERR", 0

!zone ss_format_all
ss_format_all:
        ldx #0
.l:     stx ss_fi
        lda ss_type,x
        cmp #T_NUM
        bcc .next
        lda ss_flags,x
        and #F_ERR
        beq +
        ldy #4
-       lda str_err,y
        sta ss_dbuf,y
        dey
        bpl -
        jmp .cmp
+       lda ss_vlo,x
        ldy ss_vhi,x
        jsr MOVFM
        ldx ss_fi
        lda ss_flags,x
        and #F_FMT
        jsr ss_fmt
.cmp:   ldx ss_fi
        lda ss_dlo,x
        sta SP_DST
        lda ss_dhi,x
        sta SP_DST+1
        ldy #0
-       lda ss_dbuf,y
        cmp (SP_DST),y
        bne .copy
        cmp #0
        beq .next
        iny
        bne -
.copy:  ldy #0
-       lda ss_dbuf,y
        sta (SP_DST),y
        beq +
        iny
        cpy #11
        bne -
        lda #0
        sta (SP_DST),y
+       lda #1
        sta ss_dirty,x
.next:  ldx ss_fi
        inx
        cpx #NCELLS
        bne .l
        rts

; FAC -> ss_dbuf in format A
!zone ss_fmt
ss_fmt:
        sta ss_ff
        cmp #FMT_GEN
        bne .rounded
        jsr FOUT
        ldx #0                  ; without the leading space
        ldy #0
        lda $0100
        cmp #' '
        bne +
        iny
+
-       lda $0100,y
        sta ss_dbuf,x
        beq +
        iny
        inx
        cpx #15
        bne -
        lda #0
        sta ss_dbuf,x
+       ; long decimals: cut to 7 characters (no exponent)
        cpx #8
        bcc .out
        ldy #0
-       lda ss_dbuf,y
        cmp #'E'
        beq .out
        cmp #'.'
        beq .cut
        iny
        cpy #7
        bne -
        jmp .out
.cut:   lda #0
        sta ss_dbuf+7
        lda ss_dbuf+6
        cmp #'.'
        bne .out
        lda #0
        sta ss_dbuf+6
.out:   rts
.rounded:
        lda FAC_SGN
        ldx FAC_EXP
        bne +
        lda #0
+       sta ss_neg
        lda #0                  ; |x|
        sta FAC_SGN
        lda ss_ff
        cmp #FMT_INT
        beq +
        lda #<ss_c100           ; two decimals: x * 100
        ldy #>ss_c100
        jsr FMULT
+       lda #<ss_chalf          ; round
        ldy #>ss_chalf
        jsr FADD
        jsr INT_
        jsr FOUT                ; " 12345"
        ldx #0
        lda ss_neg
        bpl +
        lda #'-'
        sta ss_dbuf,x
        inx
+       lda ss_ff
        cmp #FMT_CUR
        bne +
        lda #'$'
        sta ss_dbuf,x
        inx
+       ; count the digits (FOUT gives " 12345")
        ldy #1
-       lda $0100,y
        beq +
        cmp #'E'
        beq .big
        iny
        bne -
+       dey
        sty ss_nd
        lda ss_ff
        cmp #FMT_INT
        bne .dec
        ldy #1                  ; integer: just the digits
-       lda $0100,y
        sta ss_dbuf,x
        beq .end
        inx
        iny
        bne -
.dec:   lda ss_nd               ; at least 3 digits, "." before the last 2
        cmp #3
        bcs +
        lda #3
+       sta ss_nt
        sec
        sbc ss_nd
        sta ss_npad
        lda #0
        sta ss_ni
        ldy #1
.dl:    lda ss_ni
        cmp ss_nt
        beq .end0
        lda ss_nt
        sec
        sbc #2
        cmp ss_ni
        bne +
        lda #'.'
        sta ss_dbuf,x
        inx
+       lda ss_ni
        cmp ss_npad
        bcs .real
        lda #'0'
        bne .put
.real:  lda $0100,y
        iny
.put:   sta ss_dbuf,x
        inx
        inc ss_ni
        jmp .dl
.end0:  lda #0
        sta ss_dbuf,x
.end:   rts
.big:   ldx #0
-       lda str_err,x           ; too big for a fixed format
        sta ss_dbuf,x
        beq +
        inx
        bne -
+       lda #'#'
        sta ss_dbuf+1
        sta ss_dbuf+2
        sta ss_dbuf+3
        rts

; ---------------------------------------------------------------------
; Drawing (normal zero page again)
; ---------------------------------------------------------------------
; local rect: A = x1, X = y1, Y = x2, t7 = y2 (x below 256)
ss_rect = cp_rect

; local rect with 16 bit x: sl_x1, sl_y1, sl_x2, sl_y2 -> rx..ry
sl_x1:  !word 0
sl_y1:  !byte 0
sl_x2:  !word 0
sl_y2:  !byte 0
ss_lrect:
        clc
        lda wc_x1
        adc sl_x1
        sta rx1
        lda wc_x1+1
        adc sl_x1+1
        sta rx1+1
        clc
        lda wc_x1
        adc sl_x2
        sta rx2
        lda wc_x1+1
        adc sl_x2+1
        sta rx2+1
        clc
        lda wc_y1
        adc sl_y1
        sta ry1
        clc
        lda wc_y1
        adc sl_y2
        sta ry2
        rts

; x of the left grid line of column c (and of the right edge, c = 7)
ss_colx_lo: !for c, 0, COLS { !byte <(RHW + c*CW) }
ss_colx_hi: !for c, 0, COLS { !byte >(RHW + c*CW) }

; sl_x1 = colx[A] + X, sl_x2 = colx[A] + Y
ss_colx:
        stx t5
        sty t6
        tax
        clc
        lda ss_colx_lo,x
        adc t5
        sta sl_x1
        lda ss_colx_hi,x
        adc #0
        sta sl_x1+1
        clc
        lda ss_colx_lo,x
        adc t6
        sta sl_x2
        lda ss_colx_hi,x
        adc #0
        sta sl_x2+1
        rts

; horizontal line across the grid width at local y A, from x = X
ss_hline:
        sta sl_y1
        sta sl_y2
        stx sl_x1
        lda #0
        sta sl_x1+1
        lda #<(RHW+COLS*CW)
        sta sl_x2
        lda #>(RHW+COLS*CW)
        sta sl_x2+1
        jmp ss_lrect

; X = cell -> u2 = column, u3 = row
ss_cr:
        txa
        ldy #0
-       cmp #COLS
        bcc +
        sbc #COLS
        iny
        bne -
+       sta u2
        sty u3
        rts

; inside of cell X on screen -> rx..ry, carry set if not visible
!zone ss_cell_rect
ss_cell_rect:
        jsr ss_cr
        lda u3
        sec
        sbc ss_top
        bcc .no
        cmp #VROWS
        bcs .no
        sta t3
        asl                     ; y1 = GT + vr*10 + 1
        asl
        adc t3
        asl
        clc
        adc #GT+1
        tax
        clc
        adc #CH-2
        sta t7
        stx sl_y1
        lda t7
        sta sl_y2
        lda u2                  ; x from the column table
        ldx #1
        ldy #CW-1
        jsr ss_colx
        jsr ss_lrect
        clc
        rts
.no:    sec
        rts

; the selection: the cell drawn inverted (XOR, so it toggles)
ss_sel_frame:
        ldx ss_sel
        jsr ss_cell_rect
        bcs +
        jsr invert_rect
+       rts

; redraw one cell
!zone ss_draw_cell
ss_draw_cell:
        stx u4
        lda ss_full             ; whole window: already white, skip empties
        beq +
        lda ss_type,x
        bne +
        cpx ss_sel
        beq +
        rts
+       jsr ss_cell_rect
        bcc .bf1296
        jmp .out
.bf1296:
        lda ss_full
        bne +
        jsr fill_white
+       ldx u4
        lda ss_type,x
        bne .bf1300
        jmp .sel
.bf1300:
        ; what to show, and where
        cmp #T_TEXT
        beq .text
        cmp #T_FORM
        bne .num
        lda ss_showf
        bne .text
.num:   lda ss_dlo,x
        sta tstr
        lda ss_dhi,x
        sta tstr+1
        lda #1
        sta u5                  ; right aligned
        jmp .draw
.text:  lda ss_tlo,x
        sta tstr
        lda ss_thi,x
        sta tstr+1
        lda #0
        sta u5
.draw:  lda #1
        sta font
        jsr text_width
        lda u5
        beq .left
        ; too wide for the column: ####
        lda twidth+1
        bne .hash
        lda twidth
        cmp #CW-3
        bcc .right
.hash:  lda #<str_hash
        sta tstr
        lda #>str_hash
        sta tstr+1
        jsr text_width
.right: sec
        lda rx2
        sbc twidth
        sta tx
        lda rx2+1
        sbc twidth+1
        sta tx+1
        jmp .go
.left:  clc
        lda rx1
        adc #2
        sta tx
        lda rx1+1
        adc #0
        sta tx+1
.go:    lda ry1
        clc
        adc #1
        sta ty
        lda #0
        sta ty+1
        lda #B_OR
        sta tmode
        jsr clip_push
        jsr clip_rect
        jsr draw_text
        jsr clip_pop
.sel:   ldx u4
        cpx ss_sel
        bne .out
        jsr ss_sel_frame
.out:   rts
str_hash: !text "####", 0

; the formula bar: cell name, then contents (or what is being typed)
!zone ss_draw_fbar
ss_draw_fbar:
        lda #0
        sta sl_y1
        lda #FBH-2
        sta sl_y2
        lda #0
        sta sl_x1
        sta sl_x1+1
        lda #<(RHW+COLS*CW)
        sta sl_x2
        lda #>(RHW+COLS*CW)
        sta sl_x2+1
        jsr ss_lrect
        jsr fill_white
        lda #12
        sta t7
        lda #2
        ldx #2
        ldy #30
        jsr ss_rect
        jsr set_black
        jsr frame_rect
        ; name, e.g. B12
        ldx ss_sel
        jsr ss_cr
        lda u2
        clc
        adc #'A'
        sta ss_name
        lda u3
        clc
        adc #1
        ldx #0
        jsr utoa
        ldx #0
-       lda numbuf,x
        sta ss_name+1,x
        beq +
        inx
        bne -
+       lda #<ss_name
        ldy #>ss_name
        ldx #4
        jsr .text
        ; contents
        lda ss_editing
        bne +
        ldx ss_sel
        lda ss_tlo,x
        ldy ss_thi,x
        jmp ++
+       lda #<ss_edit
        ldy #>ss_edit
++      ldx #36
        jsr .text
        lda twidth
        clc
        adc #36
        sta ss_cx               ; caret position (local x)
        lda #0
        sta ss_caret
        ; line under the bar
        lda #FBH-1
        ldx #0
        jsr ss_hline
        jmp fill_black
.text:  sta tstr
        sty tstr+1
        stx t4
        clc
        lda wc_x1
        adc t4
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #3
        sta ty
        lda #0
        sta ty+1
        sta font
        lda #B_OR
        sta tmode
        jmp draw_text
ss_name: !fill 5
ss_cx:   !byte 0

; M_DRAW: the whole window (already white)
!zone ss_draw
ss_draw:
        jsr ss_draw_fbar
        lda #1
        sta ss_full
        jsr ss_draw_grid
        lda #0
        sta ss_full
        rts
ss_full: !byte 0

; headers, lines and the visible cells
ss_draw_grid:
        ; column letters
        lda #0
        sta u6
.ch:    lda u6
        clc
        adc #'A'
        sta ss_name
        lda #0
        sta ss_name+1
        lda u6
        ldx #17
        ldy #17
        jsr ss_colx
        ldx sl_x1
        lda sl_x1+1
        sta .hi
        lda #FBH+1
        jsr .small
        lda #0
        sta .hi
        inc u6
        lda u6
        cmp #COLS
        bne .ch
        ; row numbers
        lda #0
        sta u6
.rh:    lda u6
        clc
        adc ss_top
        adc #1
        ldx #0
        jsr utoa
        ldx #0
-       lda numbuf,x
        sta ss_name,x
        beq +
        inx
        bne -
+       lda #<ss_name
        sta tstr
        lda #>ss_name
        sta tstr+1
        lda #1
        sta font
        jsr text_width
        lda #RHW-3
        sec
        sbc twidth
        tax
        lda u6
        asl
        asl
        adc u6
        asl
        clc
        adc #GT+2
        jsr .small
        inc u6
        lda u6
        cmp #VROWS
        bne .rh
        ; grid lines: dotted between cells, solid along the headers
        lda #1
        sta u6
.hl:    lda u6                  ; horizontal
        asl
        asl
        adc u6
        asl
        clc
        adc #GT
        ldx #RHW
        jsr ss_hline
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        jsr fill_rect
        inc u6
        lda u6
        cmp #VROWS+1
        bne .hl
        lda #1
        sta u6
.vl:    lda u6                  ; vertical
        ldx #0
        ldy #0
        jsr ss_colx
        lda #FBH
        sta sl_y1
        lda #GT+VROWS*CH
        sta sl_y2
        jsr ss_lrect
        lda #<pat_gray
        ldy #>pat_gray
        jsr set_pat_copy
        jsr fill_rect
        inc u6
        lda u6
        cmp #COLS+1
        bne .vl
        lda #GT                 ; solid: under the letters,
        ldx #0
        jsr ss_hline
        jsr fill_black
        lda #GT+VROWS*CH        ; right of the numbers
        sta t7
        lda #RHW
        ldx #FBH
        ldy #RHW
        jsr ss_rect
        jsr fill_black
        ; cells
        ldx #0
-       stx u7
        jsr ss_draw_cell
        ldx u7
        inx
        cpx #NCELLS
        bne -
        rts
.small: ; ss_name at local (.hi:X, A) in the small font
        sta t4
        stx t5
        clc
        lda wc_x1
        adc t5
        sta tx
        lda wc_x1+1
        adc .hi
        sta tx+1
        lda wc_y1
        clc
        adc t4
        sta ty
        lda #0
        sta ty+1
        lda #1
        sta font
        lda #B_OR
        sta tmode
        lda #<ss_name
        ldy #>ss_name
        jmp draw_str
.hi:    !byte 0

; draw changed cells (inside the window)
ss_redraw_dirty:
        jsr ss_clip
        ldx #0
-       lda ss_dirty,x
        beq +
        lda #0
        sta ss_dirty,x
        stx u7
        jsr ss_draw_cell
        ldx u7
+       inx
        cpx #NCELLS
        bne -
        jmp clip_pop

ss_clip:
        jsr clip_push
        jsr clip_screen
        ldx ss_win
        jsr win_get_content
        jmp clip_rect

; formula bar only
ss_redraw_fbar:
        jsr ss_clip
        jsr ss_draw_fbar
        jmp clip_pop

; after scrolling: the scroll bar and the grid, not the formula bar
ss_redraw_scrolled:
        jsr clip_push
        jsr clip_screen
        ldx ss_win
        jsr win_get_full
        jsr clip_rect
        ldx ss_win
        jsr win_draw_frame
        ldx ss_win
        jsr win_get_content
        lda ry1
        clc
        adc #FBH
        sta ry1
        jsr clip_rect
        jsr fill_white
        lda #1
        sta ss_full
        jsr ss_draw_grid
        lda #0
        sta ss_full
        jmp clip_pop

; the whole content (New, Show Formulas)
ss_redraw_all:
        jsr clip_push
        jsr clip_screen
        ldx ss_win
        jsr win_get_full
        jsr clip_rect
        ldx ss_win
        jsr win_draw_frame      ; the scroll bar moves too
        ldx ss_win
        jsr win_draw_content
        jmp clip_pop

; ---------------------------------------------------------------------
; Selection, editing
; ---------------------------------------------------------------------
; select cell A (scrolling if needed).  While more keys are waiting,
; a scroll only updates ss_top; the redraw happens once they are done.
!zone ss_select
ss_select:
        pha
        lda ss_pending
        bne +
        jsr ss_clip
        jsr ss_sel_frame        ; old selection off
        jsr clip_pop
+       pla
        sta ss_sel
        tax
        jsr ss_cr
        lda u3
        cmp ss_top
        bcs +
        sta ss_top              ; above the window
        jmp .scroll
+       sec
        sbc #VROWS-1
        bcc .vis
        beq .vis
        cmp ss_top
        bcc .vis
        beq .vis
        sta ss_top              ; below the window
.scroll:
        ldx ss_win
        lda ss_top
        sta w_scroll,x
        lda #1
        sta ss_pending
.vis:   lda ss_pending
        beq .frame
        lda key_head            ; more keys queued: later
        cmp key_tail
        bne .out
ss_flush:                       ; the deferred redraw
        lda #0
        sta ss_pending
        jsr ss_redraw_scrolled
        jmp ss_redraw_fbar
.frame: jsr ss_clip
        jsr ss_sel_frame
        jsr ss_draw_fbar
        jmp clip_pop
.out:   rts
ss_pending: !byte 0

; move the selection: A = column change, X = row change (signed)
!zone ss_move
ss_move:
        sta t0
        stx t1
        ldx ss_sel
        jsr ss_cr
        lda u2
        clc
        adc t0
        bmi .out
        cmp #COLS
        bcs .out
        sta u2
        lda u3
        clc
        adc t1
        bmi .out
        cmp #ROWS
        bcs .out
        sta u3
        asl
        asl
        asl
        sec
        sbc u3
        clc
        adc u2
        jmp ss_select
.out:   rts

; put what was typed into the cell
!zone ss_commit
ss_commit:
        lda ss_editing
        beq .out
        lda #0
        sta ss_editing
        ldx ss_sel
        lda ss_tlo,x
        sta q1
        lda ss_thi,x
        sta q1+1
        lda #<ss_edit
        sta q0
        lda #>ss_edit
        sta q0+1
        jsr strcpy
ss_changed_cell:                ; the selected cell's text changed
        lda ss_sel
        jsr ss_compute
        ldx ss_sel
        lda #1
        sta ss_dirty,x
        jsr ss_redraw_dirty
        jmp ss_redraw_fbar
.out:   rts

ss_start_edit:                  ; A = 0 empty, else keep the contents
        sta t0
        lda #1
        sta ss_editing
        lda #0
        sta ss_edit
        lda t0
        beq +
        ldx ss_sel
        lda ss_tlo,x
        sta q0
        lda ss_thi,x
        sta q0+1
        lda #<ss_edit
        sta q1
        lda #>ss_edit
        sta q1+1
        jsr strcpy
+       rts

!zone ss_key
ss_key:
        lda key_char
        cmp #K_RETURN
        bne +
        jsr ss_commit
        lda #0
        ldx #1
        jmp ss_move
+       cmp #K_ESC
        bne +
        lda ss_editing
        bne .bf1785
        jmp .out
.bf1785:
        lda #0
        sta ss_editing
        jmp ss_redraw_fbar
+       cmp #K_UP
        bne +
        jsr ss_commit
        lda #0
        ldx #$ff
        jmp ss_move
+       cmp #K_DOWN
        bne +
        jsr ss_commit
        lda #0
        ldx #1
        jmp ss_move
+       cmp #K_LEFT
        bne +
        jsr ss_commit
        lda #$ff
        ldx #0
        jmp ss_move
+       cmp #K_RIGHT
        bne +
        jsr ss_commit
        lda #1
        ldx #0
        jmp ss_move
+       cmp #K_DEL
        bne .chr
        lda ss_editing
        bne +
        lda #1                  ; edit what is there
        jsr ss_start_edit
+       ldx #0
-       lda ss_edit,x
        beq +
        inx
        bne -
+       cpx #0
        beq +
        lda #0
        sta ss_edit-1,x
+       jmp ss_redraw_fbar
.chr:   cmp #32
        bcc .out
        cmp #127
        bcs .out
        lda ss_editing          ; typing replaces the cell
        bne +
        lda #0
        jsr ss_start_edit
+       ldx #0
-       lda ss_edit,x
        beq +
        inx
        bne -
+       cpx #TEXTLEN
        bcs .out
        lda key_char
        sta ss_edit,x
        lda #0
        sta ss_edit+1,x
        jmp ss_redraw_fbar
.out:   rts

; click: a cell, or the formula bar to edit the contents
!zone ss_click
ss_click:
        sec
        lda mouse_y
        sbc wc_y1
        cmp #FBH
        bcs .grid
        lda ss_editing
        bne .out
        lda #1
        jsr ss_start_edit
        jsr ss_redraw_fbar
        jmp wait_release
.grid:  cmp #GT
        bcc .out
        sec
        sbc #GT
        ldy #0
-       cmp #CH
        bcc +
        sbc #CH
        iny
        bne -
+       cpy #VROWS
        bcs .out
        sty t1
        sec                     ; x within the grid (16 bit)
        lda mouse_x
        sbc wc_x1
        sta t0
        lda mouse_x+1
        sbc wc_x1+1
        sta t2
        sec
        lda t0
        sbc #RHW
        sta t0
        lda t2
        sbc #0
        sta t2
        bmi .out
        ldx #0
-       lda t0
        sec
        sbc #CW
        tay
        lda t2
        sbc #0
        bcc +
        sta t2
        sty t0
        inx
        bne -
+       cpx #COLS
        bcs .out
        stx t0
        jsr ss_commit
        lda t1                  ; cell = (top+vr)*7 + col
        clc
        adc ss_top
        sta t1
        asl
        asl
        asl
        sec
        sbc t1
        clc
        adc t0
        jsr ss_select
        jmp wait_release
.out:   rts

; blink the caret while typing
!zone ss_idle
ss_idle:
        cpx zlist
        bne .out
        lda ss_pending          ; a scroll waiting for the keys to stop
        beq +
        lda key_head
        cmp key_tail
        bne .out
        jmp ss_flush
+
        lda ss_editing
        beq .out
        inc ss_ctime
        lda ss_ctime
        cmp np_blink
        bcc .out
        lda #0
        sta ss_ctime
        lda ss_caret
        eor #1
        sta ss_caret
        jsr ss_clip
        lda #11
        sta t7
        lda ss_cx
        ldx #3
        ldy ss_cx
        jsr ss_rect
        jsr invert_rect
        jmp clip_pop
.out:   rts

ss_close:
        lda #SA_QUIT
        sta pending_action
        rts

; scroll bar
!zone ss_scroll
ss_scroll:
        lda win_part_hit
        cmp #P_UP
        bne +
        lda #$ff
        bne .by
+       cmp #P_DOWN
        bne +
        lda #1
        bne .by
+       cmp #P_PGUP
        bne +
        lda #-VROWS
        bne .by
+       cmp #P_PGDN
        bne .out
        lda #VROWS
.by:    clc
        adc ss_top
        bpl +
        lda #0
+       cmp #MAXTOP+1
        bcc +
        lda #MAXTOP
+       cmp ss_top
        beq .wait
        sta ss_top
        ldx ss_win
        sta w_scroll,x
        jsr ss_redraw_scrolled
.wait:  lda #4
        jsr wait_frames
        lda mbtn
        beq .out
        jmp ss_scroll
.out:   rts

; ---------------------------------------------------------------------
; Menus
; ---------------------------------------------------------------------
ss_acts:
        !word ss_about, ss_new, quit_app
        !word nop_method, ss_cut, ss_copy, ss_paste, ss_clear
        !word ss_format, ss_format, ss_format, ss_format
        !word ss_calc, ss_toggle_f

!zone ss_action
ss_action:
        asl
        tay
        lda ss_acts,y
        sta jvec
        lda ss_acts+1,y
        sta jvec+1
        jmp (jvec)

; is a desk accessory in front?  Then Edit commands are for it.
ss_da_front:
        jsr front_win
        cpx #$ff
        beq +
        lda w_class,x
        cmp #CL_APPBASE
        bcs +
        lda cur_action
        sec
        sbc #SA_UNDO
        sta key_char
        lda #M_EDIT
        jsr win_call
        sec
        rts
+       clc
        rts

ss_copy:
        jsr ss_da_front
        bcs +
        jsr ss_commit
        ldx ss_sel
        lda ss_tlo,x
        sta q0
        lda ss_thi,x
        sta q0+1
        ldy #0
-       lda (q0),y
        sta clip_buf,y
        beq ++
        iny
        bne -
++      sty clip_len
+       rts

ss_cut:
        jsr ss_da_front
        bcs +
        jsr ss_copy
        jmp ss_clear_cell
+       rts

ss_clear:
        jsr ss_da_front
        bcs +
        jmp ss_clear_cell
+       rts

ss_clear_cell:
        lda #0
        sta ss_editing
        ldx ss_sel
        lda ss_tlo,x
        sta q0
        lda ss_thi,x
        sta q0+1
        ldy #0
        tya
        sta (q0),y
        jmp ss_changed_cell

ss_paste:
        jsr ss_da_front
        bcs .out
        lda #0
        sta ss_editing
        ldx ss_sel
        lda ss_tlo,x
        sta q0
        lda ss_thi,x
        sta q0+1
        ldy #0
-       cpy clip_len
        beq +
        cpy #TEXTLEN
        beq +
        lda clip_buf,y
        cmp #K_RETURN           ; stop at a line break
        beq +
        cmp #'|'
        beq +
        sta (q0),y
        iny
        bne -
+       lda #0
        sta (q0),y
        jmp ss_changed_cell
.out:   rts

ss_format:
        jsr ss_commit
        lda cur_action
        sec
        sbc #SA_GEN
        asl
        asl
        asl
        asl
        sta t0
        ldx ss_sel
        lda ss_flags,x
        and #$ff-F_FMT
        ora t0
        sta ss_flags,x
        jmp ss_changed_cell

ss_calc:
        jsr ss_commit
        lda #$fe
        jsr ss_compute
        jmp ss_redraw_dirty

ss_toggle_f:
        lda ss_showf
        eor #1
        sta ss_showf
        jmp ss_redraw_all

ss_new:
        lda #0
        sta ss_editing
        ldx #NCELLS-1
-       lda ss_tlo,x
        sta q0
        lda ss_thi,x
        sta q0+1
        ldy #0
        tya
        sta (q0),y
        sta ss_flags,x
        sta ss_type,x
        dex
        bpl -
        lda #$fe
        jsr ss_compute
        lda #0
        sta ss_sel
        sta ss_top
        ldx ss_win
        sta w_scroll,x
        jsr win_select
        jmp ss_redraw_all

!zone ss_about
ss_about:
        lda #DLG_CUSTOM
        sta dlg_kind
        lda #<ss_about_draw
        sta dlg_custom
        lda #>ss_about_draw
        sta dlg_custom+1
        lda #84
        sta dlg_h
        lda #1
        sta dlg_x2h
        lda #34
        ldx #50
        ldy #<285
        jsr dlg_open
        bcs .out
        jsr wait_click_or_key
        jmp dlg_close
.out:   rts

ss_about_draw:
        lda #0
        sta font
        lda #<str_ss_name
        ldy #>str_ss_name
        ldx #6
        jsr draw_centred_at
        lda #1
        sta font
        lda #<str_ss_ab1
        ldy #>str_ss_ab1
        ldx #22
        jsr draw_centred_at
        lda #<str_ss_ab2
        ldy #>str_ss_ab2
        ldx #32
        jsr draw_centred_at
        lda #<str_ss_ab3
        ldy #>str_ss_ab3
        ldx #42
        jsr draw_centred_at
        lda #<str_ss_ab4
        ldy #>str_ss_ab4
        ldx #52
        jsr draw_centred_at
        lda #<str_ss_ab5
        ldy #>str_ss_ab5
        ldx #66
        jmp draw_centred_at

!zone ss_update_menus
ss_update_menus:
        ; Edit: a desk accessory in front decides, otherwise the cell
        jsr front_win
        cpx #$ff
        beq .sheet
        lda w_class,x
        cmp #CL_APPBASE
        bcs .sheet
        ldy #0
        sty u1
        sty u2
        cmp #CL_NOTEPAD
        bne +
        inc u1
        inc u2
+       cmp #CL_CALC
        bne +
        inc u2
+       jmp .edit
.sheet: lda #1
        sta u1                  ; cut / copy / clear
        lda clip_len
        sta u2                  ; paste
        lda u1
        ldx #32+2
        jsr menu_set
        lda u1
        ldx #32+3
        jsr menu_set
        lda u2
        ldx #32+4
        jsr menu_set
        lda u1
        ldx #32+5
        jsr menu_set
        jmp .fmt
.edit:  lda u1
        ldx #32+2
        jsr menu_set
        lda u2
        ldx #32+3
        jsr menu_set
        lda u2
        ldx #32+4
        jsr menu_set
        lda u1
        ldx #32+5
        jsr menu_set
.fmt:   ldx #32+0
        jsr menu_disable
        ; Format: check the selected cell's format
        ldx ss_sel
        lda ss_flags,x
        and #F_FMT
        lsr
        lsr
        lsr
        lsr
        sta t0
        ldx #0
-       lda menu_flags+48,x
        and #$ff-MF_CHECKED
        cpx t0
        bne +
        ora #MF_CHECKED
+       sta menu_flags+48,x
        inx
        cpx #4
        bne -
        ; Sheet: Show Formulas
        lda menu_flags+64+1
        and #$ff-MF_CHECKED
        ldx ss_showf
        beq +
        ora #MF_CHECKED
+       sta menu_flags+64+1
        rts

ss_menus:
        !word str_ss_file, str_ss_edit, str_ss_format, str_ss_sheet
        !word ss_items_file, ss_items_edit, ss_items_format, ss_items_sheet
ss_items_file:
        !byte 3
        +item str_ss_new, 'N', SA_NEW
        +sep
        +item str_ss_quit, 'Q', SA_QUIT
ss_items_edit:
        !byte 6
        +item str_ss_undo, 'Z', SA_UNDO
        +sep
        +item str_ss_cut, 'X', SA_CUT
        +item str_ss_copy, 'C', SA_COPY
        +item str_ss_paste, 'V', SA_PASTE
        +item str_ss_clear, 0, SA_CLEAR
ss_items_format:
        !byte 4
        +item str_ss_gen, 0, SA_GEN
        +item str_ss_fix, 0, SA_FIX
        +item str_ss_int, 0, SA_INT
        +item str_ss_cur, 0, SA_CUR
ss_items_sheet:
        !byte 2
        +item str_ss_calc, 'R', SA_CALC
        +item str_ss_showf, 'F', SA_SHOWF

str_ss_about:  !text "About Spreadsheet", $13, 0
str_ss_name:   !text "Spreadsheet", 0
str_ss_title:  !text "Budget 1987", 0
str_ss_file:   !text "File", 0
str_ss_edit:   !text "Edit", 0
str_ss_format: !text "Format", 0
str_ss_sheet:  !text "Sheet", 0
str_ss_new:    !text "New", 0
str_ss_quit:   !text "Quit", 0
str_ss_undo:   !text "Undo", 0
str_ss_cut:    !text "Cut", 0
str_ss_copy:   !text "Copy", 0
str_ss_paste:  !text "Paste", 0
str_ss_clear:  !text "Clear", 0
str_ss_gen:    !text "General", 0
str_ss_fix:    !text "Fixed  0.00", 0
str_ss_int:    !text "Integer  0", 0
str_ss_cur:    !text "Currency  $0.00", 0
str_ss_calc:   !text "Calculate Now", 0
str_ss_showf:  !text "Show Formulas", 0
str_ss_ab1:    !text "A little worksheet for the Commodore 64 desktop.", 0
str_ss_ab2:    !text "Arithmetic by the BASIC ROM's floating point.", 0
str_ss_ab3:    !text "Formulas: + - * / ( )  cells like B4,", 0
str_ss_ab4:    !text "SUM AVG MIN MAX COUNT over ranges like B4:D8.", 0
str_ss_ab5:    !text "Click to continue.", 0
