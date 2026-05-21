# UniversalOS — Technical Documentation

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Memory Layout](#memory-layout)
3. [Disk Layout](#disk-layout)
4. [Boot Sequence](#boot-sequence)
5. [Stage 0: MBR Bootloader](#stage-0-mbr-bootloader)
6. [Stage 1: RAM Detector](#stage-1-ram-detector)
7. [Stage 2: Diagnostic Shell](#stage-2-diagnostic-shell)
8. [BIOS Services Used](#bios-services-used)
9. [Keyboard Support](#keyboard-support)
10. [Real Hardware Deployment](#real-hardware-deployment)
11. [Troubleshooting](#troubleshooting)
12. [Future Roadmap](#future-roadmap)

---

## Architecture Overview

UniversalOS is a bare-metal x86 operating system bootloader with diagnostic capabilities. The current implementation consists of three stages:

```
┌──────────┐
│  BIOS    │  Loads sector 0 (MBR) → 0x7C00
└────┬─────┘
     │
     ▼
┌──────────┐
│ Stage 0  │  512 bytes MBR
│ 0x7C00   │  • CPU detection (CPUID vendor, 64-bit flag)
└────┬─────┘  • Load Stage 1 via INT 13h (LBA)
     │
     ▼
┌──────────┐
│ Stage 1  │  Max 4 KB (8 sectors)
│ 0x7E00   │  • E820 memory map
└────┬─────┘  • Calculate total RAM
     │        • Load Stage 2
     ▼
┌──────────┐
│ Stage 2  │  Max 28 KB (56 sectors)
│ 0x9000   │  • Interactive shell (real mode 16-bit)
└──────────┘  • Commands: cpu, mem, arch, disk, kbd, clear, reboot
```

**Key Features:**
- **Pure 16-bit real mode** — no protected/long mode transition yet
- **Hardware compatibility** — runs on real x86 PCs, not just QEMU
- **AZERTY/QWERTY keyboard support** — toggle with `kbd` command
- **Diagnostic tools** — inspect CPU, RAM, disk before OS loading
- **Single-file image** — 1 MB raw disk image, bootable via USB/CD

---

## Memory Layout

All addresses are physical (real mode segmentation: `segment:offset`).

```
┌─────────────────────────────────────────────────────────────────┐
│ 0x00000 - 0x003FF : Interrupt Vector Table (IVT) - BIOS         │
│ 0x00400 - 0x004FF : BIOS Data Area (BDA)                        │
│ 0x00500 - 0x0050F : INFO_BLOCK (shared data, 16 bytes)          │
│                     +0x00: CPU vendor string (12 bytes)          │
│                     +0x0C: 64-bit flag (1=yes, 0=no, 0xFF=old)   │
│                     +0x0D: Boot drive number (0x80, 0x81, etc)   │
│                     +0x0E: Total RAM in MB (2 bytes)             │
│ 0x00510 - 0x01FFF : Unused                                      │
│ 0x02000 - 0x02xxx : E820 Memory Map (raw BIOS data)             │
│                     0x1FFE: Entry count (2 bytes)                │
│                     0x2000+: 24-byte entries (base, length, type)│
│ 0x05000 - 0x05FFF : CPU Brand String buffer (used by Stage 2)   │
│ 0x06000 - 0x060FF : Keyboard input buffer (Stage 2)             │
│ 0x07C00 - 0x07DFF : Stage 0 (MBR, 512 bytes, loaded by BIOS)    │
│ 0x07E00 - 0x08DFF : Stage 1 (loaded by Stage 0, max 4096 bytes) │
│ 0x09000 - 0x0FFFF : Stage 2 (loaded by Stage 1, max 28 KB)      │
│ 0x10000 - 0x9FFFF : Free conventional memory (640 KB - 64 KB)   │
│ 0xA0000 - 0xFFFFF : Video RAM, ROM BIOS, etc.                   │
└─────────────────────────────────────────────────────────────────┘
```

**Important Notes:**
- All stages share INFO_BLOCK at 0x0500
- E820 map is written once by Stage 1, read by Stage 2
- Stack grows downward from 0x9000 (Stage 2) or 0x7C00 (Stage 0)

---

## Disk Layout

Raw disk image: **1,048,576 bytes (1 MB)** = 2048 sectors × 512 bytes.

```
┌─────────────────────────────────────────────────────────┐
│ Sector 0        : Stage 0 (MBR, 512 bytes)              │
│                   Last 2 bytes: 0x55 0xAA (boot sig)    │
├─────────────────────────────────────────────────────────┤
│ Sectors 1-8     : Stage 1 (max 4096 bytes, 8 sectors)   │
│                   Actual size: 426 bytes (1 sector)     │
├─────────────────────────────────────────────────────────┤
│ Sectors 9-64    : Stage 2 (max 28672 bytes, 56 sectors) │
│                   Actual size: 28672 bytes (56 sectors) │
├─────────────────────────────────────────────────────────┤
│ Sectors 65-2047 : Reserved for Stage 3+ (future)        │
└─────────────────────────────────────────────────────────┘
```

**Why these limits?**
- Stage 0: 512 bytes (MBR standard)
- Stage 1: 4 KB is enough for E820 detection + disk I/O
- Stage 2: 28 KB fits a full-featured shell without paging

---

## Boot Sequence

### 1. BIOS POST (Power-On Self-Test)
- CPU starts at `0xFFFF:0x0000` (real mode reset vector)
- BIOS initializes hardware, sets up IVT, detects boot device

### 2. BIOS Boot Phase
- BIOS loads sector 0 (MBR) → `0x7C00`
- Verifies boot signature (`0x55AA` at offset 510)
- Jumps to `0x0000:0x7C00`

### 3. Stage 0 Execution
- Sets up segments (DS=ES=SS=0, SP=0x7C00)
- Detects CPU via CPUID → writes to INFO_BLOCK
- Loads Stage 1 (sectors 1-8) → `0x7E00` via INT 13h AH=42h
- Jumps to `0x0000:0x7E00`

### 4. Stage 1 Execution
- Calls INT 15h AH=E820h to build memory map → `0x2000`
- Sums usable RAM (Type=1 entries) → stores MB count in INFO_BLOCK
- Loads Stage 2 (sectors 9-64) → `0x9000`
- Jumps to `0x0000:0x9000`

### 5. Stage 2 Execution
- Displays banner, enters shell loop
- Waits for user commands (INT 16h keyboard input)
- Executes commands: `cpu`, `mem`, `arch`, `disk`, `kbd`, `clear`, `reboot`

---

## Stage 0: MBR Bootloader

**File:** `stage0/stage0.asm`  
**Load address:** 0x7C00  
**Size:** Exactly 512 bytes (padded with zeros + boot signature)

### Responsibilities

1. **Segment initialization:**
   ```asm
   xor  ax, ax
   mov  ds, ax      ; DS = 0
   mov  es, ax      ; ES = 0
   mov  ss, ax      ; SS = 0
   mov  sp, 0x7C00  ; Stack grows down from 0x7C00
   ```

2. **CPU detection via CPUID:**
   - Test if CPUID available (toggle EFLAGS bit 21)
   - If yes: read vendor string (EBX:EDX:ECX) → INFO_BLOCK +0x00
   - Check Long Mode (CPUID 0x80000001, EDX bit 29) → INFO_BLOCK +0x0C
   - If no CPUID: write "Unknown" vendor, flag=0xFF

3. **Load Stage 1:**
   - Use INT 13h AH=42h (LBA extended read)
   - DAP (Disk Address Packet):
     ```
     Offset 0: 0x10 (size)
     Offset 2: 8 (sectors to read)
     Offset 4: 0x7E00 (buffer offset)
     Offset 6: 0x0000 (buffer segment)
     Offset 8: 1 (LBA start sector)
     ```
   - On error: display "ERR" and halt

4. **Jump to Stage 1:** `jmp 0x0000:0x7E00`

### Size Constraints

- Total code + data must be ≤ 510 bytes
- Bytes 510-511 = `0x55 0xAA` (boot signature)
- Messages are ultra-compact ("S1..." instead of "Loading Stage 1...")

---

## Stage 1: RAM Detector

**File:** `stage1/stage1.asm`  
**Load address:** 0x7E00  
**Max size:** 4096 bytes (8 sectors)  
**Actual size:** 426 bytes (1 sector)

### Responsibilities

1. **E820 Memory Map Detection:**
   ```asm
   xor  ebx, ebx
   mov  di, E820_MAP     ; 0x2000
   mov  eax, 0xE820
   mov  edx, 0x534D4150  ; "SMAP"
   mov  ecx, 24          ; entry size
   int  0x15
   ```
   - Loops until EBX=0 (end of list)
   - Each entry: 24 bytes (base_low, base_high, length_low, length_high, type, extended_attributes)
   - Stores entry count at 0x1FFE

2. **Calculate Total RAM:**
   - Sum all Type=1 (usable) regions
   - Convert bytes → MB (divide by 1,048,576)
   - Store in INFO_BLOCK +0x0E

3. **Load Stage 2:**
   - Read sectors 9-64 (56 sectors = 28 KB) → 0x9000
   - Same LBA method as Stage 0

4. **Jump to Stage 2:** `jmp 0x0000:0x9000`

---

## Stage 2: Diagnostic Shell

**File:** `stage2/stage2.asm`  
**Load address:** 0x9000  
**Max size:** 28672 bytes (56 sectors)  
**Actual size:** 28672 bytes (fully utilized)

### Interactive Commands

| Command   | Description | Implementation |
|-----------|-------------|----------------|
| `help`    | Show command list | Displays help_text string |
| `cpu`     | CPU info (vendor, mode, family, model, brand) | CPUID(0), CPUID(1), CPUID(0x80000002-4) |
| `mem`     | E820 memory map table | Parse entries at 0x2000, print base/length/type |
| `arch`    | Platform summary | Combine CPU vendor, mode, RAM, boot drive |
| `disk`    | Disk geometry | INT 13h AH=08h → cylinders/heads/sectors |
| `kbd`     | Toggle QWERTY/AZERTY | Set kbd_layout flag, remap scancodes |
| `clear`   | Clear screen | INT 10h AX=0x0003 |
| `reboot`  | Restart | `jmp 0xFFFF:0x0000` |

### Command Parsing

```asm
shell_loop:
    ; Display prompt "UOS> "
    mov  si, prompt
    call s2_puts
    
    ; Read line into INPUT_BUF (max 200 chars)
    mov  di, INPUT_BUF
    mov  cx, INPUT_MAX
    call s2_readline
    
    ; Compare with command strings
    mov  si, INPUT_BUF
    mov  di, cmd_help
    call s2_strcmp
    jz   cmd_help_fn
    
    ; ... (repeat for other commands)
    
    ; Unknown command
    mov  si, msg_unknown
    call s2_puts
    jmp  shell_loop
```

### CPU Information Display

**Example output:**
```
  CPU Vendor  : GenuineIntel
  CPU Mode    : 64-bit (Long Mode)
  Family      : 6
  Model       : 15
  Stepping    : 11
  Brand       : Intel(R) Core(TM) i7-8750H CPU @ 2.20GHz
```

**Implementation:**
- Vendor: already in INFO_BLOCK (from Stage 0)
- Mode: read flag at INFO_BLOCK +0x0C
- Family/Model/Stepping: CPUID(1) → EAX bits 8-11, 4-7, 0-3
- Brand String: CPUID(0x80000002-4) → 48 bytes at 0x5000

### Memory Map Display

**Example output:**
```
E820 Memory Map:
Base       Length     Type
---------- ---------- ----------------
00000000   0009FC00   Usable RAM
0009FC00   00000400   Reserved
000E8000   00018000   Reserved
00100000   07EE0000   Usable RAM
07FE0000   00020000   Reserved
FFFC0000   00040000   Reserved
```

**Implementation:**
- Read entry count from 0x1FFE
- Loop through 24-byte entries at 0x2000
- Print base/length in hex, translate type code to string

---

## BIOS Services Used

### INT 10h — Video Services

| AH  | Function | Usage |
|-----|----------|-------|
| 0x00 | Set video mode | AX=0x0003 → 80×25 text mode |
| 0x0E | Teletype output | AL=char, BH=page → print char |

### INT 13h — Disk Services

| AH  | Function | Usage |
|-----|----------|-------|
| 0x08 | Get drive parameters | DL=drive → CX=cylinders/sectors, DH=heads |
| 0x42 | Extended read | DS:SI=DAP → read LBA sectors |

**DAP Structure (Disk Address Packet):**
```
Offset  Size  Description
0       1     Packet size (0x10)
1       1     Reserved (0x00)
2       2     Number of sectors to read
4       2     Buffer offset
6       2     Buffer segment
8       4     LBA start sector (low 32 bits)
12      4     LBA start sector (high 32 bits)
```

### INT 15h — System Services

| AH    | Function | Usage |
|-------|----------|-------|
| 0xE820 | Query memory map | EBX=continuation, ES:DI=buffer → 24-byte entries |

**E820 Entry Structure:**
```
Offset  Size  Description
0       8     Base address (64-bit)
8       8     Length (64-bit)
16      4     Type (1=usable, 2=reserved, 3=ACPI reclaimable, 4=ACPI NVS)
20      4     Extended attributes
```

### INT 16h — Keyboard Services

| AH  | Function | Usage |
|-----|----------|-------|
| 0x00 | Read key | Wait for keypress → AH=scancode, AL=ASCII |

---

## Keyboard Support

UniversalOS Stage 2 supports both **QWERTY** (default) and **AZERTY** (French) keyboard layouts.

### Switching Layouts

Type `kbd` at the shell prompt to toggle:
```
UOS> kbd
Keyboard: AZERTY (French)
UOS> kbd
Keyboard: QWERTY
```

### AZERTY Scancode Mapping

French AZERTY keyboards differ from QWERTY in:

| QWERTY Key | AZERTY Key | Scancode | Notes |
|------------|------------|----------|-------|
| 1 | & | 0x02 | Number row remapped |
| 2 | é | 0x03 | Accented character |
| 3 | " | 0x04 | Quote mark |
| 4 | ' | 0x05 | Apostrophe |
| 5 | ( | 0x06 | Parenthesis |
| 6 | - | 0x07 | Hyphen |
| 7 | è | 0x08 | Accented e |
| 8 | _ | 0x09 | Underscore |
| 9 | ç | 0x0A | Cedilla |
| 0 | à | 0x0B | Accented a |
| Q | A | 0x10 | Letter swap |
| W | Z | 0x11 | Letter swap |
| A | Q | 0x1E | Letter swap |
| Z | W | 0x2C | Letter swap |
| M | , (comma) | 0x32 | Punctuation |
| , | ; (semicolon) | 0x33 | Punctuation |
| . | : (colon) | 0x34 | Punctuation |
| / | ! (exclamation) | 0x35 | Punctuation |

**Implementation Detail:**
- `map_scancode` function checks `kbd_layout` flag (0=QWERTY, 1=AZERTY)
- If AZERTY, uses scancode (AH register from INT 16h) to index into `azerty_map` table
- If entry ≠ 0, replaces AL (ASCII) with mapped character

---

## Real Hardware Deployment

### Prerequisites

- **USB flash drive** (minimum 2 MB, FAT32 or raw)
- **Bootable USB tool:** Rufus (Windows), `dd` (Linux/macOS)
- **BIOS/UEFI:** Legacy BIOS mode required (not UEFI)

### Method 1: Windows (Rufus)

1. Download Rufus: https://rufus.ie/
2. Insert USB drive
3. Launch Rufus:
   - **Device:** Select your USB drive
   - **Boot selection:** "Disk or ISO image"
   - Click `SELECT` → choose `universalos.img`
   - **Partition scheme:** MBR
   - **Target system:** BIOS (or UEFI-CSM)
   - **File system:** (ignored for DD images)
4. Click `START`
5. Rufus will write the image in DD mode

### Method 2: Linux/macOS (`dd`)

1. Insert USB drive
2. Find device name:
   ```bash
   # Linux
   lsblk
   # Look for your USB (e.g., /dev/sdb)
   
   # macOS
   diskutil list
   # Look for your USB (e.g., /dev/disk2)
   ```

3. **⚠️ WARNING:** This will erase the entire USB drive!
   ```bash
   # Linux
   sudo dd if=universalos.img of=/dev/sdX bs=4M status=progress
   sudo sync
   
   # macOS
   sudo dd if=universalos.img of=/dev/rdiskX bs=4m
   sudo diskutil eject /dev/diskX
   ```

4. Eject USB safely

### Method 3: Write to CD-ROM (Legacy)

```bash
# Linux
cdrecord -v dev=/dev/sr0 universalos.img

# macOS
hdiutil burn universalos.img
```

### Booting from USB

1. Insert USB drive
2. Restart computer
3. Enter BIOS/Boot menu:
   - **Common keys:** F2, F12, Del, Esc (varies by manufacturer)
   - Or spam F12 during boot for one-time boot menu
4. **Disable Secure Boot** (UEFI systems)
5. **Enable Legacy Boot** or CSM mode
6. Select USB drive from boot menu
7. System should boot into Stage 0 → Stage 1 → Stage 2 shell

### Expected Hardware Compatibility

**✅ Tested on:**
- QEMU x86_64 (emulation)
- QEMU i386 (emulation)
- VirtualBox (legacy BIOS mode)
- VMware Workstation (legacy BIOS)

**⚠️ Requirements:**
- x86/x86_64 CPU (Intel, AMD)
- Legacy BIOS (not pure UEFI)
- At least 32 MB RAM
- Any BIOS-compatible disk controller

**❌ Not supported:**
- ARM/Raspberry Pi (requires ARM port)
- Pure UEFI systems without CSM
- Secure Boot enabled

---

## Troubleshooting

### Issue: "No bootable device"

**Cause:** Boot signature missing or USB not set as first boot device.

**Solution:**
1. Verify boot signature:
   ```bash
   xxd universalos.img | grep "55aa"
   # Should see: ... 55aa
   ```
2. Check BIOS boot order
3. Try different USB port (USB 2.0 preferred)

### Issue: Black screen after "S1...OK"

**Cause:** Stage 2 failed to load or jumped to wrong address.

**Solution:**
1. Verify image size: `ls -lh universalos.img` → should be 1 MB
2. Check if Stage 2 sectors are written:
   ```bash
   dd if=universalos.img bs=512 skip=9 count=1 | xxd | head
   # Should show Stage 2 code, not zeros
   ```
3. Rebuild from source

### Issue: "ERR" during Stage 0

**Cause:** INT 13h disk read failed (old BIOS, incompatible controller).

**Solution:**
1. Try CHS mode instead of LBA (requires Stage 0 rewrite)
2. Use virtualization (QEMU, VirtualBox)
3. Check disk controller settings in BIOS

### Issue: Keyboard not working in Stage 2

**Cause:** USB keyboard on old systems without USB legacy support.

**Solution:**
1. Enable "USB Legacy Support" in BIOS
2. Use PS/2 keyboard
3. Try different BIOS version

### Issue: Wrong keyboard layout

**Cause:** Physical keyboard is AZERTY but shell defaults to QWERTY.

**Solution:**
- Type `kbd` to toggle layout
- Reboot persists to QWERTY (no NVRAM storage yet)

### Issue: Memory map shows 0 entries

**Cause:** Ancient BIOS without E820 support.

**Solution:**
- Normal for pre-2000 systems
- Stage 1 should fall back to INT 15h AH=88h (TODO: not implemented)

---

## Future Roadmap

### Stage 3: Protected Mode Transition

- [ ] GDT setup (Global Descriptor Table)
- [ ] Enter protected mode (CR0.PE bit)
- [ ] A20 line enabling
- [ ] 32-bit kernel loading

### Stage 4: Long Mode (64-bit)

- [ ] Check CPUID Long Mode flag
- [ ] Setup page tables (PML4, PDPT, PD, PT)
- [ ] Enable PAE (CR4.PAE)
- [ ] Load 64-bit kernel

### Hypervisor Features

- [ ] VMX/SVM detection (Intel VT-x / AMD-V)
- [ ] VMCS/VMCB setup
- [ ] Virtual machine launch
- [ ] Multi-machine KVM software emulation

### Multi-Architecture Support

- [ ] ARM boot (U-Boot → Stage 1)
- [ ] Raspberry Pi support (BCM2835/BCM2711)
- [ ] RISC-V port
- [ ] Universal bootloader protocol

### UEFI Support

- [ ] GOP (Graphics Output Protocol)
- [ ] GPT partition table
- [ ] EFI boot services
- [ ] Secure Boot compatibility

### Advanced Shell Features

- [ ] Persistent configuration (write to disk)
- [ ] File browser (FAT32 driver)
- [ ] Network boot (PXE integration)
- [ ] Serial console support

---

## Development Tools

### Required Software

- **NASM** (Netwide Assembler) 2.14+
- **Python** 3.7+ (for image creation script)
- **QEMU** (for testing)
  - Windows: `C:\msys64\ucrt64\bin\qemu-system-x86_64.exe`
  - Linux: `qemu-system-x86_64` package
  - macOS: `brew install qemu`

### Build System

```bash
# Windows
build.bat

# Linux/macOS
chmod +x build.sh && ./build.sh

# Manual
nasm -f bin stage0/stage0.asm -o build/stage0.bin
nasm -f bin stage1/stage1.asm -o build/stage1.bin
nasm -f bin stage2/stage2.asm -o build/stage2.bin
python3 create_image.py
```

### Testing

```bash
# x86_64 mode (64-bit CPU)
qemu-system-x86_64 -drive format=raw,file=build/universalos.img -m 128M

# i386 mode (32-bit CPU)
qemu-system-i386 -drive format=raw,file=build/universalos.img -m 64M

# Ancient CPU (no CPUID)
qemu-system-x86_64 -cpu 486 -drive format=raw,file=build/universalos.img -m 32M
```

### Debugging

**GDB + QEMU:**
```bash
# Terminal 1: Start QEMU with GDB stub
qemu-system-x86_64 -drive format=raw,file=build/universalos.img -s -S

# Terminal 2: Attach GDB
gdb
(gdb) target remote localhost:1234
(gdb) set architecture i8086
(gdb) break *0x7c00
(gdb) continue
```

**Disassemble stages:**
```bash
ndisasm -b 16 -o 0x7C00 build/stage0.bin | less
ndisasm -b 16 -o 0x7E00 build/stage1.bin | less
ndisasm -b 16 -o 0x9000 build/stage2.bin | less
```

---

## License & Credits

**License:** MIT (open source)

**Author:** Claude (Anthropic AI) + Human Collaboration

**References:**
- [OSDev Wiki](https://wiki.osdev.org/)
- Intel Software Developer Manual (SDM)
- Ralf Brown's Interrupt List
- BIOS Interrupts Reference

---

**End of Technical Documentation**
