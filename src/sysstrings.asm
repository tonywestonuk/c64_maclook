; =====================================================================
; sysstrings.asm - System text and the C= menu
; =====================================================================

items_apple:                    ; item 0's text comes from the application
        !byte 1
        +item str_none, 0, 0
items_none:
        !byte 0
str_none: !byte 0
str_noload: !text "The Finder could not be loaded from drive 8. Check the disk, then click OK to try again.", 0

str_m_apple:   !byte $14, 0
str_ok:      !text "OK", 0
str_cancel:  !text "Cancel", 0
str_restart: !text "Restart", 0

str_toomany:  !text "Too many windows are open. Close one and try again.", 0
str_welcome:  !text "Welcome to Commodore 64.", 0
str_switchoff: !text "You may now switch off your Commodore 64 safely.", 0

