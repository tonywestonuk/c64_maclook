; =====================================================================
; basic_str.asm - BASIC's words: menus, messages, errors
; =====================================================================

; A/X = the bytes free for the program (between it and the top)
ws_free:
        sec
        lda #<WS_END
        sbc prog_end
        pha
        lda #>WS_END
        sbc prog_end+1
        tax
        pla
        rts

str_e_mem:       !text "Out of memory", 0
str_e_long:      !text "Line too long", 0
str_e_lineno:    !text "Line numbers go from 0 to 999", 0
str_e_notnow:    !text "Not in a program here", 0
str_e_npubig:    !text "Matrix size doesn't fit", 0
str_e_noarray:   !text "No such array (DIM it first)", 0
str_e_wic:       !text "WiC64: ", 0
str_e_nowic:     !text "No WiC64 answers", 0
str_error:       !text " error", 0
str_inline:      !text " in line ", 0

str_fe_notfound: !text "That file isn't there.", 0
str_fe_nowic:    !text "No WiC64 answers.", 0
str_fe_full:     !text "The disk is full.", 0
str_fe_denied:   !text "That isn't allowed there.", 0
str_fe_noshare:  !text "The network share isn't connected.", 0
str_fe_other:    !text "The file couldn't be read or written.", 0

str_ab_item:   !text "About BASIC", $13, 0
str_ab_name:   !text "BASIC", 0
str_ab1:       !text "For the Commodore 64 desktop, after QuickBASIC.", 0
str_ab2:       !text "Commodore BASIC V2, with NPU statements", 0
str_ab3:       !text "for the WiC64's matrix unit.", 0
str_ab_free:   !text " bytes free", 0
str_ab5:       !text "Click to continue.", 0
str_output:    !text "Output", 0
str_untitled:  !text "Untitled", 0
str_m_file:    !text "File", 0
str_m_edit:    !text "Edit", 0
str_m_run:     !text "Run", 0
str_m_windows: !text "Windows", 0
str_i_new:     !text "New", 0
str_i_open:    !text "Open", $13, 0
str_i_save:    !text "Save", 0
str_i_saveas:  !text "Save As", $13, 0
str_i_quit:    !text "Quit", 0
str_i_undo:    !text "Undo", 0
str_i_cut:     !text "Cut Line", 0
str_i_copy:    !text "Copy Line", 0
str_i_paste:   !text "Paste", 0
str_i_clear:   !text "Clear Line", 0
str_i_start:   !text "Start", 0
str_i_stop:    !text "Stop", 0
str_i_list:    !text "Listing", 0
str_i_out:     !text "Output", 0
str_qmark:     !text "? "
str_redo:      !text "?Redo from start", 13, "? "
str_redo_end:
str_openq:     !text "Open which program?", 0
str_saveq:     !text "Save the program as:", 0
str_askq1:     !text "Save changes to ", $22, 0
str_askq2:     !text $22, "?", 0
str_dotbas:    !text ".bas", 0
str_b_yes:     !text "Yes", 0
str_b_no:      !text "No", 0
str_b_cancel:  !text "Cancel", 0
str_b_ok:      !text "OK", 0
