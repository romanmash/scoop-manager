@echo off
setlocal

:: Thin proxy that launches PowerShell manager
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"
set "MANAGER=%SCRIPT_DIR%scripts\Manage-ScoopMenu.ps1"

if not exist "%MANAGER%" (
  echo Error: Manager not found: %MANAGER%
  pause
  exit /b 1
)

where /q pwsh.exe
if %errorlevel% equ 0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%MANAGER%"
)

set "EXIT_CODE=%errorlevel%"

:: If there was an error, pause so user can see the error message
if not %EXIT_CODE% equ 0 (
  echo.
  echo Script exited with error code: %EXIT_CODE%
  echo Press any key to close this window...
  pause >nul
)

exit /b %EXIT_CODE%
