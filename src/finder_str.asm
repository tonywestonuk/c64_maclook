; =====================================================================
; finder_str.asm - the Finder's menus and text
; =====================================================================

str_m_file:    !text "File", 0
str_m_edit:    !text "Edit", 0
str_m_view:    !text "View", 0
str_m_special: !text "Special", 0

items_file:
        !byte 10
        +item str_i_newfolder, 'N', ACT_NEWFOLDER
        +item str_i_open, 'O', ACT_OPEN
        +item str_i_print, 0, ACT_PRINT
        +item str_i_close, 'W', ACT_CLOSE
        +sep
        +item str_i_info, 'I', ACT_INFO
        +item str_i_dup, 'D', ACT_DUP
        +item str_i_putback, 0, ACT_PUTBACK
        +sep
        +item str_i_eject, 'E', ACT_EJECT
items_edit:
        !byte 9
        +item str_i_undo, 'Z', ACT_UNDO
        +sep
        +item str_i_cut, 'X', ACT_CUT
        +item str_i_copy, 'C', ACT_COPY
        +item str_i_paste, 'V', ACT_PASTE
        +item str_i_clear, 0, ACT_CLEAR
        +item str_i_selall, 'A', ACT_SELALL
        +sep
        +item str_i_showclip, 0, ACT_SHOWCLIP
items_view:
        !byte 6
        +item str_i_vicon, 0, ACT_VICON
        +item str_i_vsmall, 0, ACT_VSMALL
        +item str_i_vname, 0, ACT_VNAME
        +item str_i_vdate, 0, ACT_VDATE
        +item str_i_vsize, 0, ACT_VSIZE
        +item str_i_vkind, 0, ACT_VKIND
items_special:
        !byte 8
        +item str_i_cleanup, 0, ACT_CLEANUP
        +item str_i_empty, 0, ACT_EMPTY
        +sep
        +item str_i_erase, 0, ACT_ERASE
        +item str_i_startup, 0, ACT_STARTUP
        +sep
        +item str_i_restart, 0, ACT_RESTART
        +item str_i_shutdown, 0, ACT_SHUTDOWN

str_i_about:     !text "About the Finder", $13, 0
str_i_newfolder: !text "New Folder", 0
str_i_open:      !text "Open", 0
str_i_print:     !text "Print", 0
str_i_close:     !text "Close", 0
str_i_info:      !text "Get Info", 0
str_i_dup:       !text "Duplicate", 0
str_i_putback:   !text "Put Back", 0
str_i_eject:     !text "Eject", 0
str_i_undo:      !text "Undo", 0
str_i_cut:       !text "Cut", 0
str_i_copy:      !text "Copy", 0
str_i_paste:     !text "Paste", 0
str_i_clear:     !text "Clear", 0
str_i_selall:    !text "Select All", 0
str_i_showclip:  !text "Show Clipboard", 0
str_i_vicon:     !text "by Icon", 0
str_i_vsmall:    !text "by Small Icon", 0
str_i_vname:     !text "by Name", 0
str_i_vdate:     !text "by Date", 0
str_i_vsize:     !text "by Size", 0
str_i_vkind:     !text "by Kind", 0
str_i_cleanup:   !text "Clean Up", 0
str_i_empty:     !text "Empty Trash", 0
str_i_erase:     !text "Erase Disk", $13, 0
str_i_startup:   !text "Set Startup", $13, 0
str_i_restart:   !text "Restart", 0
str_i_shutdown:  !text "Shut Down", 0

; names and words
str_o_trash:   !text "Trash", 0
str_trashdir:  !text ".Trash", 0
str_dotfinder: !text ".finder", 0
str_newfolder: !text "Empty Folder", 0
str_copyof:    !text "Copy of ", 0
str_space:     !text " ", 0
str_dash:      !text "--", 0
str_k:         !text "K", 0
str_months:    !text " Jan", 0, " Feb", 0, " Mar", 0, " Apr", 0, " May", 0, " Jun", 0
               !text " Jul", 0, " Aug", 0, " Sep", 0, " Oct", 0, " Nov", 0, " Dec", 0

str_items:   !text " items", 0
str_item:    !text " item", 0
str_indisk:  !text " in disk", 0
str_avail:   !text " available", 0

str_noeject:  !text "The startup disk can", $27, "t be ejected.", 0
str_sysfile:  !text "That file is used by the system, and can", $27, "t be opened.", 0
str_noapp:    !text "No application can open this document.", 0
str_toolong:  !text "That path is too long.", 0
str_nocopyfolder: !text "Folders can", $27, "t be copied to another disk.", 0
str_e_notfound: !text "That item could not be found.", 0
str_e_exists:   !text "That name is already taken.", 0
str_e_notempty: !text "That folder is not empty.", 0
str_e_noshare:  !text "That disk isn", $27, "t available.", 0
str_e_full:     !text "The disk is full.", 0
str_e_denied:   !text "The disk is locked.", 0
str_e_nowic64:  !text "The WiC64 is not answering.", 0
str_e_other:    !text "The operation could not be completed.", 0
str_erase:    !text "The startup disk can", $27, "t be erased.", 0
str_startup:  !text "System Disk is already the startup disk.", 0
str_about1: !text "Commodore 64 Finder", 0
str_about2: !text "A Finder 5.4 / System 4.1 look-alike", 0
str_about3: !text "in 320x200 hires, 1 MHz, 64K", 0
str_about4: !text "Original Finder by Bruce Horn & Steve Capps", 0
str_about5: !text "38911 BASIC bytes free.  Click to continue.", 0

str_info:     !text "Info", 0
str_kind:     !text "Kind:", 0
str_size:     !text "Size:", 0
str_where:    !text "Where:", 0
str_modified: !text "Modified:", 0
str_desktop:  !text "Desktop", 0

str_k_disk:   !text "startup disk", 0
str_k_share:  !text "network share", 0
str_k_trash:  !text "trash", 0
str_k_folder: !text "folder", 0
str_k_app:    !text "application", 0
str_k_doc:    !text "document", 0
str_k_text:   !text "text document", 0
str_k_sys:    !text "system file", 0

str_clipboard: !text "Clipboard", 0
str_clipempty: !text "The Clipboard is empty.", 0
