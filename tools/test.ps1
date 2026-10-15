param([switch]$Full)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime.ps1')
& $taskPython (Join-Path $PSScriptRoot 'check_project.py')
if ($LASTEXITCODE -ne 0) { throw 'Portable project preflight failed' }
$taskTestArgs=@((Join-Path $taskRoot 'sim/run_tests.py'),'--iverilog',$taskIcarus)
if (!$Full) { $taskTestArgs+='--quick' }
& $taskPython @taskTestArgs
if ($LASTEXITCODE -ne 0) { throw 'Regression tests failed' }
