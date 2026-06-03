; =============================================================================
; UNIOS - STAGE 2 : Diagnostic Shell (Real Mode)                  v0.6
; =============================================================================
; Loaded at 0x9000. Interactive shell.
;
; Commands: help, cpu, mem, arch, disk, clear, reboot, exit,
;           kbd, lg, install
;
; Memory layout:
;   0x0500  INFO_BLOCK   (shared with Stage 0/1)
;   0x2000  E820_MAP
;   0x5000  CPU brand string temp buffer
;   0x6000  INPUT_BUF    (current input line, 200 bytes)
;   0x6300  HIST_BUF     (command history, 10 × 80 bytes)
;   0x7C00  [Stack boundary — do not cross]
;   0x9000  Stage 2 code (here)
; =============================================================================

[BITS 16]
[ORG 0x9000]

INFO_BLOCK   equ 0x0500
E820_MAP     equ 0x2000
INPUT_BUF    equ 0x6000
INPUT_MAX    equ 200
HIST_BUF     equ 0x6300       ; history ring buffer
HIST_MAX     equ 10            ; max history entries
HIST_LEN     equ 80            ; max chars per entry (including null)
LANG_COUNT   equ 12           ; locale presets
KBD_COUNT    equ 12           ; keyboard presets

; =============================================================================
; Entry point
; =============================================================================
_start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x8F00             ; stack below Stage 2 code
    sti

    ; Load persistent settings saved by Stage 1 / previous session
    mov  al, [INFO_BLOCK + 0x10]
    mov  [lang_id], al         ; locale preset
    mov  al, [INFO_BLOCK + 0x11]
    mov  [kbd_layout], al       ; keyboard preset

    ; Initialise history state
    mov  word [hist_head],  0
    mov  word [hist_count], 0
    mov  word [hist_cur],   0xFFFF

    mov  ax, 0x0003             ; 80×25 text mode
    int  0x10

    ; Make the hardware cursor visible and stable like a classic CMD prompt.
    mov  ah, 0x01
    mov  ch, 0x06
    mov  cl, 0x07
    int  0x10

    mov  si, msg_banner
    call s2_puts
    mov  si, msg_prompt
    call s2_puts

; =============================================================================
; Main shell loop
; =============================================================================
shell_loop:
    mov  si, prompt
    call s2_puts

    mov  di, INPUT_BUF
    mov  cx, INPUT_MAX
    call s2_readline

    ; Empty line → loop
    cmp  byte [INPUT_BUF], 0
    je   shell_loop

    ; ── Command dispatch ─────────────────────────────────────────────────────
    mov  si, INPUT_BUF
    mov  di, cmd_help
    call s2_strcmp
    jz   cmd_help_fn

    mov  si, INPUT_BUF
    mov  di, cmd_cpu
    call s2_strcmp
    jz   cmd_cpu_fn

    mov  si, INPUT_BUF
    mov  di, cmd_mem
    call s2_strcmp
    jz   cmd_mem_fn

    mov  si, INPUT_BUF
    mov  di, cmd_arch
    call s2_strcmp
    jz   cmd_arch_fn

    mov  si, INPUT_BUF
    mov  di, cmd_disk
    call s2_strcmp
    jz   cmd_disk_fn

    mov  si, INPUT_BUF
    mov  di, cmd_clear
    call s2_strcmp
    jz   cmd_clear_fn

    mov  si, INPUT_BUF
    mov  di, cmd_reboot
    call s2_strcmp
    jz   cmd_reboot_fn

    mov  si, INPUT_BUF
    mov  di, cmd_exit
    call s2_strcmp
    jz   cmd_exit_fn

    mov  si, INPUT_BUF
    mov  di, cmd_kbd
    call s2_strcmp
    jz   cmd_kbd_fn

    mov  si, INPUT_BUF
    mov  di, cmd_install
    call s2_strcmp
    jz   cmd_install_fn

    ; Check "lg" prefix (with or without argument)
    cmp  byte [INPUT_BUF + 0], 'l'
    jne  .not_lg
    cmp  byte [INPUT_BUF + 1], 'g'
    jne  .not_lg
    mov  al, [INPUT_BUF + 2]
    test al, al             ; "lg" with no argument
    jz   cmd_lg_fn
    cmp  al, ' '            ; "lg en-us" / "lg fr-fr"
    je   cmd_lg_fn
.not_lg:

    ; Unknown command
    mov  si, msg_unknown
    call s2_puts
    jmp  shell_loop

; =============================================================================
; COMMAND: help
; =============================================================================
cmd_help_fn:
    mov  si, help_text
    call s2_puts
    jmp  shell_loop

; =============================================================================
; COMMAND: cpu
; =============================================================================
cmd_cpu_fn:
    mov  si, msg_cpu_vendor
    call s2_puts
    mov  si, INFO_BLOCK
    call s2_puts
    call s2_crlf

    mov  si, msg_cpu_mode
    call s2_puts
    mov  al, [INFO_BLOCK + 0x0C]
    cmp  al, 1
    je   .mode_64
    cmp  al, 0
    je   .mode_32
    mov  si, msg_cpu_old
    call s2_puts
    jmp  .after_mode
.mode_64:
    mov  si, msg_cpu_64
    call s2_puts
    jmp  .after_mode
.mode_32:
    mov  si, msg_cpu_32
    call s2_puts
.after_mode:

    mov  eax, 1
    cpuid
    mov  ebx, eax

    mov  eax, ebx
    shr  eax, 8
    and  eax, 0x0F
    mov  si, msg_cpu_family
    call s2_puts
    call s2_print_dec
    call s2_crlf

    mov  eax, ebx
    shr  eax, 4
    and  eax, 0x0F
    mov  si, msg_cpu_model
    call s2_puts
    call s2_print_dec
    call s2_crlf

    mov  eax, ebx
    and  eax, 0x0F
    mov  si, msg_cpu_stepping
    call s2_puts
    call s2_print_dec
    call s2_crlf

    mov  eax, 0x80000000
    cpuid
    cmp  eax, 0x80000004
    jb   .no_brand

    mov  si, msg_cpu_brand
    call s2_puts

    mov  edi, 0x5000
    mov  eax, 0x80000002
    cpuid
    mov  [edi + 0], eax
    mov  [edi + 4], ebx
    mov  [edi + 8], ecx
    mov  [edi +12], edx

    mov  eax, 0x80000003
    cpuid
    mov  [edi +16], eax
    mov  [edi +20], ebx
    mov  [edi +24], ecx
    mov  [edi +28], edx

    mov  eax, 0x80000004
    cpuid
    mov  [edi +32], eax
    mov  [edi +36], ebx
    mov  [edi +40], ecx
    mov  [edi +44], edx

    mov  byte [edi +48], 0
    mov  si, 0x5000
    call s2_puts
    call s2_crlf

.no_brand:
    jmp  shell_loop

; =============================================================================
; COMMAND: mem
; =============================================================================
cmd_mem_fn:
    movzx ecx, word [E820_MAP - 2]
    test  ecx, ecx
    jz    .no_map

    mov   si, msg_mem_header
    call  s2_puts

    mov   si, E820_MAP
.print_loop:
    push  cx
    push  si

    mov   eax, [si + 0]
    call  s2_print_hex32
    mov   al, ' '
    call  s2_putc

    mov   eax, [si + 8]
    call  s2_print_hex32
    mov   al, ' '
    call  s2_putc

    mov   eax, [si + 16]
    cmp   eax, 1
    je    .type_usable
    cmp   eax, 2
    je    .type_reserved
    cmp   eax, 3
    je    .type_acpi_reclaim
    cmp   eax, 4
    je    .type_acpi_nvs
    mov   si, msg_type_unknown
    jmp   .type_done
.type_usable:
    mov   si, msg_type_usable
    jmp   .type_done
.type_reserved:
    mov   si, msg_type_reserved
    jmp   .type_done
.type_acpi_reclaim:
    mov   si, msg_type_acpi_reclaim
    jmp   .type_done
.type_acpi_nvs:
    mov   si, msg_type_acpi_nvs
.type_done:
    call  s2_puts
    call  s2_crlf

    pop   si
    add   si, 24
    pop   cx
    loop  .print_loop

    jmp   shell_loop

.no_map:
    mov   si, msg_mem_fail
    call  s2_puts
    jmp   shell_loop

; =============================================================================
; COMMAND: arch
; =============================================================================
cmd_arch_fn:
    mov  si, msg_arch_summary
    call s2_puts

    mov  si, msg_cpu_vendor
    call s2_puts
    mov  si, INFO_BLOCK
    call s2_puts
    call s2_crlf

    mov  si, msg_cpu_mode
    call s2_puts
    mov  al, [INFO_BLOCK + 0x0C]
    cmp  al, 1
    je   .mode_64
    cmp  al, 0
    je   .mode_32
    mov  si, msg_cpu_old
    call s2_puts
    jmp  .after_mode
.mode_64:
    mov  si, msg_cpu_64
    call s2_puts
    jmp  .after_mode
.mode_32:
    mov  si, msg_cpu_32
    call s2_puts
.after_mode:

    mov  si, msg_ram_label
    call s2_puts
    movzx eax, word [INFO_BLOCK + 0x0E]
    call s2_print_dec
    mov  si, msg_mb
    call s2_puts
    call s2_crlf

    mov  si, msg_boot_drive
    call s2_puts
    movzx eax, byte [INFO_BLOCK + 0x0D]
    call s2_print_hex8
    call s2_crlf

    mov  si, msg_arch_lang
    call s2_puts
    xor  bx, bx
    mov  bl, [lang_id]
    cmp  bl, LANG_COUNT
    jb   .lang_ok
    xor  bx, bx
.lang_ok:
    shl  bx, 1
    mov  si, [lang_display_table + bx]
    call s2_puts
    call s2_crlf

    mov  si, msg_arch_kbd
    call s2_puts
    xor  bx, bx
    mov  bl, [kbd_layout]
    cmp  bl, KBD_COUNT
    jb   .kbd_ok
    xor  bx, bx
.kbd_ok:
    shl  bx, 1
    mov  si, [kbd_display_table + bx]
    call s2_puts
    call s2_crlf

    jmp  shell_loop

; =============================================================================
; COMMAND: disk
; =============================================================================
cmd_disk_fn:
    mov  si, msg_disk_info
    call s2_puts

    mov  ah, 0x08
    mov  dl, [INFO_BLOCK + 0x0D]
    int  0x13
    jc   .disk_fail

    ; Sauvegarde immédiate des registres retournés par le BIOS
    push cx
    push dx

    ; --- 1. Cylindres ---
    xor  ax, ax
    mov  al, cl
    and  al, 0xC0
    shl  ax, 2
    mov  al, ch
    inc  ax                 ; Total cylindres = Max index + 1
    movzx eax, ax

    mov  si, msg_disk_cyl
    call s2_puts
    call s2_print_dec
    call s2_crlf

    ; --- 2. Têtes (Heads) ---
    pop  dx
    push dx
    mov  al, dh
    inc  al
    movzx eax, al

    mov  si, msg_disk_heads
    call s2_puts
    call s2_print_dec
    call s2_crlf

    ; --- 3. Secteurs ---
    pop  dx
    pop  cx
    mov  al, cl
    and  al, 0x3F
    movzx eax, al

    mov  si, msg_disk_sect
    call s2_puts
    call s2_print_dec
    call s2_crlf

    jmp  shell_loop

.disk_fail:
    mov  si, msg_disk_fail
    call s2_puts
    jmp  shell_loop

; =============================================================================
; COMMAND: clear
; =============================================================================
cmd_clear_fn:
    mov  ax, 0x0003
    int  0x10
    jmp  shell_loop

; =============================================================================
; COMMAND: reboot
; =============================================================================
cmd_reboot_fn:
    mov  si, msg_reboot
    call s2_puts
    jmp  0xFFFF:0x0000

; =============================================================================
; COMMAND: exit
; =============================================================================
cmd_exit_fn:
    mov  si, msg_exit
    call s2_puts

    mov  ax, 0x5301
    xor  bx, bx
    int  0x15

    mov  ax, 0x5308
    mov  bx, 0x0001
    mov  cx, 0x0001
    int  0x15

    mov  ax, 0x5307
    mov  bx, 0x0001
    mov  cx, 0x0003
    int  0x15

    mov  dx, 0x604
    mov  ax, 0x2000
    out  dx, ax

    mov  dx, 0xB004
    mov  ax, 0x2000
    out  dx, ax

    mov  si, msg_halt
    call s2_puts
    cli
    hlt

; =============================================================================
; COMMAND: install
; =============================================================================
cmd_install_fn:
    mov  si, msg_install
    call s2_puts
    jmp  shell_loop

; =============================================================================
; COMMAND: kbd
; =============================================================================
cmd_kbd_fn:
    mov  al, [kbd_layout]
    inc  al
    cmp  al, KBD_COUNT
    jb   .store
    xor  al, al
.store:
    mov  [kbd_layout], al
    mov  [INFO_BLOCK + 0x11], al

    mov  si, msg_kbd_set
    call s2_puts
    xor  bx, bx
    mov  bl, al
    shl  bx, 1
    mov  si, [kbd_display_table + bx]
    call s2_puts
    call s2_crlf
    jmp  shell_loop

; =============================================================================
; COMMAND: lg
; =============================================================================
cmd_lg_fn:
    cmp  byte [INPUT_BUF + 2], ' '
    jne  .show_current

    mov  si, INPUT_BUF
    add  si, 3

    xor  bx, bx

.match_loop:
    cmp  bx, LANG_COUNT * 2
    jae  .unknown

    push si
    mov  di, [locale_code_table + bx]
    call s2_strcmp
    pop  si
    jz   .found

    add  bx, 2
    jmp  .match_loop

.found:
    mov  ax, bx
    shr  ax, 1

    mov  [lang_id], al
    mov  [INFO_BLOCK + 0x10], al

    mov  si, locale_default_kbd
    add  si, ax
    mov  al, [si]
    mov  [kbd_layout], al
    mov  [INFO_BLOCK + 0x11], al

    mov  si, msg_lg_set
    call s2_puts

    xor  bx, bx
    mov  bl, [lang_id]
    cmp  bl, LANG_COUNT
    jb   .lang_ok
    xor  bx, bx
.lang_ok:
    shl  bx, 1
    mov  si, [lang_display_table + bx]
    call s2_puts

    mov  si, msg_lg_sep
    call s2_puts

    xor  bx, bx
    mov  bl, [kbd_layout]
    cmp  bl, KBD_COUNT
    jb   .kbd_ok
    xor  bx, bx
.kbd_ok:
    shl  bx, 1
    mov  si, [kbd_display_table + bx]
    call s2_puts
    call s2_crlf
    jmp  shell_loop

.unknown:
    mov  si, msg_lg_usage
    call s2_puts
    jmp  shell_loop

.show_current:
    mov  si, msg_lg_current
    call s2_puts

    xor  bx, bx
    mov  bl, [lang_id]
    cmp  bl, LANG_COUNT
    jb   .cur_lang_ok
    xor  bx, bx
.cur_lang_ok:
    shl  bx, 1
    mov  si, [lang_display_table + bx]
    call s2_puts

    mov  si, msg_lg_sep
    call s2_puts

    xor  bx, bx
    mov  bl, [kbd_layout]
    cmp  bl, KBD_COUNT
    jb   .cur_kbd_ok
    xor  bx, bx
.cur_kbd_ok:
    shl  bx, 1
    mov  si, [kbd_display_table + bx]
    call s2_puts
    call s2_crlf

    mov  si, msg_lg_usage
    call s2_puts
    jmp  shell_loop

; =============================================================================
; History functions
; =============================================================================
hist_save_current:
    push ax
    push si
    push di
    push cx

    mov  ax, [hist_head]
    mov  cx, HIST_LEN
    mul  cx
    add  ax, HIST_BUF
    mov  di, ax

    mov  si, INPUT_BUF
    mov  cx, HIST_LEN - 1
.copy:
    lodsb
    stosb
    test al, al
    jz   .done
    loop .copy
    mov  byte [di], 0
.done:

    mov  ax, [hist_head]
    inc  ax
    cmp  ax, HIST_MAX
    jb   .no_wrap
    xor  ax, ax
.no_wrap:
    mov  [hist_head], ax

    mov  ax, [hist_count]
    cmp  ax, HIST_MAX
    jge  .skip_inc
    inc  ax
    mov  [hist_count], ax
.skip_inc:

    mov  word [hist_cur], 0xFFFF

    pop  cx
    pop  di
    pop  si
    pop  ax
    ret

hist_get_ptr:
    push ax
    push bx
    push cx
    push dx

    mov  bx, ax
    mov  ax, [hist_head]
    dec  ax
    sub  ax, bx
    add  ax, 1000
    xor  dx, dx
    mov  cx, HIST_MAX
    div  cx

    mov  ax, dx
    mov  cx, HIST_LEN
    mul  cx
    add  ax, HIST_BUF
    mov  si, ax

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

hist_load_entry:
    push ax
    push si

    mov  ax, [hist_cur]
    call hist_get_ptr

    xor  bx, bx
.copy:
    lodsb
    test al, al
    jz   .done
    cmp  bx, INPUT_MAX - 1
    jae  .done
    mov  [di + bx], al
    inc  bx
    jmp  .copy
.done:
    mov  byte [di + bx], 0

    pop  si
    pop  ax
    ret

; =============================================================================
; Text processing / Screen mapping
; =============================================================================

; =============================================================================
; s2_set_cursor_offset (SÉCURISÉE - AUCUN EFFET SECONDAIRE)
; =============================================================================
s2_set_cursor_offset:
    push ax
    push bx
    push cx
    push dx

    xor  bx, bx
    mov  bl, [rl_start_col]
    add  ax, bx

    xor  dx, dx
    mov  bx, 80
    div  bx                 ; AX = quotient (lignes), DX = reste (colonnes)

    mov  cx, ax
    mov  al, [rl_start_row]
    add  al, cl             ; AL = start_row + ligne calculée
    mov  dh, al             ; DH = ligne finale
    ; DL contient déjà la bonne colonne absolue car c'était le reste de la division

    mov  ah, 0x02
    xor  bh, bh
    int  0x10               ; Positionnement du curseur physique par le BIOS

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; =============================================================================
; s2_readline
; =============================================================================
s2_readline:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    ; === FIX CRITIQUE 1: Forcer ES à 0 ===
    ; Répare le bogue d'insertion (caractère fantôme)
    xor  ax, ax
    mov  es, ax
    ; =====================================

    mov  ah, 0x03
    xor  bh, bh
    int  0x10
    mov  [rl_start_row], dh
    mov  [rl_start_col], dl

    mov  ax, cx
    dec  ax
    mov  [rl_max], ax

    xor  bx, bx
    xor  dx, dx
    mov  word [rl_prev_len], 0
    mov  word [hist_cur], 0xFFFF
    mov  byte [di], 0

.loop:
    xor  ah, ah
    int  0x16

    cmp  al, 13
    je   .enter
    cmp  al, 8
    je   .backspace

    test al, al
    jz   .special
    cmp  al, 0xE0
    je   .special

    cmp  bx, [rl_max]
    jae  .loop

    call map_scancode
.insert_or_append:
    cmp  dx, bx
    je   .append

    push di
    mov  bp, di
    add  bp, dx
    mov  si, di
    add  si, bx
    mov  di, si
    inc  di
    
    ; === FIX CRITIQUE 3: Protection de AL ===
    ; Utilisation exclusive de CX pour éviter de détruire la lettre dans AL
    mov  cx, bx
    sub  cx, dx
    inc  cx
    ; ========================================

    std
    rep  movsb
    cld
    pop  di
    jmp  .store_char

.append:
    mov  bp, di
    add  bp, bx

.store_char:
    mov  [bp], al
    inc  bx
    inc  dx
    mov  byte [di + bx], 0
    call s2_redraw_line
    jmp  .loop

.backspace:
    test dx, dx
    jz   .loop
    dec  dx

    push di
    mov  bp, di
    add  bp, dx
    mov  si, bp
    inc  si
    mov  di, bp

    ; Optimisé pour ne pas utiliser AX
    mov  cx, bx
    sub  cx, dx

    cld
    rep  movsb
    dec  bx
    pop  di

    mov  byte [di + bx], 0
    call s2_redraw_line
    jmp  .loop

.special:
    cmp  ah, 0x48
    je   .hist_up
    cmp  ah, 0x50
    je   .hist_down
    cmp  ah, 0x4B
    je   .cursor_left
    cmp  ah, 0x4D
    je   .cursor_right
    cmp  ah, 0x47
    je   .cursor_home
    cmp  ah, 0x4F
    je   .cursor_end
    cmp  ah, 0x53
    je   .delete_char
    
    test al, al
    jz   .loop
    cmp  bx, [rl_max]
    jae  .loop
    call map_scancode
    jmp  .insert_or_append

.cursor_left:
    test dx, dx
    jz   .loop
    dec  dx
    call s2_redraw_line
    jmp  .loop

.cursor_right:
    cmp  dx, bx
    jae  .loop
    inc  dx
    call s2_redraw_line
    jmp  .loop

.cursor_home:
    xor  dx, dx
    call s2_redraw_line
    jmp  .loop

.cursor_end:
    mov  dx, bx
    call s2_redraw_line
    jmp  .loop

.delete_char:
    cmp  dx, bx
    jae  .loop

    push di
    mov  bp, di
    add  bp, dx
    mov  si, bp
    inc  si
    mov  di, bp

    ; Optimisé pour ne pas utiliser AX
    mov  cx, bx
    sub  cx, dx

    cld
    rep  movsb
    dec  bx
    pop  di

    mov  byte [di + bx], 0
    call s2_redraw_line
    jmp  .loop

.hist_up:
    mov  ax, [hist_cur]
    cmp  ax, 0xFFFF
    je   .hist_up_start
    inc  ax
    jmp  .hist_up_check
.hist_up_start:
    xor  ax, ax
.hist_up_check:
    cmp  ax, [hist_count]
    jae  .loop
    mov  [hist_cur], ax
    call hist_load_entry
    mov  dx, bx
    call s2_redraw_line
    jmp  .loop

.hist_down:
    mov  ax, [hist_cur]
    cmp  ax, 0xFFFF
    je   .loop
    test ax, ax
    jz   .hist_down_clear
    dec  ax
    mov  [hist_cur], ax
    call hist_load_entry
    mov  dx, bx
    call s2_redraw_line
    jmp  .loop

.hist_down_clear:
    mov  byte [di], 0
    xor  bx, bx
    xor  dx, dx
    mov  word [hist_cur], 0xFFFF
    call s2_redraw_line
    jmp  .loop

.enter:
    mov  byte [di + bx], 0
    test bx, bx
    jz   .skip_save
    call hist_save_current
.skip_save:
    call s2_crlf

    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

s2_line_vram_offset:
    push bx
    push cx
    push dx

    xor  bx, bx
    mov  bl, [rl_start_col]
    add  ax, bx

    xor  dx, dx
    mov  bx, 80
    div  bx

    push dx
    xor  bx, bx
    mov  bl, [rl_start_row]
    add  ax, bx

    mov  bx, 80
    mul  bx
    pop  cx
    add  ax, cx
    shl  ax, 1
    mov  di, ax

    pop  dx
    pop  cx
    pop  bx
    ret

; =============================================================================
; s2_redraw_line (STABLE & RESTAURÉ)
; =============================================================================
s2_redraw_line:
    push ax
    push bx
    push cx
    push dx       ; <-- DX (Position curseur) sauvegardé sur la pile
    push si
    push di
    push es

    ; --- CALCUL ET GESTION DU SCROLLING AUTOMATIQUE ---
    mov  ax, bx
    cmp  ax, [rl_prev_len]
    jae  .use_bx
    mov  ax, [rl_prev_len]
.use_bx:
    xor  cx, cx
    mov  cl, [rl_start_col]
    add  ax, cx
    mov  cx, 80
    xor  dx, dx
    div  cx                 ; division (AH = reste, AL = quotient)
    add  al, [rl_start_row]
    cmp  al, 25
    jb   .no_scroll

    sub  al, 24
    push ax

    mov  ah, 0x06
    mov  bh, 0x07
    xor  cx, cx
    mov  dx, 0x184F
    int  0x10

    pop  ax
    sub  [rl_start_row], al
.no_scroll:

    ; Dessin VRAM
    mov  ax, 0xB800
    mov  es, ax
    cld

    mov  si, di
    xor  ax, ax
    call s2_line_vram_offset
    mov  cx, bx

    mov  ah, 0x07
.draw_chars:
    test cx, cx
    jz   .clear_tail
    lodsb
    stosw
    dec  cx
    jmp  .draw_chars

.clear_tail:
    mov  ax, [rl_prev_len]
    cmp  ax, bx
    jbe  .set_cursor
    sub  ax, bx
    mov  cx, ax
    mov  ax, 0x0720
.clear_loop:
    test cx, cx
    jz   .set_cursor
    stosw
    dec  cx
    jmp  .clear_loop

.set_cursor:
    mov  [rl_prev_len], bx

    ; === RESTAURATION PROPRE ET COMPLÈTE ===
    pop  es
    pop  di
    pop  si
    pop  dx                 ; <-- DX retrouve sa VRAIE valeur d'index texte
    pop  cx
    pop  bx
    pop  ax

    ; On appelle notre fonction de curseur sans AUCUN risque de corruption
    push ax
    mov  ax, dx
    call s2_set_cursor_offset
    pop  ax
    ret

; =============================================================================
; map_scancode
; =============================================================================
map_scancode:
    push bx
    push si
    push di

    mov  bl, [kbd_layout]
    cmp  bl, KBD_COUNT
    jb   .ok
    xor  bl, bl
.ok:
    xor  bh, bh
    shl  bx, 1
    mov  di, [kbd_map_table + bx]
    cmp  di, qwerty_chars
    je   .done

    mov  si, qwerty_chars
.search:
    mov  bl, [si]
    test bl, bl
    jz   .done
    cmp  al, bl
    je   .mapped
    inc  si
    inc  di
    jmp  .search

.mapped:
    mov  al, [di]

.done:
    pop  di
    pop  si
    pop  bx
    ret

; =============================================================================
; Utility functions
; =============================================================================
s2_puts:
    push ax
    push bx
.loop:
    lodsb
    or   al, al
    jz   .done
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    jmp  .loop
.done:
    pop  bx
    pop  ax
    ret

s2_putc:
    push ax
    push bx
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    pop  bx
    pop  ax
    ret

s2_crlf:
    push ax
    mov  al, 13
    call s2_putc
    mov  al, 10
    call s2_putc
    pop  ax
    ret

s2_strcmp:
    push ax
.loop:
    lodsb
    mov  ah, [di]
    inc  di
    cmp  al, ah
    jne  .not_equal
    test al, al
    jz   .equal
    jmp  .loop
.not_equal:
    pop  ax
    xor  ax, ax
    inc  ax
    ret
.equal:
    pop  ax
    xor  ax, ax
    ret

s2_print_dec:
    push ax
    push bx
    push cx
    push dx

    mov  bx, 10
    xor  cx, cx

.push_loop:
    xor  dx, dx
    div  bx
    push dx
    inc  cx
    test eax, eax
    jnz  .push_loop

.pop_loop:
    pop  ax
    add  al, '0'
    call s2_putc
    loop .pop_loop

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

s2_print_hex32:
    push eax
    push ebx
    push ecx

    mov  ecx, 8
    mov  ebx, eax

.loop:
    rol  ebx, 4
    mov  eax, ebx
    and  eax, 0x0F
    add  al, '0'
    cmp  al, '9'
    jbe  .digit
    add  al, 7
.digit:
    call s2_putc
    loop .loop

    pop  ecx
    pop  ebx
    pop  eax
    ret

s2_print_hex8:
    push eax
    push ebx
    push ecx

    movzx ebx, al
    mov   ecx, 2

.loop:
    rol   bl, 4
    movzx eax, bl
    and   eax, 0x0F
    add   al, '0'
    cmp   al, '9'
    jbe   .digit
    add   al, 7
.digit:
    call  s2_putc
    loop  .loop

    pop   ecx
    pop   ebx
    pop   eax
    ret

; =============================================================================
; Data
; =============================================================================
msg_banner      db 13,10
                db "=== UNIOS Stage 2 v0.5 - Diagnostic Shell ===",13,10,0
msg_prompt      db "Type 'help' for command list.",13,10,13,10,0
prompt          db "UNIOS> ",0

msg_unknown     db "Unknown command. Type 'help'.",13,10,0

help_text       db 13,10
                db "Commands:",13,10
                db "  help          Show this help",13,10
                db "  cpu           CPU info (vendor, mode, family, brand)",13,10
                db "  mem           Memory map (E820 table)",13,10
                db "  arch          Platform summary (CPU + RAM + drive)",13,10
                db "  disk          Disk geometry (BIOS INT 13h)",13,10
                db "  kbd           Cycle keyboard presets (QWERTY, AZERTY, QWERTZ, ...)",13,10
                db "  lg <locale>   Set locale: en-us fr-fr de-de es-es it-it pt-br ru-ru",13,10
                db "  install       Stage 3 installation guide",13,10
                db "  clear         Clear screen",13,10
                db "  reboot        Restart machine",13,10
                db "  exit          Power off machine",13,10
                db 13,10,0

cmd_help        db "help",0
cmd_cpu         db "cpu",0
cmd_mem         db "mem",0
cmd_arch        db "arch",0
cmd_disk        db "disk",0
cmd_clear       db "clear",0
cmd_reboot      db "reboot",0
cmd_exit        db "exit",0
cmd_kbd         db "kbd",0
cmd_install     db "install",0

msg_cpu_vendor  db "  CPU Vendor  : ",0
msg_cpu_mode    db "  CPU Mode    : ",0
msg_cpu_64      db "64-bit (Long Mode)",13,10,0
msg_cpu_32      db "32-bit",13,10,0
msg_cpu_old     db "Ancient (no CPUID)",13,10,0
msg_cpu_family  db "  Family      : ",0
msg_cpu_model   db "  Model       : ",0
msg_cpu_stepping db "  Stepping    : ",0
msg_cpu_brand   db "  Brand       : ",0

msg_mem_header  db 13,10,"E820 Memory Map:",13,10
                db "Base       Length     Type",13,10
                db "---------- ---------- ----------------",13,10,0
msg_type_usable db "Usable RAM",0
msg_type_reserved db "Reserved",0
msg_type_acpi_reclaim db "ACPI Reclaim",0
msg_type_acpi_nvs db "ACPI NVS",0
msg_type_unknown db "Unknown",0
msg_mem_fail    db "No memory map available.",13,10,0

msg_arch_summary db 13,10,"Platform Summary:",13,10,0
msg_ram_label   db "  Total RAM   : ",0
msg_mb          db " MB",0
msg_boot_drive  db "  Boot Drive  : 0x",0
msg_arch_lang   db "  Language    : ",0
msg_arch_kbd    db "  Keyboard    : ",0

msg_disk_info   db 13,10,"Disk Geometry (BIOS INT 13h AH=08h):",13,10,0
msg_disk_cyl    db "  Cylinders   : ",0
msg_disk_heads  db "  Heads       : ",0
msg_disk_sect   db "  Sectors/Trk : ",0
msg_disk_fail   db "BIOS disk query failed.",13,10,0

msg_reboot      db "Rebooting...",13,10,0
msg_exit        db "Shutting down...",13,10,0
msg_halt        db "ACPI/APM unavailable. System halted.",13,10,0

msg_lg_usage    db "Usage: lg <locale> (en-us fr-fr de-de es-es it-it pt-br ru-ru)",13,10,0
msg_lg_set_en   db "Language: English (en-us) — Keyboard: QWERTY",13,10,0
msg_lg_set_fr   db "Langue : Francais (fr-fr) — Clavier : AZERTY",13,10,0
msg_lg_current_old  db "Language: ",0

msg_install     db 13,10
                db "+-----------------------------------------+",13,10
                db "| UNIOS Stage 3 Installation              |",13,10
                db "+-----------------------------------------+",13,10
                db "Stage 3 adds:",13,10
                db "  - Protected mode (32-bit / 64-bit)",13,10
                db "  - OS launcher (Windows / Linux / macOS)",13,10
                db 13,10,0

str_en_us       db "en-us",0
str_fr_fr       db "fr-fr",0
str_de_de       db "de-de",0
str_es_es       db "es-es",0
str_it_it       db "it-it",0
str_pt_br       db "pt-br",0
str_ru_ru       db "ru-ru",0
str_ar_sa       db "ar-sa",0
str_zh_cn       db "zh-cn",0
str_zh_tw       db "zh-tw",0
str_ja_jp       db "ja-jp",0
str_ko_kr       db "ko-kr",0

disp_en_us      db "English (en-us)",0
disp_fr_fr      db "French (fr-fr)",0
disp_de_de      db "German (de-de)",0
disp_es_es      db "Spanish (es-es)",0
disp_it_it      db "Italian (it-it)",0
disp_pt_br      db "Portuguese (pt-br)",0
disp_ru_ru      db "Russian (ru-ru)",0
disp_ar_sa      db "Arabic (ar-sa)",0
disp_zh_cn      db "Chinese Simplified (zh-cn)",0
disp_zh_tw      db "Chinese Traditional (zh-tw)",0
disp_ja_jp      db "Japanese (ja-jp)",0
disp_ko_kr      db "Korean (ko-kr)",0

kbd_disp_qwerty  db "US QWERTY",0
kbd_disp_azerty  db "French AZERTY",0
kbd_disp_qwertz  db "German QWERTZ",0
kbd_disp_es_es   db "Spanish (Latin fallback)",0
kbd_disp_it_it   db "Italian (Latin fallback)",0
kbd_disp_pt_br   db "Brazilian ABNT2 (Latin fallback)",0
kbd_disp_ru_ru   db "Russian (Latin fallback)",0
kbd_disp_ar_sa   db "Arabic (Latin fallback)",0
kbd_disp_zh_cn   db "Chinese Simplified (Pinyin fallback)",0
kbd_disp_zh_tw   db "Chinese Traditional (Zhuyin fallback)",0
kbd_disp_ja_jp   db "Japanese (Romaji fallback)",0
kbd_disp_ko_kr   db "Korean (Romanized fallback)",0

msg_kbd_set      db "Keyboard: ",0
msg_lg_set       db "Language: ",0
msg_lg_current   db "Current locale: ",0
msg_lg_sep       db " | Keyboard: ",0

lang_id         db 0
kbd_layout      db 0

hist_head       dw 0
hist_count      dw 0
hist_cur        dw 0xFFFF
rl_start_row    db 0
rl_start_col    db 0
rl_prev_len     dw 0
rl_max          dw 0

; =============================================================================
; Tables & Mappings
; =============================================================================
lang_display_table dw disp_en_us, disp_fr_fr, disp_de_de, disp_es_es, disp_it_it, disp_pt_br, disp_ru_ru, disp_ar_sa, disp_zh_cn, disp_zh_tw, disp_ja_jp, disp_ko_kr
kbd_display_table  dw kbd_disp_qwerty, kbd_disp_azerty, kbd_disp_qwertz, kbd_disp_es_es, kbd_disp_it_it, kbd_disp_pt_br, kbd_disp_ru_ru, kbd_disp_ar_sa, kbd_disp_zh_cn, kbd_disp_zh_tw, kbd_disp_ja_jp, kbd_disp_ko_kr
locale_code_table  dw str_en_us, str_fr_fr, str_de_de, str_es_es, str_it_it, str_pt_br, str_ru_ru, str_ar_sa, str_zh_cn, str_zh_tw, str_ja_jp, str_ko_kr
locale_default_kbd db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
kbd_map_table      dw qwerty_chars, azerty_chars, qwertz_chars, qwerty_chars, qwerty_chars, qwerty_chars, qwerty_chars, qwerty_chars, qwerty_chars, qwerty_chars, qwerty_chars, qwerty_chars

; =============================================================================
; Keyboard layout tables (CP437)
; =============================================================================
qwerty_chars    db "1234567890-=qwertyuiop[]asdfghjkl;'`zxcvbnm,./"
                db "!@#$%^&*()_+QWERTYUIOP{}ASDFGHJKL:", 0x22, "~ZXCVBNM<>?",0

azerty_chars    db "&", 0x82, 0x22, 0x27, "(-", 0x8A, "_", 0x87, 0x85, ")=azertyuiop^$qsdfghjklm", 0x97, 0xFD, "wxcvbn,;:!"
                db "1234567890", 0xF8, "+AZERTYUIOP", 0x22, "$QSDFGHJKLM%", 0x9C, "WXCVBN?./", 0x15, 0

qwertz_chars    db "1234567890-=qwertzuiop[]asdfghjkl;'`yxcvbnm,./"
                db "!@#$%^&*()_+QWERTZUIOP{}ASDFGHJKL:", 0x22, "~YXCVBNM<>?",0

; =============================================================================
; Zero-pad to exactly 28672 bytes (56 sectors x 512)
; =============================================================================
times (28672 - ($ - $$)) db 0
