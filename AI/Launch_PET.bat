@echo off
setlocal
cd /d "%~dp0"
set "MODE=Pet"
if /i "%~1"=="safe" set "MODE=Safe"
if /i "%~1"=="gpu" set "MODE=GPU"
if /i "%~1"=="check" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0PET_Start.ps1" -SelfTest
  pause
  exit /b %errorlevel%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0PET_Start.ps1" -Mode %MODE% -Restart
if errorlevel 1 (
  echo PET failed to start. Check %%TEMP%%\ComfyUI_Pet_Start.log
  pause
)
endlocal
