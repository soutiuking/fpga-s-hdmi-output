@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0tools\media.ps1" %*
set "task_status=%errorlevel%"
if "%~1"=="" pause
exit /b %task_status%
