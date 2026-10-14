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

; object names
str_o_disk:    !text "System Disk", 0
str_o_trash:   !text "Trash", 0
str_o_sysfold: !text "System Folder", 0
str_o_brickles: !text "Brickles", 0
str_o_sheet: !text "Spreadsheet", 0
str_o_shapes: !text "Shapes", 0
str_o_readme:  !text "Read Me", 0
str_o_empty:   !text "Empty Folder", 0
str_o_system:  !text "System", 0
str_o_finder:  !text "Finder", 0
str_o_clipf:   !text "Clipboard File", 0
str_o_scrapf:  !text "Scrapbook File", 0

str_items:   !text " items", 0
str_item:    !text " item", 0
str_indisk:  !text " blocks used", 0
str_avail:   !text " blocks free", 0
str_untitled: !text "untitled", 0
str_copyof:  !text "Copy of ", 0

str_noeject:  !text "The startup disk can", $27, "t be ejected.", 0
str_sysfile:  !text "That file is used by the system, and can", $27, "t be opened.", 0
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
str_created:  !text "Created:", 0
str_modified: !text "Modified:", 0
str_locked:   !text "Locked", 0
str_kondisk:  !text " blocks", 0
str_desktop:  !text "Desktop", 0

str_k_disk:   !text "disk", 0
str_k_trash:  !text "trash", 0
str_k_folder: !text "folder", 0
str_k_app:    !text "desk accessory", 0
str_k_doc:    !text "document", 0
str_k_sys:    !text "system document", 0

str_d0: !text "Thu, Apr 2, 1987", 0
str_d1: !text "Fri, Apr 3, 1987", 0
str_d2: !text "Mon, Jun 1, 1987", 0
str_d3: !text "Tue, Jul 14, 1987", 0
str_d4: !text "Mon, Oct 5, 1987", 0
str_d5: !text "Wed, Sep 9, 1987", 0
str_d6: !text "Mon, Oct 5, 1987", 0

str_clipboard: !text "Clipboard", 0
str_clipempty: !text "The Clipboard is empty.", 0

str_readme_text:
        !text "Welcome to the Commodore 64 desktop!|"
        !text "|"
        !text "A tribute to the 1987 Macintosh Finder, running on a "
        !text "Commodore 64 in 2 colour hires mode.|"
        !text "|"
        !text "- Point with the mouse (or a joystick in port 2).|"
        !text "- Double-click icons to open them.|"
        !text "- Drag windows by the title bar, resize with the grow box.|"
        !text "- Drag icons to folders, or to the Trash.|"
        !text "- Click an icon and type to rename it.|"
        !text "- Desk accessories live in the Apple menu.|"
        !text "- The Command key is C= (Alt on a PC keyboard).", 0

