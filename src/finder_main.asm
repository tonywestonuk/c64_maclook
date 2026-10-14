; =====================================================================
; FINDER - the desktop application, loaded by the System from drive 8.
; It uses the System only through its API (build/sysapi.asm).
; =====================================================================
!cpu 6510
!to "build/finder.prg", cbm
!source "build/sysapi.asm"
!source "src/macros.asm"

* = APP_BASE
        jmp app_init            ; entry points, see events.asm
        jmp app_action
        jmp update_menus
        jmp draw_desk_icons
        jmp app_desk_click
        jmp rename_key
        jmp app_quit
        !word app_classes
        !word app_menus
        !word str_i_about
        !text "APP!"

app_init:
        jmp finder_init

app_quit:
        rts

app_menus:
        !word str_m_file, str_m_edit, str_m_view, str_m_special
        !word items_file, items_edit, items_view, items_special

; mouse down on the desktop: an icon, or deselect
app_desk_click:
        lda #DESKTOP
        jsr obj_at_mouse
        cpx #NOOBJ
        beq +
        jmp icon_click
+       lda #NOOBJ
        sta last_obj
        jmp deselect

!source "src/finder.asm"
!source "src/finder_win.asm"
!source "src/finder_str.asm"
!source "build/icons_finder.asm"

finder_end:

; Storage after the code (not part of the file), cleared by finder_init
; where it matters
FBSS = finder_end
LISTBUF_SIZE = 320
POSBUF_SIZE  = 352
o_names   = FBSS                        ; MAXOBJ names of NAMELEN bytes
o_parent  = o_names + MAXOBJ*NAMELEN    ; container (DESKTOP, NOOBJ = free)
o_oldpar  = o_parent + MAXOBJ           ; where it was before the Trash
o_vol     = o_oldpar + MAXOBJ           ; its volume
o_xl      = o_vol + MAXOBJ              ; its place in its window
o_xh      = o_xl + MAXOBJ
o_y       = o_xh + MAXOBJ               ; ($ff: not placed yet)
o_icon    = o_y + MAXOBJ
o_type    = o_icon + MAXOBJ
o_kl      = o_type + MAXOBJ             ; size in K
o_kh      = o_kl + MAXOBJ
o_dl      = o_kh + MAXOBJ               ; date changed (DOS/FAT)
o_dh      = o_dl + MAXOBJ
o_win     = o_dh + MAXOBJ               ; its window ($ff: none)
o_flags   = o_win + MAXOBJ
vol_n     = o_flags + MAXOBJ            ; the volumes
vol_obj   = vol_n + 1
vol_kind  = vol_obj + MAXVOL
vol_conn  = vol_kind + MAXVOL
vol_total = vol_conn + MAXVOL           ; KB, 4 bytes each
vol_free  = vol_total + MAXVOL*4
vol_namebuf = vol_free + MAXVOL*4
trash_n   = vol_namebuf + NAMELEN       ; things in the Trash
list_buf  = trash_n + 2                 ; fs_list and fs_volumes results
pos_buf   = list_buf + LISTBUF_SIZE     ; a folder's .finder file
pos_len   = pos_buf + POSBUF_SIZE
path_a    = pos_len + 2                 ; paths
path_b    = path_a + 128
label_buf = path_b + 128                ; a name as shown
rn_buf    = label_buf + NAMELEN         ; renaming: the typed name
rn_ext    = rn_buf + NAMELEN            ;   its hidden extension
rn_new    = rn_ext + 8                  ;   the result (and other new names)
rn_max    = rn_new + NAMELEN
ut_v      = rn_max + 1                  ; utoa32
ut_buf    = ut_v + 4
text_title = ut_buf + 12
text_buf  = text_title + NAMELEN        ; a text document
FBSS_END  = text_buf + TEXTMAX
!if FBSS_END > $a000 {
        !error "the Finder and its storage are too large"
}
