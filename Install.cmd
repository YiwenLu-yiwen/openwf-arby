@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Arbitration4.ps1" %*
set "ARBITRATION4_EXIT=%ERRORLEVEL%"
echo.
if not "%ARBITRATION4_EXIT%"=="0" echo Installation failed with exit code %ARBITRATION4_EXIT%.
pause
exit /b %ARBITRATION4_EXIT%
