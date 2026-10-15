param([switch]$Refresh)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hash.ps1')
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskManifest = Join-Path $taskRoot 'vendor/manifest.json'
$taskConfig = Join-Path $taskRoot '.runtime/current.json'
if (!$Refresh -and (Test-Path -LiteralPath $taskConfig)) {
    $taskCurrent = Get-Content -LiteralPath $taskConfig -Raw | ConvertFrom-Json
    $taskPython = Join-Path $taskRoot $taskCurrent.python
    $taskFfmpeg = Join-Path $taskRoot $taskCurrent.ffmpeg
    $taskIcarus = Join-Path $taskRoot $taskCurrent.iverilog
    if ((Test-Path $taskPython) -and (Test-Path $taskFfmpeg) -and (Test-Path $taskIcarus)) {
        & $taskPython -c 'from PIL import Image; import ctypes,ssl; print(Image.__version__)'
        if ($LASTEXITCODE -eq 0) { return }
    }
}
$taskDependencies = Get-Content -LiteralPath $taskManifest -Raw | ConvertFrom-Json
foreach ($taskDependency in $taskDependencies) {
    $taskArchive = Join-Path $taskRoot ('vendor/' + $taskDependency.file)
    if ((Get-TaskSHA256 $taskArchive) -ne $taskDependency.sha256) {
        throw "Dependency SHA256 mismatch: $taskArchive"
    }
}
# Each refresh uses a new directory; old runtimes are preserved.
$taskRelative = '.runtime/bundle-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$taskBundle = Join-Path $taskRoot $taskRelative
New-Item -ItemType Directory -Path $taskBundle -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($taskDependency in $taskDependencies) {
    $taskArchive = Join-Path $taskRoot ('vendor/' + $taskDependency.file)
    if ($taskDependency.file -like 'python-*') { $taskDest = Join-Path $taskBundle 'python' }
    elseif ($taskDependency.file -like '*.whl') { $taskDest = Join-Path $taskBundle 'python/Lib/site-packages' }
    else { $taskDest = Join-Path $taskBundle 'iverilog' }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($taskArchive, $taskDest)
}
$taskPth = Join-Path $taskBundle 'python/python312._pth'
[System.IO.File]::WriteAllText($taskPth, "python312.zip`n.`nLib/site-packages`n../../../tools`n../../../sim`nimport site`n", (New-Object System.Text.UTF8Encoding($false)))
$taskPython = Join-Path $taskBundle 'python/python.exe'
& $taskPython -c 'from PIL import Image; import ctypes,ssl; print(Image.__version__)'
if ($LASTEXITCODE -ne 0) { throw 'Portable Python check failed' }
$taskFfmpeg = Get-ChildItem -LiteralPath (Join-Path $taskBundle 'python/Lib/site-packages/imageio_ffmpeg/binaries') -Filter 'ffmpeg*.exe' | Select-Object -First 1
if (!$taskFfmpeg) { throw 'FFmpeg binary missing' }
$taskIcarus = Join-Path $taskBundle 'iverilog/bin/iverilog.exe'
& $taskFfmpeg.FullName -version | Select-Object -First 1
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg check failed' }
& $taskIcarus -V *> (Join-Path $taskBundle 'iverilog-version.txt')
if ($LASTEXITCODE -ne 0) { throw 'Icarus check failed' }
$taskFfmpegRelative = $taskRelative + '/python/Lib/site-packages/imageio_ffmpeg/binaries/' + $taskFfmpeg.Name
$taskValue = @{python="$taskRelative/python/python.exe";ffmpeg=$taskFfmpegRelative;iverilog="$taskRelative/iverilog/bin/iverilog.exe"}
[System.IO.File]::WriteAllText($taskConfig, ($taskValue | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Offline initialization complete. No pip or external tool directory is needed.'
