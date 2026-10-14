; =====================================================================
; macros.asm - shared by the System and applications (no symbols here)
; =====================================================================

; set rx1,ry1,rx2,ry2 to constants
!macro rect .x1, .y1, .x2, .y2 {
        lda #<(.x1)
        sta rx1
        lda #>(.x1)
        sta rx1+1
        lda #.y1
        sta ry1
        lda #<(.x2)
        sta rx2
        lda #>(.x2)
        sta rx2+1
        lda #.y2
        sta ry2
}

; window X rect from constants
!macro winrect .x1, .y1, .x2, .y2 {
        lda #<(.x1)
        sta w_x1l,x
        lda #>(.x1)
        sta w_x1h,x
        lda #.y1
        sta w_y1,x
        lda #<(.x2)
        sta w_x2l,x
        lda #>(.x2)
        sta w_x2h,x
        lda #.y2
        sta w_y2,x
}

; set tx,ty to constants
!macro txy .x, .y {
        lda #<(.x)
        sta tx
        lda #>(.x)
        sta tx+1
        lda #<(.y)
        sta ty
        lda #>(.y)
        sta ty+1
}

; 16 bit store
!macro st16 .val, .addr {
        lda #<(.val)
        sta .addr
        lda #>(.val)
        sta .addr+1
}


!macro item .text, .key, .act {
        !word .text
        !byte .key, .act
}
!macro sep {
        !word 0
        !byte 0, ACT_NONE
}

