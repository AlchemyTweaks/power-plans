@echo off
setlocal
cd /d "%~dp0"
title Alchemy Power Plan Tool
set "TOOLDIR=%~dp0."

rem --- Guard: running from inside a ZIP preview (files not extracted) ---
if not exist "%~dp0plans\" (
  echo.
  echo  [ERROR] The "plans" folder was not found next to this file.
  echo  Extract the whole ZIP first ^(right-click the ZIP ^> Extract All^), then run this file again.
  echo.
  pause
  exit /b 2
)
if not exist "%~dp0PowerPlanTool.ps1" (
  echo  [ERROR] PowerPlanTool.ps1 is missing. Download the repository again.
  pause
  exit /b 2
)

rem --- Always use the native 64-bit Windows PowerShell ---
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo  [ERROR] Windows PowerShell was not found at %PS%
  pause
  exit /b 3
)

rem --- Remove the downloaded-from-internet mark from the tool files ---
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:TOOLDIR -Recurse -File | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0PowerPlanTool.ps1" -Mode ImportAll
if errorlevel 1 (
  echo.
  echo  The tool did not finish ^(exit code %errorlevel%^).
  echo  If you saw "running scripts is disabled" your PC has a script policy set by an administrator.
  echo  Logs are in the "logs" folder next to this file. Attach them to a GitHub issue.
  echo.
  pause
)
endlocal
