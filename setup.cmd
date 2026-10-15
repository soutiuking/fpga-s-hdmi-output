@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup.ps1" %*
set "task_status=%errorlevel%"
if not "%task_status%"=="0" pause
exit /b %task_status%
