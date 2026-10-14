; =====================================================================
; sys.asm - hardware setup, raster IRQ, mouse / joystick / keyboard,
; pointer sprites, beep, timing
; =====================================================================

SCREEN  = $c000         ; colour matrix (VIC bank 3)
SPRPTR  = SCREEN + $3f8
SPRITES = $c400         ; cursor sprites, pairs of black/white

MOD_SHIFT = 1
MOD_CMD   = 2           ; C= key (Alt/Option on the host) acts as Command
MOD_CTRL  = 4

; key codes returned by get_key (printable keys are ASCII)
K_DEL    = $08
K_RETURN = $0d
K_ESC    = $1b          ; RUN/STOP
K_RIGHT  = $1c
K_LEFT   = $1d
K_UP     = $1e
K_DOWN   = $1f
K_HOME   = $01
K_CLR    = $02

IRQ_LINE = 251

!zone hw_init
hw_init:
        lda #$7f                ; no CIA interrupts
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        sta $0318
        lda #>nmi
        sta $fffb
        sta $0319
        lda #$0b                ; blank the screen while we set up
        sta $d011
        lda #0
        sta $d020
        sta $d021
        sta $d015
        sta $d017
        sta $d01b
        sta $d01c
        sta $d01d
        lda $dd02               ; VIC bank 3 ($c000-$ffff)
        ora #3
        sta $dd02
        lda $dd00
        and #$fc
        sta $dd00
        lda #$08                ; matrix $c000, bitmap $e000
        sta $d018
        lda #$08                ; hires, 40 columns
        sta $d016
        ; colour matrix: black ink on white paper
        ldx #0
        lda #$01
-       sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        inx
        bne -
        ; CIA1: port A out (keyboard columns), port B in
        lda #$ff
        sta $dc02
        lda #0
        sta $dc03
        lda #$7f
        sta $dc00
        ; SID: silence, volume
        ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        lda #$0f
        sta $d418
        ; TOD clock: 50 Hz, set 10:09:41 AM
        lda $dc0e
        ora #$80
        sta $dc0e
        lda $dc0f
        and #$7f
        sta $dc0f
        lda #$10
        sta $dc0b
        lda #$09
        sta $dc0a
        lda #$41
        sta $dc09
        lda #0
        sta $dc08
        ; pointer sprites
        lda #0
        sta $d027               ; black shape
        lda #1
        sta $d028               ; white outline
        lda #3
        sta $d015
        lda #CUR_ARROW
        jsr set_cursor
        ; input state
        lda $d419
        sta old_potx
        lda $d41a
        sta old_poty
        lda #0
        sta mbtn
        sta joy_spd
        sta modkeys
        sta key_head
        sta key_tail
        lda #$ff
        sta rep_key
        ldx #7
-       sta kbd_old,x
        dex
        bpl -
        ; raster IRQ
        lda #IRQ_LINE
        sta $d012
        lda #1
        sta $d01a
        sta $d019
        rts

nmi:    rti

screen_on:
        lda #$3b                ; bitmap mode, display on
        sta $d011
        rts

; ---------------------------------------------------------------------
!zone irq
irq:    pha
        txa
        pha
        tya
        pha
        lda $d019
        sta $d019
        jsr irq_body
        pla
        tay
        pla
        tax
        pla
        rti

; the same, entered through the KERNAL's IRQ vector ($0314) while the
; KERNAL is banked in for disk access (it has pushed the registers)
irq_k:  lda $d019
        sta $d019
        jsr irq_body
        jmp $ea81

irq_body:
        inc jiffy
        bne +
        inc jiffy+1
+       jsr read_mouse
        jsr read_keyboard
        jsr place_sprite
        jmp beep_tick

; ---------------------------------------------------------------------
; 1351 mouse in port 1 (proportional mode) plus joystick in port 2
; ---------------------------------------------------------------------
!zone read_mouse
read_mouse:
        lda $d419
        ldy old_potx
        jsr move_check
        sty old_potx
        cmp #0
        beq .noxm
        clc
        adc mouse_x
        sta mouse_x
        txa
        adc mouse_x+1
        sta mouse_x+1
.noxm:  lda $d41a
        ldy old_poty
        jsr move_check
        sty old_poty
        cmp #0
        beq .noym
        ; y -= dy (16 bit via irq_t0/t1 then clamp)
        sta irq_t0
        stx irq_t1
        sec
        lda mouse_y
        sbc irq_t0
        sta mouse_y
        lda #0
        sbc irq_t1
        sta irq_t2              ; high byte of y
        jsr clamp_y
.noym:  ; buttons and joystick
        lda #$ff
        sta $dc00
        lda $dc01               ; port 1: mouse (left = fire, right = up)
        sta joy1
        lda $dc00               ; port 2: joystick
        sta joy2
        lda #0
        sta irq_t0
        lda joy1
        and #$11
        cmp #$11
        beq +
        inc irq_t0
+       lda joy2
        and #$10
        bne +
        lda #1
        sta irq_t0
+       lda irq_t0
        cmp mbtn
        beq +
        sta mbtn
        cmp #0
        beq +
        inc press_count         ; a new press: remember it, and when
        lda jiffy
        sta press_jiffy
        lda jiffy+1
        sta press_jiffy+1
+
        ; joystick movement with acceleration
        lda joy2
        and #$0f
        cmp #$0f
        bne .joy
        lda #0
        sta joy_spd
        jmp clamp_x
.joy:   lda joy_spd
        cmp #40
        bcs +
        inc joy_spd
+       lsr
        lsr
        lsr
        clc
        adc #1                  ; speed 1..6
        sta irq_t1
        lda joy2
        lsr
        bcs +                   ; up
        pha
        lda mouse_y
        sec
        sbc irq_t1
        sta mouse_y
        lda #0
        sbc #0
        sta irq_t2
        jsr clamp_y
        pla
+       lsr
        bcs +                   ; down
        pha
        lda mouse_y
        clc
        adc irq_t1
        sta mouse_y
        lda #0
        adc #0
        sta irq_t2
        jsr clamp_y
        pla
+       lsr
        bcs +                   ; left
        pha
        sec
        lda mouse_x
        sbc irq_t1
        sta mouse_x
        lda mouse_x+1
        sbc #0
        sta mouse_x+1
        pla
+       lsr
        bcs +                   ; right
        clc
        lda mouse_x
        adc irq_t1
        sta mouse_x
        lda mouse_x+1
        adc #0
        sta mouse_x+1
+       ; fall into clamp_x

clamp_x:
        lda mouse_x+1
        bpl +
        lda #0                  ; negative -> 0
        sta mouse_x
        sta mouse_x+1
        rts
+       lda mouse_x
        cmp #<320
        lda mouse_x+1
        sbc #>320
        bcc +
        lda #<319
        sta mouse_x
        lda #>319
        sta mouse_x+1
+       rts

clamp_y:                        ; mouse_y with high byte irq_t2
        lda irq_t2
        beq +
        bpl .max
        lda #0
        sta mouse_y
        rts
+       lda mouse_y
        cmp #200
        bcc +
.max:   lda #199
        sta mouse_y
+       rts

; A = new pot value, Y = old.  Returns A = signed delta, X = sign
; extension, Y = value to keep as "old" (unchanged if no movement).
move_check:
        sty irq_t0
        sta irq_t1
        ldx #0
        sec
        sbc irq_t0
        and #%01111111
        cmp #%01000000
        bcs .neg
        lsr
        beq .none
        ldy irq_t1
        rts
.neg:   ora #%11000000
        cmp #$ff
        beq .none
        sec
        ror
        ldx #$ff
        ldy irq_t1
        rts
.none:  lda #0
        rts

; ---------------------------------------------------------------------
; Keyboard: scan the matrix, queue new key presses, auto-repeat
; ---------------------------------------------------------------------
kbd_new: !fill 8
kbd_old: !fill 8
key_buf: !fill 16
key_head: !byte 0
key_tail: !byte 0
rep_key: !byte $ff
rep_cnt: !byte 0
col_sel: !byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f

!zone read_keyboard
read_keyboard:
        lda joy2                ; joystick 2 active: matrix unreliable
        and #$1f
        cmp #$1f
        beq +
        lda #$7f
        sta $dc00
        rts
+       lda joy1
        eor #$ff
        sta joy1_ignore
        ldx #7
-       lda col_sel,x
        sta $dc00
        lda $dc01
        ora joy1_ignore         ; ignore lines held by port 1
        eor #$ff
        sta kbd_new,x
        dex
        bpl -
        lda #$7f                ; idle: select port 1 paddles
        sta $dc00
        ; modifiers
        lda #0
        sta irq_t0
        lda kbd_new+1
        and #$80                ; left shift
        bne .sh
        lda kbd_new+6
        and #$10                ; right shift
        beq +
.sh:    lda #MOD_SHIFT
        sta irq_t0
+       lda kbd_new+7
        and #$20                ; C=
        beq +
        lda irq_t0
        ora #MOD_CMD
        sta irq_t0
+       lda kbd_new+7
        and #$04                ; CTRL
        beq +
        lda irq_t0
        ora #MOD_CTRL
        sta irq_t0
+       lda irq_t0
        sta modkeys
        ; new presses
        ldx #7
.col:   lda kbd_old,x
        eor #$ff
        and kbd_new,x
        beq .nextc
        sta irq_t1
        ldy #7
.bit:   asl irq_t1
        bcc .nextb
        ; keycode = x*8 + y
        txa
        asl
        asl
        asl
        sta irq_t2
        tya
        ora irq_t2
        jsr .push
.nextb: dey
        bpl .bit
.nextc: lda kbd_new,x
        sta kbd_old,x
        dex
        bpl .col
        ; auto-repeat of the last key
        ldx rep_key
        bmi .done
        txa
        lsr
        lsr
        lsr
        tay
        txa
        and #7
        tax
        lda kbd_new,y
        and .bitmask,x
        bne +
        lda #$ff
        sta rep_key
        rts
+       dec rep_cnt
        bne .done
        lda #4
        sta rep_cnt
        lda rep_key
        jsr .queue
.done:  rts

.bitmask: !byte $01,$02,$04,$08,$10,$20,$40,$80

; A = keycode: skip modifiers, start repeat, queue
.push:  cmp #15                 ; left shift
        beq .skip
        cmp #52                 ; right shift
        beq .skip
        cmp #58                 ; ctrl
        beq .skip
        cmp #61                 ; C=
        beq .skip
        sta rep_key
        pha
        lda #22
        sta rep_cnt
        pla
.queue: sta irq_t2              ; preserves X and Y
        stx .sx
        lda key_head
        tax
        clc
        adc #1
        and #15
        cmp key_tail
        beq .full
        sta key_head
        lda irq_t2
        sta key_buf,x
        lda modkeys
        sta key_mods,x
.full:  ldx .sx
.skip:  rts
.sx:    !byte 0

joy1_ignore: !byte 0
press_count: !byte 0     ; mouse presses so far (wraps)
press_seen:  !byte 0     ; presses already handled
press_jiffy: !word 0     ; time of the last press
key_mods: !fill 16

; get_key: returns Z=1 if no key, else A = character / key code,
; X = modifiers.  Command-key combinations return the plain letter.
!zone get_key
get_key:
        ldx key_tail
        cpx key_head
        beq .none
        lda key_buf,x
        tay
        lda key_mods,x
        sta .mods
        txa
        clc
        adc #1
        and #15
        sta key_tail
        lda .mods
        and #MOD_SHIFT
        beq +
        lda key_shifted,y
        jmp ++
+       lda key_plain,y
++      ldx .mods
        cmp #0
        beq get_key             ; unmapped key, try the next one
        rts
.none:  lda #0
        rts
.mods:  !byte 0

key_plain:
        !byte K_DEL,K_RETURN,K_RIGHT,$87,$81,$83,$85,K_DOWN
        !text "3wa4zse",0
        !text "5rd6cftx"
        !text "7yg8bhuv"
        !text "9ij0mkon"
        !text "+pl-.:@,"
        !text "#*;",K_HOME,0,"=^/"
        !text "1_",0,"2 ",0,"q",K_ESC
key_shifted:
        !byte K_DEL,K_RETURN,K_LEFT,$88,$82,$84,$86,K_UP
        !text "#WA$ZSE",0
        !text "%RD&CFTX"
        !text "'YG(BHUV"
        !text ")IJ0MKON"
        !text "+PL->[@<"
        !text "#*]",K_CLR,0,"=^?"
        !text "!_",0,$22," ",0,"Q",K_ESC

; ---------------------------------------------------------------------
; Pointer sprites
; ---------------------------------------------------------------------
; A = cursor shape
!zone set_cursor
set_cursor:
        sta cursor
        asl
        clc
        adc #(SPRITES-$c000)/64
        sta SPRPTR
        adc #1
        sta SPRPTR+1
        rts

!zone place_sprite
place_sprite:
        ldx cursor
        sec
        lda mouse_x
        sbc cursor_hx,x
        sta irq_t0
        lda mouse_x+1
        sbc #0
        sta irq_t1
        clc
        lda irq_t0
        adc #24
        sta $d000
        sta $d002
        lda irq_t1
        adc #0
        beq +
        lda #3
+       sta irq_t2
        lda $d010               ; leave the other sprites' bits alone
        and #$fc
        ora irq_t2
        sta $d010
        sec
        lda mouse_y
        sbc cursor_hy,x
        clc
        adc #50
        sta $d001
        sta $d003
        rts

hide_cursor:                    ; sprites 0/1 only; others are the application's
        php
        sei
        lda $d015
        and #$fc
        sta $d015
        plp
        rts
show_cursor:
        php
        sei
        lda $d015
        ora #3
        sta $d015
        plp
        rts

; ---------------------------------------------------------------------
; Timing
; ---------------------------------------------------------------------
; wait_frame: wait until the next IRQ
!zone wait_frame
wait_frame:
        lda jiffy
-       cmp jiffy
        beq -
        rts

; wait_frames: A = number of frames
wait_frames:
        sta .n
-       jsr wait_frame
        dec .n
        bne -
        rts
.n:     !byte 0

; wait_release: wait until the mouse button is up
wait_release:
-       lda mbtn
        bne -
        rts

; new_press: carry set if there is a press not handled yet (also if the
; button went down and up while we were busy); it is then handled.
new_press:
        lda mbtn
        bne +
        lda press_count
        cmp press_seen
        bne +
        clc
        rts
+       lda press_count
        sta press_seen
        sec
        rts

; wait_click_or_key: for "click to continue" boxes
wait_click_or_key:
        jsr wait_release
-       jsr get_key
        bne +
        jsr new_press
        bcc -
+       jmp wait_release

; ---------------------------------------------------------------------
; Beep (the classic "Simple Beep"): square wave, short envelope
; ---------------------------------------------------------------------
beep_vol:  !byte 5          ; 0..7, set in the Control Panel
beep_time: !byte 0

!zone beep
beep:
        lda beep_vol
        beq .off
        asl
        ora #1
        sta $d418
        lda #<15000
        sta $d400
        lda #>15000
        sta $d401
        lda #0
        sta $d402
        lda #8
        sta $d403
        lda #$00
        sta $d405
        lda #$f6
        sta $d406
        lda #$41
        sta $d404
        lda #10
        sta beep_time
.off:   rts

beep_tick:
        lda beep_time
        beq +
        dec beep_time
        bne +
        lda #$40
        sta $d404
+       rts

; ---------------------------------------------------------------------
; Random numbers (16 bit Galois LFSR)
; ---------------------------------------------------------------------
rnd_seed: !word $ace1
!zone random
random:
        lda rnd_seed
        lsr rnd_seed+1
        ror rnd_seed
        bcc +
        lda rnd_seed+1
        eor #$b4
        sta rnd_seed+1
+       lda rnd_seed
        eor jiffy
        rts
