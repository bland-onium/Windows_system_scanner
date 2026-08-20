@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: 1. Check for admin rules
net session >nul 2>&1
if %errorlevel% == 0 (
    goto :AdminStart
) else (
    echo [!] No admin rights. Requesting UAC elevation...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs; exit $LASTEXITCODE"
    if %errorlevel% neq 0 (
        echo [!] Failed to elevate. exiting.
        pause
        exit /b 1
    )
    exit /b
)

:AdminStart
:: 2. cd to folder with running code
cd /d "%~dp0"

:: 3. Run ps1 file
echo running Checker...
powershell -NoProfile -ExecutionPolicy Bypass -File "PSChecker.ps1"
set PS_EXIT=%errorlevel%

if %PS_EXIT% neq 0 (
    echo [!] Script failed with code %PS_EXIT%
) else (
    echo [+] All scripts executed.
)

echo.
pause
exit /b %PS_EXIT%
