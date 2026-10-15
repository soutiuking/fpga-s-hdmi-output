# 写卡工具

推荐在工程根目录运行 `setup.cmd` 初始化包内离线 Python、Pillow 和 FFmpeg，再运行 `media.cmd`。双击 `media.cmd` 提供菜单和媒体选择窗口；命令行便于明确播放顺序。无需旧写卡工具。

```powershell
.\setup.cmd
.\media.cmd pack 'C:\media\test.png' 'C:\media\clip.mp4' --audio -o .\output\tf_media.img
.\media.cmd inspect .\output\tf_media.img
```

输入顺序即轮播顺序。图片自动保持比例加黑边、转 RGB、640×480、baseline JPEG 4:2:0，使用标准 Huffman 表（`optimize=False`）。06 固件采用固定表解码器；验证器会拒绝优化/自定义 Huffman 表、非标准扫描映射、多扫描和 restart interval，避免软件能读而 FPGA 无法解码的镜像。
视频转 25 fps，默认单帧不超过 28000 字节，质量从 75 向下调整；过于复杂的帧无法压入预算时明确报错。
`--quality 85` 改最高质量；`--max-frame-bytes 32000` 改视频预算；硬上限 65536。
默认不存音轨。`--audio` 输出 48 kHz 单声道 PCM；无音轨时补静音。`--max-frames 50` 用于短测试。
FFmpeg 自动使用包内初始化的版本，也支持 `--ffmpeg 'C:\tools\ffmpeg.exe'` 指定其他版本。

生成后会完整检查超级块/元数据 CRC、区域重叠、帧表边界、所有 JPEG 的尺寸和采样格式。
验证器也兼容旧 `tf_media.img`。`inspect` 不写 TF 卡。

实际写卡仅在管理员终端执行：

```powershell
.\media.cmd disks
# 根据上一个命令核对 TF 读卡器的物理磁盘号。下面的 N 必须替换为实际卡号。
.\media.cmd write .\output\tf_media.img --disk N --confirm-disk N
```

写卡覆盖目标卡原分区和数据，Windows 后续提示格式化时取消。
脚本拒绝系统盘、启动盘、非 USB/SD/MMC 盘、只读盘和存放镜像本身的盘，锁定/卸载已有盘符后写入，执行 SHA256 全量回读。
实际物理卡写入未在本次软件测试中执行。部分读卡器若无法锁盘会明确报错，不能当作写入成功。

## 工程构建与仿真

```powershell
.\build.cmd -Target segtest -TdRoot 'E:\ANLU-TD'
.\build.cmd -Target TFMEDIA3_Player -TdRoot 'E:\ANLU-TD'
.\test.cmd
.\test.cmd -Full
```

以上命令均从工程根目录执行。TD 支持 `-TdRoot`、`TD_ROOT` 或 PATH；输出在 `output/<目标>-<时间戳>/`。验收固件固定保存在 `firmware/`。

如选择系统 Python 而不使用离线入口，需要 Python 3.10+、Pillow（`python -m pip install -r tools/requirements.txt`）及 FFmpeg，脚本路径为 `tools/media_card.py`。
