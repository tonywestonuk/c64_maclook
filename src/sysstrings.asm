; =====================================================================
; sysstrings.asm - System text and the C= menu
; =====================================================================

items_apple:                    ; item 0's text comes from the application
        !byte 1
        +item str_none, 0, 0
items_none:
        !byte 0
str_none: !byte 0
str_noload: !text "The application could not be loaded. Check the WiC64 and the share.", 0

str_m_apple:   !byte $14, 0
str_ok:      !text "OK", 0
str_cancel:  !text "Cancel", 0
str_restart: !text "Restart", 0

str_toomany:  !text "Too many windows are open. Close one and try again.", 0

