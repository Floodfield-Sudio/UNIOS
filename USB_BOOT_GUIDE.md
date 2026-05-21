# UniversalOS — Guide Clé USB Bootable (Vrai PC)

## ⚠️ ATTENTION

**Ce guide permet de créer une clé USB bootable pour tester UniversalOS sur un vrai PC.**

**AVERTISSEMENT :** L'écriture de l'image `universalos.img` sur une clé USB **EFFACERA TOUTES LES DONNÉES** présentes sur celle-ci. Assurez-vous d'avoir sauvegardé vos fichiers importants avant de continuer.

---

## Prérequis

- Une clé USB (minimum 2 Mo, recommandé 1 Go pour tests futurs)
- L'image disque `universalos.img` (1 Mo)
- Un PC avec BIOS Legacy (pas uniquement UEFI)
- Droits administrateur (Windows) ou `sudo` (Linux/macOS)

---

## Méthode 1 : Windows (Rufus - Recommandé)

### Étape 1 : Télécharger Rufus

1. Visitez https://rufus.ie/
2. Téléchargez la dernière version portable (pas d'installation requise)

### Étape 2 : Préparer la clé USB

1. **Insérez votre clé USB**
2. **Sauvegardez vos données** si nécessaire
3. Lancez `rufus.exe`

### Étape 3 : Configuration Rufus

```
┌─────────────────────────────────────────┐
│ Périphérique         : [Votre clé USB] │
│ Méthode de boot      : Disque/Image ISO│
│ [SÉLECTIONNER] → universalos.img        │
│ Schéma de partition  : MBR              │
│ Système cible        : BIOS (ou UEFI-CSM)│
│ Système de fichiers  : (ignoré)         │
└─────────────────────────────────────────┘
```

4. Cliquez sur `DÉMARRER`
5. Rufus détectera que c'est une image DD (raw)
6. Sélectionnez **"Écrire en mode Image DD"**
7. Confirmez l'effacement des données
8. Attendez la fin (quelques secondes)

### Étape 4 : Éjecter la clé

1. Une fois terminé, cliquez sur `FERMER`
2. Éjectez proprement la clé USB (icône "Retirer le périphérique en toute sécurité")

---

## Méthode 2 : Linux (dd)

### Étape 1 : Identifier la clé USB

```bash
# Lister les périphériques
lsblk

# Exemple de sortie :
# NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
# sda      8:0    0 465,8G  0 disk 
# └─sda1   8:1    0 465,8G  0 part /
# sdb      8:16   1   7,5G  0 disk          ← Votre clé USB
# └─sdb1   8:17   1   7,5G  0 part /media/user/USB
```

⚠️ **IMPORTANT :** Notez bien le nom du périphérique (`/dev/sdb` dans l'exemple). **NE PAS confondre avec votre disque dur principal !**

### Étape 2 : Démonter la clé (si montée)

```bash
sudo umount /dev/sdb1    # Remplacez sdb1 par votre partition
```

### Étape 3 : Écrire l'image

```bash
sudo dd if=universalos.img of=/dev/sdb bs=4M status=progress
sudo sync
```

**Explication :**
- `if=` : fichier d'entrée (input file)
- `of=` : périphérique de sortie (output file) — **utilisez `/dev/sdb`, PAS `/dev/sdb1` !**
- `bs=4M` : taille de bloc (4 Mo = rapide)
- `status=progress` : affiche la progression

### Étape 4 : Éjecter

```bash
sudo eject /dev/sdb
```

---

## Méthode 3 : macOS (dd)

### Étape 1 : Identifier la clé USB

```bash
diskutil list
```

**Exemple de sortie :**
```
/dev/disk0 (internal, physical):
   0: GUID_partition_scheme          *500.3 GB   disk0
   1: EFI EFI                         209.7 MB   disk0s1
   2: Apple_APFS Container disk1      500.1 GB   disk0s2

/dev/disk2 (external, physical):       ← Votre clé USB
   0: FDisk_partition_scheme          *8.0 GB     disk2
   1: Windows_FAT_32 USBKEY            8.0 GB     disk2s1
```

⚠️ **Notez le numéro de disque** (`disk2` dans l'exemple).

### Étape 2 : Démonter la clé

```bash
diskutil unmountDisk /dev/disk2
```

### Étape 3 : Écrire l'image

```bash
sudo dd if=universalos.img of=/dev/rdisk2 bs=4m
```

**Note :** Utilisez `rdisk2` (avec le "r") au lieu de `disk2` pour un accès brut plus rapide.

### Étape 4 : Éjecter

```bash
sudo diskutil eject /dev/disk2
```

---

## Méthode 4 : CD-ROM Bootable (Optionnel)

Si vous préférez graver sur CD :

### Linux
```bash
cdrecord -v dev=/dev/sr0 universalos.img
```

### macOS
```bash
hdiutil burn universalos.img
```

---

## Démarrage sur un Vrai PC

### Étape 1 : Insérer la clé USB

1. **Éteignez complètement votre PC** (pas de mise en veille)
2. Insérez la clé USB bootable
3. Démarrez le PC

### Étape 2 : Accéder au menu de boot

**Méthode A : Menu de démarrage temporaire**

Pendant le démarrage, **appuyez rapidement** sur l'une de ces touches :

| Fabricant | Touche Boot Menu |
|-----------|------------------|
| Dell | F12 |
| HP | F9 ou Esc |
| Lenovo | F12 ou F8 |
| Asus | F8 ou Esc |
| Acer | F12 |
| MSI | F11 |
| Gigabyte | F12 |
| Autres | F12, F11, F9, Esc, F2 |

**Méthode B : Configuration BIOS permanente**

1. Pendant le démarrage, appuyez sur **F2**, **Del**, ou **F10** pour entrer dans le BIOS
2. Allez dans **Boot** → **Boot Priority** ou **Boot Order**
3. Placez votre clé USB en **première position**
4. **Sauvegardez et quittez** (F10 → Yes)

### Étape 3 : Désactiver Secure Boot (si UEFI)

1. Entrez dans le BIOS (F2, Del, ou F10)
2. Cherchez **Secure Boot** (souvent dans **Security** ou **Boot**)
3. Réglez sur **Disabled**
4. Cherchez **Boot Mode** ou **CSM**
5. Réglez sur **Legacy** ou **UEFI + Legacy** ou **CSM Enabled**
6. Sauvegardez et redémarrez

### Étape 4 : Sélectionner la clé USB

1. Dans le menu de boot, sélectionnez votre clé USB (souvent nommée "USB HDD" ou avec la marque de la clé)
2. Appuyez sur **Enter**

---

## Ce que vous devriez voir

```
[S0] UniversalOS v0.1
CPU: GenuineIntel
[64-bit]
S1...OK

[S1] UniversalOS - Stage 1
Detecting RAM...
RAM: 8192 MB
Loading Stage 2...OK

=== UniversalOS Stage 2 - Diagnostic Shell ===
Type 'help' for command list.

UOS>
```

**À ce stade, vous pouvez taper des commandes :**
- `help` : liste des commandes
- `cpu` : informations CPU
- `mem` : carte mémoire E820
- `arch` : résumé plateforme
- `disk` : géométrie du disque
- `kbd` : basculer clavier QWERTY/AZERTY
- `clear` : effacer l'écran
- `reboot` : redémarrer

---

## Compatibilité Matérielle

### ✅ Testé et Fonctionnel

- **Émulateurs :** QEMU, VirtualBox, VMware
- **PC de bureau :** Intel Core i3/i5/i7/i9 (toutes générations)
- **PC portables :** Dell, HP, Lenovo, Asus (mode Legacy)
- **Serveurs :** Dell PowerEdge, HP ProLiant (BIOS mode)

### ⚠️ Prérequis Obligatoires

- **Architecture :** x86 ou x86_64 (Intel, AMD)
- **BIOS :** Legacy BIOS ou UEFI avec CSM activé
- **RAM :** Minimum 32 Mo (recommandé 128 Mo+)
- **Clavier :** PS/2 ou USB avec support Legacy activé dans le BIOS

### ❌ Non Supporté

- **ARM / Raspberry Pi** : nécessite un port ARM (non implémenté)
- **UEFI pur** : sans CSM/Legacy BIOS mode
- **Secure Boot activé** : doit être désactivé
- **Tablettes Windows RT** : architecture ARM

---

## Dépannage

### Problème : "No bootable device" ou "Reboot and select proper boot device"

**Cause :** Le BIOS ne trouve pas la clé USB bootable.

**Solutions :**
1. Vérifiez que la signature de boot est présente :
   ```bash
   xxd universalos.img | grep "55aa"
   # Doit afficher : ... 55aa
   ```
2. Réécrivez l'image sur la clé USB avec Rufus/dd
3. Essayez un **autre port USB** (privilégiez les ports USB 2.0, pas 3.0)
4. Vérifiez l'ordre de boot dans le BIOS

### Problème : Écran noir après "S1...OK"

**Cause :** Stage 2 n'a pas chargé correctement.

**Solutions :**
1. Vérifiez la taille de l'image : `ls -lh universalos.img` → doit faire 1 Mo (1 048 576 octets)
2. Rebuilder depuis les sources : `build.bat` ou `build.sh`
3. Testez d'abord dans QEMU avant le vrai PC

### Problème : Clavier ne fonctionne pas

**Cause :** Clavier USB sur un vieux PC sans support USB Legacy.

**Solutions :**
1. Activez **USB Legacy Support** dans le BIOS
2. Utilisez un **clavier PS/2** (port violet rond)
3. Essayez un autre PC plus récent

### Problème : Touches mal mappées (AZERTY affiche QWERTY)

**Cause :** Le shell démarre par défaut en QWERTY.

**Solutions :**
- Tapez `kbd` pour basculer en AZERTY
- Notez que le réglage est perdu au reboot (pas de stockage persistant pour l'instant)

### Problème : "ERR" pendant Stage 0

**Cause :** Échec de lecture du disque (contrôleur incompatible ou ancien BIOS).

**Solutions :**
1. Vérifiez le mode SATA dans le BIOS :
   - Essayez **IDE** ou **Legacy** au lieu de **AHCI**
2. Testez sur un autre PC
3. Utilisez la virtualisation (VirtualBox, QEMU)

### Problème : Carte mémoire affiche 0 zones

**Cause :** BIOS très ancien (avant 2000) sans support E820.

**Solutions :**
- Normal pour les systèmes pré-2000
- `arch` affichera quand même le total RAM détecté par une méthode alternative (à implémenter)

---

## Retour au Mode Normal

Pour **réutiliser votre clé USB normalement** après les tests :

### Windows
1. Ouvrez **Gestion des disques** (Win+X → Gestion des disques)
2. Faites un clic droit sur la clé USB → **Supprimer le volume**
3. Clic droit → **Nouveau volume simple**
4. Formatez en **FAT32** ou **NTFS**

### Linux
```bash
sudo fdisk /dev/sdb
# Dans fdisk : d (delete partition), n (new partition), w (write)
sudo mkfs.vfat /dev/sdb1   # Formatage FAT32
```

### macOS
```bash
diskutil eraseDisk FAT32 USBKEY /dev/disk2
```

---

## Remarques Importantes

1. **UniversalOS ne modifie JAMAIS votre disque dur** — tout tourne en RAM
2. Aucune donnée n'est sauvegardée entre les sessions (redémarrer = état initial)
3. Le système est **100% safe** : impossible d'endommager votre PC ou disque dur
4. C'est un **outil de diagnostic** — pas encore un OS complet

---

## Prochaines Étapes (Développement)

- [ ] Ajout du mode protégé 32-bit
- [ ] Passage en Long Mode 64-bit
- [ ] Chargement d'un noyau ELF
- [ ] Support UEFI natif (sans CSM)
- [ ] Driver FAT32 pour lire/écrire des fichiers
- [ ] Network stack (PXE boot)

---

**Bon test !** 🚀

Si vous rencontrez des problèmes non listés ici, consultez `TECHNICAL.md` pour plus de détails techniques.
