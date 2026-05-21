#!/usr/bin/env python3
"""
UNIOS — Créateur d'image disque                                  v0.2
======================================================================
Assemble stage0.bin, stage1.bin et stage2.bin dans une image RAW.

Layout (secteurs de 512 octets) :
  Secteur 0          → Stage 0  (MBR, 512 octets exactement)
  Secteurs 1 – 8     → Stage 1  (4 096 octets max)
  Secteurs 9 – 64    → Stage 2  (28 672 octets max)

Taille image : 128 Ko (256 secteurs).
Stage 3 n'est PAS inclus ici — il sera installé séparément
depuis une clé USB ou via le réseau (commande 'install' du shell).
"""

import os, sys

SECTOR    = 512
DISK_SIZE = 128 * 1024   # 128 Ko  (au lieu de 1 Mo auparavant)
                          # Stage 3 sera installé plus tard via USB/réseau

STAGE0_LBA      = 0
STAGE1_LBA      = 1
STAGE1_MAX_SECT = 8
STAGE2_LBA      = 9
STAGE2_MAX_SECT = 56      # secteurs 9–64 → jusqu'à 28 672 octets


def read_bin(path):
    with open(path, "rb") as f:
        return f.read()


def create_image(out, s0_path, s1_path, s2_path):
    disk = bytearray(DISK_SIZE)

    # ── Stage 0 ──────────────────────────────────────────────────────────────
    s0 = read_bin(s0_path)
    if len(s0) != SECTOR:
        sys.exit(f"[ERREUR] Stage 0 doit faire exactement {SECTOR} octets, "
                 f"obtenu : {len(s0)}")
    if s0[-2:] != b"\x55\xAA":
        sys.exit("[ERREUR] Stage 0 : signature 0x55AA manquante au secteur 0")
    disk[0:SECTOR] = s0
    print(f"  Stage 0 : {len(s0)} o  →  secteur {STAGE0_LBA}")

    # ── Stage 1 ──────────────────────────────────────────────────────────────
    s1 = read_bin(s1_path)
    s1_sects = (len(s1) + SECTOR - 1) // SECTOR
    if s1_sects > STAGE1_MAX_SECT:
        sys.exit(f"[ERREUR] Stage 1 trop grand : {len(s1)} o "
                 f"(max {STAGE1_MAX_SECT * SECTOR} o = {STAGE1_MAX_SECT} sect.)")
    off1 = STAGE1_LBA * SECTOR
    disk[off1 : off1 + len(s1)] = s1
    print(f"  Stage 1 : {len(s1)} o ({s1_sects} sect.)  →  "
          f"secteurs {STAGE1_LBA}–{STAGE1_LBA + s1_sects - 1}")

    # ── Stage 2 ──────────────────────────────────────────────────────────────
    s2 = read_bin(s2_path)
    s2_sects = (len(s2) + SECTOR - 1) // SECTOR
    if s2_sects > STAGE2_MAX_SECT:
        sys.exit(f"[ERREUR] Stage 2 trop grand : {len(s2)} o "
                 f"(max {STAGE2_MAX_SECT * SECTOR} o = {STAGE2_MAX_SECT} sect.)")
    off2 = STAGE2_LBA * SECTOR
    disk[off2 : off2 + len(s2)] = s2
    print(f"  Stage 2 : {len(s2)} o ({s2_sects} sect.)  →  "
          f"secteurs {STAGE2_LBA}–{STAGE2_LBA + s2_sects - 1}")

    # ── Résumé ────────────────────────────────────────────────────────────────
    used_sects = STAGE2_LBA + s2_sects
    used_bytes = used_sects * SECTOR
    free_bytes = DISK_SIZE - used_bytes

    with open(out, "wb") as f:
        f.write(disk)

    kb = DISK_SIZE // 1024
    print(f"\n  Image créée  : {out}  ({kb} Ko)")
    print(f"  Utilisé      : {used_bytes} o  ({used_sects} sect.)")
    print(f"  Libre        : {free_bytes} o  (réservé pour config future)")
    print(f"\n  Note : Stage 3 n'est pas dans cette image.")
    print(f"         Lancez 'install' depuis le shell UNIOS pour l'obtenir.")


if __name__ == "__main__":
    here  = os.path.dirname(os.path.abspath(__file__))
    build = os.path.join(here, "build")
    os.makedirs(build, exist_ok=True)

    create_image(
        os.path.join(build, "unios.img"),
        os.path.join(build, "stage0.bin"),
        os.path.join(build, "stage1.bin"),
        os.path.join(build, "stage2.bin"),
    )