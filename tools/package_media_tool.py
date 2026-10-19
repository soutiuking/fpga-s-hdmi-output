"""Build the standalone Tk tool from verified offline archives."""
from datetime import datetime
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import zipfile
ROOT = Path(__file__).resolve().parents[1]

def dependencies():
    items = json.loads((ROOT/'vendor/gui-manifest.json').read_text(encoding='utf-8'))
    items += [d for d in json.loads((ROOT/'vendor/manifest.json').read_text(encoding='utf-8')) if d['file'].startswith('imageio_ffmpeg')]
    for item in items:
        archive = ROOT/'vendor'/item['file']
        if archive.stat().st_size != item['bytes'] or hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Dependency verification failed: '+archive.name)
    return items

def extract_runtime(target, items, tools_path):
    python = target/'python'
    for item in items:
        destination = python/'Lib/site-packages' if item.get('kind') == 'wheel' or item['file'].startswith('imageio_ffmpeg') else python
        with zipfile.ZipFile(ROOT/'vendor'/item['file']) as archive:
            archive.extractall(destination)
    (python/'python311._pth').write_text(f'python311.zip\n.\nLib/site-packages\n{tools_path}\nimport site\n', encoding='utf-8')
    ffmpeg = next((python/'Lib/site-packages/imageio_ffmpeg/binaries').glob('ffmpeg*.exe'))
    return python/'python.exe', ffmpeg

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--setup', action='store_true')
    args = parser.parse_args()
    items = dependencies()
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    if args.setup:
        target = ROOT/'.runtime'/('gui-bundle-'+stamp)
        python, ffmpeg = extract_runtime(target, items, '../../../tools')
        config = dict(python=python.relative_to(ROOT).as_posix(), ffmpeg=ffmpeg.relative_to(ROOT).as_posix())
        (ROOT/'.runtime/gui-current.json').write_text(json.dumps(config, indent=2), encoding='utf-8')
        print(python, flush=True)
        return
    target = ROOT/'dist'/('FPGA_TF_Media_Tool_Windows_x64_字幕增强版-'+stamp)
    target.mkdir(parents=True, exist_ok=False)
    for folder in ['tools', 'demo', 'docs', 'build']:
        (target/folder).mkdir()
    for name in ['media_card.py', 'subtitles.py', 'jpeg_profile.py', 'media_gui_tk.py']:
        shutil.copy2(ROOT/'tools'/name, target/'tools'/name)
    for name in ['自定义字幕与上位机.md', 'TFMEDIA3_FORMAT.md']:
        shutil.copy2(ROOT/'docs'/name, target/'docs'/name)
    shutil.copy2(ROOT/'demo/subtitles.json', target/'demo/subtitles.json')
    python, ffmpeg = extract_runtime(target/'.runtime', items, '../../tools')
    config = dict(python=python.relative_to(target).as_posix(), ffmpeg=ffmpeg.relative_to(target).as_posix())
    (target/'.runtime/current.json').write_text(json.dumps(config, indent=2), encoding='utf-8')
    (target/'media.cmd').write_text('@echo off\r\nsetlocal\r\nset "PYTHONUTF8=1"\r\n"%~dp0.runtime\\python\\python.exe" "%~dp0tools\\media_card.py" %*\r\n', encoding='ascii')
    (target/'以管理员身份运行.bat').write_text('@echo off\r\nset "TFMEDIA_LAUNCHER=%~dp0FPGA_TF_Media_Tool.exe"\r\npowershell.exe -NoProfile -Command "Start-Process -FilePath $env:TFMEDIA_LAUNCHER -Verb RunAs"\r\n', encoding='ascii')
    env = os.environ.copy()
    env['TFMEDIA_LAUNCH_SOURCE'] = str(ROOT/'tools/MediaToolLauncher.cs')
    env['TFMEDIA_LAUNCH_OUTPUT'] = str(target/'FPGA_TF_Media_Tool.exe')
    subprocess.run(['powershell.exe', '-NoProfile', '-Command', 'Add-Type -Path $env:TFMEDIA_LAUNCH_SOURCE -OutputAssembly $env:TFMEDIA_LAUNCH_OUTPUT -OutputType WindowsApplication -ReferencedAssemblies System.Windows.Forms'], check=True, env=env)
    (target/'使用说明.txt').write_text('''FPGA TF 媒体制作工具 · 字幕增强版

双击 FPGA_TF_Media_Tool.exe。无需安装 Python、FFmpeg 或 FPGA 工程。
复制到其他电脑时必须复制整个文件夹，包含 .runtime 和 tools。
支持 Windows 10/11 x64，默认字体为 Windows 黑体 SimHei。

1. 添加图片或视频，上移/下移调整播放顺序。图片自动预览；视频自动静音播放，可重播、停止或输入秒数定位。
2. “字幕设置”支持最多 10 条、每条 32 字，可逐条选颜色或炫彩、预览、保存/载入配置。全部为空则使用板上默认字幕。
3. 选择输出镜像路径。“仅生成镜像”不操作 TF 卡；“检查镜像”验证镜像数据。
4. 插入读卡器后刷新，按盘符、卷标、容量、型号、物理磁盘编号核对目标。
   不会自动选择设备；裸卡可能无盘符。USB 设备也可能是移动硬盘，请核对容量和型号。
   仅在启动、设备插拔和手动刷新时查询，空闲期间不定时启动 PowerShell。
5. 写卡会覆盖整张目标卡。写卡时请使用“以管理员身份运行.bat”。
   勾选目标确认后选择“生成并写入 TF 卡”或“写入已有镜像”，最终弹窗需输入“磁盘 N”。
   拔卡或身份变化会清除确认；写入前重新核对设备身份，写入后全量回读 SHA256 校验。

媒体格式保持 640×480、25 fps，最多 10 张图片和 10 个视频，默认保留音轨。
自定义字幕需 12 版或更新固件；SW3 开启字幕后，S0 下一条、S1 上一条，SW0～SW2 的设置优先。
本文件夹提供电脑工具，不包含板卡固件。视频预览静音不影响镜像保留音轨。

命令行：
media.cmd pack 图片.png 视频.mp4 --audio --subtitles demo/subtitles.json -o 我的镜像.img
media.cmd inspect 我的镜像.img
media.cmd disks

DEPENDENCIES.json 记录依赖来源与 SHA256；运行时内保留许可证。
MANIFEST.json 是交付时文件清单；build 用于自动验证输出。
''', encoding='utf-8-sig')
    (target/'DEPENDENCIES.json').write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding='utf-8')
    records = [dict(path=p.relative_to(target).as_posix(), bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(target.rglob('*')) if p.is_file()]
    (target/'MANIFEST.json').write_text(json.dumps(dict(files=records), ensure_ascii=False, indent=2), encoding='utf-8')
    print(target, flush=True)

if __name__ == '__main__':
    main()
