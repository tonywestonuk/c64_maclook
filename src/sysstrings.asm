; =====================================================================
; sysstrings.asm - System text and the C= menu
; =====================================================================

items_apple:                    ; item 0's text comes from the application
        !byte 8
        +item str_none, 0, 0
        +sep
        +item str_o_clock, 0, SACT_CLOCK
        +item str_o_calc, 0, SACT_CALC
        +item str_o_cpanel, 0, SACT_CPANEL
        +item str_o_keycaps, 0, SACT_KEYCAPS
        +item str_o_notepad, 0, SACT_NOTEPAD
        +item str_o_puzzle, 0, SACT_PUZZLE
items_none:
        !byte 0
str_none: !byte 0
str_noload: !text "The Finder could not be loaded from drive 8. Check the disk, then click OK to try again.", 0

str_m_apple:   !byte $14, 0
str_o_calc:    !text "Calculator", 0
str_o_notepad: !text "Note Pad", 0
str_o_puzzle:  !text "Puzzle", 0
str_o_clock:   !text "Alarm Clock", 0
str_o_keycaps: !text "Key Caps", 0
str_o_cpanel:  !text "Control Panel", 0
str_ok:      !text "OK", 0
str_cancel:  !text "Cancel", 0
str_restart: !text "Restart", 0

str_toomany:  !text "Too many windows are open. Close one and try again.", 0
str_welcome:  !text "Welcome to Commodore 64.", 0
str_switchoff: !text "You may now switch off your Commodore 64 safely.", 0

