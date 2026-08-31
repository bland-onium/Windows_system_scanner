@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: 2. cd to folder with running code
cd /d "%~dp0"

:: 3. Run ps1 file
echo running Checker...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "PSCheckerNoAdmin.ps1"
set PS_EXIT=%errorlevel%

if %PS_EXIT% neq 0 (
    echo [!] Script failed with code %PS_EXIT%
) else (
    echo [+] All scripts executed.
)

::exit /b %PS_EXIT%

exit
