@echo off
setlocal enabledelayedexpansion

REM Se place dans le dossier du .bat, peu importe d'ou il est lance
cd /d "%~dp0"

echo.
echo ==========================================
echo   UNIOS Build System
echo ==========================================
echo [Dossier] %~dp0
echo.

REM ==========================================================================
REM CONFIGURATION MANUELLE (decommentez et adaptez si detection automatique echoue)
REM set NASM_EXE=C:\Users\VotreNom\AppData\Local\bin\NASM\nasm.exe
REM set PYTHON_EXE=C:\Users\VotreNom\AppData\Local\Programs\Python\Python312\python.exe
REM ==========================================================================
set NASM_EXE=
set PYTHON_EXE=

REM ==========================================================================
REM Detection NASM
REM ==========================================================================
if not "%NASM_EXE%"=="" goto :nasm_found

set _C=%USERPROFILE%\AppData\Local\bin\NASM\nasm.exe
if exist "%_C%" ( set NASM_EXE=%_C% & goto :nasm_found )

if not "%LOCALAPPDATA%"=="" (
    if exist "%LOCALAPPDATA%\bin\NASM\nasm.exe" (
        set NASM_EXE=%LOCALAPPDATA%\bin\NASM\nasm.exe
        goto :nasm_found
    )
)

for %%F in (
    "C:\NASM\nasm.exe"
    "C:\Program Files\NASM\nasm.exe"
    "C:\Program Files (x86)\NASM\nasm.exe"
    "C:\msys64\ucrt64\bin\nasm.exe"
    "C:\msys64\usr\bin\nasm.exe"
) do ( if exist %%F ( set NASM_EXE=%%~F & goto :nasm_found ) )

where nasm >nul 2>&1
if not errorlevel 1 ( set NASM_EXE=nasm & goto :nasm_found )

echo ERREUR : nasm.exe introuvable.
echo Editez build.bat et decommentez : set NASM_EXE=...
pause & exit /b 1

:nasm_found
echo [NASM]   "%NASM_EXE%"

REM ==========================================================================
REM Detection Python
REM ==========================================================================
if not "%PYTHON_EXE%"=="" goto :python_found

REM -- Via le launcher py.exe (present si Python installe normalement) --------
where py >nul 2>&1
if not errorlevel 1 ( set PYTHON_EXE=py & goto :python_found )

REM -- python / python3 dans le PATH ------------------------------------------
where python >nul 2>&1
if not errorlevel 1 ( set PYTHON_EXE=python & goto :python_found )

where python3 >nul 2>&1
if not errorlevel 1 ( set PYTHON_EXE=python3 & goto :python_found )

REM -- Cherche dans les emplacements standards Python (toutes versions) --------
for %%V in (313 312 311 310 39 38) do (
    for %%F in (
        "%USERPROFILE%\AppData\Local\Programs\Python\Python%%V\python.exe"
        "%LOCALAPPDATA%\Programs\Python\Python%%V\python.exe"
        "C:\Python%%V\python.exe"
        "C:\Program Files\Python%%V\python.exe"
    ) do (
        if exist %%F ( set PYTHON_EXE=%%~F & goto :python_found )
    )
)

REM -- Microsoft Store python (WindowsApps) ------------------------------------
for %%F in ("%USERPROFILE%\AppData\Local\Microsoft\WindowsApps\python.exe") do (
    if exist %%F ( set PYTHON_EXE=%%~F & goto :python_found )
)

echo.
echo ERREUR : Python introuvable.
echo.
echo Verifiez votre installation :
echo   - Ouvrez PowerShell et tapez : Get-Command python ^| Select-Object Source
echo   - Ou cherchez python.exe avec : where /r C:\ python.exe
echo.
echo Puis editez build.bat et decommentez :
echo   set PYTHON_EXE=C:\chemin\vers\python.exe
echo.
pause & exit /b 1

:python_found
echo [PYTHON] "%PYTHON_EXE%"
echo.

REM ==========================================================================
REM Build
REM ==========================================================================
if not exist build mkdir build

echo [1/4] Assemblage Stage 0...
"%NASM_EXE%" -f bin stage0.asm -o build\stage0.bin -l build\stage0.lst
if errorlevel 1 ( echo       ECHEC & pause & exit /b 1 )
echo       OK — build\stage0.bin

echo [2/4] Assemblage Stage 1...
"%NASM_EXE%" -f bin stage1.asm -o build\stage1.bin -l build\stage1.lst
if errorlevel 1 ( echo       ECHEC & pause & exit /b 1 )
echo       OK — build\stage1.bin

echo [3/4] Assemblage Stage 2...
"%NASM_EXE%" -f bin stage2.asm -o build\stage2.bin -l build\stage2.lst
if errorlevel 1 ( echo       ECHEC & pause & exit /b 1 )
echo       OK — build\stage2.bin

echo [4/4] Creation image disque...
"%PYTHON_EXE%" create_image.py
if errorlevel 1 ( echo       ECHEC & pause & exit /b 1 )

echo.
echo ==========================================
echo   BUILD REUSSI  --  build\unios.img
echo ==========================================
echo.
echo Lancez run_x86_64.bat pour tester dans QEMU.
echo.
pause