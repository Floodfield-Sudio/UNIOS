# UniversalOS — Guide de Test QEMU (Stage 0 → Stage 2)

## Structure du projet

```
universalos/
├── stage0/stage0.asm     MBR 512 octets (CPUID + chargement Stage 1)
├── stage1/stage1.asm     Détection RAM E820 + chargement Stage 2
├── stage2/stage2.asm     Shell interactif (commandes : help/cpu/mem/arch/disk/clear/reboot)
├── build/universalos.img Image disque RAW 1 Mo (prête à lancer)
├── create_image.py       Assemble les 3 binaires en image RAW
├── build.bat             Build Windows (NASM + Python)
├── build.sh              Build Linux/macOS
├── run_x86_64.bat        Lance QEMU 64-bit
└── run_x86_32.bat        Lance QEMU 32-bit (i386)
```

## Layout disque (secteurs de 512 octets)

| Secteur(s) | Contenu       | Taille max |
|-----------|---------------|------------|
| 0         | Stage 0 (MBR) | 512 o      |
| 1–8       | Stage 1       | 4096 o     |
| 9–64      | Stage 2       | 28672 o    |

---

## Test 1 : x86_64 (PC moderne, 64-bit)

### Windows (MSYS64)
```bat
C:\msys64\ucrt64\bin\qemu-system-x86_64.exe ^
  -drive format=raw,file=build\universalos.img ^
  -m 128M ^
  -name "UniversalOS x86_64"
```

### Linux / macOS
```bash
qemu-system-x86_64 \
  -drive format=raw,file=build/universalos.img \
  -m 128M
```

**Ce que vous devez voir :**
```
[S0] UniversalOS v0.1
CPU: GenuineIntel   ← ou AuthenticAMD
[64bit]
S1...OK
[S1] UniversalOS - Stage 1
RAM: 128 MB
Stage 1 OK - Chargement Stage 2...

=== UniversalOS Stage 2 - Shell de diagnostic ===
Tapez 'help' pour la liste des commandes.
UOS>
```

---

## Test 2 : i386 (PC 32-bit)

### Windows
```bat
C:\msys64\ucrt64\bin\qemu-system-x86_64.exe ^
  -drive format=raw,file=build\universalos.img ^
  -m 64M ^
  -cpu 486 ^
  -name "UniversalOS i386"
```

### Linux / macOS
```bash
qemu-system-i386 \
  -drive format=raw,file=build/universalos.img \
  -m 64M
```

**Différence attendue :** `[32bit]` au lieu de `[64bit]` — Stage 2 fonctionne identiquement.

---

## Test 3 : Très ancien CPU (pré-CPUID)

```bat
C:\msys64\ucrt64\bin\qemu-system-x86_64.exe ^
  -drive format=raw,file=build\universalos.img ^
  -cpu 486 ^
  -m 32M ^
  -name "UniversalOS 486"
```

**Différence attendue :** `[OLD]` — vendor = "Unknown" dans `cpu`.

---

## Commandes du Shell Stage 2

Une fois au prompt `UOS>`, tapez :

| Commande | Description |
|----------|-------------|
| `help`   | Liste toutes les commandes |
| `cpu`    | Vendor, mode 64/32bit, Family/Model/Stepping, Brand String |
| `mem`    | Table mémoire E820 complète (zones RAM/ROM/ACPI) |
| `arch`   | Résumé plateforme (CPU + RAM totale + boot drive) |
| `disk`   | Géométrie du disque (cylindres/têtes/secteurs via BIOS) |
| `kbd`    | Bascule entre clavier QWERTY/AZERTY (Français) |
| `clear`  | Efface l'écran |
| `reboot` | Redémarre la machine |

**Note:** Le shell est en anglais. Les messages système apparaissent en anglais, mais vous pouvez changer le clavier en AZERTY avec `kbd`.

---

## Rebuild depuis les sources

### Windows (MSYS64 ou cmd)
```bat
build.bat
```
Nécessite : `nasm` et `python3` dans le PATH.

### Linux / macOS
```bash
chmod +x build.sh && ./build.sh
```

### Manuellement
```bash
nasm -f bin stage0/stage0.asm -o build/stage0.bin
nasm -f bin stage1/stage1.asm -o build/stage1.bin
nasm -f bin stage2/stage2.asm -o build/stage2.bin
python3 create_image.py
```

---

## Dépannage

| Symptôme | Cause probable | Solution |
|----------|---------------|----------|
| Écran noir | BIOS ne trouve pas le boot | Vérifier signature `55AA` en offset 510 |
| `ERR` au chargement S1 | INT 13h échoue | Utiliser `-drive format=raw` (pas `file=`) |
| Bloqué à `S1...` | Stage 1 non assemblé | Rebuild depuis les sources |
| `UOS>` n'apparaît pas | Stage 2 corrompu | Vérifier taille image (doit être 1 Mo) |
| `mem` affiche 0 zones | BIOS QEMU sans E820 | Essayer avec `-m 256M` |

---

## Architecture mémoire (real-mode)

```
0x0000–0x03FF   IVT (vecteurs d'interruptions BIOS)
0x0400–0x04FF   BDA (BIOS Data Area)
0x0500          Info Block partagé Stage 0/1/2
                  +00 [12B] Vendor CPU ("GenuineIntel" etc.)
                  +0C [1B]  Flag: 0x01=64bit, 0x00=32bit, 0xFF=ancien
                  +0D [1B]  Numéro lecteur boot (0x80 = premier disque dur)
0x2000          Carte mémoire E820 brute
0x6000          Buffer clavier Stage 2
0x7C00          Stage 0 (MBR, exécuté en premier)
0x7E00          Stage 1 (chargé par Stage 0)
0x9000          Stage 2 (shell, chargé par Stage 1)
```

---

## Roadmap Stage 3+

- [ ] Passage en mode protégé 32-bit (Stage 3a)
- [ ] Passage en mode long 64-bit (Stage 3b)
- [ ] Chargement d'un noyau ELF
- [ ] Hyperviseur minimal (VMX/SVM)
- [ ] KVM logiciel multi-machines
- [ ] Support UEFI (GOP, GPT)
- [ ] Port ARM / Raspberry Pi (U-Boot → Stage 1)
