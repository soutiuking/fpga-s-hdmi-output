@echo off
set "TFMEDIA_LAUNCHER=%~dp0FPGA_TF_Media_Tool.exe"
powershell.exe -NoProfile -Command "Start-Process -FilePath $env:TFMEDIA_LAUNCHER -Verb RunAs"
