@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\package.ps1" %*
exit /b %errorlevel%
