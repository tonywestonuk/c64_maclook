; =====================================================================
; finder.asm - the Finder: the WiC64's volumes (its flash, the startup
; disk, and network shares), their folders and files, the desktop, and
; the menu commands
;
; Objects are the volumes and the Trash on the desktop, and the entries
; of every open folder, listed from the WiC64 when the folder's window
; opens and dropped when it closes.  Each object knows its parent, so its
; path ("1:Documents/Notes.txt") is built by walking up to its volume.
; =====================================================================

MAXOBJ  = 32
NAMELEN = 32            ; bytes per name: 31 characters and the end
DESKTOP = $fe
NOOBJ   = $ff
IB_H    = 14            ; info bar height in folder windows
CELL_W  = 68
CELL_H  = 36
MAXVOL  = 8

; kinds of object: containers first
T_DISK   = 0            ; the startup disk (the WiC64's flash)
T_SHARE  = 1            ; a network share
T_TRASH  = 2
T_FOLDER = 3
T_APP    = 4            ; .app
T_DOC    = 5            ; other files
T_TEXT   = 6            ; .txt
T_SYS    = 7            ; .sys, .ovl: parts of the System
T_BAS    = 8            ; .bas: a BASIC program

IC_DISK = 0
IC_SHARE = 1
IC_TRASH = 2
IC_TRASHFULL = 3
IC_FOLDER = 4
IC_DOC = 5
IC_SYSTEM = 6
IC_APP = 7

OBJ_TRASH = 0           ; the Trash; the volumes follow it

CL_FOLDER  = CL_APPBASE+0
CL_INFO    = CL_APPBASE+1
CL_TEXT    = CL_APPBASE+2

app_classes:            ; draw, click, key, idle, close, edit, resize, scroll
        !word folder_draw, folder_click, folder_key, nop_method, folder_close, folder_edit, folder_resize, folder_scroll_m
        !word info_draw, nop_method, nop_method, nop_method, info_close, nop_method, nop_method, nop_method
        !word text_draw, nop_method, nop_method, nop_method, text_close, nop_method, nop_method, nop_method

icon_table:
        !word icon_disk, icon_share, icon_trash, icon_trashfull, icon_folder
        !word icon_doc, icon_system, icon_app
type_icon:              ; the icon of each kind
        !byte IC_DISK, IC_SHARE, IC_TRASH, IC_FOLDER, IC_APP, IC_DOC, IC_DOC, IC_SYSTEM
        !byte IC_DOC

; file kinds by extension (the Finder hides these extensions)
ext_names:
        !text "app", 0, "sys", 0, "ovl", 0, "txt", 0, "sheet", 0, "bas", 0, 0
ext_types:
        !byte T_APP, T_SYS, T_SYS, T_TEXT, T_DOC, T_BAS

OF_SEL = 1
OF_HILITE = 2

sel_obj:   !byte NOOBJ
last_obj:  !byte NOOBJ   ; object of the previous click (double clicks)
renaming:  !byte 0

; ---------------------------------------------------------------------
; finder_init: the Trash and the volumes
; ---------------------------------------------------------------------
!zone finder_init
finder_init:
        ldx #MAXOBJ-1
-       lda #NOOBJ
        sta o_parent,x
        sta o_win,x
        sta o_oldpar,x
        lda #0
        sta o_flags,x
        dex
        bpl -
        lda #NOOBJ
        sta sel_obj
        sta last_obj
        lda #0
        sta renaming
        ; the Trash
        ldx #OBJ_TRASH
        lda #<str_o_trash
        ldy #>str_o_trash
        jsr obj_set_name
        ldx #OBJ_TRASH
        lda #DESKTOP
        sta o_parent,x
        lda #T_TRASH
        sta o_type,x
        lda #IC_TRASH
        sta o_icon,x
        lda #0
        sta o_dl,x
        sta o_dh,x
        lda #<284
        sta o_xl,x
        lda #>284
        sta o_xh,x
        lda #158
        sta o_y,x
        ; the volumes, down the right
        jsr vol_query
        ldx #0
.v:     cpx vol_n
        bcs .done
        stx u5
        jsr new_obj
        bcs .done
        ldy u5
        txa
        sta vol_obj,y
        tya
        sta o_vol,x
        lda #DESKTOP
        sta o_parent,x
        lda vol_kind,y          ; 0 flash, 1 network
        sta o_type,x
        tay
        lda type_icon,y
        sta o_icon,x
        lda #<280
        sta o_xl,x
        lda #>280
        sta o_xh,x
        lda u5                  ; y = 16 + 36 * number
        asl
        asl
        asl
        sta t0
        asl
        asl
        clc
        adc t0
        adc #16
        sta o_y,x
        lda u5                  ; the name, from the volume list
        jsr vol_name_ptr
        ldx u5
        lda vol_obj,x
        tax
        lda q0
        ldy q0+1
        jsr obj_set_name
        ldx u5
        inx
        jmp .v
.done:  jmp count_trash

; X = object -> q1 = its name buffer (X preserved)
obj_name_ptr:
        txa                     ; X * 32
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<o_names
        sta q1
        txa
        lsr
        lsr
        lsr
        adc #>o_names
        sta q1+1
        rts

; X = object, A/Y = name: copy it (at most 31 characters)
obj_set_name:
        sta q0
        sty q0+1
        jsr obj_name_ptr
        ldy #0
-       lda (q0),y
        sta (q1),y
        beq +
        iny
        cpy #NAMELEN-1
        bne -
        lda #0
        sta (q1),y
+       rts

; X = object -> carry clear if it is a container (volume, Trash, folder)
is_container:
        lda o_type,x
        cmp #T_FOLDER+1
        rts

; does the trash hold anything?  A = 1 (Z clear) if so
trash_full:
        lda trash_n
        ora trash_n+1
        beq +
        lda #1
+       rts

; icon pointer for object X -> iptr
obj_icon_ptr:
        lda o_icon,x
        cpx #OBJ_TRASH
        bne +
        stx t0
        jsr trash_full          ; A = 0 empty, 1 full
        ldx t0
        clc
        adc #IC_TRASH
+       asl
        tay
        lda icon_table,y
        sta iptr
        lda icon_table+1,y
        sta iptr+1
        rts

; ---------------------------------------------------------------------
; Names: the extension of a known kind of file is hidden
; ---------------------------------------------------------------------
; ext_of: name at (q1) -> A = kind (T_DOC if not known), Y = where its
; extension's dot is (the length of the name if there is none), carry
; clear if the extension is a known one (and so hidden).  Uses X, t5-t7.
!zone ext_of
ext_of:
        lda #$ff
        sta t6                  ; the last dot
        ldy #0
-       lda (q1),y
        beq +
        cmp #"."
        bne ++
        sty t6
++      iny
        bne -
+       sty t7                  ; length
        ldy t6
        cpy #$ff
        beq .none
        ldx #0                  ; compare the extension with each known one
        stx t5                  ; (kind number)
.ext:   lda ext_names,x
        beq .none
        ldy t6
.ch:    iny
        lda (q1),y
        ora #$20                ; (lower case)
        cmp ext_names,x
        bne .skip
        inx
        lda ext_names,x
        bne .ch
        iny                     ; the name ends here too?
        lda (q1),y
        bne .skip2
        ldx t5
        lda ext_types,x
        ldy t6
        clc
        rts
.skip:  inx                     ; to the next known extension
        lda ext_names,x
        bne .skip
.skip2: inx
        inc t5
        jmp .ext
.none:  lda #T_DOC
        ldy t7
        sec
        rts

; obj_label: X = object -> q1 = the name it shows (q1 points at
; label_buf, or at the name being typed while it is renamed)
!zone obj_label
obj_label:
        lda renaming
        beq +
        cpx sel_obj
        bne +
        lda #<rn_buf
        sta q1
        lda #>rn_buf
        sta q1+1
        rts
+       stx t4
        jsr obj_name_ptr
        lda o_type,x            ; only files have extensions to hide
        cmp #T_APP
        bcc .all
        jsr ext_of
        bcs .all
        sty t7                  ; copy up to the dot
.copy:  ldy #0
-       cpy t7
        beq +
        lda (q1),y
        sta label_buf,y
        iny
        bne -
+       lda #0
        sta label_buf,y
        lda #<label_buf
        sta q1
        lda #>label_buf
        sta q1+1
        ldx t4
        rts
.all:   ldy #0                  ; the whole name
-       lda (q1),y
        beq +
        iny
        bne -
+       sty t7
        jmp .copy

; ---------------------------------------------------------------------
; Volumes
; ---------------------------------------------------------------------
; vol_query: the WiC64's volume list -> vol_n, vol_kind, vol_conn,
; vol_total, vol_free (the names stay in list_buf for vol_name_ptr)
!zone vol_query
vol_query:
        lda #<list_buf
        sta fs_rptr
        lda #>list_buf
        sta fs_rptr+1
        lda #<LISTBUF_SIZE
        sta fs_rmax
        lda #>LISTBUF_SIZE
        sta fs_rmax+1
        jsr fs_volumes
        bcc +
        lda #0                  ; no WiC64: no volumes
        sta vol_n
        rts
+       lda list_buf
        cmp #MAXVOL+1
        bcc +
        lda #MAXVOL
+       sta vol_n
        lda #<(list_buf+1)
        sta q0
        lda #>(list_buf+1)
        sta q0+1
        ldx #0
.v:     cpx vol_n
        bcs .out
        ldy #1
        lda (q0),y
        sta vol_kind,x
        iny
        lda (q0),y
        sta vol_conn,x
        txa                     ; total and free KB
        asl
        asl
        sta t0
        ldy #3
-       tya
        pha
        lda (q0),y
        ldy t0
        sta vol_total,y
        pla
        tay
        iny
        inc t0
        cpy #7
        bne -
        lda t0
        sec
        sbc #4
        sta t0
-       tya
        pha
        lda (q0),y
        ldy t0
        sta vol_free,y
        pla
        tay
        iny
        inc t0
        cpy #11
        bne -
        lda (q0),y              ; name length: to the next entry
        clc
        adc #12
        adc q0
        sta q0
        bcc +
        inc q0+1
+       inx
        jmp .v
.out:   rts

; vol_name_ptr: A = volume -> q0 = its name in list_buf (a copy with an
; end, in vol_namebuf)
!zone vol_name_ptr
vol_name_ptr:
        sta t5
        lda #<(list_buf+1)
        sta q0
        lda #>(list_buf+1)
        sta q0+1
-       lda t5
        beq +
        ldy #11
        lda (q0),y
        clc
        adc #12
        adc q0
        sta q0
        bcc ++
        inc q0+1
++      dec t5
        jmp -
+       ldy #11                 ; copy the name
        lda (q0),y
        cmp #NAMELEN
        bcc +
        lda #NAMELEN-1
+       sta t5
        ldx #0
-       cpx t5
        beq +
        iny
        lda (q0),y
        sta vol_namebuf,x
        inx
        bne -
+       lda #0
        sta vol_namebuf,x
        lda #<vol_namebuf
        sta q0
        lda #>vol_namebuf
        sta q0+1
        rts

; count_trash: trash_n = how many things are in the volumes' .Trash folders
!zone count_trash
count_trash:
        lda #0
        sta trash_n
        sta trash_n+1
        ldx #0
.v:     cpx vol_n
        bcs .out
        lda vol_conn,x
        beq .n
        stx u5
        txa
        jsr trash_path          ; path_a = "n:.Trash"
        jsr list_total
        clc
        adc trash_n
        sta trash_n
        txa
        adc trash_n+1
        sta trash_n+1
        ldx u5
.n:     inx
        jmp .v
.out:   rts

; trash_path: A = volume -> path_a = "n:.Trash"
trash_path:
        ora #"0"
        sta path_a
        lda #":"
        sta path_a+1
        ldx #0
-       lda str_trashdir,x
        sta path_a+2,x
        beq +
        inx
        bne -
+       rts

; list_total: entries in the folder path_a -> A/X (0 if there is none)
list_total:
        lda #0
        sta fs_first
        sta fs_first+1
        sta fs_max
        jsr list_path_a
        bcs +
        lda list_buf
        ldx list_buf+1
        rts
+       lda #0
        tax
        rts

; fs_list of path_a into list_buf
list_path_a:
        lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        lda #<list_buf
        sta fs_rptr
        lda #>list_buf
        sta fs_rptr+1
        lda #<LISTBUF_SIZE
        sta fs_rmax
        lda #>LISTBUF_SIZE
        sta fs_rmax+1
        jmp fs_list

; ---------------------------------------------------------------------
; Paths
; ---------------------------------------------------------------------
; obj_path: X = object -> path_a = its path ("n:" for a volume, else
; "n:name/name/..."; things in the Trash are in "n:.Trash/").  Carry set
; if it is too long.  X preserved.
PATHMAX = 120
op_chain: !fill 12
op_n:    !byte 0
op_x:    !byte 0
!zone obj_path
obj_path:
        stx op_x
        lda #0
        sta op_n
        sta t7                  ; in the Trash?
.up:    ldy op_n
        cpy #12
        bcc .bf532
        jmp .long
.bf532:
        txa
        sta op_chain,y
        inc op_n
        lda o_type,x
        cmp #T_TRASH            ; a volume: the root
        bcc .root
        lda o_parent,x
        cmp #OBJ_TRASH
        beq .trash
        cmp #MAXOBJ
        bcs .long
        tax
        jmp .up
.trash: inc t7
.root:  ldy op_n                ; the volume's number
        dey
        ldx op_chain,y
        lda o_vol,x
        ora #"0"
        sta path_a
        lda #":"
        sta path_a+1
        ldx #2
        lda t7
        beq +
        ldy #0
-       lda str_trashdir,y
        beq +
        sta path_a,x
        inx
        iny
        bne -
+       stx t6                  ; the names, from the top down
        ldy op_n
        lda t7                  ; (a volume at the top has no name in it)
        bne .n
        dey
.n:     dey
        bmi .end
        sty t5
        ldx op_chain,y
        jsr obj_name_ptr
        ldx t6
        lda path_a-1,x          ; "/" unless just after "n:"
        cmp #":"
        beq +
        lda #"/"
        sta path_a,x
        inx
+       ldy #0
-       lda (q1),y
        beq +
        cpx #PATHMAX
        bcs .long
        sta path_a,x
        inx
        iny
        bne -
+       stx t6
        ldy t5
        jmp .n
.end:   ldx t6
        lda #0
        sta path_a,x
        ldx op_x
        clc
        rts
.long:  ldx op_x
        sec
        rts

; path_add: path_a += "/" + the name at (q0) (no "/" just after "n:")
!zone path_add
path_add:
        ldx #0
-       lda path_a,x
        beq +
        inx
        bne -
+       lda path_a-1,x
        cmp #":"
        beq +
        lda #"/"
        sta path_a,x
        inx
+       ldy #0
-       lda (q0),y
        sta path_a,x
        beq +
        inx
        iny
        cpx #PATHMAX
        bcc -
        lda #0
        sta path_a,x
+       rts

; path_a -> path_b
path_save:
        ldx #0
-       lda path_a,x
        sta path_b,x
        beq +
        inx
        bne -
+       rts

; ---------------------------------------------------------------------
; Loading a container's entries
; ---------------------------------------------------------------------
; load_children: X = container (a volume or a folder): its entries
; become objects (those that are objects already stay), placed where
; its .finder file says, or in free places.  The Trash lists the .Trash
; folder of every connected volume.
lc_c:    !byte 0
lc_vol:  !byte 0
lc_first: !word 0
lc_ptr:  !word 0
lc_i:    !byte 0
!zone load_children
load_children:
        stx lc_c
        cpx #OBJ_TRASH
        bne +
        jmp load_trash
+       lda o_vol,x
        sta lc_vol
        jsr obj_path
        bcs .out
        jsr read_positions
        jsr lc_list
        jmp place_new
.out:   rts

load_trash:
        lda #0
        sta pos_len
        sta pos_len+1
        ldx #0
-       cpx vol_n
        bcs +
        stx lc_vol
        lda vol_conn,x
        beq ++
        txa
        jsr trash_path
        jsr lc_list
++      ldx lc_vol
        inx
        bne -
+       jmp place_new

; list path_a into objects, children of lc_c on volume lc_vol
!zone lc_list
lc_list:
        lda #0
        sta lc_first
        sta lc_first+1
.chunk: lda lc_first
        sta fs_first
        lda lc_first+1
        sta fs_first+1
        lda #8
        sta fs_max
        jsr list_path_a
        bcs .out
        lda list_buf+2          ; count
        beq .out
        sta lc_i
        lda #<(list_buf+3)
        sta lc_ptr
        lda #>(list_buf+3)
        sta lc_ptr+1
.ent:   jsr lc_entry
        bcs .out                ; no room for more objects
        lda lc_ptr              ; next entry: 8 + name length
        sta q0
        lda lc_ptr+1
        sta q0+1
        ldy #7
        lda (q0),y
        clc
        adc #8
        adc lc_ptr
        sta lc_ptr
        bcc +
        inc lc_ptr+1
+       inc lc_first
        bne +
        inc lc_first+1
+       dec lc_i
        bne .ent
        lda lc_first            ; more to come?
        cmp list_buf
        lda lc_first+1
        sbc list_buf+1
        bcc .chunk
.out:   rts

; the entry at (lc_ptr) -> an object.  Carry set if there is no room.
!zone lc_entry
lc_entry:
        lda lc_ptr
        sta q2
        lda lc_ptr+1
        sta q2+1
        ldy #7                  ; its name, with an end, in label_buf
        lda (q2),y
        cmp #NAMELEN
        bcc +
        lda #NAMELEN-1
+       sta t5
        ldx #0
-       cpx t5
        beq +
        txa
        clc
        adc #8
        tay
        lda (q2),y
        sta label_buf,x
        inx
        bne -
+       lda #0
        sta label_buf,x
        jsr find_child          ; an object already?
        cpx #NOOBJ
        beq +
        clc
        rts
+       jsr new_obj
        bcc +
        rts
+       stx u4
        lda lc_c
        sta o_parent,x
        lda lc_vol
        sta o_vol,x
        lda #<label_buf
        ldy #>label_buf
        jsr obj_set_name
        ldx u4
        ldy #0                  ; folder or file
        lda (q2),y
        beq .file
        lda #T_FOLDER
        bne .kind
.file:  jsr obj_name_ptr
        jsr ext_of
        ldx u4
.kind:  sta o_type,x
        tay
        lda type_icon,y
        sta o_icon,x
        ; size in K, rounded up, at most 65535: bytes 1-4 of the entry
        ldy #2                  ; K = size >> 10
        lda (q2),y
        sta t0
        iny
        lda (q2),y
        sta t1
        iny
        lda (q2),y
        sta t2
        lsr t2
        ror t1
        ror t0
        lsr t2
        ror t1
        ror t0
        ldy #1                  ; something left over: one more
        lda (q2),y
        bne .up
        iny
        lda (q2),y
        and #3
        beq .k
.up:    inc t0
        bne .k
        inc t1
        bne .k
        inc t2
.k:     lda t2                  ; too big: 65535
        beq +
        lda #$ff
        sta t0
        sta t1
+       lda t0
        sta o_kl,x
        lda t1
        sta o_kh,x
        ldy #5                  ; date
        lda (q2),y
        sta o_dl,x
        iny
        lda (q2),y
        sta o_dh,x
        lda #$ff                ; not placed yet
        sta o_y,x
        lda #0
        sta o_xl,x
        sta o_xh,x
        jsr obj_name_ptr        ; a place from .finder?
        lda q1
        sta q0
        lda q1+1
        sta q0+1
        jsr find_position
        bcs +
        ldx u4
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
+       clc
        rts

; find_child: the child of lc_c on lc_vol named label_buf -> X (NOOBJ)
!zone find_child
find_child:
        ldx #MAXOBJ-1
.l:     lda o_parent,x
        cmp lc_c
        bne .n
        lda o_vol,x
        cmp lc_vol
        bne .n
        jsr obj_name_ptr
        ldy #0
-       lda (q1),y
        cmp label_buf,y
        bne .n
        cmp #0
        beq .yes
        iny
        bne -
.n:     dex
        bpl .l
        ldx #NOOBJ
.yes:   rts

; place_new: children of lc_c without a place go to free places
!zone place_new
place_new:
        ldx #0
.l:     lda o_parent,x
        cmp lc_c
        bne .n
        lda o_y,x
        cmp #$ff
        bne .n
        stx u4
        ldx lc_c
        jsr free_slot
        ldx u4
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
.n:     inx
        cpx #MAXOBJ
        bne .l
        rts

; ---------------------------------------------------------------------
; Where icons are: a hidden ".finder" file in each folder keeps them,
; as records: name length, name, x (2), y
; ---------------------------------------------------------------------
; read_positions: the .finder file of the folder in path_a -> pos_buf,
; pos_len (path_a stays as it was)
!zone read_positions
read_positions:
        jsr path_save
        lda #<str_dotfinder
        sta q0
        lda #>str_dotfinder
        sta q0+1
        jsr path_add
        lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        lda #0
        ldx #3
-       sta fs_off,x
        dex
        bpl -
        lda #<POSBUF_SIZE
        sta fs_len
        lda #>POSBUF_SIZE
        sta fs_len+1
        lda #<pos_buf
        sta fs_rptr
        lda #>pos_buf
        sta fs_rptr+1
        jsr fs_read
        lda fs_rlen
        ldx fs_rlen+1
        bcc +
        lda #0
        tax
+       sta pos_len
        stx pos_len+1
        ; path_a back
        ldx #0
-       lda path_b,x
        sta path_a,x
        beq +
        inx
        bne -
+       rts

; find_position: name at (q0) -> fs_x/fs_y, carry clear if pos_buf has it
!zone find_position
find_position:
        lda #<pos_buf
        sta q2
        lda #>pos_buf
        sta q2+1
.rec:   sec                     ; at the end?
        lda q2
        sbc #<pos_buf
        sta t0
        lda q2+1
        sbc #>pos_buf
        sta t1
        lda t0
        cmp pos_len
        lda t1
        sbc pos_len+1
        bcs .no
        ldy #0
        lda (q2),y
        sta t2                  ; its name's length
        ldx #0
-       cpx t2
        beq .end
        inx
        txa
        tay
        lda (q2),y
        dey
        cmp (q0),y
        bne .next
        jmp -
.end:   ldy t2                  ; and the name has ended too
        lda (q0),y
        bne .next
        iny
        lda (q2),y
        sta fs_x
        iny
        lda (q2),y
        sta fs_x+1
        iny
        lda (q2),y
        sta fs_y
        clc
        rts
.next:  lda t2
        clc
        adc #4
        adc q2
        sta q2
        bcc .rec
        inc q2+1
        jmp .rec
.no:    sec
        rts

; save_positions: X = container: its children's places -> its .finder
!zone save_positions
save_positions:
        cpx #OBJ_TRASH
        bne .bf1011
        jmp .out
.bf1011:
        stx u6
        jsr obj_path
        bcc .bf1014
        jmp .out
.bf1014:
        lda #<str_dotfinder
        sta q0
        lda #>str_dotfinder
        sta q0+1
        jsr path_add
        lda #<pos_buf
        sta q2
        lda #>pos_buf
        sta q2+1
        ldx #0
.l:     stx u5
        lda o_parent,x
        cmp u6
        bne .n
        jsr obj_name_ptr
        ldy #0                  ; length
-       lda (q1),y
        beq +
        iny
        bne -
+       sty t2
        tya                     ; room for it?
        clc
        adc #4
        adc q2
        sta t0
        lda q2+1
        adc #0
        cmp #>(pos_buf+POSBUF_SIZE)
        bcc +
        bne .write
        lda t0
        cmp #<(pos_buf+POSBUF_SIZE)
        bcs .write
+       ldy #0
        lda t2
        sta (q2),y
-       cpy t2
        beq +
        lda (q1),y
        iny
        sta (q2),y
        jmp -
+       ldx u5
        iny
        lda o_xl,x
        sta (q2),y
        iny
        lda o_xh,x
        sta (q2),y
        iny
        lda o_y,x
        sta (q2),y
        iny
        tya
        clc
        adc q2
        sta q2
        bcc .n
        inc q2+1
.n:     ldx u5
        inx
        cpx #MAXOBJ
        bne .l
.write: sec
        lda q2
        sbc #<pos_buf
        sta fs_dlen
        lda q2+1
        sbc #>pos_buf
        sta fs_dlen+1
        lda #<pos_buf
        sta fs_dptr
        lda #>pos_buf
        sta fs_dptr+1
        lda #FSW_REPLACE
        sta fs_mode
        lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        jsr fs_write            ; (a read-only share: never mind)
.out:   rts

; ---------------------------------------------------------------------
; Geometry: where an object's icon is on the screen
; ---------------------------------------------------------------------
ob_x:   !word 0          ; icon box (24x20) top-left
ob_y:   !word 0          ; (both signed: folders scroll)
ob_win: !byte 0
ic_x:   !word 0          ; image top-left
ic_y:   !word 0
lb_x1:  !word 0          ; label rect
lb_x2:  !word 0
lb_y1:  !word 0
lw:     !word 0
ob_id:  !byte 0

; obj_base: X = object.  Carry set if not visible (container closed).
!zone obj_base
obj_base:
        stx ob_id
        lda o_parent,x
        cmp #DESKTOP
        bne .folder
        lda o_xl,x
        sta ob_x
        lda o_xh,x
        sta ob_x+1
        lda o_y,x
        sta ob_y
        lda #0
        sta ob_y+1
        lda #$ff
        sta ob_win
        clc
        rts
.folder:
        cmp #MAXOBJ
        bcs .hidden
        tay
        lda o_win,y
        cmp #$ff
        beq .hidden
        sta ob_win
        tax
        jsr win_get_content
        ldx ob_id
        clc
        lda wc_x1
        adc o_xl,x
        sta ob_x
        lda wc_x1+1
        adc o_xh,x
        sta ob_x+1
        clc
        lda wc_y1
        adc #IB_H
        sta ob_y
        lda #0
        adc #0
        sta ob_y+1
        clc
        lda ob_y
        adc o_y,x
        sta ob_y
        bcc +
        inc ob_y+1
+       ldy ob_win
        sec
        lda ob_x
        sbc w_hscroll,y
        sta ob_x
        lda ob_x+1
        sbc #0
        sta ob_x+1
        sec
        lda ob_y
        sbc w_scroll,y
        sta ob_y
        lda ob_y+1
        sbc #0
        sta ob_y+1
        clc
        rts
.hidden:
        sec
        rts

; obj_geom: after obj_base, compute image and label positions
!zone obj_geom
obj_geom:
        ldx ob_id
        jsr obj_icon_ptr
        ldy #2
        lda (iptr),y            ; width in pixels
        sta t0
        lda #24
        sec
        sbc t0
        lsr
        clc
        adc ob_x
        sta ic_x
        lda ob_x+1
        adc #0
        sta ic_x+1
        ldy #1
        lda (iptr),y            ; height
        sta t0
        lda #20
        sec
        sbc t0
        clc
        adc ob_y
        sta ic_y
        lda ob_y+1
        adc #0
        sta ic_y+1
        ; label
        ldx ob_id
        jsr obj_label
        lda q1
        sta tstr
        lda q1+1
        sta tstr+1
        lda #1
        sta font
        jsr text_width
        lda twidth
        sta lw
        lda twidth+1
        sta lw+1
        ; lb_x1 = ob_x + 12 - lw/2 - 1
        lda lw+1
        lsr
        lda lw
        ror
        sta t0
        clc
        lda ob_x
        adc #11
        sta lb_x1
        lda ob_x+1
        adc #0
        sta lb_x1+1
        sec
        lda lb_x1
        sbc t0
        sta lb_x1
        lda lb_x1+1
        sbc #0
        sta lb_x1+1
        bpl +
        ldx ob_win              ; desktop labels stay on the screen
        bpl +
        lda #0
        sta lb_x1
        sta lb_x1+1
+       clc
        lda lb_x1
        adc lw
        sta lb_x2
        lda lb_x1+1
        adc lw+1
        sta lb_x2+1
        inc lb_x2
        bne +
        inc lb_x2+1
+       clc
        lda ob_y
        adc #21
        sta lb_y1
        lda ob_y+1
        adc #0
        sta lb_y1+1
        rts

; rx/ry = bounding rect of the object (after obj_geom), clamped to screen
!zone obj_bounds
obj_bounds:
        ; x1 = min(ob_x, lb_x1), x2 = max(ob_x+23, lb_x2), signed
        lda ob_x
        sta rx1
        lda ob_x+1
        sta rx1+1
        lda lb_x1
        cmp rx1
        lda lb_x1+1
        sbc rx1+1
        bvc +
        eor #$80
+       bpl +
        lda lb_x1
        sta rx1
        lda lb_x1+1
        sta rx1+1
+       clc
        lda ob_x
        adc #23
        sta rx2
        lda ob_x+1
        adc #0
        sta rx2+1
        lda rx2
        cmp lb_x2
        lda rx2+1
        sbc lb_x2+1
        bvc +
        eor #$80
+       bpl +
        lda lb_x2
        sta rx2
        lda lb_x2+1
        sta rx2+1
+       ; clamp to 0..319
        lda rx2+1
        bmi .off
        lda rx1+1
        bpl +
        lda #0
        sta rx1
        sta rx1+1
+       lda rx2
        cmp #<320
        lda rx2+1
        sbc #>320
        bcc +
        lda #<319
        sta rx2
        lda #>319
        sta rx2+1
+       ; y range ob_y .. ob_y+29, clamped
        lda ob_y+1
        bmi .ytop
        bne .off
        lda ob_y
        sta ry1
        jmp +
.ytop:  lda #0
        sta ry1
+       clc
        lda ob_y
        adc #29
        sta t0
        lda ob_y+1
        adc #0
        bmi .off
        bne .ybot
        lda t0
        cmp #200
        bcc +
.ybot:  lda #199
+       sta ry2
        clc
        rts
.off:   lda #0                  ; entirely off screen: empty rect
        sta ry1
        sta ry2
        sec
        rts

; ---------------------------------------------------------------------
; draw_obj: X = object, inside the current clip
; ---------------------------------------------------------------------
!zone draw_obj
draw_obj:
        jsr obj_base
        bcc .bf509
        jmp .out
.bf509:
        jsr obj_geom
        jsr obj_bounds
        jsr rect_visible
        bcc .bf513
        jmp .out
.bf513:
        ldx ob_id
        lda o_flags,x
        and #OF_SEL|OF_HILITE
        beq +
        lda #ICON_SEL
+       sta iflags
        lda o_win,x             ; open disks and folders look grey
        cmp #$ff
        beq +
        lda iflags
        ora #ICON_OPEN
        sta iflags
+
        lda ic_x
        sta tx
        lda ic_x+1
        sta tx+1
        lda ic_y
        sta ty
        lda ic_y+1
        sta ty+1
        jsr draw_icon
        ; label background
        jsr .labelrect
        ldx ob_id
        lda o_flags,x
        and #OF_SEL
        beq +
        jsr fill_black
        lda #B_BIC
        jmp ++
+       jsr fill_white
        lda #B_OR
++      sta tmode
        clc
        lda lb_x1
        adc #1
        sta tx
        lda lb_x1+1
        adc #0
        sta tx+1
        lda lb_y1
        sta ty
        lda lb_y1+1
        sta ty+1
        ldx ob_id
        jsr obj_label
        lda #1
        sta font
        lda q1
        ldy q1+1
        jsr draw_str
        ; renaming: show an insertion point after the name
        lda renaming
        beq .out
        ldx ob_id
        cpx sel_obj
        bne .out
        jsr .labelrect
        lda rx2
        sta rx1
        lda rx2+1
        sta rx1+1
        jsr invert_rect
.out:   rts
.labelrect:
        lda lb_x1
        sta rx1
        lda lb_x1+1
        sta rx1+1
        lda lb_x2
        sta rx2
        lda lb_x2+1
        sta rx2+1
        lda lb_y1
        sta t0
        lda lb_y1+1
        jsr clamp_y16
        sta ry1
        clc
        lda lb_y1
        adc #8
        sta t0
        lda lb_y1+1
        adc #0
        jsr clamp_y16
        sta ry2
        rts

; A = high, t0 = low byte of a signed y -> A = y clamped to 0..199
clamp_y16:
        bmi .zero
        bne .max
        lda t0
        cmp #200
        bcc .ok
.max:   lda #199
        rts
.zero:  lda #0
.ok:    rts

; redraw the screen area of object X
!zone redraw_obj
redraw_obj:
        cpx #MAXOBJ
        bcs .out
        lda o_parent,x
        cmp #NOOBJ
        beq .out
        jsr obj_base
        bcs .out
        jsr obj_geom
        jsr obj_bounds
        bcs .out
        jsr redraw_obj_rect
.out:   rts
redraw_obj_rect:                ; redraw rx..ry, limited to the container
        jsr limit_to_container
        bcs +
        jmp redraw_region
+       rts

; rx..ry = rx..ry AND the icon area of window ob_win (if any).
; Carry set if that is empty.
!zone limit_to_container
limit_to_container:
        ldx ob_win
        cpx #$ff
        beq .ok
        jsr clip_push
        ldy #5
-       lda rx1,y
        sta clx1,y
        dey
        bpl -
        ldx ob_win
        jsr win_get_content
        lda ry1
        clc
        adc #IB_H
        sta ry1
        jsr clip_rect
        php
        ldy #5
-       lda clx1,y
        sta rx1,y
        dey
        bpl -
        jsr clip_pop
        plp
        rts
.ok:    clc
        rts

; draw all desktop icons (inside the current clip)
!zone draw_desk_icons
draw_desk_icons:
        ldx #0
-       lda o_parent,x
        cmp #DESKTOP
        bne +
        stx u5
        jsr draw_obj
        ldx u5
+       inx
        cpx #MAXOBJ
        bne -
        rts

; ---------------------------------------------------------------------
; Hit testing: object of container A under the mouse -> X (NOOBJ)
; ---------------------------------------------------------------------
oam_c:  !byte 0
!zone obj_at_mouse
obj_at_mouse:
        sta oam_c
        ldx #MAXOBJ-1
.l:     stx u5
        lda o_parent,x
        cmp oam_c
        beq .bf691
        jmp .next
.bf691:
        jsr obj_base
        bcc .bf693
        jmp .next
.bf693:
        jsr obj_geom
        ; image box
        lda ic_x
        sta rx1
        lda ic_x+1
        sta rx1+1
        ldx ob_id
        jsr obj_icon_ptr
        ldy #2
        lda (iptr),y
        clc
        adc ic_x
        sta rx2
        lda ic_x+1
        adc #0
        sta rx2+1
        lda ic_y
        sta t0
        lda ic_y+1
        jsr clamp_y16
        sta ry1
        clc
        lda ob_y
        adc #19
        sta t0
        lda ob_y+1
        adc #0
        jsr clamp_y16
        sta ry2
        jsr mouse_in_rect
        bcc .hit
        ; label
        lda lb_x1
        sta rx1
        lda lb_x1+1
        sta rx1+1
        lda lb_x2
        sta rx2
        lda lb_x2+1
        sta rx2+1
        lda lb_y1
        sta t0
        lda lb_y1+1
        jsr clamp_y16
        sta ry1
        clc
        lda lb_y1
        adc #8
        sta t0
        lda lb_y1+1
        adc #0
        jsr clamp_y16
        sta ry2
        jsr mouse_in_rect
        bcc .hit
.next:  ldx u5
        dex
        bmi +
        jmp .l
+       ldx #NOOBJ
        rts
.hit:   ldx u5
        rts

; ---------------------------------------------------------------------
; Selection
; ---------------------------------------------------------------------
; select_obj: X = object (NOOBJ = deselect)
!zone select_obj
select_obj:
        cpx sel_obj
        beq .same
        stx u4
        jsr end_rename
        ldx sel_obj
        stx u3
        cpx #NOOBJ
        beq +
        lda o_flags,x
        and #$ff-OF_SEL
        sta o_flags,x
+       ldx u4
        stx sel_obj
        cpx #NOOBJ
        beq +
        lda o_flags,x
        ora #OF_SEL
        sta o_flags,x
+       ldx u3
        jsr redraw_obj
        ldx sel_obj
        jsr redraw_obj
.same:  rts

deselect:
        ldx #NOOBJ
        jmp select_obj

; ---------------------------------------------------------------------
; Folder windows
; ---------------------------------------------------------------------
; open_folder: X = container object (a volume, the Trash, a folder)
fo_obj: !byte 0
fo_win: !byte 0
!zone open_folder
open_folder:
        stx fo_obj
        lda o_win,x
        cmp #$ff
        beq +
        tax
        jmp win_select
+       lda o_type,x            ; a network share: connect first
        cmp #T_SHARE
        bne +
        jsr connect_share
        bcc +
        rts
+       jsr win_alloc
        bcc +
        jmp too_many_windows
+       stx fo_win
        ; default rect: staggered
        lda fo_obj
        and #15
        tay
        lda fold_x1,y
        sta w_x1l,x
        lda #0
        sta w_x1h,x
        lda fold_y1,y
        sta w_y1,x
        clc
        lda fold_x1,y
        adc #250
        sta w_x2l,x
        lda #0
        adc #0
        sta w_x2h,x
        lda fold_y1,y
        clc
        adc fold_h,y
        sta w_y2,x
        lda #WF_CLOSE|WF_ZOOM|WF_GROW|WF_VSCROLL|WF_HSCROLL|WF_SHADOW
        sta w_flags,x
        lda #CL_FOLDER
        sta w_class,x
        lda fo_obj
        sta w_data,x
        tax
        jsr obj_name_ptr
        ldx fo_win
        lda q1
        sta w_titl,x
        lda q1+1
        sta w_tith,x
        ldy fo_obj
        txa
        sta o_win,y
        ; zoom from the icon
        ldx fo_obj
        jsr zoom_from_obj
        ; its entries, from the WiC64
        lda #CUR_WATCH
        jsr set_cursor
        ldx fo_obj
        jsr load_children
        lda #CUR_ARROW
        jsr set_cursor
        ldx fo_win
        stx wsr_id
        jsr folder_layout
        ldx fo_win
        jmp win_open

; staggered default positions (by object number & 15)
; (object 0 is the Trash, 1 the startup disk, 2 and up the shares)
fold_x1: !byte 60, 24, 40, 30, 36, 42, 48, 54, 60, 30, 36, 42, 48, 54, 60, 66
fold_y1: !byte 70, 30, 50, 30, 36, 42, 48, 54, 60, 34, 40, 46, 52, 58, 64, 70
fold_h:  !byte 112, 148, 120, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112

; connect_share: X = a share's object.  Carry set (and an alert shown)
; if it could not be connected.
cs_obj: !byte 0
!zone connect_share
connect_share:
        stx cs_obj
        ldy o_vol,x
        lda vol_conn,y
        bne .ok
        lda #CUR_WATCH
        jsr set_cursor
        ldx cs_obj
        lda o_vol,x
        jsr fs_connect
        php
        pha
        lda #CUR_ARROW
        jsr set_cursor
        pla
        plp
        bcs .fail
        jsr vol_query
        jsr count_trash
        ldx #OBJ_TRASH
        jsr redraw_obj
.ok:    ldx cs_obj
        clc
        rts
.fail:  jsr fs_alert
        ldx cs_obj
        sec
        rts

; zr_* = icon rect of object X (sets zr_on if visible)
!zone zoom_from_obj
zoom_from_obj:
        lda #0
        sta zr_on
        jsr obj_base
        bcs +
        lda ob_x+1              ; scrolled off the left
        bmi +
        lda ob_x
        sta zr_x1
        lda ob_x+1
        sta zr_x1+1
        clc
        lda ob_x
        adc #23
        sta zr_x2
        lda ob_x+1
        adc #0
        sta zr_x2+1
        lda ob_y+1
        bne +
        lda ob_y
        cmp #DESK_Y1
        bcc +
        sta zr_y1
        clc
        adc #19
        bcs +
        sta zr_y2
        lda #1
        sta zr_on
+       rts

wsr_id: !byte 0          ; window for folder_layout
; folder_layout: window wsr_id - compute the scroll ranges.
; fl_moved is set if a scroll position had to change.
fl_moved: !byte 0
fl_need:  !word 0
!zone folder_layout
folder_layout:
        lda #0
        sta fl_moved
        ldx wsr_id
        lda w_data,x
        sta u0
        jsr win_get_content
        ; visible height of the icon area
        lda wc_y2
        sec
        sbc wc_y1
        sec
        sbc #IB_H
        sta u1
        ; needed height = max(o_y + 34)
        lda #0
        sta u2
        ldx #MAXOBJ-1
-       lda o_parent,x
        cmp u0
        bne +
        lda o_y,x
        clc
        adc #32
        cmp u2
        bcc +
        sta u2
+       dex
        bpl -
        ldx wsr_id
        lda u2
        sec
        sbc u1
        bcs +
        lda #0
+       sta w_maxscr,x
        cmp w_scroll,x
        bcs +
        sta w_scroll,x
        inc fl_moved
+       ; needed width = max(right edge of icon or label) + 3
        lda #0
        sta fl_need
        sta fl_need+1
        ldx #MAXOBJ-1
.w:     stx u3
        lda o_parent,x
        cmp u0
        bne .wnext
        ; right edge from o_x = max(23, 12 + lw - lw/2)
        jsr obj_name_ptr
        lda q1
        sta tstr
        lda q1+1
        sta tstr+1
        lda #1
        sta font
        jsr text_width
        lda twidth+1
        lsr
        lda twidth
        ror
        sta t0
        sec
        lda twidth
        sbc t0
        clc
        adc #12+3
        cmp #23+3
        bcs +
        lda #23+3
+       ldx u3
        clc
        adc o_xl,x
        sta t0
        lda o_xh,x
        adc #0
        sta t1
        lda fl_need
        cmp t0
        lda fl_need+1
        sbc t1
        bcs .wnext
        lda t0
        sta fl_need
        lda t1
        sta fl_need+1
.wnext: ldx u3
        dex
        stx u3
        bpl .w
        ; hmax = needed - visible width, 0..255
        ldx wsr_id
        jsr win_get_content
        ldx wsr_id
        sec
        lda wc_x2
        sbc wc_x1
        sta t0
        lda wc_x2+1
        sbc wc_x1+1
        sta t1
        inc t0                  ; visible width
        bne +
        inc t1
+       sec
        lda fl_need
        sbc t0
        sta t0
        lda fl_need+1
        sbc t1
        bcs +
        lda #0
        sta t0
        beq ++
+       beq ++
        lda #255
        sta t0
++      lda t0
        sta w_hmax,x
        cmp w_hscroll,x
        bcs +
        sta w_hscroll,x
        inc fl_moved
+       rts

folder_close:
        ldy w_data,x
        lda #$ff
        sta o_win,y
        tya
        pha
        tax
        jsr free_children
        pla                     ; zoom back to the icon
        tax
        stx u5
        jsr zoom_from_obj
        ; and if its own folder is closed, it goes too (and so on up)
        ldx u5
-       lda o_type,x
        cmp #T_FOLDER
        bcc +
        lda o_parent,x
        cmp #MAXOBJ
        bcs +
        tay
        lda o_win,y
        cmp #$ff
        bne +
        sty u5
        jsr pinned
        bcs +
        jsr free_obj
        ldx u5
        jmp -
+       rts

; free_children: X = container: its entries stop being objects, except
; those with a window (or with one inside them)
fc_c:   !byte 0
fc_x:   !byte 0
!zone free_children
free_children:
        stx fc_c
        ldx #MAXOBJ-1
.l:     lda o_parent,x
        cmp fc_c
        bne .n
        stx fc_x
        jsr pinned
        ldx fc_x
        bcs .n
        jsr free_obj
        ldx fc_x
.n:     dex
        bpl .l
        rts

; pinned: X = object -> carry set if it, or something inside it, has a
; window open
!zone pinned
pinned:
        lda o_win,x
        cmp #$ff
        bne .yes
        stx t3
        ldy #MAXOBJ-1
.w:     lda o_win,y             ; each object with a window
        cmp #$ff
        beq .nw
        sty t2
        lda #12
        sta t1
        tya
        tax
-       lda o_parent,x          ; is t3 above it?
        cmp t3
        beq .yes
        cmp #MAXOBJ
        bcs +
        tax
        dec t1
        bne -
+       ldy t2
.nw:    dey
        bpl .w
        ldx t3
        clc
        rts
.yes:   sec
        rts

; free_obj: X = object: no longer an object
free_obj:
        lda #NOOBJ
        sta o_parent,x
        cpx sel_obj
        bne +
        sta sel_obj
        lda #0
        sta renaming
+       cpx last_obj
        bne +
        lda #NOOBJ
        sta last_obj
+       txa                     ; nothing may come back to it
        ldy #MAXOBJ-1
-       cmp o_oldpar,y
        bne +
        lda #NOOBJ
        sta o_oldpar,y
        txa
+       dey
        bpl -
        rts

; M_DRAW
!zone folder_draw
folder_draw:
        lda w_data,x
        sta fd_f
        ; info bar: "n items   nnnK in disk   nnnK available"
        lda #1
        sta font
        lda #B_OR
        sta tmode
        jsr count_items
        sta u0
        ldx #0
        jsr utoa
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcpy
        lda #<str_items
        ldy #>str_items
        ldx u0
        dex
        bne +
        lda #<str_item
        ldy #>str_item
+       sta q0
        sty q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcat
        clc
        lda wc_x1
        adc #4
        sta tx
        lda wc_x1+1
        adc #0
        sta tx+1
        lda wc_y1
        clc
        adc #2
        sta ty
        lda #0
        sta ty+1
        lda #<fd_buf
        ldy #>fd_buf
        jsr draw_str
        ; the other two go only where they fit: free at the right after
        ; the item count, then used in the middle between them
        clc                     ; fd_le = end of the item count + gap
        lda wc_x1
        adc #4+8
        sta fd_le
        lda wc_x1+1
        adc #0
        sta fd_le+1
        clc
        lda fd_le
        adc twidth
        sta fd_le
        lda fd_le+1
        adc twidth+1
        sta fd_le+1
        lda fd_f                ; the container's volume (the Trash: 0)
        tax
        lda o_vol,x
        cpx #OBJ_TRASH
        bne +
        lda #0
+       sta fd_v
        jsr vol_free_str
        jsr .kbuf32
        lda #<str_avail
        sta q0
        lda #>str_avail
        sta q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcat
        lda #<fd_buf
        sta tstr
        lda #>fd_buf
        sta tstr+1
        jsr text_width
        sec
        lda wc_x2
        sbc #3
        sta tx
        lda wc_x2+1
        sbc #0
        sta tx+1
        sec
        lda tx
        sbc twidth
        sta tx
        sta fd_re
        lda tx+1
        sbc twidth+1
        sta tx+1
        sta fd_re+1
        lda tx                  ; tx < fd_le: no room
        cmp fd_le
        lda tx+1
        sbc fd_le+1
        bvc +
        eor #$80
+       bpl +
        jmp .line
+       jsr draw_text
        sec                     ; fd_re = start of free - gap
        lda fd_re
        sbc #8
        sta fd_re
        bcs +
        dec fd_re+1
+       lda fd_v
        jsr vol_used_str
        jsr .kbuf32
        lda #<str_indisk
        sta q0
        lda #>str_indisk
        sta q0+1
        lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jsr strcat
        ; centre
        lda #<fd_buf
        sta tstr
        lda #>fd_buf
        sta tstr+1
        jsr text_width
        clc
        lda wc_x1
        adc wc_x2
        sta tx
        lda wc_x1+1
        adc wc_x2+1
        sta tx+1
        sec
        lda tx
        sbc twidth
        sta tx
        lda tx+1
        sbc twidth+1
        lsr
        sta tx+1
        lda tx
        ror
        sta tx
        lda tx                  ; starts before fd_le: no room
        cmp fd_le
        lda tx+1
        sbc fd_le+1
        bvc +
        eor #$80
+       bmi .line
        clc                     ; ends after fd_re: no room
        lda tx
        adc twidth
        sta t0
        lda tx+1
        adc twidth+1
        sta t1
        lda fd_re
        cmp t0
        lda fd_re+1
        sbc t1
        bvc +
        eor #$80
+       bmi .line
        jsr draw_text
.line:
        ; double line
        lda wc_x1
        sta rx1
        lda wc_x1+1
        sta rx1+1
        lda wc_x2
        sta rx2
        lda wc_x2+1
        sta rx2+1
        lda wc_y1
        clc
        adc #IB_H-4
        sta ry1
        sta ry2
        jsr fill_black
        inc ry1
        inc ry1
        inc ry2
        inc ry2
        jsr fill_black
        ; icons, clipped to the icon area
        jsr clip_push
        lda wc_x1
        sta rx1
        lda wc_x1+1
        sta rx1+1
        lda wc_x2
        sta rx2
        lda wc_x2+1
        sta rx2+1
        lda wc_y1
        clc
        adc #IB_H
        sta ry1
        lda wc_y2
        sta ry2
        jsr clip_rect
        bcs .done
        ldx #0
-       lda o_parent,x
        cmp fd_f
        bne +
        stx u5
        jsr draw_obj
        ldx u5
+       inx
        cpx #MAXOBJ
        bne -
.done:  jmp clip_pop
.kbuf32: ; fd_buf = ut_buf
        lda #<ut_buf
        sta q0
        lda #>ut_buf
        sta q0+1
        jmp +
.kbuf:  ; fd_buf = numbuf
        lda #<numbuf
        sta q0
        lda #>numbuf
        sta q0+1
+       lda #<fd_buf
        sta q1
        lda #>fd_buf
        sta q1+1
        jmp strcpy
fd_f:   !byte 0
fd_v:   !byte 0
fd_le:  !word 0
fd_re:  !word 0
fd_buf: !fill 24

; vol_free_str, vol_used_str: A = volume -> its free or used KB in ut_buf
vol_free_str:
        asl
        asl
        tax
        ldy #0
-       lda vol_free,x
        sta ut_v,y
        inx
        iny
        cpy #4
        bne -
        jmp kb_str
vol_used_str:
        asl
        asl
        tax
        ldy #0
        sec
-       lda vol_total,x
        sbc vol_free,x
        sta ut_v,y
        inx
        iny
        tya                     ; (keep the borrow)
        eor #4
        bne -
        ; fall through

; kb_str: ut_v KB -> ut_buf, "nK", or "nM" or "nG" when it is large
!zone kb_str
kb_str:
        lda #"K"
        sta t4
.big:   lda ut_v+2              ; 64K and up: the next unit
        ora ut_v+3
        beq .num
        ldx #10                 ; / 1024
-       lsr ut_v+3
        ror ut_v+2
        ror ut_v+1
        ror ut_v
        dex
        bne -
        lda t4
        cmp #"K"
        bne +
        lda #"M"
        bne ++
+       lda #"G"
++      sta t4
        jmp .big
.num:   jsr utoa32
        lda t4
        sta ut_buf,x
        lda #0
        sta ut_buf+1,x
        rts

; utoa32: the 32 bit number ut_v -> decimal in ut_buf (ut_v is used up)
!zone utoa32
utoa32:
        ldy #0                  ; digits
.div:   lda #0                  ; ut_v /= 10, A = the remainder
        ldx #32
-       asl ut_v
        rol ut_v+1
        rol ut_v+2
        rol ut_v+3
        rol
        cmp #10
        bcc +
        sbc #10
        inc ut_v
+       dex
        bne -
        ora #"0"
        pha
        iny
        lda ut_v
        ora ut_v+1
        ora ut_v+2
        ora ut_v+3
        bne .div
        ldx #0
-       pla
        sta ut_buf,x
        inx
        dey
        bne -
        lda #0
        sta ut_buf,x
        rts

; count children of fd_f -> A
count_items:
        lda #0
        sta t0
        ldx #MAXOBJ-1
-       lda o_parent,x
        cmp fd_f
        bne +
        inc t0
+       dex
        bpl -
        lda t0
        rts

; M_KEY: typing renames the selected icon
folder_key:
        lda key_char
        jmp rename_key

; M_RESIZE: recompute the scroll range
folder_resize:
        stx wsr_id
        jmp folder_layout

; M_SCROLL: part in win_part_hit
folder_scroll_m:
        lda win_part_hit
        jmp scroll_track

; M_CLICK in a folder window
!zone folder_click
folder_click:
        lda w_data,x
        sta u0
        lda mouse_y
        sec
        sbc wc_y1
        cmp #IB_H
        bcc .none
        lda u0
        jsr obj_at_mouse
        cpx #NOOBJ
        beq .none
        jmp icon_click
.none:  lda #NOOBJ
        sta last_obj
        jmp deselect

; Edit menu in a folder: Select All selects the first item (single selection)
folder_edit:
        rts

; scroll the front folder window by A (signed).  fs_h = 0 scrolls
; vertically, W_H sideways.
fs_h:   !byte 0
!zone folder_scroll
folder_scroll:
        sta t0
        lda zlist
        clc
        adc fs_h
        tax
        lda w_scroll,x
        clc
        adc t0
        bit t0
        bmi .neg
        bcs .max
        cmp w_maxscr,x
        bcc .set
.max:   lda w_maxscr,x
        jmp .set
.neg:   bcs .set
        lda #0
.set:   cmp w_scroll,x
        beq .out
        sta w_scroll,x
        jsr clip_push
        jsr clip_screen
        ldx zlist
        jsr win_get_full
        jsr clip_rect
        ldx zlist
        jsr win_draw_frame
        ldx zlist
        jsr win_draw_content
        jsr clip_pop
.out:   rts

; mouse down in a scroll bar part A of the front window
!zone scroll_track
scroll_track:
        ldx #0
        cmp #P_LEFT             ; horizontal parts are the vertical ones + 5
        bcc +
        sbc #P_LEFT-P_UP
        ldx #W_H
+       stx fs_h
        sta u7
.loop:  lda u7
        cmp #P_UP
        bne +
        lda #-4
        jmp .go
+       cmp #P_DOWN
        bne +
        lda #4
        jmp .go
+       cmp #P_PGUP
        bne +
        lda #-32
        jmp .go
+       cmp #P_PGDN
        bne .thumb
        lda #32
.go:    jsr folder_scroll
        lda #3
        jsr wait_frames
        lda mbtn
        bne .loop
        jmp .done
.thumb: ; drag the thumb: scroll proportional to mouse position in the track
        ldx zlist
        lda fs_h
        jsr win_track
        lda fs_h
        bne .hthumb
        lda mouse_y
        sec
        sbc ry1
        bcs +
        lda #0
+       sta t0                  ; offset in track
        lda ry2
        sec
        sbc ry1
        sta t1                  ; track length
        jmp .scale
.hthumb:
        sec
        lda mouse_x
        sbc rx1
        sta t0
        lda mouse_x+1
        sbc rx1+1
        sta t2
        bcs +
        lda #0
        sta t0
        sta t2
+       sec
        lda rx2
        sbc rx1
        sta t1
        lda rx2+1
        sbc rx1+1
        beq +                   ; over 255 pixels: half scale
        lsr
        ror t1
        lsr t2
        ror t0
+       lda t2
        beq .scale
        lda t1
        sta t0
.scale: lda t0
        cmp t1
        bcc +
        lda t1
        sta t0
+       ; scroll = maxscr * t0 / t1
        lda t1
        sta .len
        lda zlist
        clc
        adc fs_h
        sta .w
        tax
        lda w_maxscr,x
        ldx t0
        jsr mul8
        sta t2
        stx t3
        lda #0
        sta t4
-       lda t2
        sec
        sbc .len
        tay
        lda t3
        sbc #0
        bcc +
        sta t3
        sty t2
        inc t4
        jmp -
+       ldx .w
        lda t4
        sec
        sbc w_scroll,x
        beq +
        jsr folder_scroll
+       jsr wait_frame
        lda mbtn
        beq .done
        jmp .thumb
.done:  lda #0
        sta fs_h
        rts
.len:   !byte 0
.w:     !byte 0

; ---------------------------------------------------------------------
; Clicking and dragging icons
; ---------------------------------------------------------------------
ick_obj: !byte 0
ick_mx:  !word 0
ick_my:  !byte 0
!zone icon_click
icon_click:
        stx ick_obj
        lda dbl_click
        beq +
        cpx last_obj
        bne +
        lda #NOOBJ
        sta last_obj
        jsr wait_release
        ldx ick_obj
        jmp open_obj
+       stx last_obj
        jsr select_obj
        lda mouse_x
        sta ick_mx
        lda mouse_x+1
        sta ick_mx+1
        lda mouse_y
        sta ick_my
.wait:  lda mbtn
        beq .out
        sec
        lda mouse_x
        sbc ick_mx
        clc
        adc #3
        cmp #7
        bcs .drag
        lda mouse_y
        sec
        sbc ick_my
        clc
        adc #3
        cmp #7
        bcs .drag
        jsr wait_frame
        jmp .wait
.drag:  ldx ick_obj
        jmp icon_drag
.out:   rts

dr_obj:  !byte 0
dr_gx:   !word 0         ; grab offset
dr_gy:   !word 0
dr_x:    !word 0         ; outline position (image top-left)
dr_y:    !word 0
dr_w:    !byte 0
dr_h:    !byte 0
dr_tgt:  !byte NOOBJ     ; highlighted drop target
dr_ox:   !byte 0         ; image offset inside the icon box
dr_oy:   !byte 0

!zone icon_drag
icon_drag:
        stx dr_obj
        jsr obj_base
        jsr obj_geom
        ldx dr_obj
        jsr obj_icon_ptr
        ldy #2
        lda (iptr),y
        sta dr_w
        dey
        lda (iptr),y
        sta dr_h
        sec
        lda ic_x
        sbc ob_x
        sta dr_ox
        sec
        lda ic_y
        sbc ob_y
        sta dr_oy
        sec
        lda ick_mx
        sbc ic_x
        sta dr_gx
        lda ick_mx+1
        sbc ic_x+1
        sta dr_gx+1
        sec
        lda ick_my
        sbc ic_y
        sta dr_gy
        lda #0
        sbc ic_y+1
        sta dr_gy+1
        lda #NOOBJ
        sta dr_tgt
        jsr dr_pos
        jsr dr_outline
.loop:  jsr wait_frame
        lda dr_x
        sta dr_px
        lda dr_x+1
        sta dr_px+1
        lda dr_y
        sta dr_py
        jsr dr_pos
        lda dr_x
        cmp dr_px
        bne .moved
        lda dr_x+1
        cmp dr_px+1
        bne .moved
        lda dr_y
        cmp dr_py
        beq .same
.moved: lda dr_x                ; erase at the old position
        sta dr_nx
        lda dr_x+1
        sta dr_nx+1
        lda dr_y
        sta dr_ny
        lda dr_px
        sta dr_x
        lda dr_px+1
        sta dr_x+1
        lda dr_py
        sta dr_y
        jsr dr_outline
        lda dr_nx
        sta dr_x
        lda dr_nx+1
        sta dr_x+1
        lda dr_ny
        sta dr_y
        jsr dr_check_target
        jsr dr_outline
.same:  lda mbtn
        bne .loop
        ; dropped
        jsr dr_outline
        ldx dr_tgt
        cpx #NOOBJ
        beq .notgt
        stx dr_tgt_save
        jsr unhilite
        lda #NOOBJ
        sta dr_tgt
        ldx dr_tgt_save
        jmp drop_into
.notgt: jmp drop_at

dr_nx:  !word 0
dr_ny:  !byte 0
dr_px:  !word 0
dr_py:  !byte 0
dr_tgt_save: !byte 0

; dr_x/dr_y from the mouse, kept on screen
dr_pos:
        sec
        lda mouse_x
        sbc dr_gx
        sta dr_x
        lda mouse_x+1
        sbc dr_gx+1
        sta dr_x+1
        bpl +
        lda #0
        sta dr_x
        sta dr_x+1
+       ; x + w <= 320
        clc
        lda dr_x
        adc dr_w
        sta t0
        lda dr_x+1
        adc #0
        sta t1
        lda t0
        cmp #<321
        lda t1
        sbc #>321
        bcc +
        sec
        lda #<320
        sbc dr_w
        sta dr_x
        lda #>320
        sbc #0
        sta dr_x+1
+       sec
        lda mouse_y
        sbc dr_gy
        sta t0
        lda #0
        sbc dr_gy+1
        bmi .top
        bne .bot
        lda t0
        cmp #DESK_Y1
        bcs +
.top:   lda #DESK_Y1
        sta t0
+       lda t0
        clc
        adc dr_h
        bcs .bot
        cmp #201
        bcc +
.bot:   lda #200
        sec
        sbc dr_h
        sta t0
+       lda t0
        sta dr_y
        rts

dr_outline:
        jsr clip_push
        jsr clip_screen
        lda #DESK_Y1
        sta cly1
        ldx dr_obj
        jsr obj_icon_ptr
        lda dr_x
        sta tx
        lda dr_x+1
        sta tx+1
        lda dr_y
        sta ty
        lda #0
        sta ty+1
        lda #ICON_OUTLINE
        sta iflags
        jsr draw_icon
        jmp clip_pop

; highlight the container under the pointer
!zone dr_check_target
dr_check_target:
        jsr find_target
        cpx dr_tgt
        beq .out
        stx u3
        ; erase the outline while icons are redrawn
        jsr dr_outline
        ldx dr_tgt
        jsr unhilite
        ldx u3
        stx dr_tgt
        cpx #NOOBJ
        beq +
        lda o_flags,x
        ora #OF_HILITE
        sta o_flags,x
        jsr redraw_obj
+       jsr dr_outline
.out:   rts

unhilite:
        cpx #NOOBJ
        beq +
        lda o_flags,x
        and #$ff-OF_HILITE
        sta o_flags,x
        jmp redraw_obj
+       rts

; container object under the mouse that dr_obj could be dropped into
!zone find_target
find_target:
        jsr win_at_mouse
        cpx #$ff
        bne .win
        lda #DESKTOP
        jmp .look
.win:   lda w_class,x
        cmp #CL_FOLDER
        bne .none
        stx u2
        jsr win_get_content
        jsr mouse_in_rect
        bcs .none
        ldx u2
        lda w_data,x
.look:  jsr obj_at_mouse
        cpx #NOOBJ
        beq .none
        cpx dr_obj
        beq .none
        jsr is_container
        bcs .none
        rts
.none:  ldx #NOOBJ
        rts

; ---------------------------------------------------------------------
; Dropping
; ---------------------------------------------------------------------
; drop into container X
!zone drop_into
drop_into:
        stx u4
        lda #0
        sta mc_place            ; (to a free place)
        ldx dr_obj
        lda o_type,x
        cmp #T_TRASH
        bcc .vol
        beq .no
        lda u4                  ; a file or folder
        cmp #OBJ_TRASH
        bne +
        jmp to_trash
+       jsr obj_inside          ; not a folder into itself or its contents
        bcc .no
        ldx dr_obj
        lda o_parent,x
        cmp u4
        beq .no                 ; already there
        jmp move_or_copy
.vol:   lda u4                  ; a volume: only to the Trash, to eject it
        cmp #OBJ_TRASH
        bne .no
        jmp eject_vol
.no:    rts

; carry clear if object A is X itself or inside X
!zone obj_inside
obj_inside:
        stx t5
        ldy #10
-       cmp t5
        beq .yes
        cmp #MAXOBJ
        bcs .no
        tax
        lda o_parent,x
        dey
        bne -
.no:    sec
        rts
.yes:   clc
        rts

; dropped on empty space
!zone drop_at
drop_at:
        ldx dr_obj
        lda o_type,x
        sta u5
        jsr win_at_mouse
        cpx #$ff
        bne .win
        ; desktop: only the volumes and the Trash live there
        lda u5
        cmp #T_FOLDER
        bcs .no
        sec
        lda dr_x
        sbc dr_ox
        sta fs_x
        lda dr_x+1
        sbc #0
        sta fs_x+1
        bpl +
        lda #0
        sta fs_x
        sta fs_x+1
+       lda dr_y
        sec
        sbc dr_oy
        cmp #DESK_Y1
        bcs +
        lda #DESK_Y1
+       cmp #170
        bcc +
        lda #170
+       sta fs_y
        lda fs_x
        cmp #<290
        lda fs_x+1
        sbc #>290
        bcc +
        lda #<290
        sta fs_x
        lda #>290
        sta fs_x+1
+       ldx dr_obj
        lda #DESKTOP
        jmp move_obj
.win:   lda w_class,x
        cmp #CL_FOLDER
        beq .bf1942
.no:    rts
.bf1942:
        lda u5                  ; volumes and the Trash stay on the desktop
        cmp #T_FOLDER
        bcc .no
        stx u2
        jsr win_get_content
        jsr mouse_in_rect
        bcs .no
        ldx u2
        lda w_data,x
        sta u4
        ldx dr_obj
        jsr obj_inside
        bcc .no
        ; position relative to the icon area
        ldx u2
        sec
        lda dr_x
        sbc dr_ox
        sta t0
        lda dr_x+1
        sbc #0
        sta t1
        sec
        lda t0
        sbc wc_x1
        sta fs_x
        lda t1
        sbc wc_x1+1
        sta fs_x+1
        bpl +
        lda #0
        sta fs_x
        sta fs_x+1
+       clc
        lda fs_x
        adc w_hscroll,x
        sta fs_x
        bcc +
        inc fs_x+1
+       lda dr_y
        sec
        sbc dr_oy
        sec
        sbc wc_y1
        bcs +
        lda #0
+       sec
        sbc #IB_H
        bcs +
        lda #0
+       clc
        adc w_scroll,x
        sta fs_y
        lda #1                  ; at this place
        sta mc_place
        ldx dr_obj
        lda o_parent,x
        cmp u4
        bne .other
        lda u4                  ; the same folder: just a new place
        jsr move_obj
        ldx u4
        jmp save_positions
.other: lda u4
        cmp #OBJ_TRASH
        bne +
        jmp to_trash
+       jmp move_or_copy

; ---------------------------------------------------------------------
; Moving and copying on the WiC64
; ---------------------------------------------------------------------
; move_or_copy: dr_obj into container u4.  On the same volume it moves;
; to another one, a file is copied.  mc_place: 0 = to a free place,
; else to fs_x/fs_y.
mc_place: !byte 0
mc_obj:   !byte 0
!zone move_or_copy
move_or_copy:
        ldx dr_obj
        stx mc_obj
        ldy u4
        lda o_vol,y
        cmp o_vol,x
        bne .copy
        jsr paths_to            ; path_b = where it is, path_a = where it goes
        bcc .bf3060
        jmp .long
.bf3060:
        jsr fs_rename
        bcc +
        jmp fs_alert
+       jsr .place
        ldx mc_obj
        lda u4
        jsr move_obj
        ldx u4
        jmp save_positions
.copy:  lda o_type,x
        cmp #T_FOLDER
        bne +
        lda #<str_nocopyfolder
        ldy #>str_nocopyfolder
        jmp alert_stop
+       jsr paths_to
        bcc .bf3077
        jmp .long
.bf3077:
        lda #CUR_WATCH
        jsr set_cursor
        jsr fs_copy
        php
        pha
        lda #CUR_ARROW
        jsr set_cursor
        pla
        plp
        bcc +
        jmp fs_alert
+       jsr vol_query           ; (less room there now)
        ldx u4                  ; the copy shows if its folder is open
        lda o_win,x
        cmp #$ff
        beq .out
        jsr new_obj
        bcs .out
        stx u5
        ldy mc_obj              ; the same as the original...
        lda o_type,y
        sta o_type,x
        lda o_icon,y
        sta o_icon,x
        lda o_kl,y
        sta o_kl,x
        lda o_kh,y
        sta o_kh,x
        lda o_dl,y
        sta o_dl,x
        lda o_dh,y
        sta o_dh,x
        lda u4                  ; ...but there
        sta o_parent,x
        tay
        lda o_vol,y
        sta o_vol,x
        ldx mc_obj
        jsr obj_name_ptr
        ldx u5
        lda q1
        ldy q1+1
        jsr obj_set_name
        jsr .place
        ldx u5
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
        jsr redraw_obj
        lda u4
        jsr refresh_info
        ldx u4
        jmp save_positions
.long:  lda #<str_toolong
        ldy #>str_toolong
        jmp alert_stop
.out:   rts
.place: lda mc_place            ; a free place unless dropped at one
        bne +
        ldx u4
        jmp free_slot
+       rts

; paths_to: path_b = path of mc_obj, path_a = path of u4 + "/" + its name.
; q0 = path_b, q1 = path_a for fs_rename / fs_copy.  Carry set if too long.
paths_to:
        ldx mc_obj
        jsr obj_path
        bcs +
        jsr path_save
        ldx u4
        jsr obj_path
        bcs +
        ldx mc_obj
        jsr obj_name_ptr
        lda q1
        sta q0
        lda q1+1
        sta q0+1
        jsr path_add
        lda #<path_b
        sta q0
        lda #>path_b
        sta q0+1
        lda #<path_a
        sta q1
        lda #>path_a
        sta q1+1
        clc
+       rts

; to_trash: dr_obj into the Trash: it moves to .Trash on its volume
tt_obj: !byte 0
tt_try: !byte 0
!zone to_trash
to_trash:
        ldx dr_obj
        stx tt_obj
        lda o_vol,x             ; the volume needs a .Trash
        jsr trash_path
        lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        jsr fs_mkdir            ; (it may be there already)
        lda #0
        sta tt_try
.try:   ldx tt_obj
        jsr obj_path
        bcs .long
        jsr path_save
        ldx tt_obj
        lda o_vol,x
        jsr trash_path
        ldx tt_obj
        jsr obj_name_ptr
        lda q1
        sta q0
        lda q1+1
        sta q0+1
        jsr path_add
        lda #<path_b
        sta q0
        lda #>path_b
        sta q0+1
        lda #<path_a
        sta q1
        lda #>path_a
        sta q1+1
        jsr fs_rename
        bcc .ok
        cmp #FS_EXISTS          ; an older one of that name: away with it
        bne .err
        lda tt_try
        bne .err
        inc tt_try
        jsr delete_tree
        jmp .try
.err:   jmp fs_alert
.long:  lda #<str_toolong
        ldy #>str_toolong
        jmp alert_stop
.ok:    ldx tt_obj
        lda o_parent,x
        sta o_oldpar,x
        inc trash_n             ; (before move_obj, which redraws the Trash)
        bne +
        inc trash_n+1
+       lda mc_place
        bne +
        ldx #OBJ_TRASH
        jsr free_slot
+       ldx tt_obj
        lda #OBJ_TRASH
        jmp move_obj

; eject_vol: X = a volume: a share is disconnected (its windows close);
; the startup disk can't be ejected
ev_vol: !byte 0
!zone eject_vol
eject_vol:
        lda o_type,x
        cmp #T_SHARE
        beq +
        lda #<str_noeject
        ldy #>str_noeject
        jmp alert_stop
+       lda o_vol,x
        sta ev_vol
        ldy #MAXWIN-1           ; close its windows, and the Trash's
.w:     sty u5
        lda w_used,y
        beq .nw
        lda w_class,y
        cmp #CL_FOLDER
        bne .nw
        ldx w_data,y
        cpx #OBJ_TRASH
        beq .close
        lda o_vol,x
        cmp ev_vol
        bne .nw
.close: ldx u5
        jsr win_close
.nw:    ldy u5
        dey
        bpl .w
        ldx #MAXOBJ-1           ; nothing on it is an object any more
-       lda o_parent,x
        cmp #NOOBJ
        beq +
        lda o_type,x
        cmp #T_TRASH
        bcc +
        lda o_vol,x
        cmp ev_vol
        bne +
        cpx #OBJ_TRASH
        beq +
        jsr free_obj
+       dex
        bpl -
        lda ev_vol
        jsr fs_disconnect
        jsr vol_query
        jsr count_trash
        ldx #OBJ_TRASH
        jmp redraw_obj

; delete_tree: delete the file or folder path_a, and everything in it
dt_len: !byte 0
!zone delete_tree
delete_tree:
        lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        lda #<list_buf
        sta fs_rptr
        lda #>list_buf
        sta fs_rptr+1
        jsr fs_stat
        bcs .out
        lda list_buf            ; a file: just that
        bne +
        jmp .del
+       jsr path_len
        stx dt_len
.loop:  lda #0                  ; the folder's first entry
        sta fs_first
        sta fs_first+1
        lda #1
        sta fs_max
        jsr list_path_a
        bcs .out
        lda list_buf+2
        beq .rmdir
        ldx list_buf+10         ; its name
        cpx #NAMELEN
        bcc +
        ldx #NAMELEN-1
+       lda #0
        sta label_buf,x
-       dex
        bmi +
        lda list_buf+11,x
        sta label_buf,x
        jmp -
+       lda #<label_buf
        sta q0
        lda #>label_buf
        sta q0+1
        jsr path_add
        lda list_buf+3          ; a folder: into it
        bne .loop
        jsr .del                ; a file: delete it, back up
        bcs .out
        jsr path_up
        jmp .loop
.rmdir: jsr .del
        bcs .out
        jsr path_len
        cpx dt_len
        beq .out
        jsr path_up
        jmp .loop
.del:   lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        jmp fs_delete
.out:   rts

; path_len: X = length of path_a
path_len:
        ldx #0
-       lda path_a,x
        beq +
        inx
        bne -
+       rts

; path_up: path_a loses its last name
path_up:
        jsr path_len
-       dex
        bmi +
        lda path_a,x
        cmp #"/"
        beq +
        cmp #":"
        bne -
        inx                     ; (keep "n:")
+       lda #0
        sta path_a,x
        rts

; fs_alert: A = the status of a file call that failed
!zone fs_alert
fs_alert:
        ldx #0
-       ldy fs_errs,x
        beq .other
        cmp fs_errs,x
        beq +
        inx
        bne -
+       lda fs_err_lo,x
        ldy fs_err_hi,x
        jmp alert_stop
.other: lda #<str_e_other
        ldy #>str_e_other
        jmp alert_stop
fs_errs:   !byte FS_NOTFOUND, FS_EXISTS, FS_NOTEMPTY, FS_NOSHARE, FS_FULL, FS_DENIED, FS_NOWIC64, 0
fs_err_lo: !byte <str_e_notfound, <str_e_exists, <str_e_notempty, <str_e_noshare, <str_e_full, <str_e_denied, <str_e_nowic64
fs_err_hi: !byte >str_e_notfound, >str_e_exists, >str_e_notempty, >str_e_noshare, >str_e_full, >str_e_denied, >str_e_nowic64

; ---------------------------------------------------------------------
; move_obj: X = object, A = new container, fs_x/fs_y = position
; ---------------------------------------------------------------------
fs_x:   !word 0
fs_y:   !byte 0
mo_obj: !byte 0
mo_old: !byte 0
mo_new: !byte 0
mo_rect: !fill 6
mo_trash: !byte 0

!zone move_obj
move_obj:
        stx mo_obj
        sta mo_new
        lda o_parent,x
        sta mo_old
        jsr trash_full
        sta mo_trash
        ; old area
        ldx mo_obj
        lda #0
        sta mo_rect+5           ; empty unless visible
        jsr obj_base
        bcs +
        jsr obj_geom
        jsr obj_bounds
        bcs +
        jsr limit_to_container
        bcs +
        ldx #5
-       lda rx1,x
        sta mo_rect,x
        dex
        bpl -
+       ldx mo_obj
        lda mo_new
        cmp #OBJ_TRASH
        bne +
        lda mo_old
        sta o_oldpar,x
+       lda mo_new
        sta o_parent,x
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
        ; repaint where it was
        lda mo_rect+5
        beq +
        ldx #5
-       lda mo_rect,x
        sta rx1,x
        dex
        bpl -
        jsr redraw_region
+       ldx mo_obj
        jsr redraw_obj
        lda mo_old
        cmp mo_new
        beq +
        jsr refresh_info_old
        lda mo_new
        jsr refresh_info
+       ; trash icon changes between empty and full
        jsr trash_full
        cmp mo_trash
        beq +
        ldx #OBJ_TRASH
        jsr redraw_obj
+       ldx mo_new              ; into a closed folder: not an object now
        cpx #MAXOBJ
        bcs +
        lda o_win,x
        cmp #$ff
        bne +
        ldx mo_obj
        jsr pinned
        bcs +
        jsr free_obj
+       rts
refresh_info_old:
        lda mo_old
        ; fall through
; refresh_info: A = container - repaint its info bar, recompute scrolling
refresh_info:
        cmp #MAXOBJ
        bcs +
        tax
        lda o_win,x
        cmp #$ff
        beq +
        tax
        stx wsr_id
        jsr folder_layout
        ldx wsr_id
        jsr win_get_rect
        lda fl_moved            ; scrolled back: everything moved
        bne .all
        ldx wsr_id
        jsr win_get_content
        lda ry1
        clc
        adc #IB_H-1
        sta ry2
        jsr redraw_region
        ; scroll bars too
        ldx wsr_id
        jsr win_get_rect
        sec
        lda rx2
        sbc #SB_W
        sta rx1
        lda rx2+1
        sbc #0
        sta rx1+1
        jsr redraw_region
        ldx wsr_id
        jsr win_get_rect
        lda ry2
        sec
        sbc #SB_W
        sta ry1
.all:   jmp redraw_region
+       rts

; free_slot: X = container -> fs_x/fs_y = first free grid cell
fsl_c:  !byte 0
!zone free_slot
free_slot:
        stx fsl_c
        lda #4
        sta fs_y
.row:   lda #18
        sta fs_x
        lda #0
        sta fs_x+1
.col:   ldx #MAXOBJ-1
-       lda o_parent,x
        cmp fsl_c
        bne +
        lda o_y,x               ; (not placed yet)
        cmp #$ff
        beq +
        lda o_xh,x
        bne +
        lda o_xl,x
        sec
        sbc fs_x
        clc
        adc #CELL_W/2
        cmp #CELL_W
        bcs +
        lda o_y,x
        sec
        sbc fs_y
        clc
        adc #18
        cmp #36
        bcc .taken
+       dex
        bpl -
        rts
.taken: lda fs_x
        clc
        adc #CELL_W
        sta fs_x
        cmp #18+CELL_W*3
        bcc .col
        lda fs_y
        clc
        adc #CELL_H
        sta fs_y
        cmp #200
        bcc .row
        lda #18
        sta fs_x
        lda #4
        sta fs_y
        rts

; ---------------------------------------------------------------------
; Opening things
; ---------------------------------------------------------------------
!zone open_obj
open_obj:
        lda o_type,x
        cmp #T_FOLDER+1
        bcs +
        jmp open_folder
+       cmp #T_APP
        beq launch_obj
        cmp #T_TEXT
        bne +
        jmp text_open
+       cmp #T_BAS
        bne +
        jmp open_bas
+       cmp #T_SYS
        bne +
        lda #<str_sysfile
        ldy #>str_sysfile
        jmp alert_note
+       lda #<str_noapp         ; a document of no known kind
        ldy #>str_noapp
        jmp alert_note

; open_bas: X = a BASIC program: BASIC, with the program's path
open_bas:
        jsr obj_path
        bcs launch_obj          ; (too long: launch_obj says so)
        ldy #0
-       lda path_a,y
        sta app_doc,y
        beq +
        iny
        bne -
+       ldy #0
-       lda str_basic,y
        sta path_a,y
        beq launch_doc
        iny
        bne -

; launch_obj: X = an application: the System replaces the Finder with it
!zone launch_obj
launch_obj:
        lda #0                  ; (no document for it)
        sta app_doc
        jsr obj_path
        bcc launch_doc
        lda #<str_toolong
        ldy #>str_toolong
        jmp alert_stop
launch_doc:
        jsr zoom_from_obj
        lda zr_on               ; zoom from the icon to the whole screen
        beq +
        +rect 0, DESK_Y1, 319, 199
        jsr zoom_to_rect
+       jsr path_len
        lda #<path_a
        ldy #>path_a
        jmp launch_app

; ---------------------------------------------------------------------
; Renaming: typing while an icon is selected replaces its name
; ---------------------------------------------------------------------
!zone rename_key
rename_key:                     ; A = key
        ldx sel_obj
        cpx #NOOBJ
        bne .bf3626
        jmp .out
.bf3626:
        sta u4
        lda o_type,x            ; volumes and the Trash keep their names
        cmp #T_FOLDER
        bcs .bf3630
        jmp .out
.bf3630:
        lda u4
        cmp #K_RETURN
        bne +
        jmp end_rename
+       ldx sel_obj             ; the label's place, to repaint
        jsr obj_base
        bcc .bf3637
        jmp .out
.bf3637:
        jsr obj_geom
        jsr obj_bounds
        jsr limit_to_container
        ldx #5
-       lda rx1,x
        sta mo_rect,x
        dex
        bpl -
        lda renaming
        bne +
        lda #1                  ; typing starts a new name; a hidden
        sta renaming            ; extension stays
        lda #0
        sta rn_buf
        sta rn_ext
        ldx sel_obj
        jsr obj_name_ptr
        jsr ext_of
        bcs ++
        ldx #0
-       lda (q1),y
        sta rn_ext,x
        beq ++
        inx
        iny
        bne -
++      ldx #0                  ; room for the name
-       lda rn_ext,x
        beq +
        inx
        bne -
+       stx t0
        lda #NAMELEN-1
        sec
        sbc t0
        sta rn_max
+       ldy #0                  ; find the end of the name
-       lda rn_buf,y
        beq +
        iny
        bne -
+       lda u4
        cmp #K_DEL
        bne .add
        cpy #0
        beq .redraw
        dey
        lda #0
        sta rn_buf,y
        jmp .redraw
.add:   cmp #32
        bcc .out
        cmp #127
        bcs .out
        cmp #"/"                ; (not in names)
        beq .out
        cmp #":"
        beq .out
        cpy rn_max
        bcs .out
        sta rn_buf,y
        iny
        lda #0
        sta rn_buf,y
.redraw:
        ldx #5
-       lda mo_rect,x
        sta rx1,x
        dex
        bpl -
        jsr redraw_region
        ldx sel_obj
        jsr redraw_obj
.out:   rts

; end_rename: the typed name (with any hidden extension) becomes the
; object's name on the WiC64.  An empty name changes nothing.
!zone end_rename
end_rename_now:
end_rename:
        lda renaming
        bne +
        rts
+       ldx sel_obj             ; where the typed label is, to repaint
        jsr obj_base
        bcs +
        jsr obj_geom
        jsr obj_bounds
        jsr limit_to_container
        ldx #5
-       lda rx1,x
        sta mo_rect,x
        dex
        bpl -
+       lda #0
        sta renaming
        lda rn_buf
        bne .bf3735
        jmp .done
.bf3735:
        ldx #0                  ; rn_new = rn_buf + rn_ext
        ldy #0
-       lda rn_buf,x
        beq +
        sta rn_new,y
        inx
        iny
        bne -
+       ldx #0
-       lda rn_ext,x
        sta rn_new,y
        beq +
        inx
        iny
        bne -
+       ldx sel_obj             ; the same as before?
        jsr obj_name_ptr
        ldy #0
-       lda (q1),y
        cmp rn_new,y
        bne .new
        cmp #0
        beq .done
        iny
        bne -
.new:   ldx sel_obj             ; path_b = old path, path_a = new one
        stx mc_obj
        jsr obj_path
        bcs .done
        jsr path_save
        ldx mc_obj
        lda o_parent,x
        cmp #MAXOBJ
        bcs .done
        tax
        jsr obj_path
        bcs .done
        lda #<rn_new
        sta q0
        lda #>rn_new
        sta q0+1
        jsr path_add
        lda #<path_b
        sta q0
        lda #>path_b
        sta q0+1
        lda #<path_a
        sta q1
        lda #>path_a
        sta q1+1
        jsr fs_rename
        bcc +
        jsr fs_alert
        jmp .done
+       ldx mc_obj
        lda #<rn_new
        ldy #>rn_new
        jsr obj_set_name
        ldx mc_obj
        lda o_parent,x
        tax
        jsr save_positions
.done:  ldx #5
-       lda mo_rect,x
        sta rx1,x
        dex
        bpl -
        jsr redraw_region
        ldx sel_obj
        cpx #NOOBJ
        beq +
        jsr redraw_obj
+       rts

; ---------------------------------------------------------------------
; Menu commands
; ---------------------------------------------------------------------
ACT_ABOUT     = 0
ACT_NEWFOLDER = 1
ACT_OPEN      = 2
ACT_PRINT     = 3
ACT_CLOSE     = 4
ACT_INFO      = 5
ACT_DUP       = 6
ACT_PUTBACK   = 7
ACT_EJECT     = 8
ACT_UNDO      = 9
ACT_CUT       = 10
ACT_COPY      = 11
ACT_PASTE     = 12
ACT_CLEAR     = 13
ACT_SELALL    = 14
ACT_SHOWCLIP  = 15
ACT_VICON     = 16
ACT_VSMALL    = 17
ACT_VNAME     = 18
ACT_VDATE     = 19
ACT_VSIZE     = 20
ACT_VKIND     = 21
ACT_CLEANUP   = 22
ACT_EMPTY     = 23
ACT_ERASE     = 24
ACT_STARTUP   = 25
ACT_RESTART   = 26
ACT_SHUTDOWN  = 27

action_table:
        !word about_box
        !word new_folder, act_open, nop_method, act_close, get_info, act_dup, put_back, act_eject
        !word nop_method, act_edit, act_edit, act_edit, act_edit, act_edit, clip_open
        !word act_view, act_view, act_view, act_view, act_view, act_view
        !word clean_up, empty_trash, erase_disk, set_startup, restart, shut_down

; app_action: A = one of the actions above (called by the System)
!zone app_action
app_action:
        asl
        tay
        lda action_table,y
        sta jvec
        lda action_table+1,y
        sta jvec+1
        lda cur_action
        jmp (jvec)

act_open:
        ldx sel_obj
        cpx #NOOBJ
        beq +
        jmp open_obj
+       rts

act_close:
        jsr front_win
        beq +
        jmp close_win
+       rts

act_edit:                       ; route to the front window
        jsr front_win
        beq +
        lda cur_action
        sec
        sbc #ACT_UNDO           ; -> EDIT_ command
        sta key_char
        lda #M_EDIT
        jmp win_call
+       rts

act_view:
        jsr front_win
        beq +
        lda w_class,x
        cmp #CL_FOLDER
        bne +
        lda cur_action
        sec
        sbc #ACT_VICON
        sta w_view,x
+       rts

; Eject: a network share is disconnected
act_eject:
        ldx sel_obj
        cpx #NOOBJ
        beq +
        lda o_type,x
        cmp #T_TRASH
        bcs +
        jmp eject_vol
+       rts

; the container of the front folder window (else the startup disk) -> X
front_container:
        jsr front_win
        cpx #$ff
        beq +
        lda w_class,x
        cmp #CL_FOLDER
        bne +
        lda w_data,x
        tax
        rts
+       ldx vol_obj
        rts

; New Folder: "Empty Folder" (or "Empty Folder 2" ...) in the front
; folder window, or on the startup disk
!zone new_folder
new_folder:
        jsr front_container
        cpx #OBJ_TRASH
        bne +
        rts
+       stx nf_par
        lda #<str_newfolder     ; the name
        ldy #>str_newfolder
        sta q0
        sty q0+1
        ldx #0
-       lda str_newfolder,x
        sta rn_new,x
        beq +
        inx
        bne -
+       stx nf_end
        lda #"1"
        sta nf_n
.try:   ldx nf_par
        jsr obj_path
        bcc .bf3946
        jmp .out
.bf3946:
        lda #<rn_new
        sta q0
        lda #>rn_new
        sta q0+1
        jsr path_add
        lda #<path_a
        sta q0
        lda #>path_a
        sta q0+1
        jsr fs_mkdir
        bcc .made
        cmp #FS_EXISTS
        bne .err
        inc nf_n                ; taken: "Empty Folder 2", 3, ...
        lda nf_n
        cmp #'9'+1
        bcs .err
        ldx nf_end
        lda #" "
        sta rn_new,x
        lda nf_n
        sta rn_new+1,x
        lda #0
        sta rn_new+2,x
        jmp .try
.err:   jmp fs_alert
.made:  jsr vol_query
        ldx nf_par              ; shows if its folder is open
        lda o_win,x
        cmp #$ff
        beq .out
        jsr new_obj
        bcs .out
        stx nf_obj
        lda nf_par
        sta o_parent,x
        tay
        lda o_vol,y
        sta o_vol,x
        lda #T_FOLDER
        sta o_type,x
        lda #IC_FOLDER
        sta o_icon,x
        lda #0
        sta o_kl,x
        sta o_kh,x
        sta o_dl,x
        sta o_dh,x
        lda #<rn_new
        ldy #>rn_new
        jsr obj_set_name
        ldx nf_par
        jsr free_slot
        ldx nf_obj
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
        jsr select_obj
        lda nf_par
        jsr refresh_info
        ldx nf_par
        jmp save_positions
.out:   rts

nf_par: !byte 0
nf_obj: !byte 0
nf_end: !byte 0
nf_n:   !byte 0

; new_obj: X = a free object (carry set if there is none)
new_obj:
        ldx #0
-       lda o_parent,x
        cmp #NOOBJ
        beq +
        inx
        cpx #MAXOBJ
        bne -
        sec
        rts
+       lda #0
        sta o_flags,x
        sta o_vol,x
        sta o_kl,x
        sta o_kh,x
        sta o_dl,x
        sta o_dh,x
        lda #$ff
        sta o_win,x
        lda #NOOBJ
        sta o_oldpar,x
        clc
        rts

; Duplicate: a file, as "Copy of <name>" next to it
!zone act_dup
act_dup:
        ldx sel_obj
        cpx #NOOBJ
        bne .bf4065
        jmp .no
.bf4065:
        lda o_type,x
        cmp #T_APP
        bcs .bf4068
        jmp .no
.bf4068:
        lda o_parent,x
        cmp #OBJ_TRASH
        bne .bf4071
        jmp .no
.bf4071:
        stx mc_obj
        sta u4
        ; rn_new = "Copy of " + the name, cut so the extension stays
        ldx #0
-       lda str_copyof,x
        beq +
        sta rn_new,x
        inx
        bne -
+       stx t3
        ldx mc_obj
        jsr obj_name_ptr
        jsr ext_of              ; Y = the dot (or the end)
        sty t2
        ; name characters that fit: NAMELEN-1 - "Copy of " - extension
        lda t7
        sec
        sbc t2
        sta t1                  ; extension length
        lda #NAMELEN-1
        sec
        sbc t3
        sec
        sbc t1
        cmp t2
        bcc +
        lda t2
+       sta t0                  ; name characters
        ldy #0
        ldx t3
-       cpy t0
        beq +
        lda (q1),y
        sta rn_new,x
        inx
        iny
        bne -
+       ldy t2                  ; the extension, and the end
-       lda (q1),y
        sta rn_new,x
        beq +
        inx
        iny
        bne -
+       ldx mc_obj              ; path_b = it, path_a = the copy
        jsr obj_path
        bcc .bf4118
        jmp .no
.bf4118:
        jsr path_save
        ldx u4
        jsr obj_path
        bcc .bf4122
        jmp .no
.bf4122:
        lda #<rn_new
        sta q0
        lda #>rn_new
        sta q0+1
        jsr path_add
        lda #<path_b
        sta q0
        lda #>path_b
        sta q0+1
        lda #<path_a
        sta q1
        lda #>path_a
        sta q1+1
        jsr fs_copy
        bcc +
        jmp fs_alert
+       jsr vol_query
        jsr new_obj
        bcs .no
        stx nf_obj
        ldy mc_obj
        lda u4
        sta o_parent,x
        lda o_vol,y
        sta o_vol,x
        lda o_type,y
        sta o_type,x
        lda o_icon,y
        sta o_icon,x
        lda o_kl,y
        sta o_kl,x
        lda o_kh,y
        sta o_kh,x
        lda o_dl,y
        sta o_dl,x
        lda o_dh,y
        sta o_dh,x
        lda #<rn_new
        ldy #>rn_new
        jsr obj_set_name
        ldx u4
        jsr free_slot
        ldx nf_obj
        lda fs_x
        sta o_xl,x
        lda fs_x+1
        sta o_xh,x
        lda fs_y
        sta o_y,x
        jsr select_obj
        lda u4
        jsr refresh_info
        ldx u4
        jmp save_positions
.no:    rts

; Put Back: from the Trash to the folder it came from (or, if that is
; not open any more, the top of its volume)
!zone put_back
put_back:
        ldx sel_obj
        cpx #NOOBJ
        beq .out
        lda o_parent,x
        cmp #OBJ_TRASH
        bne .out
        stx mc_obj
        stx dr_obj
        lda o_oldpar,x
        cmp #MAXOBJ
        bcs .root
        tay
        lda o_parent,y          ; (still an object, on the same volume?)
        cmp #NOOBJ
        beq .root
        lda o_vol,y
        cmp o_vol,x
        bne .root
        tya
        jmp .go
.root:  ldy o_vol,x
        lda vol_obj,y
.go:    sta u4
        jsr paths_to
        bcs .out
        jsr fs_rename
        bcc +
        jmp fs_alert
+       lda trash_n             ; one less in the Trash
        bne +
        dec trash_n+1
+       dec trash_n
        ldx u4
        jsr free_slot
        ldx mc_obj
        lda u4
        jsr move_obj
        ldx u4
        jmp save_positions
.out:   rts

; Clean Up: snap the icons of the front folder to the grid
!zone clean_up
clean_up:
        jsr front_win
        bne .bf2482
        jmp .out
.bf2482:
        lda w_class,x
        cmp #CL_FOLDER
        beq .bf2485
        jmp .out
.bf2485:
        stx u6
        lda w_data,x
        sta u4
        jsr win_get_content
        ; columns that fit
        sec
        lda wc_x2
        sbc wc_x1
        sec
        sbc #18
        ldx #0
-       cmp #CELL_W
        bcc +
        sbc #CELL_W
        inx
        bne -
+       cpx #0
        bne +
        inx
+       stx u5
        lda #0
        sta u3                  ; column
        lda #18
        sta fs_x
        lda #4
        sta fs_y
        ldx #0
.l:     lda o_parent,x
        cmp u4
        bne .n
        lda fs_x
        sta o_xl,x
        lda #0
        sta o_xh,x
        lda fs_y
        sta o_y,x
        lda fs_x
        clc
        adc #CELL_W
        sta fs_x
        inc u3
        lda u3
        cmp u5
        bcc .n
        lda #0
        sta u3
        lda #18
        sta fs_x
        lda fs_y
        clc
        adc #CELL_H
        sta fs_y
.n:     inx
        cpx #MAXOBJ
        bne .l
        ldx u6
        stx wsr_id
        jsr folder_layout
        ldx u6
        jsr win_get_content
        jsr redraw_region
        ldx u4
        jmp save_positions
.out:   rts

; Empty Trash: the .Trash folder of every connected volume goes
!zone empty_trash
empty_trash:
        jsr trash_full
        beq .out
        lda #CUR_WATCH
        jsr set_cursor
        ldx #0
.v:     cpx vol_n
        bcs .done
        stx u5
        lda vol_conn,x
        beq +
        txa
        jsr trash_path
        jsr delete_tree
+       ldx u5
        inx
        jmp .v
.done:  lda #CUR_ARROW
        jsr set_cursor
        ldx #MAXOBJ-1           ; what was in the Trash is gone
-       lda o_parent,x
        cmp #OBJ_TRASH
        bne +
        lda o_win,x             ; (and the windows of folders in it)
        cmp #$ff
        beq ++
        stx u5
        tax
        jsr win_close
        ldx u5
++      jsr free_obj
+       dex
        bpl -
        jsr vol_query
        jsr count_trash
        ldx #OBJ_TRASH
        jsr redraw_obj
        lda #OBJ_TRASH
        jsr refresh_info
        ldx #OBJ_TRASH
        lda o_win,x
        cmp #$ff
        beq .out
        tax
        jsr win_get_content
        jmp redraw_region
.out:   rts

erase_disk:
        lda #<str_erase
        ldy #>str_erase
        jmp alert_stop
set_startup:
        lda #<str_startup
        ldy #>str_startup
        jmp alert_note

; ---------------------------------------------------------------------
; update_menus: enable/disable items for the current state
; ---------------------------------------------------------------------
MN_APPLE   = 0*16
MN_FILE    = 1*16
MN_EDIT    = 2*16
MN_VIEW    = 3*16
MN_SPECIAL = 4*16

!zone update_menus
update_menus:
        jsr end_rename
        ; File
        lda #0
        ldx sel_obj
        cpx #NOOBJ
        beq +
        lda #1
+       sta u0                  ; something selected
        ldx #MN_FILE+1           ; Open
        jsr menu_set
        lda u0
        ldx #MN_FILE+5           ; Get Info
        jsr menu_set
        lda #0                  ; Duplicate: files, not in the Trash
        ldx sel_obj
        cpx #NOOBJ
        beq +
        ldy o_type,x
        cpy #T_APP
        bcc +
        ldy o_parent,x
        cpy #OBJ_TRASH
        beq +
        lda #1
+       ldx #MN_FILE+6
        jsr menu_set
        lda #0                  ; Eject: a network share
        ldx sel_obj
        cpx #NOOBJ
        beq +
        ldy o_type,x
        cpy #T_SHARE
        bne +
        lda #1
+       ldx #MN_FILE+9
        jsr menu_set
        lda #0                  ; Put Back: something in the trash
        ldx sel_obj
        cpx #NOOBJ
        beq +
        ldy o_parent,x
        cpy #OBJ_TRASH
        bne +
        lda #1
+       ldx #MN_FILE+7
        jsr menu_set
        lda zcount              ; Close: any window
        ldx #MN_FILE+3
        jsr menu_set
        ldx #MN_FILE+2           ; Print
        jsr menu_disable
        ; Edit: nothing in the Finder's own windows uses it (yet)
        lda #0
        sta u1
        sta u2
        lda u1
        ldx #MN_EDIT+2           ; Cut
        jsr menu_set
        lda u2
        ldx #MN_EDIT+3           ; Copy
        jsr menu_set
        lda u2
        ldx #MN_EDIT+4           ; Paste
        jsr menu_set
        lda u1
        ldx #MN_EDIT+5           ; Clear
        jsr menu_set
        lda u1
        ldx #MN_EDIT+6           ; Select All
        jsr menu_set
        ldx #MN_EDIT+0           ; Undo
        jsr menu_disable
        ; View: folder in front, check its view
        lda #$ff
        sta u3
        jsr front_win
        cpx #$ff
        beq +
        lda w_class,x
        cmp #CL_FOLDER
        bne +
        lda w_view,x
        sta u3
+       ldx #0
.v:     lda menu_flags+MN_VIEW,x
        and #$ff-MF_CHECKED-MF_DISABLED
        ldy u3
        cpy #$ff
        bne +
        ora #MF_DISABLED
        jmp ++
+       cpx u3
        bne ++
        ora #MF_CHECKED
++      sta menu_flags+MN_VIEW,x
        inx
        cpx #6
        bne .v
        ; Special
        jsr trash_full
        ldx #MN_SPECIAL+1        ; Empty Trash
        jsr menu_set
        lda #0
        ldy u3
        cpy #$ff
        beq +
        lda #1
+       ldx #MN_SPECIAL+0        ; Clean Up
        jmp menu_set
