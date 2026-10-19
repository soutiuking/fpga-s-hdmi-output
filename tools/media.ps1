# Preserve raw Python options such as -o instead of binding common parameters.
$MediaArgs=@($args)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime.ps1')
$taskScript=Join-Path $PSScriptRoot 'media_card.py'
if ($MediaArgs.Count -gt 0) {
    & $taskPython $taskScript @MediaArgs
    exit $LASTEXITCODE
}
$taskGuiConfig = Join-Path $taskRoot '.runtime/gui-current.json'
if (!(Test-Path -LiteralPath $taskGuiConfig)) { & (Join-Path $PSScriptRoot 'setup_gui.ps1') }
$taskGuiCurrent = Get-Content -LiteralPath $taskGuiConfig -Raw | ConvertFrom-Json
$taskGuiPython = Join-Path $taskRoot $taskGuiCurrent.python
if (!(Test-Path -LiteralPath $taskGuiPython)) { throw 'GUI runtime missing. Run tools/setup_gui.ps1 again.' }
& $taskGuiPython (Join-Path $PSScriptRoot 'media_gui_tk.py')
exit $LASTEXITCODE
