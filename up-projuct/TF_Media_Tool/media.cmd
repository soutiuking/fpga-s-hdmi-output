@echo off
setlocal
set "PYTHONUTF8=1"
"%~dp0.runtime\python\python.exe" "%~dp0tools\media_card.py" %*
