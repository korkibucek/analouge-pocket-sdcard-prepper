@echo off
REM Analogue Pocket SD Card Prepper - Windows launcher.
REM Double-click this file to start the wizard. Requires PowerShell 7+ (pwsh).
REM This does NOT require Administrator for the normal copy workflow.

where pwsh >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh^) was not found.
    echo Install it from https://aka.ms/powershell and run this again.
    pause
    exit /b 1
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Start-PocketPrep.ps1" %*
pause
