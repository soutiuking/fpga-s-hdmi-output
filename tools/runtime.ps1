$taskRoot = Split-Path $PSScriptRoot -Parent
$taskConfig = Join-Path $taskRoot '.runtime/current.json'
if (!(Test-Path -LiteralPath $taskConfig)) { & (Join-Path $PSScriptRoot 'setup.ps1') }
$taskCurrent = Get-Content -LiteralPath $taskConfig -Raw | ConvertFrom-Json
$taskPython = Join-Path $taskRoot $taskCurrent.python
$taskFfmpeg = Join-Path $taskRoot $taskCurrent.ffmpeg
$taskIcarus = Join-Path $taskRoot $taskCurrent.iverilog
if (!(Test-Path -LiteralPath $taskPython)) { throw 'Runtime missing. Run setup.cmd again.' }
$env:TFMEDIA_FFMPEG = $taskFfmpeg
$env:PYTHONUTF8 = '1'
