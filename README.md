# UniOS - Documentation Technique Complète

## Table des Matières

1. [Introduction et Vision](#introduction-et-vision)
2. [Architecture Globale](#architecture-globale)
3. [Structure du Projet](#structure-du-projet)
4. [Documentation des Stages](#documentation-des-stages)
5. [Organisation Mémoire](#organisation-mémoire)
6. [Protocole de Communication Inter-Stages](#protocole-de-communication-inter-stages)
7. [Système de Clavier AZERTY/QWERTY](#système-de-clavier-azertyqwerty)
8. [Processus de Build](#processus-de-build)
9. [Format de l'Image Disque](#format-de-limage-disque)
10. [Roadmap et Évolutions Futures](#roadmap-et-évolutions-futures)

---

## Introduction et Vision

UniOS est un projet de système d'exploitation modulaire conçu pour être **universel** - c'est-à-dire capable de fonctionner sur n'importe quelle architecture matérielle et de gérer plusieurs systèmes d'exploitation simultanément.

### Objectifs Principaux

1. **Multi-Architecture** : Compatible avec toutes les architectures (x86, x86_64, ARM, anciennes machines)
2. **Hyperviseur Natif** : Fonctionne au niveau du boot, peut héberger d'autres OS
3. **KVM Logiciel** : Partage de périphériques entre plusieurs machines physiques
4. **Diagnostic Universel** : Outils de récupération et test fonctionnant sur toutes les plateformes

### Vision du Projet

UniversalOS ne remplace pas les systèmes d'exploitation existants - il les **orchestre**. L'OS d'origine de chaque machine devient une "fenêtre" dans l'environnement UniversalOS, permettant :

- De lancer rapidement une instance Android ou macOS pour tester des applications
- D'utiliser plusieurs PC avec leurs spécificités depuis un seul poste de travail
- De récupérer des fichiers sur d'anciennes machines qui ne bootent plus
- De streamer un jeu depuis un PC puissant tout en utilisant le stockage d'un autre

---

## Architecture Globale

UniversalOS utilise une architecture en **4 stages** (couches) progressifs :

```
┌─────────────────────────────────────────────────────────────┐
│                     STAGE 3: OS COMPLET                      │
│  • Interface graphique complète                              │
│  • Virtualisation/Émulation multi-OS                         │
│  • Gestion multi-machines (KVM logiciel)                     │
│  • Tous les drivers et fonctionnalités                       │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────┐
│                  STAGE 2: OS LÉGER (actuel)                  │
│  • Shell interactif de diagnostic                            │
│  • Commandes système (cpu, mem, disk, arch)                  │
│  • Fonctionne avec un minimum de ressources                  │
│  • Peut installer Stage 3 depuis disque/USB/réseau           │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────┐
│               STAGE 1: BOOTLOADER ADAPTÉ                     │
│  • Détection RAM (E820 memory map)                           │
│  • Calcul RAM totale                                         │
│  • Chargement Stage 2 depuis disque                          │
│  • Spécifique à l'architecture détectée par Stage 0          │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────┐
│           STAGE 0: PRÉ-BOOTLOADER (MBR - 512 o)             │
│  • Premier code exécuté par le BIOS                          │
│  • Détection automatique architecture (CPUID)                │
│  • Identifie : CPU vendor, mode 64/32 bit                    │
│  • Charge Stage 1                                            │
│  • Tient dans exactement 512 octets (secteur boot)           │
└─────────────────────────────────────────────────────────────┘
```

### Modes de Fonctionnement

**Mode 1 : Installation Complète (accès BIOS)**
- Installation des 4 stages
- L'OS d'origine devient une "fenêtre" dans le nouvel OS
- Contrôle total de la machine au boot

**Mode 2 : Application (sans droits admin)**
- Pour les machines où on ne peut pas modifier le BIOS
- Connexion des stockages/écrans/entrées/sorties entre machines
- Fonctionne sur un réseau (possiblement via Raspberry Pi comme pont)

---

## Structure du Projet

```
universalos/
│
├── stage0.asm              # MBR 512 octets (CPUID + chargement Stage 1)
├── stage1.asm              # Détection RAM E820 + chargement Stage 2
├── stage2.asm              # Shell interactif avec commandes de diagnostic
│
├── build/                  # Dossier de sortie (généré)
│   ├── stage0.bin         # Binaire Stage 0 (512 octets)
│   ├── stage1.bin         # Binaire Stage 1 (max 4096 octets)
│   ├── stage2.bin         # Binaire Stage 2 (max 28672 octets)
│   ├── stage0.lst         # Listing assembleur Stage 0
│   ├── stage1.lst         # Listing assembleur Stage 1
│   ├── stage2.lst         # Listing assembleur Stage 2
│   └── universalos.img    # Image disque RAW complète (1 Mo)
│
├── create_image.py         # Script Python d'assemblage de l'image disque
├── build.bat               # Script de build Windows (NASM + Python)
├── build.sh                # Script de build Linux/macOS
│
├── run_x86_64.bat          # Lance QEMU 64-bit (Windows)
├── run_x86_32.bat          # Lance QEMU 32-bit (Windows)
│
├── GUIDE.md                # Guide de test QEMU
└── README.md               # Documentation principale
```

---

## Documentation des Stages

### Stage 0 : Pré-Bootloader (MBR)

**Fichier** : `stage0.asm`  
**Taille** : Exactement 512 octets  
**Chargé à** : `0x7C00` par le BIOS  
**Objectif** : Premier code exécuté, détection architecture et chargement Stage 1

#### Responsabilités

1. **Initialisation système**
   - Configuration des segments (DS, ES, SS = 0x0000)
   - Configuration de la pile (SP = 0x7C00)
   - Mode vidéo texte 80x25

2. **Détection CPU (CPUID)**
   ```assembly
   ; Test si CPUID disponible (bit 21 de EFLAGS)
   ; Si oui : récupère vendor string (EBX:EDX:ECX)
   ;          teste Long Mode (bit 29 de EDX après CPUID 0x80000001)
   ; Si non : CPU ancien (pré-Pentium)
   ```

3. **Stockage des informations** dans `INFO_BLOCK` (0x0500)
   - +0x00 [12B] : CPU Vendor ("GenuineIntel", "AuthenticAMD", "Unknown")
   - +0x0C [1B]  : Flag 64-bit (0x01=64-bit, 0x00=32-bit, 0xFF=ancien)
   - +0x0D [1B]  : Numéro du disque de boot (0x80 = premier disque dur)

4. **Chargement Stage 1**
   - Utilise INT 13h, AH=42h (LBA extended)
   - Charge 8 secteurs (LBA 1-8) vers 0x7E00
   - DAP (Disk Address Packet) pour spécifier secteur/adresse

5. **Saut vers Stage 1**
   - `jmp 0x0000:0x7E00`

#### Code Important

```assembly
; Détection CPUID
cpu_detect:
    pushfd
    pop  eax
    mov  ecx, eax
    xor  eax, (1 << 21)      ; Flip bit 21
    push eax
    popfd
    pushfd
    pop  eax
    xor  eax, ecx
    jz   .ancient            ; Si bit 21 ne change pas → pas de CPUID

    ; Récupère vendor string
    mov  eax, 0
    cpuid
    mov  [INFO_BLOCK + 0], ebx    ; "Genu"
    mov  [INFO_BLOCK + 4], edx    ; "ineI"
    mov  [INFO_BLOCK + 8], ecx    ; "ntel"

    ; Teste Long Mode
    mov  eax, 0x80000001
    cpuid
    test edx, (1 << 29)
    jz   .no_lm
    mov  byte [INFO_BLOCK + 0x0C], 1    ; 64-bit supporté
```

#### Messages Affichés

```
[S0] UniversalOS v0.1
CPU: GenuineIntel          ← Vendor détecté
[64-bit]                   ← ou [32-bit] ou [OLD]
S1...OK                    ← Chargement Stage 1 réussi
```

---

### Stage 1 : Bootloader Adapté

**Fichier** : `stage1.asm`  
**Taille** : Maximum 4096 octets (8 secteurs)  
**Chargé à** : `0x7E00` par Stage 0  
**Objectif** : Détection RAM et chargement Stage 2

#### Responsabilités

1. **Détection de la RAM (E820 Memory Map)**
   - Utilise INT 15h, EAX=0xE820 (BIOS function)
   - Récupère toutes les régions mémoire (RAM, ROM, ACPI, etc.)
   - Stocke la carte complète à `0x2000`
   - Compte le nombre d'entrées et le stocke à `0x1FFE`

2. **Calcul de la RAM totale**
   - Parcourt toutes les entrées E820
   - Additionne les régions de Type=1 (RAM utilisable)
   - Convertit en MB et stocke dans `INFO_BLOCK+0x0E`

3. **Chargement Stage 2**
   - Charge 56 secteurs (LBA 9-64) vers 0x9000
   - Utilise INT 13h, AH=42h (LBA extended)

4. **Saut vers Stage 2**
   - `jmp 0x0000:0x9000`

#### Structure E820 Entry (24 octets)

```
Offset | Taille | Description
-------|--------|------------
+0     | 8B     | Base Address (64-bit)
+8     | 8B     | Length (64-bit)
+16    | 4B     | Type (1=RAM, 2=Reserved, 3=ACPI Reclaim, 4=ACPI NVS)
+20    | 4B     | Extended Attributes
```

#### Code Important

```assembly
detect_ram:
    xor  ebx, ebx
    mov  di, E820_MAP           ; 0x2000
    xor  cx, cx                  ; compteur d'entrées

.loop:
    mov  eax, 0xE820
    mov  edx, 0x534D4150         ; "SMAP" signature
    mov  ecx, 24                 ; taille buffer
    int  0x15
    jc   .done                   ; Carry = fin de liste

    add  di, 24
    inc  cx
    test ebx, ebx
    jz   .done
    jmp  .loop

.done:
    mov  [E820_MAP - 2], cx      ; stocke nombre d'entrées à 0x1FFE
```

#### Messages Affichés

```
[S1] UniversalOS - Stage 1
Detecting RAM...
RAM: 128 MB                    ← RAM totale calculée
Loading Stage 2...OK
```

---

### Stage 2 : Shell de Diagnostic

**Fichier** : `stage2.asm`  
**Taille** : Maximum 28672 octets (56 secteurs)  
**Chargé à** : `0x9000` par Stage 1  
**Objectif** : Shell interactif avec commandes de diagnostic système

#### Responsabilités

1. **Shell interactif**
   - Boucle principale lecture/parsing/exécution de commandes
   - Gestion du buffer clavier (200 caractères max)
   - Support AZERTY/QWERTY commutable

2. **Commandes disponibles**
   - `help` : Liste toutes les commandes
   - `cpu` : Informations CPU détaillées
   - `mem` : Carte mémoire E820 complète
   - `arch` : Résumé plateforme
   - `disk` : Géométrie disque BIOS
   - `kbd` : Bascule QWERTY/AZERTY
   - `clear` : Efface l'écran
   - `reboot` : Redémarre la machine

#### Commande CPU

Affiche les informations détaillées du processeur :

```
UOS> cpu
  CPU Vendor  : GenuineIntel
  CPU Mode    : 64-bit (Long Mode)
  Family      : 6
  Model       : 142
  Stepping    : 10
  Brand       : Intel(R) Core(TM) i7-8550U CPU @ 1.80GHz
```

**Code important** :

```assembly
cmd_cpu_fn:
    ; Vendor (déjà stocké dans INFO_BLOCK par Stage 0)
    mov  si, INFO_BLOCK
    call s2_puts

    ; Mode 64/32 bit
    mov  al, [INFO_BLOCK + 0x0C]
    cmp  al, 1
    je   .mode_64

    ; Family/Model/Stepping via CPUID(1)
    mov  eax, 1
    cpuid
    ; Family = bits 8-11
    shr  eax, 8
    and  eax, 0x0F

    ; Brand String (CPUID 0x80000002-0x80000004)
    mov  eax, 0x80000002
    cpuid
    ; ... récupère 48 caractères sur 3 appels
```

#### Commande MEM

Affiche la carte mémoire E820 complète :

```
UOS> mem

E820 Memory Map:
Base       Length     Type
---------- ---------- ----------------
00000000   0009FC00   Usable RAM
0009FC00   00000400   Reserved
000F0000   00010000   Reserved
00100000   07EE0000   Usable RAM
07FE0000   00020000   Reserved
FFFC0000   00040000   Reserved
```

**Code important** :

```assembly
cmd_mem_fn:
    movzx ecx, word [E820_MAP - 2]   ; nombre d'entrées
    mov   si, E820_MAP

.print_loop:
    mov   eax, [si + 0]     ; base_low
    call  s2_print_hex32
    
    mov   eax, [si + 8]     ; length_low
    call  s2_print_hex32
    
    mov   eax, [si + 16]    ; type
    ; ... affiche "Usable RAM", "Reserved", etc.
    
    add   si, 24
    loop  .print_loop
```

#### Commande ARCH

Résumé rapide de la plateforme :

```
UOS> arch

Platform Summary:
  CPU Vendor  : GenuineIntel
  CPU Mode    : 64-bit (Long Mode)
  Total RAM   : 128 MB
  Boot Drive  : 0x80
```

#### Commande DISK

Géométrie du disque via BIOS INT 13h :

```
UOS> disk

Disk Geometry (BIOS INT 13h AH=08h):
  Cylinders   : 130
  Heads       : 16
  Sectors/Trk : 63
```

**Code important** :

```assembly
cmd_disk_fn:
    mov  ah, 0x08
    mov  dl, [INFO_BLOCK + 0x0D]   ; boot drive
    int  0x13
    
    ; Cylinders = CH + ((CL & 0xC0) << 2)
    mov  al, cl
    and  al, 0xC0
    shl  ax, 2
    mov  ah, ch
    inc  ax                         ; BIOS donne max, on veut count
```

---

## Organisation Mémoire

### Layout Mémoire Real-Mode (0x00000 - 0xFFFFF)

```
┌─────────────────────────────────────────────────────────────┐
│ 0x00000 - 0x003FF   IVT (Interrupt Vector Table)            │
│                     Vecteurs d'interruptions BIOS            │
├─────────────────────────────────────────────────────────────┤
│ 0x00400 - 0x004FF   BDA (BIOS Data Area)                    │
│                     Variables BIOS (ports, config)           │
├─────────────────────────────────────────────────────────────┤
│ 0x00500 - 0x0050F   INFO_BLOCK (partagé Stage 0/1/2)        │
│   +0x00 [12B]       CPU Vendor ("GenuineIntel", etc.)       │
│   +0x0C [1B]        Flag 64-bit (0x01/0x00/0xFF)            │
│   +0x0D [1B]        Boot drive number (0x80 = HDD)          │
│   +0x0E [2B]        RAM totale en MB                        │
├─────────────────────────────────────────────────────────────┤
│ 0x00510 - 0x01FFF   Espace libre                            │
├─────────────────────────────────────────────────────────────┤
│ 0x01FFE - 0x01FFF   E820 entry count (2 octets)             │
├─────────────────────────────────────────────────────────────┤
│ 0x02000 - 0x04FFF   E820 Memory Map (jusqu'à 512 entrées)   │
│                     Chaque entrée = 24 octets                │
├─────────────────────────────────────────────────────────────┤
│ 0x05000 - 0x05FFF   Buffer temporaire (Brand String, etc.)  │
├─────────────────────────────────────────────────────────────┤
│ 0x06000 - 0x060C8   INPUT_BUF (buffer clavier Stage 2)      │
│                     200 caractères max + null terminator     │
├─────────────────────────────────────────────────────────────┤
│ 0x07C00 - 0x07DFF   STAGE 0 (MBR)                           │
│                     512 octets chargés par BIOS              │
├─────────────────────────────────────────────────────────────┤
│ 0x07E00 - 0x08DFF   STAGE 1 (Bootloader)                    │
│                     Max 4096 octets (8 secteurs)             │
├─────────────────────────────────────────────────────────────┤
│ 0x09000 - 0x0FFFF   STAGE 2 (Shell)                         │
│                     Max 28672 octets (56 secteurs)           │
├─────────────────────────────────────────────────────────────┤
│ 0x10000 - 0x9FFFF   Espace libre pour Stage 3+              │
│                     ~576 Ko disponibles                      │
├─────────────────────────────────────────────────────────────┤
│ 0xA0000 - 0xBFFFF   Video RAM (VGA)                         │
├─────────────────────────────────────────────────────────────┤
│ 0xC0000 - 0xFFFFF   BIOS ROM, Option ROMs                   │
└─────────────────────────────────────────────────────────────┘
```

### Justifications des Adresses

- **0x7C00** : Adresse standard où le BIOS charge le MBR (512 premiers octets du disque)
- **0x7E00** : Immédiatement après Stage 0, emplacement logique pour Stage 1
- **0x9000** : Assez haut pour éviter BIOS/IVT, assez bas pour rester en conventional memory
- **0x0500** : Zone libre standard après BDA, idéale pour partager des données entre stages

---

## Protocole de Communication Inter-Stages

### INFO_BLOCK (0x0500) - Structure Partagée

Cette zone mémoire est le **pont de communication** entre les 3 stages. Chaque stage y lit et écrit des informations pour les suivants.

```
Offset | Taille | Rempli par | Lu par     | Contenu
-------|--------|------------|------------|----------------------------------
+0x00  | 12B    | Stage 0    | Stage 1,2  | CPU Vendor String (null-terminated)
+0x0C  | 1B     | Stage 0    | Stage 1,2  | CPU Mode (0x01=64-bit, 0x00=32-bit, 0xFF=ancien)
+0x0D  | 1B     | Stage 0    | Stage 1,2  | Boot Drive Number (0x80 = 1er disque dur)
+0x0E  | 2B     | Stage 1    | Stage 2    | RAM totale en MB (word, little-endian)
```

### Flux de Données

```
STAGE 0 (0x7C00)
    │
    ├─> Détecte CPU vendor → INFO_BLOCK+0x00
    ├─> Détecte 64/32 bit  → INFO_BLOCK+0x0C
    ├─> Stocke boot drive  → INFO_BLOCK+0x0D
    │
    ├─> Charge Stage 1 (LBA 1-8) → 0x7E00
    │
    └─> jmp 0x7E00
         │
         ▼
    STAGE 1 (0x7E00)
         │
         ├─> Lit boot drive ← INFO_BLOCK+0x0D
         ├─> Détecte RAM E820 → 0x2000
         ├─> Calcule RAM totale → INFO_BLOCK+0x0E
         │
         ├─> Charge Stage 2 (LBA 9-64) → 0x9000
         │
         └─> jmp 0x9000
              │
              ▼
         STAGE 2 (0x9000)
              │
              ├─> Lit CPU vendor ← INFO_BLOCK+0x00
              ├─> Lit CPU mode ← INFO_BLOCK+0x0C
              ├─> Lit boot drive ← INFO_BLOCK+0x0D
              ├─> Lit RAM totale ← INFO_BLOCK+0x0E
              ├─> Lit E820 map ← 0x2000
              │
              └─> Affiche shell interactif
```

---

## Système de Clavier AZERTY/QWERTY

### Problème Résolu

Le système original avait une **table de mapping AZERTY incorrecte** avec :
- Des scancodes mal alignés
- Des `times` qui sautaient des entrées importantes
- Des lettres mappées aux mauvais indices

### Solution Implémentée

La nouvelle table `azerty_map` mappe correctement **chaque scancode** vers son caractère AZERTY équivalent :

```assembly
azerty_map:
    db 0        ; 0x00: unused
    db 0        ; 0x01: ESC
    db '&'      ; 0x02: '1' → '&'
    db 0xE9     ; 0x03: '2' → 'é' (CP437)
    db '"'      ; 0x04: '3' → '"'
    db 0x27     ; 0x05: '4' → '''
    db '('      ; 0x06: '5' → '('
    db '-'      ; 0x07: '6' → '-'
    db 0xE8     ; 0x08: '7' → 'è' (CP437)
    db '_'      ; 0x09: '8' → '_'
    db 0xE7     ; 0x0A: '9' → 'ç' (CP437)
    db 0xE0     ; 0x0B: '0' → 'à' (CP437)
    db ')'      ; 0x0C: '-' → ')'
    db '='      ; 0x0D: '=' → '=' (unchanged)
    db 0        ; 0x0E: Backspace
    db 0        ; 0x0F: Tab
    db 'a'      ; 0x10: Q → A
    db 'z'      ; 0x11: W → Z
    ...
    db 'q'      ; 0x1E: A → Q
    ...
    db 'w'      ; 0x2C: Z → W
    db ','      ; 0x32: M → ','
    db ';'      ; 0x33: ',' → ';'
    db ':'      ; 0x34: '.' → ':'
    db '!'      ; 0x35: '/' → '!'
```

### Fonction de Mapping

```assembly
map_scancode:
    push bx
    push si

    cmp  byte [kbd_layout], 0
    je   .qwerty_done           ; Si QWERTY → pas de mapping

    ; AZERTY : cherche dans la table
    movzx bx, ah                ; BX = scancode
    cmp   bx, 0x53              ; Vérifie range
    ja    .qwerty_done

    mov   si, azerty_map
    add   si, bx                ; SI pointe sur la bonne entrée
    mov   bl, [si]
    test  bl, bl
    jz    .qwerty_done          ; 0 = pas de mapping pour ce scancode
    
    mov   al, bl                ; Utilise le caractère mappé

.qwerty_done:
    pop  si
    pop  bx
    ret
```

### Utilisation

```
UOS> kbd                        ← Tape la commande 'kbd'
Keyboard: AZERTY (French)       ← Confirmation du changement

UOS> qzertyuiop                 ← Tape sur les touches QWERTY
azertyuiop                      ← Affiche les caractères AZERTY corrects

UOS> 1234567890                 ← Tape les chiffres QWERTY
&é"'(-è_çà                      ← Affiche les caractères AZERTY corrects
```

### Encodage CP437

Les caractères accentués utilisent le **code page 437** (DOS) :
- é = 0xE9
- è = 0xE8
- ç = 0xE7
- à = 0xE0
- ù = 0xF9
- ² = 0xB2

---

## Processus de Build

### Build Windows (build.bat)

```batch
1. Détection automatique de NASM
   - Cherche dans %LOCALAPPDATA%\bin\NASM\
   - Cherche dans C:\NASM\, C:\Program Files\NASM\
   - Cherche dans C:\msys64\ucrt64\bin\
   - Cherche dans le PATH avec 'where nasm'

2. Détection automatique de Python
   - Cherche 'py.exe' (launcher)
   - Cherche 'python' / 'python3' dans PATH
   - Cherche dans %LOCALAPPDATA%\Programs\Python\
   - Cherche dans C:\PythonXX\

3. Compilation des stages
   nasm -f bin stage0.asm -o build\stage0.bin -l build\stage0.lst
   nasm -f bin stage1.asm -o build\stage1.bin -l build\stage1.lst
   nasm -f bin stage2.asm -o build\stage2.bin -l build\stage2.lst

4. Création de l'image disque
   python create_image.py
```

### Build Linux/macOS (build.sh)

```bash
#!/bin/bash
mkdir -p build

# Compilation
nasm -f bin stage0.asm -o build/stage0.bin -l build/stage0.lst
nasm -f bin stage1.asm -o build/stage1.bin -l build/stage1.lst
nasm -f bin stage2.asm -o build/stage2.bin -l build/stage2.lst

# Création image
python3 create_image.py
```

### Script create_image.py

```python
# Constantes
SECTOR    = 512
DISK_SIZE = 1024 * 1024   # 1 Mo

STAGE0_LBA      = 0       # Secteur 0 (MBR)
STAGE1_LBA      = 1       # Secteurs 1-8
STAGE1_MAX_SECT = 8
STAGE2_LBA      = 9       # Secteurs 9-64
STAGE2_MAX_SECT = 56

# Processus
1. Crée un buffer de 1 Mo rempli de zéros
2. Lit stage0.bin (doit faire exactement 512 octets)
3. Vérifie la signature 0x55AA aux octets 510-511
4. Place stage0.bin au secteur 0
5. Lit stage1.bin (max 4096 octets = 8 secteurs)
6. Place stage1.bin aux secteurs 1-8
7. Lit stage2.bin (max 28672 octets = 56 secteurs)
8. Place stage2.bin aux secteurs 9-64
9. Écrit le buffer complet dans build/universalos.img
```

---

## Format de l'Image Disque

### Layout Physique (universalos.img - 1 Mo)

```
Offset (hex) | Secteur | Taille      | Contenu
-------------|---------|-------------|----------------------------------
0x00000000   | 0       | 512 octets  | Stage 0 (MBR)
0x000001FE   |         |             | Signature 0x55AA (octets 510-511)
0x00000200   | 1       | 4096 octets | Stage 1 (max 8 secteurs)
0x00001200   | 9       | 28672 octets| Stage 2 (max 56 secteurs)
0x00008200   | 65      | ~1008 Ko    | Espace libre pour Stage 3+
0x00100000   | 2048    |             | Fin de l'image (1 Mo total)
```

### Vérification de l'Image

```bash
# Afficher le MBR (512 premiers octets)
xxd -l 512 build/universalos.img

# Vérifier la signature 0x55AA (octets 510-511)
xxd -s 510 -l 2 build/universalos.img
# Devrait afficher : 55 aa

# Extraire Stage 0
dd if=build/universalos.img of=extracted_stage0.bin bs=512 count=1

# Extraire Stage 1
dd if=build/universalos.img of=extracted_stage1.bin bs=512 skip=1 count=8

# Extraire Stage 2
dd if=build/universalos.img of=extracted_stage2.bin bs=512 skip=9 count=56
```

---

## Roadmap et Évolutions Futures

### Stage 3a : Mode Protégé 32-bit

**Objectifs** :
- Passage du Real Mode (16-bit) au Protected Mode (32-bit)
- Mise en place de la GDT (Global Descriptor Table)
- Activation du paging (mémoire virtuelle)
- Chargement d'un noyau simple

**Étapes** :
1. Créer la GDT avec segments code/data
2. Désactiver les interruptions
3. Charger GDTR (registre GDT)
4. Activer bit PE (Protection Enable) dans CR0
5. Far jump pour recharger CS
6. Recharger DS, ES, FS, GS, SS
7. Réactiver les interruptions (IDT)

### Stage 3b : Mode Long 64-bit

**Objectifs** :
- Passage du Protected Mode au Long Mode (64-bit)
- Support PAE (Physical Address Extension)
- Page Tables pour mapping 1:1
- Support des CPUs modernes

**Étapes** :
1. Vérifier support Long Mode (déjà fait dans Stage 0)
2. Activer PAE (bit 5 de CR4)
3. Créer Page Tables (PML4, PDPT, PD, PT)
4. Charger PML4 dans CR3
5. Activer Long Mode (bit 8 de EFER MSR)
6. Activer paging (bit 31 de CR0)
7. Far jump vers code 64-bit

### Stage 4 : Hyperviseur et Multi-OS

**Objectifs** :
- Virtualisation matérielle (Intel VT-x / AMD-V)
- Gestion multi-machines (KVM logiciel)
- Interface graphique
- Support UEFI (GOP, GPT)

**Technologies** :
1. **VMX/SVM** : Extensions de virtualisation matérielle
2. **EPT/NPT** : Extended/Nested Page Tables
3. **VGA/VESA** : Modes graphiques
4. **ACPI** : Gestion avancée de l'alimentation
5. **PCI** : Énumération des périphériques

### Ports Multi-Architecture

**ARM (Raspberry Pi)** :
- Bootloader U-Boot → Stage 1 ARM
- Device Tree support
- GPIO / UART pour debug

**Android** :
- Boot via fastboot/recovery
- Application mode (sans root)
- ADB pour communication

**iOS** :
- Jailbreak nécessaire pour accès bas niveau
- Checkra1n/unc0ver compatibility
- Application mode via API restrictions

---

## Annexes

### A. Scancodes Clavier Complets

```
Scancode | Touche QWERTY | AZERTY | Notes
---------|---------------|--------|---------------------------
0x01     | ESC           | ESC    | Unchanged
0x02     | 1             | &      | 
0x03     | 2             | é      | CP437: 0xE9
0x04     | 3             | "      | 
0x05     | 4             | '      | 
0x06     | 5             | (      | 
0x07     | 6             | -      | 
0x08     | 7             | è      | CP437: 0xE8
0x09     | 8             | _      | 
0x0A     | 9             | ç      | CP437: 0xE7
0x0B     | 0             | à      | CP437: 0xE0
0x0C     | -             | )      | 
0x0D     | =             | =      | Unchanged
0x0E     | Backspace     | Backs. | Unchanged
0x0F     | Tab           | Tab    | Unchanged
0x10     | Q             | A      | 
0x11     | W             | Z      | 
0x12     | E             | E      | Unchanged
0x13     | R             | R      | Unchanged
0x14     | T             | T      | Unchanged
0x15     | Y             | Y      | Unchanged
0x16     | U             | U      | Unchanged
0x17     | I             | I      | Unchanged
0x18     | O             | O      | Unchanged
0x19     | P             | P      | Unchanged
0x1A     | [             | ^      | 
0x1B     | ]             | $      | 
0x1C     | Enter         | Enter  | Unchanged
0x1D     | Left Ctrl     | Ctrl   | Unchanged
0x1E     | A             | Q      | 
0x1F     | S             | S      | Unchanged
0x20     | D             | D      | Unchanged
0x21     | F             | F      | Unchanged
0x22     | G             | G      | Unchanged
0x23     | H             | H      | Unchanged
0x24     | J             | J      | Unchanged
0x25     | K             | K      | Unchanged
0x26     | L             | L      | Unchanged
0x27     | ;             | M      | 
0x28     | '             | ù      | CP437: 0xF9
0x29     | `             | ²      | CP437: 0xB2
0x2A     | Left Shift    | Shift  | Unchanged
0x2B     | \             | *      | 
0x2C     | Z             | W      | 
0x2D     | X             | X      | Unchanged
0x2E     | C             | C      | Unchanged
0x2F     | V             | V      | Unchanged
0x30     | B             | B      | Unchanged
0x31     | N             | N      | Unchanged
0x32     | M             | ,      | 
0x33     | ,             | ;      | 
0x34     | .             | :      | 
0x35     | /             | !      | 
0x36     | Right Shift   | Shift  | Unchanged
0x37     | Keypad *      | *      | Unchanged
0x38     | Left Alt      | Alt    | Unchanged
0x39     | Space         | Space  | Unchanged
0x3A     | Caps Lock     | Verr.  | Unchanged
```

### B. Interruptions BIOS Utilisées

```
INT 10h - Services Vidéo
  AH=00h : Set Video Mode
    AL=03h : Mode texte 80x25, 16 couleurs
  AH=0Eh : Teletype Output
    AL=caractère, BH=page, BL=attribut

INT 13h - Services Disque
  AH=08h : Get Drive Parameters
    DL=drive number
    Return: CH=cylinders, DH=heads, CL=sectors
  AH=42h : Extended Read Sectors (LBA)
    DL=drive, DS:SI=DAP (Disk Address Packet)

INT 15h - Services Système
  EAX=E820h : Query System Address Map
    EBX=continuation, ES:DI=buffer, ECX=size
    EDX=signature 'SMAP'
    Return: liste des régions mémoire

INT 16h - Services Clavier
  AH=00h : Read Keyboard
    Return: AH=scancode, AL=ASCII
```

### C. Registres CPUID

```
EAX=0 : Get Vendor ID
  Return: EBX:EDX:ECX = vendor string
  EAX = highest basic function number

EAX=1 : Get Processor Info and Feature Bits
  Return: EAX = Family, Model, Stepping
  EDX/ECX = feature flags

EAX=80000000h : Get Highest Extended Function
  Return: EAX = highest extended function

EAX=80000001h : Extended Processor Info
  Return: EDX bit 29 = Long Mode support

EAX=80000002h-80000004h : Processor Brand String
  Return: 48 bytes sur 3 appels (16 bytes chacun)
```

### D. Structure GDT (pour Stage 3)

```
Global Descriptor Table Entry (8 octets):
  Bits 0-15    : Limit Low (16 bits)
  Bits 16-31   : Base Low (16 bits)
  Bits 32-39   : Base Middle (8 bits)
  Bits 40-47   : Access Byte
    Bit 47 : Present
    Bits 45-46 : Privilege (0=kernel, 3=user)
    Bit 44 : Descriptor type (1=code/data)
    Bit 43 : Executable
    Bit 42 : Direction/Conforming
    Bit 41 : Readable/Writable
    Bit 40 : Accessed
  Bits 48-51   : Limit High (4 bits)
  Bits 52-55   : Flags
    Bit 55 : Granularity (1=4KB blocks)
    Bit 54 : Size (0=16-bit, 1=32-bit)
    Bit 53 : Long mode (1=64-bit code)
    Bit 52 : Reserved
  Bits 56-63   : Base High (8 bits)

Exemple GDT minimale :
  Entry 0: Null descriptor (obligatoire)
  Entry 1: Code 32-bit (base=0, limit=0xFFFFF, flags=0xC9A)
  Entry 2: Data 32-bit (base=0, limit=0xFFFFF, flags=0xC92)
```

---

## Conclusion

UniversalOS est conçu comme un système modulaire et évolutif. Les trois stages actuels forment une base solide pour :

1. **Diagnostiquer** n'importe quelle machine (Stage 2 actuel)
2. **Détecter** automatiquement l'architecture (Stage 0)
3. **S'adapter** aux ressources disponibles (Stage 1)

Les prochaines étapes (Stages 3+) permettront de transformer ce shell de diagnostic en un véritable système d'exploitation universel capable de virtualiser et orchestrer d'autres OS.

La correction du système AZERTY démontre l'attention portée à l'utilisabilité, même dans un environnement aussi bas niveau qu'un bootloader.

---

**Version** : 1.0  
**Date** : 2026  
**Auteur** : UniversalOS Team  
**License** : Open Source
