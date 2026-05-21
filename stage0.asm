; =============================================================================
; UNIOS - STAGE 0 : Pre-Bootloader (MBR)                         v0.2
; =============================================================================
; Loaded by BIOS at 0x7C00. Must fit in exactly 512 bytes.
; Shared Info Block @ 0x0500 :
;   +0x00 [12B] CPU Vendor   +0x0C [1B] 64-bit flag   +0x0D [1B] Boot drive
;   +0x0E [2B]  RAM (MB)     +0x10 [1B] Language       +0x11 [1B] KBD layout
; =============================================================================

[BITS 16]
[ORG 0x7C00]

STAGE1_ADDR  equ 0x7E00
STAGE1_LBA   equ 1
STAGE1_NSECT equ 8
INFO_BLOCK   equ 0x0500

_start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00
    sti

    mov  [INFO_BLOCK + 0x0D], dl   ; boot drive

    mov  ax, 0x0003                ; 80x25 text mode
    int  0x10

    mov  si, msg_banner
    call puts

    call cpu_detect
    call load_stage1

    jmp  0x0000:STAGE1_ADDR

; =============================================================================
; cpu_detect — CPUID vendor string + Long Mode flag → INFO_BLOCK
; =============================================================================
cpu_detect:
    pushfd
    pop  eax
    mov  ecx, eax
    xor  eax, (1 << 21)
    push eax
    popfd
    pushfd
    pop  eax
    push ecx
    popfd
    xor  eax, ecx
    jz   .ancient

    mov  eax, 0
    cpuid
    mov  [INFO_BLOCK + 0], ebx
    mov  [INFO_BLOCK + 4], edx
    mov  [INFO_BLOCK + 8], ecx
    mov  byte [INFO_BLOCK + 12], 0

    mov  si, msg_cpu
    call puts
    mov  si, INFO_BLOCK
    call puts
    mov  si, msg_crlf
    call puts

    mov  eax, 0x80000000
    cpuid
    cmp  eax, 0x80000001
    jb   .no_lm

    mov  eax, 0x80000001
    cpuid
    test edx, (1 << 29)
    jz   .no_lm

    mov  byte [INFO_BLOCK + 0x0C], 1
    mov  si, msg_64
    call puts
    ret

.no_lm:
    mov  byte [INFO_BLOCK + 0x0C], 0
    mov  si, msg_32
    call puts
    ret

.ancient:
    mov  byte [INFO_BLOCK + 0x0C], 0xFF
    mov  dword [INFO_BLOCK + 0], 0x6E6B6E55   ; "Unkn"
    mov  dword [INFO_BLOCK + 4], 0x006E776F   ; "own\0"
    mov  byte  [INFO_BLOCK + 8], 0
    mov  si, msg_old
    call puts
    ret

; =============================================================================
; load_stage1 — INT 13h AH=42h (LBA extended)
; =============================================================================
load_stage1:
    mov  si, msg_load
    call puts

    mov  byte  [dap + 0], 0x10
    mov  byte  [dap + 1], 0x00
    mov  word  [dap + 2], STAGE1_NSECT
    mov  word  [dap + 4], STAGE1_ADDR
    mov  word  [dap + 6], 0x0000
    mov  dword [dap + 8], STAGE1_LBA
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
; puts — display null-terminated string pointed by SI
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

; =============================================================================
; Data (compact to fit in 512 bytes)
; =============================================================================
msg_banner  db "[S0] UNIOS v0.2",13,10,0
msg_cpu     db "CPU: ",0
msg_crlf    db 13,10,0
msg_64      db "[64-bit]",13,10,0
msg_32      db "[32-bit]",13,10,0
msg_old     db "[OLD]",13,10,0
msg_load    db "S1...",0
msg_ok      db "OK",13,10,0
msg_err     db "ERR",13,10,0

dap         times 16 db 0

; ── Padding + signature ───────────────────────────────────────────────────────
times 510-($-$$) db 0
dw 0xAA55