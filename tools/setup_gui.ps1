$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime.ps1')
& $taskPython (Join-Path $PSScriptRoot 'package_media_tool.py') --setup
if ($LASTEXITCODE -ne 0) { throw 'GUI runtime setup failed.' }
