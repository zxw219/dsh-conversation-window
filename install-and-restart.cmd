@echo off
set "PS=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PS=powershell.exe"
%PS% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build\install-and-restart.ps1" %*
echo.
echo Look for OK or FAIL in the lines above.
echo   WAIT means: quit DeepSeek Harness from the tray icon and this window continues.
echo Full log: %~dp0build\install-restart.log
pause
