; =====================================================================
; startup.asm - the start-up screen (happy C64, "Welcome to Commodore
; 64.") and shutting down.  Part of the Interface overlay.
; =====================================================================

; boot_screen: grey screen, the happy C64, then the welcome box, which
; stays up while the Finder loads
!zone boot_screen
boot_screen:
        +txy 148, 88
        lda #<icon_happymac
        sta iptr
        lda #>icon_happymac
        sta iptr+1
        lda #0
        sta iflags
        jsr draw_icon
        jsr screen_on
        lda #60
        jsr wait_frames
        ; "Welcome to Commodore 64." stays up while the Finder loads
        +rect 70, 82, 249, 116
        jsr fill_white
        jsr set_black
        jsr frame_rect
        lda #2
        jsr rect_inset
        jsr frame_rect
        lda #1
        jsr rect_inset
        jsr frame_rect
        lda #0
        sta font
        lda #B_OR
        sta tmode
        lda #<str_welcome
        sta tstr
        lda #>str_welcome
        sta tstr+1
        jsr text_width
        lda #<320
        sec
        sbc twidth
        sta tx
        lda #>320
        sbc twidth+1
        lsr
        sta tx+1
        lda tx
        ror
        sta tx
        lda #95
        sta ty
        lda #0
        sta ty+1
        jsr draw_text
        rts

!zone shut_down
shut_down:
        jsr hook_quit
        jsr close_all_quiet
        lda #0
        sta app_loaded
        jsr clip_screen
        +rect 0, 0, 319, 199
        jsr fill_black
        lda #DLG_SHUTDOWN
        sta dlg_kind
        lda #64
        sta dlg_h
        lda #1
        sta dlg_nbtn
        lda #<str_restart
        sta dlg_btn
        lda #>str_restart
        sta dlg_btn+1
        lda #<50
        ldx #66
        ldy #<269
        jsr dlg_open
        jsr dialog_loop
        lda #<str_ok
        sta dlg_btn
        lda #>str_ok
        sta dlg_btn+1
        ldx dlg_win
        lda #0
        sta w_used,x
        jsr z_remove
        lda #80
        sta dlg_h
        jsr clip_screen
        +rect 0, 0, 319, 199
        jsr fill_black
        lda #30
        jsr wait_frames
        jmp reboot

shutdown_draw:
        lda #<icon_note
        sta iptr
        lda #>icon_note
        sta iptr+1
        clc
        lda wc_x1
        adc #10
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #6
        sta ty
        lda #0
        sta ty+1
        sta iflags
        jsr draw_icon
        lda #<str_switchoff
        sta q3
        lda #>str_switchoff
        sta q3+1
        clc
        lda wc_x1
        adc #42
        sta wr_x
        lda wc_x1+1
        adc #0
        sta wr_x+1
        lda wc_y1
        clc
        adc #6
        sta wr_y
        lda #160
        sta wr_w
        lda #11
        sta wr_lh
        lda #0
        sta font
        lda #B_OR
        sta tmode
        jsr wrap_draw
        ldx #0
        jsr draw_button
        ldx #0
        jsr dlg_btn_rect
        lda #3
        jsr rect_outset
        jsr frame_round
        lda #1
        jsr rect_inset
        jmp frame_round

str_welcome:  !text "Welcome to Commodore 64.", 0
str_switchoff: !text "You may now switch off your Commodore 64 safely.", 0
