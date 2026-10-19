param([switch]$SmokeTest)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runtime.ps1')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'MediaPreview.cs') -ReferencedAssemblies System.Drawing,System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
$script:temp=Join-Path ([IO.Path]::GetTempPath()) ('tfmedia-ui-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:temp | Out-Null
$script:video=$null;$script:job=$null;$script:jobOut=$null;$script:jobErr=$null
$script:previewSource='';$script:previewOffset=0.0;$script:previewStarted=Get-Date
$script:rows=@();$script:internalSeek=$false
$utf8=New-Object Text.UTF8Encoding($false)
function Button($text,$x,$y,$w=90) {
    $b=New-Object Windows.Forms.Button;$b.Text=$text;$b.SetBounds($x,$y,$w,30);return $b
}
function Label($text,$x,$y,$w=300) {
    $l=New-Object Windows.Forms.Label;$l.Text=$text;$l.SetBounds($x,$y,$w,24);return $l
}
function Set-PreviewImage($image) {
    $old=$picture.Image;$picture.Image=$image;if($old){$old.Dispose()}
}
function Load-Png($path) {
    $stream=[IO.File]::OpenRead($path)
    try { $im=[Drawing.Image]::FromStream($stream);try {return New-Object Drawing.Bitmap($im)}finally{$im.Dispose()} }
    finally {$stream.Dispose()}
}
function Stop-Video {
    if($script:video){$script:video.Dispose();$script:video=$null}
}
function Subtitle-Config {
    $entries=@()
    foreach($r in $script:rows) {
        $entries+=@{text=$r.text.Text;color=$r.color.Tag;rainbow=[bool]$r.rainbow.Checked}
    }
    return @{subtitles=$entries}
}
function Save-Json($path,$data) {
    [IO.File]::WriteAllText($path,($data | ConvertTo-Json -Depth 8),$utf8)
}
function Run-PreviewHelper($mode,$source,$output) {
    & $taskPython (Join-Path $PSScriptRoot 'media_preview.py') $mode $source $output 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){throw '预览解码失败，请检查媒体文件或字幕内容。'}
}
function Show-Media {
    if($list.SelectedIndex -lt 0){return}
    Stop-Video
    Set-PreviewImage $null
    $script:previewSource=[string]$list.SelectedItem
    $path=$script:previewSource
    $mediaTip.SetToolTip($list,$path)
    try {
        if([IO.Path]::GetExtension($path).ToLower() -in @('.png','.jpg','.jpeg','.bmp','.tif','.tiff','.webp')) {
            Run-PreviewHelper 'image' $path (Join-Path $script:temp 'image.png')
            Set-PreviewImage (Load-Png (Join-Path $script:temp 'image.png'))
            $status.Text='图片预览 · 保持比例显示';$seek.Enabled=$false
        } else {
            $seek.Enabled=$true;$seek.Value=0;$script:previewOffset=0
            Start-Video 0
        }
    } catch {$status.Text=$_.Exception.Message}
}
function Start-Video([double]$seconds) {
    Stop-Video
    try {
        $script:video=New-Object TfVideoPreview
        $script:video.Start($taskFfmpeg,$script:previewSource,$seconds)
        $script:previewOffset=$seconds;$script:previewStarted=Get-Date
        $status.Text='视频预览播放中（静音）· 可拖动定位，写卡音轨由“保留声音”决定'
    } catch {Stop-Video;$status.Text='视频预览失败：'+$_.Exception.Message}
}
function Start-Task([string[]]$arguments) {
    if($script:job){throw '已有任务正在执行，请等待完成。'}
    $p=New-Object Diagnostics.ProcessStartInfo
    $p.FileName=$taskPython
    $p.Arguments=(@((Join-Path $PSScriptRoot 'media_card.py'))+$arguments | ForEach-Object {[TfVideoPreview]::Quote([string]$_)}) -join ' '
    $p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
    $p.EnvironmentVariables['PYTHONIOENCODING']='utf-8'
    $p.StandardOutputEncoding=[Text.Encoding]::UTF8;$p.StandardErrorEncoding=[Text.Encoding]::UTF8
    $script:job=New-Object Diagnostics.Process;$script:job.StartInfo=$p
    [void]$script:job.Start();$script:jobOut=$script:job.StandardOutput.ReadToEndAsync();$script:jobErr=$script:job.StandardError.ReadToEndAsync()
    $pack.Enabled=$false;$inspect.Enabled=$false;$write.Enabled=$false
    $log.Text='正在执行，请等待。可继续预览媒体。';$status.Text='任务运行中'
}
$form=New-Object Windows.Forms.Form
$form.Text='TFMEDIA3 多媒体制卡 · 字幕与预览';$form.ClientSize=New-Object Drawing.Size(1120,820)
$form.StartPosition='CenterScreen';$form.MinimumSize=$form.Size
$tabs=New-Object Windows.Forms.TabControl;$tabs.SetBounds(12,12,1096,640)
$mediaTab=New-Object Windows.Forms.TabPage;$mediaTab.Text='媒体与预览'
$subtitleTab=New-Object Windows.Forms.TabPage;$subtitleTab.Text='字幕设置（最多10条）'
$tabs.TabPages.AddRange(@($mediaTab,$subtitleTab));$form.Controls.Add($tabs)
$list=New-Object Windows.Forms.ListBox;$list.SetBounds(12,50,410,480);$list.HorizontalScrollbar=$true;$list.FormattingEnabled=$true
$list.Add_Format({param($sender,$eventArgs) $eventArgs.Value=[IO.Path]::GetFileName([string]$eventArgs.ListItem)})
$mediaTip=New-Object Windows.Forms.ToolTip
$add=Button '添加媒体' 12 10 100;$remove=Button '移除' 118 10;$up=Button '上移' 214 10;$down=Button '下移' 310 10
$picture=New-Object Windows.Forms.PictureBox;$picture.SetBounds(442,10,630,472)
$picture.BackColor=[Drawing.Color]::Black;$picture.SizeMode='Zoom'
$play=Button '播放 / 重播' 442 490 110;$stop=Button '停止' 560 490 80
$seek=New-Object Windows.Forms.NumericUpDown;$seek.SetBounds(750,495,90,26);$seek.Maximum=86400
$go=Button '定位' 850 490 80
$mediaTab.Controls.AddRange(@($list,$add,$remove,$up,$down,$picture,$play,$stop,$seek,$go,(Label '定位秒数：' 650 495 100),
 (Label '图片自动预览；视频通过内置 FFmpeg 播放，支持中文路径。预览静音。' 442 535 630)))
$add.Add_Click({
    $d=New-Object Windows.Forms.OpenFileDialog;$d.Multiselect=$true
    $d.Filter='图片和视频|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.tiff;*.mp4;*.mkv;*.avi;*.mov;*.wmv;*.webm;*.m4v;*.mpg;*.mpeg|所有文件|*.*'
    if($d.ShowDialog() -eq 'OK'){foreach($f in $d.FileNames){if(!$list.Items.Contains($f)){[void]$list.Items.Add($f)}};if($list.SelectedIndex -lt 0){$list.SelectedIndex=0}}
    $d.Dispose()
})
$remove.Add_Click({if($list.SelectedIndex -ge 0){Stop-Video;$i=$list.SelectedIndex;$list.Items.RemoveAt($i);if($list.Items.Count){$list.SelectedIndex=[Math]::Min($i,$list.Items.Count-1)}else{$script:previewSource='';Set-PreviewImage $null;$seek.Enabled=$false}}})
$up.Add_Click({$i=$list.SelectedIndex;if($i -gt 0){$v=$list.Items[$i];$list.Items.RemoveAt($i);$list.Items.Insert($i-1,$v);$list.SelectedIndex=$i-1}})
$down.Add_Click({$i=$list.SelectedIndex;if($i -ge 0 -and $i -lt $list.Items.Count-1){$v=$list.Items[$i];$list.Items.RemoveAt($i);$list.Items.Insert($i+1,$v);$list.SelectedIndex=$i+1}})
$list.Add_SelectedIndexChanged({Show-Media})
$play.Add_Click({if($script:previewSource -and $seek.Enabled){Start-Video ([double]$seek.Value)}})
$stop.Add_Click({Stop-Video;$status.Text='预览已停止'})
$go.Add_Click({if($script:previewSource -and $seek.Enabled){Start-Video ([double]$seek.Value)}})
$subtitleTab.Controls.Add((Label '固定黑体 · 每条最多32字符 · 空行忽略 · 全部为空时使用板上默认字幕' 16 12 1000))
for($i=0;$i -lt 10;$i++) {
    $y=44+$i*39
    $t=New-Object Windows.Forms.TextBox;$t.SetBounds(50,$y,670,26);$t.MaxLength=32
    $c=Button '颜色' 735 ($y-2) 70;$c.Tag='#FDE68A';$c.BackColor=[Drawing.ColorTranslator]::FromHtml($c.Tag)
    $r=New-Object Windows.Forms.CheckBox;$r.Text='炫彩';$r.SetBounds(820,$y,80,26)
    $prev=Button '预览' 920 ($y-2) 80;$prev.Tag=$i
    $subtitleTab.Controls.AddRange(@((Label ([string]($i+1)) 18 $y 30),$t,$c,$r,$prev))
    $script:rows+=@{text=$t;color=$c;rainbow=$r}
    $c.Add_Click({$d=New-Object Windows.Forms.ColorDialog;$d.Color=$this.BackColor;if($d.ShowDialog() -eq 'OK'){$this.BackColor=$d.Color;$this.Tag=('#{0:X2}{1:X2}{2:X2}' -f $d.Color.R,$d.Color.G,$d.Color.B)};$d.Dispose()})
    $prev.Add_Click({try {
        $row=$script:rows[[int]$this.Tag]
        $entry=@{text=$row.text.Text;color=$row.color.Tag;rainbow=[bool]$row.rainbow.Checked}
        Save-Json (Join-Path $script:temp 'preview.json') $entry
        Run-PreviewHelper 'subtitle' (Join-Path $script:temp 'preview.json') (Join-Path $script:temp 'subtitle.png')
        $old=$subPicture.Image;$subPicture.Image=Load-Png (Join-Path $script:temp 'subtitle.png');if($old){$old.Dispose()}
        $status.Text='字幕预览：显示前19字符；上板后会完整滚动显示。炫彩预览显示其中一帧。'
    } catch {$status.Text=$_.Exception.Message}})
}
$subPicture=New-Object Windows.Forms.PictureBox;$subPicture.SetBounds(18,443,1000,90);$subPicture.SizeMode='Zoom';$subPicture.BackColor=[Drawing.Color]::FromArgb(17,24,39)
$saveSub=Button '保存字幕配置' 18 546 140;$loadSub=Button '载入字幕配置' 170 546 140;$clearSub=Button '清空字幕' 322 546 100
$subtitleTab.Controls.AddRange(@($subPicture,$saveSub,$loadSub,$clearSub))
$saveSub.Add_Click({$d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='字幕配置|*.json';if($d.ShowDialog() -eq 'OK'){Save-Json $d.FileName (Subtitle-Config)};$d.Dispose()})
$loadSub.Add_Click({try {
    $d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='字幕配置|*.json'
    if($d.ShowDialog() -eq 'OK'){
        $data=Get-Content -LiteralPath $d.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        if(!$data.PSObject.Properties['subtitles']){throw '配置缺少 subtitles 数组'}
        $entries=@($data.subtitles);if($entries.Count -gt 10){throw '最多10条字幕'}
        foreach($e in $entries){if($e.text.Length -gt 32 -or $e.color -notmatch '^#[0-9a-fA-F]{6}$' -or $e.rainbow -isnot [bool]){throw '配置包含无效字幕、颜色或炫彩设置'}}
        for($j=0;$j -lt 10;$j++){$r=$script:rows[$j];$r.text.Text='';$r.rainbow.Checked=$false;if($j -lt $entries.Count){$e=$entries[$j];$r.text.Text=$e.text;$r.color.Tag=$e.color;$r.color.BackColor=[Drawing.ColorTranslator]::FromHtml($e.color);$r.rainbow.Checked=$e.rainbow}}
    };$d.Dispose()
} catch {$status.Text='载入失败：'+$_.Exception.Message}})
$clearSub.Add_Click({foreach($r in $script:rows){$r.text.Text='';$r.rainbow.Checked=$false};$status.Text='字幕已清空，生成镜像时使用默认文字'})
$audio=New-Object Windows.Forms.CheckBox;$audio.Text='保留声音';$audio.SetBounds(16,661,100,28);$audio.Checked=$true
$pack=Button '生成镜像' 130 658 115;$inspect=Button '检查镜像' 255 658 115;$write=Button '写入TF卡' 380 658 115
$status=Label '就绪 · 新固件支持自定义字幕；旧卡自动使用默认字幕。' 510 665 590
$log=New-Object Windows.Forms.TextBox;$log.SetBounds(16,701,1088,103);$log.Multiline=$true;$log.ReadOnly=$true;$log.ScrollBars='Vertical'
$form.Controls.AddRange(@($audio,$pack,$inspect,$write,$status,$log))
$pack.Add_Click({try {
    if(!$list.Items.Count){throw '请先添加图片或视频'}
    $d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='TFMEDIA3 镜像|*.img';$d.FileName='tf_media.img'
    if($d.ShowDialog() -eq 'OK') {
        Save-Json (Join-Path $script:temp 'subtitles.json') (Subtitle-Config)
        $a=@('pack')+@($list.Items)+@('-o',$d.FileName,'--subtitles',(Join-Path $script:temp 'subtitles.json'))
        if($audio.Checked){$a+='--audio'};Start-Task $a
    };$d.Dispose()
} catch {[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'生成镜像')}})
$inspect.Add_Click({try {$d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='镜像|*.img';if($d.ShowDialog() -eq 'OK'){Start-Task @('inspect',$d.FileName)};$d.Dispose()}catch{$status.Text=$_.Exception.Message}})
$write.Add_Click({try {
    if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '写入需要管理员权限。请以管理员身份运行 media.cmd。'}
    $d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='镜像|*.img';if($d.ShowDialog() -ne 'OK'){$d.Dispose();return};$image=$d.FileName;$d.Dispose()
    $disks=(& $taskPython (Join-Path $PSScriptRoot 'media_card.py') disks | Out-String)
    if($LASTEXITCODE -ne 0){throw '无法列出磁盘'}
    Add-Type -AssemblyName Microsoft.VisualBasic
    $number=[Microsoft.VisualBasic.Interaction]::InputBox("写入会覆盖目标磁盘全部数据。`r`n$disks`r`n请输入目标磁盘编号：",'选择TF卡','')
    if($number -notmatch '^\d+$'){return}
    $confirm=[Microsoft.VisualBasic.Interaction]::InputBox('再次输入磁盘编号确认覆盖：','确认TF卡','')
    if($confirm -ne $number){throw '两次编号不一致，已取消'}
    Start-Task @('write',$image,'--disk',$number,'--confirm-disk',$confirm)
}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'写入TF卡')}})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=50
$timer.Add_Tick({
    if($script:video){
        $frame=$script:video.TakeFrame();if($frame){Set-PreviewImage $frame}
        if($script:video.Ended){$err=$script:video.Error;Stop-Video;if($err){$status.Text='视频预览：'+$err}else{$status.Text='视频预览结束，可重播或输入秒数定位'}}
    }
    if($script:job -and $script:job.HasExited -and $script:jobOut.IsCompleted -and $script:jobErr.IsCompleted){
        $code=$script:job.ExitCode;$log.Text=$script:jobOut.Result+"`r`n"+$script:jobErr.Result
        $script:job.Dispose();$script:job=$null;$pack.Enabled=$true;$inspect.Enabled=$true;$write.Enabled=$true
        $status.Text=if($code -eq 0){'任务完成，结果见下方'}else{'任务失败，详细原因见下方'}
    }
})
$form.Add_FormClosing({param($sender,$eventArgs)
    if($script:job){$eventArgs.Cancel=$true;[void][Windows.Forms.MessageBox]::Show('制卡或写卡任务尚未结束，请等待完成后关闭。');return}
    $timer.Stop();Stop-Video;if($picture.Image){$picture.Image.Dispose()};if($subPicture.Image){$subPicture.Image.Dispose()}
})
if($SmokeTest) {
 $script:smokeStep=0;$script:smokeTicks=0
 $form.Add_Shown({$form.BeginInvoke([Action]{
  try {
   if($script:rows.Count -ne 10){throw 'Missing subtitle editors'}
   $script:rows[0].text.Text='测试字幕 FPGA'
   Save-Json (Join-Path $script:temp 'preview.json') @{text='测试字幕 FPGA';color='#22D3EE';rainbow=$false}
   Run-PreviewHelper 'subtitle' (Join-Path $script:temp 'preview.json') (Join-Path $script:temp 'subtitle.png')
   $subPicture.Image=Load-Png (Join-Path $script:temp 'subtitle.png')
   $tabs.SelectedIndex=1
   $bmp=New-Object Drawing.Bitmap($form.Width,$form.Height)
   $form.DrawToBitmap($bmp,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
   $bmp.Save((Join-Path $taskRoot 'build/gui-smoke.png'));$bmp.Dispose()
   $script:smokeImage=Join-Path $script:temp '预览图片.png'
   $im=New-Object Drawing.Bitmap(320,180);$g=[Drawing.Graphics]::FromImage($im);$g.Clear([Drawing.Color]::Blue);$g.Dispose();$im.Save($script:smokeImage);$im.Dispose()
   [void]$list.Items.Add($script:smokeImage);$list.SelectedIndex=0
   if(!$picture.Image -or $seek.Enabled){throw 'Image preview failed'}
   Write-Host 'PASS: ten subtitle editors, fixed font, image and subtitle preview with Chinese paths'
   $script:smokeVideo=Join-Path $script:temp '预览视频.mp4'
   & $taskFfmpeg -y -v error -f lavfi -i 'color=c=red:s=320x180:r=12:d=3' -c:v mpeg4 $script:smokeVideo
   if($LASTEXITCODE -ne 0){throw 'Preview test video generation failed'}
   Set-PreviewImage $null
   [void]$list.Items.Add($script:smokeVideo);$list.SelectedIndex=1
   $tabs.SelectedIndex=0;$script:smokeStep=1
  } catch {Write-Host $_; $script:smokeFailed=$true;$form.Close()}
 }) | Out-Null})
 $timer.Add_Tick({
  if($script:smokeStep -eq 0){return}
  try {
   $script:smokeTicks++
   if($script:smokeTicks -gt 300){throw 'Preview/task smoke test timed out'}
   if($script:smokeStep -eq 1 -and $picture.Image){
    $c=$picture.Image.GetPixel(240,180)
    if($c.R -lt 200 -or $c.B -gt 30){throw 'Video decoded wrong colors'}
    $script:smokeStep=2;Set-PreviewImage $null;Start-Video 1
   } elseif($script:smokeStep -eq 2 -and $picture.Image){
    Write-Host 'PASS: FFmpeg video frames and seek/restart with Chinese paths'
    $bmp=New-Object Drawing.Bitmap($form.Width,$form.Height)
    $form.DrawToBitmap($bmp,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
    $bmp.Save((Join-Path $taskRoot 'build/gui-media-smoke.png'));$bmp.Dispose()
    Stop-Video
    Save-Json (Join-Path $script:temp 'subtitles.json') (Subtitle-Config)
    Start-Task @('pack',$script:smokeImage,'-o',(Join-Path $script:temp 'smoke.img'),'--subtitles',(Join-Path $script:temp 'subtitles.json'))
    $script:smokeStep=3
   } elseif($script:smokeStep -eq 3 -and !$script:job){
    if($status.Text -ne '任务完成，结果见下方'){throw ('GUI pack failed: '+$log.Text)}
    Write-Host 'PASS: GUI asynchronous pack process, subtitle arguments and UTF-8 output'
    $script:smokeStep=0;$form.Close()
   }
  } catch {Write-Host $_;$script:smokeFailed=$true;Stop-Video;$script:smokeStep=0;$form.Close()}
 })
}
$timer.Start()
try {[void]$form.ShowDialog()}finally{$timer.Dispose();$mediaTip.Dispose();$form.Dispose()}

if($SmokeTest -and $script:smokeFailed){exit 1}
