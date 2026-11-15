@echo off
rem Installs the conversation-window adapter. Pass -Restore to roll back.
rem -CheckOnly verifies hashes and backup without touching anything.
set "PS=pwsh.exe"
where pwsh.exe >nul 2>nul || set "PS=powershell.exe"
%PS% -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-adapter.ps1" %*
echo.
echo OK    = patch applied (or already applied) and the app was started once.
echo WAIT  = quit DeepSeek Harness from the tray; this window keeps waiting.
echo FAIL  = nothing was changed; the reason is printed above.
echo Log: %~dp0build\install-adapter.log
pause
