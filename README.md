<div align="center">

# UNIOS

**Un système d'exploitation universel, conçu depuis le secteur de boot.**

*A universal operating system, built from the boot sector up.*

[![Status](https://img.shields.io/badge/status-alpha-orange?style=for-the-badge)](#-état-actuel-du-projet)
[![Stage](https://img.shields.io/badge/stage_actuel-2_%2F_4-blueviolet?style=for-the-badge)](#-architecture-en-4-couches)
[![Arch](https://img.shields.io/badge/architecture-x86_real_mode-informational?style=for-the-badge)](#-architecture-en-4-couches)
[![Made with](https://img.shields.io/badge/assembl%C3%A9-NASM-yellow?style=for-the-badge)](#-prérequis)

[Dépôt GitHub](https://github.com/Floodfield-Sudio/UNIOS) · [Documentation technique](TECHNICAL.md) · [Guide de test QEMU](GUIDE.md) · [Boot sur clé USB réelle](USB_BOOT_GUIDE.md)

</div>

---

## Sommaire

1. [Vision](#-vision)
2. [État actuel du projet](#-état-actuel-du-projet)
3. [Architecture en 4 couches](#-architecture-en-4-couches)
4. [Documentation détaillée des stages](#-documentation-détaillée-des-stages)
5. [Organisation mémoire](#-organisation-mémoire)
6. [Protocole de communication inter-stages](#-protocole-de-communication-inter-stages)
7. [Le shell de diagnostic (Stage 2)](#-le-shell-de-diagnostic-stage-2)
8. [Système clavier & locales](#-système-clavier--locales)
9. [UNIASM, l'assembleur central](#-uniasm-lassembleur-central)
10. [Modes de fonctionnement](#-modes-de-fonctionnement)
11. [Virtualisation, émulation, traduction binaire](#-virtualisation-émulation-traduction-binaire)
12. [Cas d'usage visés](#-cas-dusage-visés)
13. [Structure du dépôt](#-structure-du-dépôt)
14. [Prérequis](#-prérequis)
15. [Compiler et lancer UNIOS](#-compiler-et-lancer-unios)
16. [Format de l'image disque](#-format-de-limage-disque)
17. [Documentation complémentaire](#-documentation-complémentaire)
18. [Feuille de route](#-feuille-de-route)
19. [Licence et crédits](#-licence-et-crédits)

---

## 🌍 Vision

**UNIOS** n'est pas un clone d'OS de plus : c'est une tentative de construire une **plateforme de boot universelle**, capable à terme :

- de démarrer sur un très grand nombre d'architectures et de machines (PC anciens et récents, Raspberry Pi, mobiles, x86 et ARM) ;
- d'**orchestrer** d'autres systèmes (Windows, Linux, Android, macOS…) plutôt que de les remplacer, en les faisant tourner comme des "fenêtres" dans son propre environnement ;
- de **partager des périphériques** (clavier, souris, audio, stockage, affichage) entre plusieurs machines physiques, comme un KVM logiciel distribué ;
- de servir d'**environnement de diagnostic et de récupération** universel, fonctionnant même quand l'OS d'origine d'une machine ne démarre plus.

Le projet est pensé en deux modes complémentaires : une **installation complète** qui prend le contrôle du boot via BIOS/UEFI, et un **mode application**, sans droits administrateur, qui relie des machines entre elles par le réseau (par exemple via un Raspberry Pi comme pont).

> *(EN)* UNIOS aims to be a universal boot platform: an OS that detects any hardware, adapts itself to it, and orchestrates other operating systems instead of replacing them — sharing input devices, storage and displays across multiple physical machines, and providing a diagnostic/recovery layer that works even when the original OS can't boot anymore.

---

## 🚦 État actuel du projet

UNIOS est en **alpha précoce**. Pour rester honnête sur ce qui existe réellement aujourd'hui par rapport à la vision long terme :

| Composant | État | Détail |
|---|---|---|
| **Stage 0** (MBR) | ✅ Fonctionnel | Détection CPUID, sauvegarde du disque de boot, chargement du Stage 1 |
| **Stage 1** (Bootloader) | ✅ Fonctionnel | Détection RAM (E820), menu multi-sources (Disque / USB émulé / PXE simulé), chargement du Stage 2 |
| **Stage 2** (Shell léger) | ✅ Fonctionnel | Shell interactif complet : édition de ligne, historique, 12 locales/claviers, diagnostic CPU/RAM/disque |
| **Stage 3** (OS complet) | 🔜 Roadmap | Mode protégé/long mode, GDT, paging — pas encore implémenté |
| **Stage 4** (Hyperviseur multi-machines) | 🔜 Roadmap | VT-x/AMD-V, partage de périphériques, virtualisation/émulation — vision long terme |
| **UNIASM** (assembleur multi-arch) | 🧪 Prototype séparé | Format source et packer expérimental ; le build actuel des stages utilise NASM directement |
| **Portage ARM / Android / iOS** | 🔜 Roadmap | Non démarré |

Concrètement, ce qui tourne aujourd'hui dans QEMU (ou sur une vraie machine x86) est un **bootloader 3 étages en mode réel 16 bits**, avec un véritable shell de diagnostic bas niveau — la fondation sur laquelle Stage 3 et Stage 4 viendront se greffer.

---

## 🏗 Architecture en 4 couches

UNIOS démarre progressivement, chaque étage ne chargeant que le strict nécessaire pour passer la main au suivant :

```
┌─────────────────────────────────────────────────────────────┐
│  STAGE 3 — OS complet                              (roadmap) │
│  Interface, virtualisation/émulation, multi-machines          │
└───────────────────────────▲───────────────────────────────────┘
┌───────────────────────────┴───────────────────────────────────┐
│  STAGE 2 — Shell léger / diagnostic            (0x9000, ✅)   │
│  Commandes système, récupération, installation du Stage 3     │
└───────────────────────────▲───────────────────────────────────┘
┌───────────────────────────┴───────────────────────────────────┐
│  STAGE 1 — Bootloader adapté                   (0x7E00, ✅)   │
│  Détection RAM (E820), menu multi-sources, charge le Stage 2   │
└───────────────────────────▲───────────────────────────────────┘
┌───────────────────────────┴───────────────────────────────────┐
│  STAGE 0 — Pré-bootloader universel         (MBR 0x7C00, ✅)  │
│  Détection CPU (CPUID), charge le Stage 1                     │
└─────────────────────────────────────────────────────────────┘
                              ▲
                           BIOS / UEFI
```

### Modes de fonctionnement (rappel rapide)

**Mode 1 — Installation complète** : accès BIOS/UEFI natif, les 4 stages installés, contrôle total du boot.
**Mode 2 — Application sans privilèges** : périphériques/stockage/affichage reliés entre machines par le réseau, sans toucher au boot principal.
(Détails complets dans la [section dédiée](#-modes-de-fonctionnement) plus bas.)

---

## 📖 Documentation détaillée des stages

### Stage 0 — Pré-bootloader (`stage0.asm`, v0.3)

**Taille** : exactement 512 octets · **Chargé à** : `0x7C00` par le BIOS · **Rôle** : premier code exécuté, détection d'architecture, chargement du Stage 1.

Responsabilités :
1. **Initialisation** — désactive les interruptions, met DS/ES/SS à 0, place SP à `0x7C00`, force le mode vidéo texte 80×25 (`INT 10h, AL=03h`).
2. **Sauvegarde immédiate** du numéro de disque de boot (registre `DL` fourni par le BIOS) dans `INFO_BLOCK+0x0D`.
3. **Détection CPUID** — teste la disponibilité de CPUID via le bit 21 d'EFLAGS, récupère la chaîne vendor (`EBX:EDX:ECX`), puis teste le support du Long Mode via `CPUID 0x80000001` (bit 29 d'EDX).
4. **Chargement du Stage 1** — 8 secteurs (LBA 1-8) vers `0x7E00`, via `INT 13h, AH=42h` (lecture LBA étendue, DAP).
5. **Saut** vers `0x0000:0x7E00`.

```assembly
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
    jz   .ancient             ; bit 21 ne change pas → pas de CPUID

    mov  eax, 0
    cpuid
    mov  [INFO_BLOCK + 0], ebx    ; "Genu"
    mov  [INFO_BLOCK + 4], edx    ; "ineI"
    mov  [INFO_BLOCK + 8], ecx    ; "ntel"

    mov  eax, 0x80000001
    cpuid
    test edx, (1 << 29)
    jz   .no_lm
    mov  byte [INFO_BLOCK + 0x0C], 1    ; 64-bit supporté
```

### Stage 1 — Bootloader adapté à choix multi-sources (`stage1.asm`, v0.3)

**Taille max** : 4 096 octets (8 secteurs) · **Chargé à** : `0x7E00` par Stage 0 · **Rôle** : détection RAM, configuration locale par défaut, menu de chargement, chargement du Stage 2.

Responsabilités :
1. **Configuration par défaut** — locale `fr-fr` et clavier AZERTY (`INFO_BLOCK+0x10`/`0x11`), avant que l'utilisateur ne change quoi que ce soit.
2. **Détection RAM (E820)** — boucle sur `INT 15h, EAX=0xE820` jusqu'à épuisement de la liste, stocke chaque entrée de 24 octets à partir de `0x2000`, compte les entrées à `0x1FFE`.
3. **Menu interactif multi-sources** :
   ```
   [1] Demarrer depuis le Disque local (LBA)
   [2] Demarrer depuis la Cle USB (Emulee)
   [3] Telecharger via Reseau (PXE/TFTP Virtualise)
   ```
   Le choix `[2]` force le BIOS drive `0x81` (lecteur USB émulé) ; le choix `[3]` simule un protocole de récupération PXE/TFTP à l'écran — préfigurant les futures sources réseau réelles.
4. **Chargement du Stage 2** — 56 secteurs (LBA 9-64) vers `0x9000`.
5. **Saut** vers `0x0000:0x9000`.

```assembly
detect_ram:
    xor  ebx, ebx
    mov  di, E820_MAP            ; 0x2000
    xor  cx, cx

.loop:
    mov  eax, 0xE820
    mov  edx, 0x534D4150          ; "SMAP"
    mov  ecx, 24
    int  0x15
    jc   .done                    ; Carry = fin de liste
    add  di, 24
    inc  cx
    test ebx, ebx
    jz   .done
    jmp  .loop

.done:
    mov  [E820_MAP - 2], cx       ; nombre d'entrées à 0x1FFE
```

### Stage 2 — Shell de diagnostic (`stage2.asm`, v0.6)

**Taille max** : 28 672 octets (56 secteurs) · **Chargé à** : `0x9000` par Stage 1 · **Rôle** : shell interactif complet.

C'est l'étage le plus riche aujourd'hui :
- boucle de lecture/parsing/exécution avec **édition de ligne complète** (curseur gauche/droite, retour arrière) ;
- **historique de commandes** sur 10 entrées, navigable aux flèches haut/bas (`HIST_BUF` à `0x6300`) ;
- **12 préréglages clavier** et **12 locales d'affichage** (voir [section dédiée](#-système-clavier--locales)) ;
- 11 commandes : `help`, `cpu`, `mem`, `arch`, `disk`, `kbd`, `lg`, `install`, `clear`, `reboot`, `exit`.

Exemple — commande `cpu` (lit l'INFO_BLOCK rempli par Stage 0, puis complète via CPUID) :

```assembly
cmd_cpu_fn:
    mov  si, INFO_BLOCK          ; vendor déjà rempli par Stage 0
    call s2_puts

    mov  al, [INFO_BLOCK + 0x0C] ; mode 64/32-bit
    cmp  al, 1
    je   .mode_64
    ...
    mov  eax, 1
    cpuid                        ; family/model/stepping
    shr  eax, 8
    and  eax, 0x0F
    ...
    mov  eax, 0x80000002         ; brand string, 3 appels CPUID
    cpuid
    mov  [edi + 0], eax
    mov  [edi + 4], ebx
    mov  [edi + 8], ecx
    mov  [edi +12], edx
```

Sortie typique :

```
UNIOS> cpu
  CPU Vendor  : GenuineIntel
  CPU Mode    : 64-bit (Long Mode)
  Family      : 6
  Model       : 142
  Stepping    : 10
  Brand       : Intel(R) Core(TM) i7-8550U CPU @ 1.80GHz
```

La commande `mem` parcourt la carte E820 stockée par Stage 1 et affiche chaque région :

```
UNIOS> mem

E820 Memory Map:
Base       Length     Type
---------- ---------- ----------------
00000000   0009FC00   Usable RAM
0009FC00   00000400   Reserved
00100000   07EE0000   Usable RAM
```

La commande `disk` interroge la géométrie BIOS du disque de boot (`INT 13h, AH=08h`) :

```
UNIOS> disk

Disk Geometry (BIOS INT 13h AH=08h):
  Cylinders   : 130
  Heads       : 16
  Sectors/Trk : 63
```

---

## 🧠 Organisation mémoire

Layout réel-mode complet (`0x00000` – `0xFFFFF`) :

```
┌─────────────────────────────────────────────────────────────────┐
│ 0x00000 - 0x003FF : Table des vecteurs d'interruption (IVT)      │
│ 0x00400 - 0x004FF : BIOS Data Area (BDA)                         │
│ 0x00500 - 0x0050F : INFO_BLOCK — partagé Stage 0/1/2             │
│ 0x00510 - 0x01FFF : Espace libre                                 │
│ 0x01FFE - 0x01FFF : Compteur d'entrées E820 (2 octets)           │
│ 0x02000 - 0x04FFF : Carte mémoire E820 (entrées de 24 octets)    │
│ 0x05000 - 0x05FFF : Buffer temporaire (CPU brand string, etc.)   │
│ 0x06000 - 0x062C8 : INPUT_BUF — ligne de commande (200 car. max) │
│ 0x06300 - 0x06xxx : HIST_BUF — historique (10 × 80 octets)       │
│ 0x07C00 - 0x07DFF : STAGE 0 (MBR, 512 octets, chargé par le BIOS)│
│ 0x07E00 - 0x08DFF : STAGE 1 (max 4 096 octets, 8 secteurs)       │
│ 0x09000 - 0x0FFFF : STAGE 2 (max 28 672 octets, 56 secteurs)     │
│ 0x10000 - 0x9FFFF : Libre pour Stage 3+ (~576 Ko disponibles)    │
│ 0xA0000 - 0xBFFFF : Video RAM (VGA)                              │
│ 0xC0000 - 0xFFFFF : BIOS ROM, Option ROMs                        │
└─────────────────────────────────────────────────────────────────┘
```

**Pourquoi ces adresses ?**
- `0x7C00` : adresse standard où le BIOS charge les 512 premiers octets du disque (le MBR).
- `0x7E00` : juste après Stage 0, emplacement logique pour Stage 1.
- `0x9000` : assez haut pour ne pas mordre sur la zone BIOS/IVT, assez bas pour rester en mémoire conventionnelle.
- `0x0500` : zone libre standard juste après la BDA, idéale pour partager des données entre étages.

---

## 🔗 Protocole de communication inter-stages

`INFO_BLOCK` (`0x0500`) est le **pont** entre les trois étages : chacun y lit et y écrit des informations pour les suivants.

| Offset | Taille | Rempli par | Lu par | Contenu |
|---|---|---|---|---|
| `+0x00` | 12 o | Stage 0 | Stage 1, 2 | Vendor CPU ("GenuineIntel", "AuthenticAMD", "Unknown") |
| `+0x0C` | 1 o | Stage 0 | Stage 1, 2 | Mode CPU (`0x01`=64-bit, `0x00`=32-bit, `0xFF`=ancien) |
| `+0x0D` | 1 o | Stage 0 | Stage 1, 2 | Numéro de disque de boot (`0x80` = 1er disque dur) |
| `+0x0E` | 2 o | Stage 1 | Stage 2 | RAM totale en Mo (word, little-endian) |
| `+0x10` | 1 o | Stage 1 / 2 | Stage 2 | Locale active (index dans `lang_display_table`) |
| `+0x11` | 1 o | Stage 1 / 2 | Stage 2 | Préréglage clavier actif (index dans `kbd_display_table`) |

Flux complet au démarrage :

```
STAGE 0 (0x7C00)
  ├─ Détecte CPU vendor / mode 64-32 bit → INFO_BLOCK
  ├─ Stocke le disque de boot → INFO_BLOCK+0x0D
  ├─ Charge Stage 1 (LBA 1-8) → 0x7E00
  └─ jmp 0x7E00
       STAGE 1 (0x7E00)
         ├─ Configure locale/clavier par défaut → INFO_BLOCK+0x10/0x11
         ├─ Détecte la RAM E820 → 0x2000, calcule le total → INFO_BLOCK+0x0E
         ├─ Affiche le menu multi-sources, charge Stage 2 (LBA 9-64) → 0x9000
         └─ jmp 0x9000
              STAGE 2 (0x9000)
                ├─ Lit tout l'INFO_BLOCK (vendor, mode, disque, RAM, locale, clavier)
                ├─ Lit la carte E820 ← 0x2000
                └─ Affiche le shell interactif `UNIOS>`
```

---

## 💻 Le shell de diagnostic (Stage 2)

Une fois les trois stages chargés, vous arrivez sur l'invite `UNIOS>` :

```
UNIOS> help

Commands:
  help          Show this help
  cpu           CPU info (vendor, mode, family, brand)
  mem           Memory map (E820 table)
  arch          Platform summary (CPU + RAM + drive)
  disk          Disk geometry (BIOS INT 13h)
  kbd           Cycle keyboard presets (QWERTY, AZERTY, QWERTZ, ...)
  lg <locale>   Set locale: en-us fr-fr de-de es-es it-it pt-br ru-ru
  install       Stage 3 installation guide
  clear         Clear screen
  reboot        Restart machine
  exit          Power off machine
```

| Commande | Détail |
|---|---|
| `help` | Liste toutes les commandes disponibles |
| `cpu` | Vendor, mode 64/32-bit, family/model/stepping, chaîne de marque complète (3 appels CPUID) |
| `mem` | Carte mémoire E820 complète, base/longueur/type de chaque région |
| `arch` | Résumé plateforme : vendor CPU, mode, RAM totale, disque de boot |
| `disk` | Géométrie disque (cylindres/têtes/secteurs) via `INT 13h, AH=08h` |
| `kbd` | Fait défiler les 12 préréglages clavier disponibles |
| `lg <locale>` | Affiche ou change la locale active parmi 12 (voir ci-dessous) ; sans argument, affiche la configuration courante |
| `install` | Affiche le guide d'installation du Stage 3 |
| `clear` | Efface l'écran (`INT 10h, AL=03h`) |
| `reboot` | Redémarre la machine |
| `exit` | Éteint la machine |

**Édition de ligne et historique** : le buffer d'entrée (`INPUT_BUF`, 200 caractères) gère le retour arrière et les flèches gauche/droite pour repositionner le curseur en cours de frappe ; les flèches haut/bas parcourent les 10 dernières commandes saisies (`HIST_BUF`).

---

## ⌨️ Système clavier & locales

Le shell gère **12 claviers** et **12 locales d'affichage**, chacun avec son propre tableau de remappage de caractères (`kbd_map_table`) appliqué en temps réel sur les scancodes BIOS :

| Code locale | Langue affichée | Clavier associé |
|---|---|---|
| `en-us` | English | US QWERTY |
| `fr-fr` | French | French AZERTY |
| `de-de` | German | German QWERTZ |
| `es-es` | Spanish | Spanish (repli latin) |
| `it-it` | Italian | Italian (repli latin) |
| `pt-br` | Portuguese | Brazilian ABNT2 (repli latin) |
| `ru-ru` | Russian | Russian (repli latin) |
| `ar-sa` | Arabic | Arabic (repli latin) |
| `zh-cn` | Chinese Simplified | Pinyin (repli) |
| `zh-tw` | Chinese Traditional | Zhuyin (repli) |
| `ja-jp` | Japanese | Romaji (repli) |
| `ko-kr` | Korean | Romanisé (repli) |

Les claviers QWERTY/AZERTY/QWERTZ disposent d'un remappage natif complet des scancodes (y compris les caractères accentués en encodage **CP437**, ex. `é`=0xE9, `è`=0xE8, `ç`=0xE7, `à`=0xE0, `ù`=0xF9). Les scripts non latins restent affichés en transcription romanisée, le mode texte VGA/BIOS ne pouvant pas rendre nativement ces alphabets.

```
UNIOS> kbd
Keyboard: French AZERTY

UNIOS> lg en-us
Language: English (en-us) | Keyboard: US QWERTY

UNIOS> lg
Current locale: English (en-us) | Keyboard: US QWERTY
Usage: lg <locale> (en-us fr-fr de-de es-es it-it pt-br ru-ru)
```

---

## 🛠 UNIASM, l'assembleur central

**UNIASM** est l'outil d'assemblage maison du projet : pas un simple wrapper, mais un format source et un *packer* pensés pour décrire **un seul projet de boot multi-architecture** puis générer les binaires x86 et ARM nécessaires à chaque Stage, sans dépendre d'un assembleur externe pour la sortie finale.

À ce stade, UNIASM existe comme **prototype indépendant** (langage `.uniasm`, conteneur binaire `.uni` avec en-tête, table d'architectures et blocs `stage0`/`stage1` natifs par plateforme). Le build des stages x86 actuels passe encore par **NASM** ([`build.bat`](build.bat) / `nasm -f bin`) — l'intégration de UNIASM comme chaîne de build officielle fait partie de la feuille de route.

Objectifs visés pour UNIASM :
- décrire un seul projet source pour x86 **et** ARM ;
- générer chaque binaire via son propre backend, sans assembleur tiers ;
- construire les images de boot et conteneurs multi-architecture finaux.

---

## 🔌 Modes de fonctionnement

**Mode 1 — Installation complète**
Accès BIOS/UEFI natif, les 4 stages sont installés, UNIOS prend le contrôle total du boot. L'OS d'origine de la machine devient une fenêtre isolée dans l'environnement UNIOS.

**Mode 2 — Application sans privilèges**
Pour les machines où l'on ne peut pas (ou ne veut pas) toucher au boot principal. UNIOS relie les périphériques, le stockage et l'affichage entre machines via le réseau — potentiellement à travers un Raspberry Pi servant de pont.

---

## ⚙️ Virtualisation, émulation, traduction binaire

Trois approches complémentaires sont prévues selon le contexte matériel rencontré :

| Technique | Quand l'utiliser | Compromis |
|---|---|---|
| **Virtualisation** | Machines de même architecture CPU | Rapide, proche du natif |
| **Émulation** | Architectures différentes | Flexible, plus lent |
| **Traduction binaire** | Compromis entre les deux | Exécute des blocs d'une architecture sur une autre, avec adaptation |

---

## 💡 Cas d'usage visés

- Récupérer des fichiers sur une vieille machine qui ne démarre plus.
- Lancer rapidement une instance Android, macOS ou Linux pour tester une application, puis revenir au système principal sans redémarrage complet.
- Piloter plusieurs PC, chacun avec ses spécificités, depuis un seul poste de travail.
- Combiner la puissance de calcul d'une machine avec le stockage ou les périphériques d'une autre.
- Streamer ou exécuter un jeu sur une machine en exploitant les ressources d'une autre.

---

## 📁 Structure du dépôt

```
UNIOS/
├── stage0.asm              # Stage 0 — MBR, 512 octets (CPUID + chargement Stage 1)
├── stage1.asm               # Stage 1 — E820 + menu multi-sources + chargement Stage 2
├── stage2.asm               # Stage 2 — shell de diagnostic interactif
├── create_image.py          # Assemble les .bin en une image disque RAW
├── build.bat                 # Build Windows (détection auto NASM + Python)
├── run_x86_32.bat            # Lance l'image dans QEMU (32-bit)
├── run_x86_64.bat            # Lance l'image dans QEMU (64-bit)
├── build/                    # Sortie de build (générée, non versionnée)
│   ├── stage0.bin / stage1.bin / stage2.bin
│   ├── *.lst                 # Listings d'assemblage
│   └── unios.img             # Image disque finale
├── README.md                 # Ce document
├── TECHNICAL.md               # Référence technique bas niveau (CPUID, BIOS, GDT…)
├── GUIDE.md                   # Guide de test dans QEMU
└── USB_BOOT_GUIDE.md          # Guide de démarrage sur clé USB / matériel réel
```

---

## 📋 Prérequis

- **[NASM](https://www.nasm.us/)** — l'assembleur x86 utilisé pour produire les `.bin` de chaque stage.
- **Python 3** — pour générer l'image disque (`create_image.py`).
- **[QEMU](https://www.qemu.org/)** — recommandé pour tester sans risquer de matériel réel.

`build.bat` détecte automatiquement NASM et Python sur Windows (PATH, emplacements standards, launcher `py`) ; si la détection échoue, éditez les variables `NASM_EXE` / `PYTHON_EXE` en tête du script.

---

## 🚀 Compiler et lancer UNIOS

### Windows

```bat
build.bat
run_x86_64.bat   REM ou run_x86_32.bat selon votre QEMU
```

`build.bat` enchaîne automatiquement : détection NASM → détection Python → assemblage des 3 stages (`nasm -f bin ... -l ...`) → génération de l'image (`create_image.py`).

### Linux / macOS

```bash
mkdir -p build
nasm -f bin stage0.asm -o build/stage0.bin -l build/stage0.lst
nasm -f bin stage1.asm -o build/stage1.bin -l build/stage1.lst
nasm -f bin stage2.asm -o build/stage2.bin -l build/stage2.lst
python3 create_image.py

qemu-system-x86_64 -drive format=raw,file=build/unios.img
```

Pour démarrer sur du matériel réel plutôt que dans QEMU, suivez [`USB_BOOT_GUIDE.md`](USB_BOOT_GUIDE.md).

---

## 💾 Format de l'image disque

`create_image.py` assemble les trois `.bin` en une image RAW de **128 Ko** (256 secteurs de 512 octets) :

```
Offset (hex) | Secteur | Taille       | Contenu
-------------|---------|--------------|----------------------------------
0x00000000   | 0       | 512 octets   | Stage 0 (MBR)
0x000001FE   |         |              | Signature 0x55AA (octets 510-511)
0x00000200   | 1       | 4 096 octets | Stage 1 (max 8 secteurs)
0x00001200   | 9       | 28 672 octets| Stage 2 (max 56 secteurs)
0x00008200   | 65      | ~96 Ko       | Réservé pour Stage 3+ / config future
0x00020000   | 256     |              | Fin de l'image (128 Ko total)
```

Le script vérifie que Stage 0 fait exactement 512 octets et porte la signature `0x55AA` aux octets 510-511 ; il refuse de construire l'image si Stage 1 ou Stage 2 dépassent leur quota de secteurs réservé. **Stage 3 n'est volontairement pas inclus** dans cette image — il sera installé séparément via la commande `install` du shell (clé USB ou réseau), une fois disponible.

Vérification rapide de l'image générée :

```bash
# MBR (512 premiers octets)
xxd -l 512 build/unios.img

# Signature de boot (doit afficher 55 aa)
xxd -s 510 -l 2 build/unios.img

# Extraire chaque stage individuellement
dd if=build/unios.img of=s0.bin bs=512 count=1
dd if=build/unios.img of=s1.bin bs=512 skip=1  count=8
dd if=build/unios.img of=s2.bin bs=512 skip=9  count=56
```

---

## 📚 Documentation complémentaire

| Document | Contenu |
|---|---|
| [`TECHNICAL.md`](TECHNICAL.md) | Référence bas niveau complète : registres CPUID, interruptions BIOS, structure GDT |
| [`GUIDE.md`](GUIDE.md) | Guide pas-à-pas pour tester UNIOS dans QEMU |
| [`USB_BOOT_GUIDE.md`](USB_BOOT_GUIDE.md) | Préparer une clé USB bootable et démarrer sur du matériel réel |

---

## 🗺 Feuille de route

- **Stage 3a — Mode protégé 32 bits** : GDT, activation du bit PE, paging.
- **Stage 3b — Mode long 64 bits** : PAE, page tables (PML4/PDPT/PD/PT), activation via EFER MSR.
- **Stage 4 — Hyperviseur multi-machines** : VT-x/AMD-V, EPT/NPT, ACPI, énumération PCI, partage de périphériques entre machines, interface graphique, support UEFI (GOP/GPT).
- **UNIASM** : sortir du statut de prototype, intégrer un backend ARM, devenir la chaîne de build officielle x86 + ARM.
- **Portages multi-architecture** : ARM/Raspberry Pi (U-Boot, Device Tree), Android (fastboot/ADB), iOS (mode application restreint, sans jailbreak requis comme cible long terme).

---

## 📄 Licence et crédits

UNIOS est un projet open source développé par **Floodfield Studios**. Consultez le fichier `LICENSE` du dépôt pour les modalités exactes d'utilisation et de redistribution.

Contributions, retours et idées sont bienvenus via les [Issues](https://github.com/Floodfield-Sudio/UNIOS/issues) du dépôt.

<div align="center">

*Fait avec NASM, Python, et beaucoup de mode réel 16 bits.*

[⬆ Retour en haut](#unios)

</div>
