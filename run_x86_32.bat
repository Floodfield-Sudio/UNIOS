@echo off
REM ==========================================================================
REM UNIOS — Lancement QEMU x86 32-bit (émulation PC 32-bit pur)
REM ==========================================================================
set QEMU=C:\msys64\ucrt64\bin\qemu-system-i386.exe

if not exist "%QEMU%" (
    echo ERREUR : qemu-system-i386 introuvable : %QEMU%
    echo Installez-le via MSYS64 : pacman -S mingw-w64-ucrt-x86_64-qemu
    pause & exit /b 1
)

echo Demarrage UNIOS sur QEMU i386 (32-bit)...

"%QEMU%" ^
  -drive format=raw,file=build\unios.img ^
  -m 64M ^
  -name "UNIOS v0.1 - i386"