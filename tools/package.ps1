$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime.ps1')
& $taskPython (Join-Path $PSScriptRoot 'package.py')
if ($LASTEXITCODE -ne 0) { throw 'Package failed' }
