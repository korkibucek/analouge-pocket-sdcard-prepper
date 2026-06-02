@echo off
REM Analogue Pocket SD Card Prepper - Windows launcher.
REM Double-click to start the web UI in your browser. Use "PocketPrep.cmd cli" for
REM the text wizard instead. Requires PowerShell 7 (pwsh). No Administrator needed
REM for the normal copy workflow.

where pwsh >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh^) was not found.
    echo Install it from https://aka.ms/powershell ^(or: winget install Microsoft.PowerShell^) and run this again.
    pause
    exit /b 1
)

if /I "%~1"=="cli" (
    shift
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Start-PocketPrep.ps1" %*
) else (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Start-PocketPrepWeb.ps1" %*
)
pause
