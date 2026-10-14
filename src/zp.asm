; =====================================================================
; Zero page.  The whole page is ours (KERNAL and BASIC are banked out);
; fp.asm swaps it with BASIC's copy around floating point ROM calls.
;
; Sections marked @public are part of the System's API: their names
; and addresses are published in build/sysapi.asm.  @private ones are
; the System's own and may change.
; =====================================================================

; @public

; scratch - any routine may clobber these
t0      = $02
t1      = $03
t2      = $04
t3      = $05
t4      = $06
t5      = $07
t6      = $08
t7      = $09

; @private
p0      = $0a           ; word pointers
p1      = $0c
p2      = $0e
p3      = $10
p4      = $12

; @public
; rectangle parameters (inclusive), x is 16 bit, y is 8 bit
rx1     = $14
ry1     = $16
rx2     = $17
ry2     = $19

; clip rectangle (always inside the screen)
clx1    = $1a
cly1    = $1c
clx2    = $1d
cly2    = $1f

; @private
pat     = $20           ; pointer to 8 pattern bytes
rmode   = $22           ; M_COPY / M_OR / M_XOR / M_BIC

; fill_rect locals
fx1     = $23
fx2     = $25
fy1     = $27
fy2     = $28
fc1     = $29
fc2     = $2a
flm     = $2b
frm     = $2c
fmask   = $2d
fcnt    = $2e
fcol    = $2f
fbase   = $30
fyoff   = $32
fpm     = $33

; @public
; text
tx      = $34           ; 16 bit x
ty      = $36           ; 16 bit signed y
tstr    = $38           ; string pointer
font    = $3a           ; 0 = system, 1 = small
tmode   = $3b           ; blit mode for text

; @private
tpos    = $3c           ; 16 bit bit position in strip
fwid    = $3e           ; font tables
flo     = $40
fhi     = $42
fheight = $44
tsi     = $45

; @public
twidth  = $46           ; 16 bit, width of the last measured/drawn string

; @private

; strip blitter
bcol    = $48
by      = $49           ; 16 bit signed
bnc     = $4b
bnr     = $4c
bmode   = $4d
br0     = $4e
bcnt    = $4f
bm      = $50
bk      = $51
bsc     = $52
bcl     = $53
bcr     = $54
bclm    = $55
bcrm    = $56
byoff   = $57
bcrow   = $58
bt      = $59
bnm     = $5a
src_lo  = $5b
src_hi  = $5c
blit_fn = $5d           ; word

; @public
; icons
iptr    = $5f           ; word
iflags  = $61

; @private
iw      = $62
ih      = $63
isz     = $64           ; word
rj      = $66
rxor    = $67
rdst    = $68
img     = $69           ; word
imask   = $6b           ; word
ioutl   = $6d           ; word

; @public
; input, written by the IRQ only
mouse_x = $70           ; word, 0..319
mouse_y = $72           ; 0..199
mbtn    = $73           ; 1 = button down
jiffy   = $74           ; word, frames since start
cursor  = $76           ; current cursor shape
modkeys = $77           ; MOD_SHIFT | MOD_CMD | MOD_CTRL

; @private
; IRQ private
irq_t0  = $78
irq_t1  = $79
irq_t2  = $7a
old_potx = $7b
old_poty = $7c
joy1    = $7d
joy2    = $7e
joy_spd = $7f

; @public
; general purpose pointers for higher level code
q0      = $80
q1      = $82
q2      = $84
q3      = $86
u0      = $88
u1      = $89
u2      = $8a
u3      = $8b
u4      = $8c
u5      = $8d
u6      = $8e
u7      = $8f

jvec    = $90           ; vector for indirect jumps (never at $xxff)

; @private
; (the KERNAL's half of zero page, ours since SYSTEM no longer uses it)
ovp     = $92           ; overlay manager: the stub's bytes
ovt     = $94           ; overlay manager: the routine to call
