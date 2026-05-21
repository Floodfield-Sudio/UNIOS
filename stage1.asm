; =============================================================================
; UNIOS - STAGE 1 : Boot Menu, RAM Detection & Stage 2 Loader    v0.2
; =============================================================================
; Loaded at 0x7E00 by Stage 0.
; Responsibilities:
;   1. Init persistent settings in INFO_BLOCK (+0x10 language, +0x11 kbd)
;   2. Show boot menu: [1] UNIOS  [2] Original OS
;   3. E820 memory map → store at 0x2000
;   4. Calculate total usable RAM in MB → INFO_BLOCK +0x0E
;   5. Load Stage 2 from disk (sectors 9-64) to 0x9000
;   6. Jump to Stage 2
;
; INFO_BLOCK layout (@ 0x0500):
;   +0x00 [12B]  CPU vendor string
;   +0x0C [1B]   64-bit flag  (set by Stage 0)
;   +0x0D [1B]   Boot drive   (set by Stage 0)
;   +0x0E [2B]   RAM total MB (set here)
;   +0x10 [1B]   Language: 0=en-us  1=fr-fr
;   +0x11 [1B]   KBD layout: 0=QWERTY  1=AZERTY
; =============================================================================

[BITS 16]
[ORG 0x7E00]

STAGE2_ADDR  equ 0x9000
STAGE2_LBA   equ 9
STAGE2_NSECT equ 56
INFO_BLOCK   equ 0x0500
E820_MAP     equ 0x2000

_start:
    mov  ax, 0x0003
    int  0x10

    ; Initialise persistent settings to defaults
    mov  byte [INFO_BLOCK + 0x10], 0   ; language  = en-us
    mov  byte [INFO_BLOCK + 0x11], 0   ; kbd layout = QWERTY

    mov  si, msg_banner
    call puts

    call detect_ram
    call show_boot_menu     ; may jump away or return normally for UNIOS path
    call load_stage2

    jmp  0x0000:STAGE2_ADDR

; =============================================================================
; show_boot_menu — Display menu, wait for key, act on choice
; =============================================================================
show_boot_menu:
    mov  si, msg_menu
    call puts

.wait:
    xor  ah, ah
    int  0x16               ; AH=scancode, AL=ASCII

    cmp  al, '1'
    je   .unios
    cmp  al, '2'
    je   .original
    jmp  .wait

.unios:
    mov  si, msg_menu_s2
    call puts
    ret                     ; return → load_stage2 → Stage 2

.original:
    mov  si, msg_menu_orig
    call puts

    ; Attempt to chainload first sector of drive 0x81 (second HDD)
    ; If that fails, boot from BIOS bootstrap (INT 19h)
    mov  byte  [dap2 + 0], 0x10
    mov  byte  [dap2 + 1], 0x00
    mov  word  [dap2 + 2], 1          ; 1 sector
    mov  word  [dap2 + 4], 0x7C00    ; load to standard MBR address
    mov  word  [dap2 + 6], 0x0000
    mov  dword [dap2 + 8], 0          ; LBA 0
    mov  dword [dap2 +12], 0

    mov  ah, 0x42
    mov  dl, 0x81                     ; second hard drive
    mov  si, dap2
    int  0x13
    jc   .try_int19

    ; Verify boot signature
    cmp  word [0x7DFE], 0xAA55
    jne  .try_int19

    ; Found bootable sector: jump to it
    mov  dl, 0x81
    jmp  0x0000:0x7C00

.try_int19:
    ; BIOS bootstrap: re-reads boot sector from first bootable device
    ; (may reload UNIOS if it's the only boot drive)
    int  0x19

    ; If INT 19 returns, fall back to UNIOS Stage 2
    mov  si, msg_menu_fallback
    call puts
    ret

; =============================================================================
; detect_ram — INT 15h E820 memory map
; =============================================================================
detect_ram:
    mov  si, msg_ram_detect
    call puts

    xor  ebx, ebx
    mov  di, E820_MAP
    xor  cx, cx

.loop:
    mov  eax, 0xE820
    mov  edx, 0x534D4150
    mov  ecx, 24
    int  0x15
    jc   .done

    add  di, 24
    inc  cx
    test ebx, ebx
    jz   .done
    jmp  .loop

.done:
    mov  [E820_MAP - 2], cx
    call calc_total_ram
    ret

; =============================================================================
; calc_total_ram — Sum Type=1 regions, store in INFO_BLOCK +0x0E (MB)
; =============================================================================
calc_total_ram:
    movzx ecx, word [E820_MAP - 2]
    test  ecx, ecx
    jz    .no_ram

    xor   eax, eax
    mov   si, E820_MAP

.sum_loop:
    cmp   dword [si + 16], 1
    jne   .skip
    mov   ebx, [si + 8]
    add   eax, ebx
.skip:
    add   si, 24
    loop  .sum_loop

    mov   ebx, 1048576
    xor   edx, edx
    div   ebx
    mov   [INFO_BLOCK + 0x0E], ax

    mov   si, msg_ram_total
    call  puts
    call  print_dec
    mov   si, msg_mb
    call  puts
    ret

.no_ram:
    mov   word [INFO_BLOCK + 0x0E], 0
    mov   si, msg_ram_fail
    call  puts
    ret

; =============================================================================
; load_stage2 — INT 13h AH=42h (LBA)
; =============================================================================
load_stage2:
    mov  si, msg_load_s2
    call puts

    mov  byte  [dap + 0], 0x10
    mov  byte  [dap + 1], 0x00
    mov  word  [dap + 2], STAGE2_NSECT
    mov  word  [dap + 4], STAGE2_ADDR
    mov  word  [dap + 6], 0x0000
    mov  dword [dap + 8], STAGE2_LBA
    mov  dword [dap +12], 0

    mov  ah, 0x42
    mov  dl, [INFO_BLOCK + 0x0D]
    mov  si, dap
    int  0x13
    jc   .fail

    mov  si, msg_ok
    call puts
    ret

.fail:
    mov  si, msg_err
    call puts
    cli
    hlt

; =============================================================================
; Utilities
; =============================================================================
puts:
    lodsb
    or   al, al
    jz   .done
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    jmp  puts
.done:
    ret

print_dec:
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
    test ax, ax
    jnz  .push_loop

.pop_loop:
    pop  ax
    add  al, '0'
    mov  ah, 0x0E
    xor  bx, bx
    int  0x10
    loop .pop_loop

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; =============================================================================
; Data
; =============================================================================
msg_banner      db 13,10,"[S1] UNIOS - Stage 1 v0.2",13,10,0
msg_ram_detect  db "Detecting RAM...",13,10,0
msg_ram_total   db "RAM: ",0
msg_mb          db " MB",13,10,0
msg_ram_fail    db "RAM detection failed",13,10,0
msg_load_s2     db "Loading Stage 2...",0
msg_ok          db "OK",13,10,13,10,0
msg_err         db "DISK ERROR",13,10,0

msg_menu        db 13,10
                db "============ UNIOS Boot Menu ============",13,10
                db "  [1] UNIOS Diagnostic Shell (Stage 2)",13,10
                db "  [2] Boot original OS",13,10
                db "=========================================",13,10
                db "Choice: ",0

msg_menu_s2     db "1",13,10,0
msg_menu_orig   db "2",13,10,
                db "Attempting to boot original OS...",13,10,0
msg_menu_fallback db "No other bootable drive found.",13,10
                  db "Falling back to UNIOS...",13,10,13,10,0

dap             times 16 db 0
dap2            times 16 db 0