param(
    [ValidateSet('segtest','hdmitest','TFMEDIA3_Player')][string]$Target='TFMEDIA3_Player',
    [string]$TdRoot=$env:TD_ROOT,
    [ValidateRange(0,2147483647)][int]$PlaceSeed=11,
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'hash.ps1')
$taskRoot=Split-Path $PSScriptRoot -Parent
$taskProject=Join-Path $taskRoot "td_project/$Target.al"
$taskStamp=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$taskWork=Join-Path $taskRoot "build/$Target-$taskStamp"
$taskTemplates=Join-Path $PSScriptRoot "td_flow/$Target"
$taskEncoding=New-Object System.Text.UTF8Encoding($false)
$taskAl=Get-Content -LiteralPath $taskProject -Raw -Encoding UTF8
# .al is the canonical source list. Generated absolute paths stay in build/.
$taskPrj=[regex]::Replace($taskAl, '<File Path="([^"]+)"', {
    param($taskMatch)
    $taskPath=[System.IO.Path]::GetFullPath((Join-Path (Split-Path $taskProject -Parent) $taskMatch.Groups[1].Value)).Replace('\','/')
    if (!(Test-Path -LiteralPath $taskPath)) { throw "Missing project source: $taskPath" }
    '<File Path="' + $taskPath + '"'
})
$taskPrj=[regex]::Replace($taskPrj,'(?s)\s*<Runs>.*?</Runs>','')
$taskPrj=[regex]::Replace($taskPrj,'(<Project\b[^>]*?)\s+Path="[^"]*"','$1')
foreach($taskStage in @('syn_1','phy_1')) {
    $taskDir=Join-Path $taskWork $taskStage
    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
    foreach($taskName in @('run.tcl',"$Target.tcl",'settings.cfg')) {
        $taskText=Get-Content -LiteralPath (Join-Path $taskTemplates "$taskStage/$taskName") -Raw -Encoding UTF8
        # Tcl list elements containing portable source paths need braces when
        # the unpacked directory contains spaces (notably IpSDCList).
        $taskText=[regex]::Replace($taskText,'(?<!")(\.\./\.\./\.\./[^\s"}]+)','{$1}')
        $taskText=$taskText.Replace('../../../',($taskRoot.Replace('\','/')+'/'))
        $taskText=[regex]::Replace($taskText,'set_param place seed \d+',"set_param place seed $PlaceSeed")
        [System.IO.File]::WriteAllText((Join-Path $taskDir $taskName),$taskText,$taskEncoding)
    }
    [System.IO.File]::WriteAllText((Join-Path $taskDir "$Target.prj"),$taskPrj,$taskEncoding)
}
Write-Host "Prepared: $taskWork"
if($PrepareOnly) { return }
if (!$TdRoot) {
    $taskCommand=Get-Command td_commands_prompt.exe -ErrorAction SilentlyContinue
    if($taskCommand) { $TdRoot=Split-Path (Split-Path $taskCommand.Source -Parent) -Parent }
    else {
        foreach($taskCandidate in @('E:/ANLU-TD','C:/Anlogic/TD','C:/ANLU-TD','D:/ANLU-TD')) {
            if(Test-Path (Join-Path $taskCandidate 'bin/td_commands_prompt.exe')) { $TdRoot=$taskCandidate;break }
        }
    }
}
if (!$TdRoot) { throw 'TD missing. Install TD 6.2.168116, set TD_ROOT, or pass -TdRoot PATH.' }
$taskExe=Join-Path $TdRoot 'bin/td_commands_prompt.exe'
if (!(Test-Path -LiteralPath $taskExe)) { throw "TD executable missing: $taskExe" }
foreach($taskStage in @('syn_1','phy_1')) {
    $taskDir=Join-Path $taskWork $taskStage
    Push-Location $taskDir
    try {
        Write-Host "Running TD: $Target $taskStage (log: $taskDir/build.log)"
        & $taskExe run.tcl *> build.log
        $taskExit=$LASTEXITCODE
        $taskLog=Get-Content -LiteralPath build.log -Raw
        if($taskExit -ne 0 -or $taskLog -match '(?m)\bERROR\b|[A-Z]+-\d+\s+Error|^Error:') { throw "TD failed; see $taskDir/build.log" }
        if($taskStage -eq 'syn_1' -and $taskLog -notmatch 'Optimized|optimize_gate') { throw 'Synthesis did not finish' }
        if($taskStage -eq 'phy_1') {
            if($taskLog -notmatch 'bitgen') { throw 'Bit generation did not finish' }
            $taskTiming=Get-Content -LiteralPath "$Target`_pr.timing" -Raw
            foreach ($taskMetric in @('SWNS','HWNS','STNS','HTNS')) {
                $taskMatch=[regex]::Match($taskTiming,($taskMetric+':\s*(-?[0-9.]+)ns'))
                if (!$taskMatch.Success -or [double]::Parse($taskMatch.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0) {
                    throw "Timing incomplete or failed ($taskMetric); see $taskDir/$Target`_pr.timing"
                }
            }
        }
    } finally { Pop-Location }
}
$taskBit=Join-Path $taskWork "phy_1/$Target.bit"
if(!(Test-Path -LiteralPath $taskBit)) { throw 'No bitstream generated' }
$taskOutput=Join-Path $taskRoot "output/$Target-$taskStamp"
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
Copy-Item -LiteralPath $taskBit -Destination (Join-Path $taskOutput "$Target.bit")
Copy-Item -LiteralPath (Join-Path $taskWork "phy_1/$Target`_pr.timing") -Destination $taskOutput
Copy-Item -LiteralPath (Join-Path $taskWork "phy_1/$Target`_phy.area") -Destination $taskOutput
Write-Host ('SHA256: ' + (Get-TaskSHA256 $taskBit))
Write-Host "Build passed: $taskOutput"
