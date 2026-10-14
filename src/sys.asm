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
        ; input state: the mouse starts at the top left
        lda #0
        ldx #4
-       sta ms_x,x
        dex
        bpl -
        sta MB_XH
        sta MB_YH
        sta MB_LO
        lda #1                  ; tracking speed: about 1 pixel per count
        sta MB_SPEED
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

irq_body:
        inc jiffy
        bne +
        inc jiffy+1
+       jsr read_mouse
        jsr read_keyboard
        jsr place_sprite
        jmp beep_tick

; ---------------------------------------------------------------------
; Mouse: a Commodore 1351 in port 1 (proportional mode), or a joystick
; in port 2.  The position is 10 bits per axis across the whole screen,
; published in the zero page block $fb-$fe.  See docs/mouse.md.
; ---------------------------------------------------------------------
MB_XH    = $fb          ; X bits 9-2
MB_YH    = $fc          ; Y bits 9-2
MB_LO    = $fd          ; changed, right, left, -, Y bits 1-0, X bits 1-0
MB_SPEED = $fe          ; tracking speed 0-3

ms_x:    !word 0        ; the driver's own copy, 0..1023
ms_y:    !word 0
ms_btn:  !byte 0        ; bit 0 left, bit 1 right
ms_px:   !word $ffff    ; as last published, to spot changes
ms_py:   !word $ffff    ; (same layout as ms_x..ms_btn)
ms_pb:   !byte $ff
ms_sx:   !byte 3        ; step sizes for the current speed
ms_sy:   !byte 5
ms_v:    !byte 0        ; scratch (interrupt only)
ms_m:    !byte 0
ms_s:    !byte 0
ms_jx:   !byte 0
ms_jy:   !byte 0
ms_t:    !word 0
ms_stepx: !byte 2, 3, 5, 6      ; units per 1351 count, by speed
ms_stepy: !byte 3, 5, 8, 10     ; (Y units are 1.6 times smaller)

!zone read_mouse
read_mouse:
        lda MB_SPEED
        and #3
        tay
        lda ms_stepx,y
        sta ms_sx
        lda ms_stepy,y
        sta ms_sy
        ; X: 1351 movement times the step
        lda $d419
        ldy old_potx
        jsr move_check
        sty old_potx
        ldy ms_sx
        jsr ms_scale
        clc
        lda ms_x
        adc irq_t0
        sta ms_x
        lda ms_x+1
        adc irq_t1
        sta ms_x+1
        ; Y: the 1351 counts upwards
        lda $d41a
        ldy old_poty
        jsr move_check
        sty old_poty
        ldy ms_sy
        jsr ms_scale
        sec
        lda ms_y
        sbc irq_t0
        sta ms_y
        lda ms_y+1
        sbc irq_t1
        sta ms_y+1
        ; buttons: port 1 fire = left, up = right; port 2 fire = left
        lda #$ff
        sta $dc00
        lda $dc01
        sta joy1
        lda $dc00
        sta joy2
        lda #0
        sta irq_t2
        lda joy1
        and #$10
        bne +
        lda #1
        sta irq_t2
+       lda joy1
        and #$01
        bne +
        lda irq_t2
        ora #2
        sta irq_t2
+       lda joy2
        and #$10
        bne +
        lda irq_t2
        ora #1
        sta irq_t2
+       lda irq_t2
        sta ms_btn
        beq +
        lda #1                  ; mbtn: any button
+       cmp mbtn
        beq +
        sta mbtn
        cmp #0
        beq +
        inc press_count         ; a new press: remember it, and when
        lda jiffy
        sta press_jiffy
        lda jiffy+1
        sta press_jiffy+1
+       jsr ms_joystick
        jsr ms_clamp
        jsr ms_publish
        jmp ms_pixels

; A = signed count, Y = step -> irq_t0/irq_t1 = count * step (signed)
ms_scale:
        sty ms_m
        sta ms_s
        cmp #$80
        bcc +
        eor #$ff                ; (carry is set: this negates)
        adc #0
+       sta ms_v
        lda #0
        sta irq_t0
        sta irq_t1
        ldy ms_v
        beq .sign
-       clc
        lda irq_t0
        adc ms_m
        sta irq_t0
        bcc +
        inc irq_t1
+       dey
        bne -
.sign:  lda ms_s
        bpl +
        sec
        lda #0
        sbc irq_t0
        sta irq_t0
        lda #0
        sbc irq_t1
        sta irq_t1
+       rts

; joystick in port 2: 1..6 pixels a frame, speeding up while held
ms_joystick:
        lda joy2
        and #$0f
        cmp #$0f
        bne +
        lda #0
        sta joy_spd
        rts
+       lda joy_spd
        cmp #40
        bcs +
        inc joy_spd
+       lsr
        lsr
        lsr
        clc
        adc #1
        sta ms_v                ; pixels
        asl
        adc ms_v
        sta ms_jx               ; X units: 3 per pixel
        lda ms_v
        asl
        asl
        adc ms_v
        sta ms_jy               ; Y units: 5 per pixel
        lda joy2
        lsr
        bcs +                   ; up
        pha
        sec
        lda ms_y
        sbc ms_jy
        sta ms_y
        lda ms_y+1
        sbc #0
        sta ms_y+1
        pla
+       lsr
        bcs +                   ; down
        pha
        clc
        lda ms_y
        adc ms_jy
        sta ms_y
        lda ms_y+1
        adc #0
        sta ms_y+1
        pla
+       lsr
        bcs +                   ; left
        pha
        sec
        lda ms_x
        sbc ms_jx
        sta ms_x
        lda ms_x+1
        sbc #0
        sta ms_x+1
        pla
+       lsr
        bcs +                   ; right
        clc
        lda ms_x
        adc ms_jx
        sta ms_x
        lda ms_x+1
        adc #0
        sta ms_x+1
+       rts

; keep X and Y within 0..1023
ms_clamp:
        ldx #0
.c:     lda ms_x+1,x
        bpl +
        lda #0                  ; below 0
        sta ms_x,x
        sta ms_x+1,x
        beq .n
+       cmp #4
        bcc .n
        lda #<1023              ; 1024 or more
        sta ms_x,x
        lda #>1023
        sta ms_x+1,x
.n:     inx
        inx
        cpx #4
        bne .c
        rts

; write the block at $fb-$fd
ms_publish:
        lda #0
        sta ms_v                ; changed since last time?
        ldx #4
-       lda ms_x,x
        cmp ms_px,x
        beq +
        inc ms_v
        sta ms_px,x
+       dex
        bpl -
        lda ms_x+1              ; high 8 bits
        sta irq_t0
        lda ms_x
        lsr irq_t0
        ror
        lsr irq_t0
        ror
        sta MB_XH
        lda ms_y+1
        sta irq_t0
        lda ms_y
        lsr irq_t0
        ror
        lsr irq_t0
        ror
        sta MB_YH
        lda ms_y                ; low bits
        and #3
        asl
        asl
        sta irq_t0
        lda ms_x
        and #3
        ora irq_t0
        sta irq_t0
        lda ms_btn
        and #1
        beq +
        lda irq_t0
        ora #$20
        sta irq_t0
+       lda ms_btn
        and #2
        beq +
        lda irq_t0
        ora #$40
        sta irq_t0
+       lda MB_LO               ; "changed" stays set until a program clears it
        and #$80
        ldx ms_v
        beq +
        lda #$80
+       ora irq_t0
        sta MB_LO
        rts

; pixels for the OS: mouse_x = X * 5 / 16, mouse_y = Y * 25 / 128
ms_pixels:
        lda ms_x
        sta irq_t0
        lda ms_x+1
        sta irq_t1
        asl irq_t0
        rol irq_t1
        asl irq_t0
        rol irq_t1
        clc
        lda irq_t0
        adc ms_x
        sta irq_t0
        lda irq_t1
        adc ms_x+1
        ldx #4
-       lsr
        ror irq_t0
        dex
        bne -
        sta mouse_x+1
        lda irq_t0
        sta mouse_x
        lda ms_y                ; Y * 8
        sta irq_t0
        lda ms_y+1
        sta irq_t1
        ldx #3
-       asl irq_t0
        rol irq_t1
        dex
        bne -
        lda irq_t0
        sta ms_t
        lda irq_t1
        sta ms_t+1
        asl irq_t0              ; Y * 16
        rol irq_t1
        clc
        lda irq_t0
        adc ms_t
        sta irq_t0
        lda irq_t1
        adc ms_t+1
        sta irq_t1
        clc                     ; + Y = Y * 25
        lda irq_t0
        adc ms_y
        sta irq_t0
        lda irq_t1
        adc ms_y+1
        sta irq_t1
        asl irq_t0              ; / 128 = high byte of (value * 2)
        rol irq_t1
        lda irq_t1
        sta mouse_y
        rts

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
; key_pending: A = 0 (Z set) if no key is waiting
key_pending:
        lda key_head
        sec
        sbc key_tail
        rts

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
