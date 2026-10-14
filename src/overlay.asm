; =====================================================================
; overlay.asm - the System's overlays: parts of the System that live on
; the share and are loaded into block 2 when they are first needed
;
; Block 2 ($4000-$5fff) is two 4K regions.  Each overlay (src/ovl_*.asm,
; a file in the System Folder) is built for one region and starts with
; a table of jmps to its routines.  The rest of the System, and
; applications through the jump table, call them through stubs made by
; tools/mkovl.py (build/ovl_stubs.asm):
;
;       alert_stop: jsr ovl_call
;                   !byte 1, 1          ; overlay 1, entry 1
;
; ovl_call loads the overlay into its region if it is not there, calls
; the routine with A, X, Y and the flags as they were, and hands them
; back.  It also remembers which overlay is running in each region: if
; a routine is called while another overlay in the same region is still
; running (say a dialog calls an application's drawing routine, which
; draws an oval), that overlay is loaded again before anything returns
; into it.
; Overlays keep no state of their own: they can be reloaded at any time.
; =====================================================================

OVL_BASE = $4000

ovl_resident: !byte 0, 0        ; overlay in each region (0 = none)
ovl_active:   !byte 0, 0        ; overlay running in each region (0 = none)

oc_a:    !byte 0
oc_x:    !byte 0
oc_y:    !byte 0
oc_p:    !byte 0
oc_id:   !byte 0

!zone ovl_call
ovl_call:
        php
        sta oc_a
        stx oc_x
        sty oc_y
        pla
        sta oc_p
        pla                     ; the stub's two bytes follow its jsr
        sta ovp
        pla
        sta ovp+1
        ldy #1
        lda (ovp),y
        sta oc_id
        tax
        iny
        lda (ovp),y             ; routine = overlay's page + entry * 3
        sta ovt
        asl
        adc ovt
        sta ovt
        lda ovl_page-1,x
        adc #0
        sta ovt+1
        ldy ovl_region-1,x
        tya                     ; for ovl_ret: the region and what ran there
        pha
        lda ovl_active,y
        pha
        lda oc_id
        sta ovl_active,y
        cmp ovl_resident,y      ; in place?
        beq +
        jsr ovl_load
+       lda #>(ovl_ret-1)       ; call it, returning through ovl_ret
        pha
        lda #<(ovl_ret-1)
        pha
        lda oc_p
        pha
        lda oc_a
        ldx oc_x
        ldy oc_y
        plp
        jmp (ovt)

ovl_ret:
        php
        sta oc_a
        stx oc_x
        sty oc_y
        pla
        sta oc_p
        pla                     ; what ran in the region before
        tax
        pla
        tay
        txa
        sta ovl_active,y
        beq +                   ; nothing: fine as it is
        cmp ovl_resident,y
        beq +
        jsr ovl_load            ; replaced meanwhile: bring it back
+       lda oc_p
        pha
        lda oc_a
        ldx oc_x
        ldy oc_y
        plp
        rts

; the stack has been reset: nothing is running in any region
ovl_reset:
        lda #0
        sta ovl_active
        sta ovl_active+1
        rts

; ---------------------------------------------------------------------
; ovl_load: A = overlay.  Reads its file into its region; if the share
; does not have it, says so and tries again after a click.  The caller's
; file parameters and q0 are kept.
; ---------------------------------------------------------------------
FS_PARAMS = fs_status - fs_off + 1
ol_id:   !byte 0
ol_save: !fill FS_PARAMS
ol_q0:   !word 0

!zone ovl_load
ovl_load:
        sta ol_id
        ldx #FS_PARAMS-1
-       lda fs_off,x
        sta ol_save,x
        dex
        bpl -
        lda q0
        sta ol_q0
        lda q0+1
        sta ol_q0+1
.try:   ldx ol_id
        ldy ovl_region-1,x
        lda #0                  ; the region is changing
        sta ovl_resident,y
        lda ovl_path_lo-1,x
        sta q0
        lda ovl_path_hi-1,x
        sta q0+1
        jsr fs_load
        bcc .ok
        jsr ovl_error
        jmp .try
.ok:    ldx ol_id
        ldy ovl_region-1,x
        txa
        sta ovl_resident,y
        ldx #FS_PARAMS-1
-       lda ol_save,x
        sta fs_off,x
        dex
        bpl -
        lda ol_q0
        sta q0
        lda ol_q0+1
        sta q0+1
        rts

; the overlay could not be loaded: a box over the middle of the screen
; until a click or a key
!zone ovl_error
ovl_error:
        jsr screen_on           ; (it may be the first thing at start-up)
        jsr clip_push
        jsr clip_screen
        lda #40/8
        sta sv_c1
        lda #279/8
        sta sv_c2
        lda #76
        sta sv_y1
        lda #124
        sta sv_y2
        jsr save_area
        +rect 40, 76, 279, 124
        jsr fill_white
        jsr set_black
        jsr frame_rect
        lda #2
        jsr rect_inset
        jsr frame_rect
        lda #0
        sta font
        lda #B_OR
        sta tmode
        +txy 52, 84
        lda #<str_ovl1
        ldy #>str_ovl1
        jsr draw_str
        +txy 52, 96
        ldx ol_id               ; the file's name
        lda ovl_path_lo-1,x
        ldy ovl_path_hi-1,x
        jsr draw_str
        +txy 52, 108
        lda #<str_ovl2
        ldy #>str_ovl2
        jsr draw_str
        jsr wait_click_or_key
        jsr restore_area
        jmp clip_pop

str_ovl1: !text "The System could not load", 0
str_ovl2: !text "from the share. Click to try again.", 0
