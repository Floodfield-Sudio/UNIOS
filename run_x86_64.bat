@echo off
REM ==========================================================================
REM UNIOS — Lancement QEMU x86_64 (architecture cible principale)
REM ==========================================================================
set QEMU=C:\msys64\ucrt64\bin\qemu-system-x86_64.exe

if not exist "%QEMU%" (
    echo ERREUR : QEMU introuvable : %QEMU%
    echo Ajustez la variable QEMU dans ce fichier.
    pause & exit /b 1
)

if not exist build\unios.img (
    echo ERREUR : Image introuvable. Lancez d'abord build.bat
    pause & exit /b 1
)

echo.
echo Demarrage UNIOS sur QEMU x86_64...
echo Utilisez Ctrl+Alt+G pour liberer la souris.
echo Fermez la fenetre QEMU pour quitter.
echo.

"%QEMU%" ^
  -drive format=raw,file=build\unios.img ^
  -m 128M ^
  -name "UNIOS v0.0.2 - x86_64"
