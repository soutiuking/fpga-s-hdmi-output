# Preserve raw Python options such as -o instead of binding common parameters.
$MediaArgs=@($args)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime.ps1')
$taskScript=Join-Path $PSScriptRoot 'media_card.py'
if ($MediaArgs.Count -gt 0) {
    & $taskPython $taskScript @MediaArgs
    exit $LASTEXITCODE
}
Write-Host 'TFMEDIA3 写卡工具 · 霁泽入微工作室'
Write-Host '1 制作图片/视频镜像  2 检查镜像  3 列出磁盘  4 写入 TF 卡  0 退出'
$taskChoice=Read-Host '请选择'
switch ($taskChoice) {
    '1' {
        Add-Type -AssemblyName System.Windows.Forms
        $taskDialog=New-Object System.Windows.Forms.OpenFileDialog
        $taskDialog.Multiselect=$true
        $taskDialog.Title='选择图片或视频（精确控制顺序请使用命令行）'
        if ($taskDialog.ShowDialog() -ne 'OK') { return }
        $taskInputs=@($taskDialog.FileNames)
        $taskSave=New-Object System.Windows.Forms.SaveFileDialog
        $taskSave.Filter='TFMEDIA3 image (*.img)|*.img'
        $taskSave.FileName='tf_media.img'
        if ($taskSave.ShowDialog() -ne 'OK') { return }
        $taskAudio=Read-Host '是否保留声音？y/N'
        $taskPack=@('pack')+$taskInputs+@('-o',$taskSave.FileName)
        if ($taskAudio -eq 'y') { $taskPack+='--audio' }
        & $taskPython $taskScript @taskPack
        if ($LASTEXITCODE -ne 0) { throw 'Pack failed' }
    }
    '2' {
        $taskImage=Read-Host '镜像路径（不需要外层引号）'
        & $taskPython $taskScript inspect $taskImage
        if ($LASTEXITCODE -ne 0) { throw 'Inspect failed' }
    }
    '3' { & $taskPython $taskScript disks; if ($LASTEXITCODE -ne 0) { throw 'Disk query failed' } }
    '4' {
        & $taskPython $taskScript disks
        if ($LASTEXITCODE -ne 0) { throw 'Disk query failed' }
        Write-Host '写入将覆盖所选 TF 卡的分区和数据，请在管理员终端执行。'
        $taskImage=Read-Host '镜像路径（不需要外层引号）'
        $taskDisk=Read-Host '目标物理磁盘编号'
        $taskConfirm=Read-Host '请再次输入目标磁盘编号确认'
        & $taskPython $taskScript write $taskImage --disk $taskDisk --confirm-disk $taskConfirm
        if ($LASTEXITCODE -ne 0) { throw 'Write failed' }
    }
    '0' { return }
    default { throw 'Unknown choice' }
}
