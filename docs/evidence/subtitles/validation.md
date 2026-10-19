# 自定义字幕与上位机验证

日期：2026-10-19。器件：EG4S20BG256。源码主工程：`td_project/TFMEDIA3_Player.al`。

## 最终 FPGA 构建

- 命令：`build.cmd`。
- 构建编号：`20261019-202326-253`，TD 6.2.168116，seed 3，布线后显式 `fix_hold`。
- 输出：[12_player_subtitles.bit](../../../firmware/12_player_subtitles.bit)。SHA256：`2E29E6D99518CD7F1B960FE935F8156218F8B60901A93AE671D2DAA841907AF1`。
- 最终 SWNS 0.173 ns、HWNS 0.022 ns、STNS/HTNS 0，建立/保持违反端点均为 0，STA 覆盖率 99.95%。
- LUT 16812/19600，寄存器 10935/19600，BRAM9K 53/64，BRAM32K 16/16，DSP 29/29，PLL 3/4。
- 最终 MSlice 4883/4900，LSlice 4863/4900。首轮实现曾因 MSlice 超限失败，最终通过样式 BRAM、共享字幕流水线及图标点阵化解决，未删减原开关功能。
- 厂商 BRAM 在 Icarus 中采用同接口、同步读语义的行为模型；实际原语映射由 TD 综合/布线验证，电路实际效果待上板。

## 字幕专项

- `check_subtitles.py`：0/10 条、32 字、非法长度/颜色/布尔值、带字幕制卡/检查、空字幕的旧格式、三个位置的 CRC 损坏、中文路径图片预览。
- `tb_subtitle_loader`：来自上位机真实编码的 22 扇区，逐字比较全部 5120 个点阵 RAM 写入和全部 10 条样式；头/数据 CRC 错误、超时、无扩展指针、越界指针均回退。
- `tb_subtitle_select`：下一条/上一条循环、10 条样式、确认前邮箱保持、快速连续切换最终选择。
- `tb_configurable_scroll_text`：第 10 个字幕槽中逐行变化的点阵，验证字格、行、位和固定色对应；炫彩、1/32 字长度、默认回退、SW3 关闭以及完整 640×480 视频/AXI 同步。
- `tb_player_volume_control`：字幕按键消抖、按住仅一次、退出需松键、正常媒体按键隔离、SW0 设置优先。
- `check_top_recovery.py`：在实际顶层注入字幕数量，验证 SW3 对 S0/S1 的接管、双向切换及关闭后恢复下一媒体。
- 实际 reader/catalog/arbiter/metadata/DMA/audio/SRAM 行为链路，分别以正常字幕卡和坏字幕卡运行两轮三帧视频、暂停/恢复及并行音频流：正常字幕卡数量 10，坏头 CRC 卡数量 0，播放生命周期通过。

## 上位机实际启动

命令：`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/media_gui.ps1 -SmokeTest`。

在 Windows PowerShell 5.1 实际显示 WinForms 窗口并完成：

1. 验证 10 行字幕控件，中文固定字模与所选颜色预览。
2. 中文路径 PNG 图片预览、中文路径 MP4 视频实际输出帧及中心像素颜色检查。
3. 视频停止/重新启动与定位到第 1 秒后输出帧。
4. 界面启动异步生成带字幕镜像，参数传递、UTF-8 输出和返回码通过。

截图：[字幕编辑](subtitle-editor.png)、[媒体预览](media-preview.png)。本验证没有写入任何物理磁盘，也没有下载到实板。

## 既有播放器回归

`test.cmd` 快速回归通过，最终打印 `PASS: host pack/inspect, CRC rejection and requested RTL tests`。覆盖播放信息、音量/亮度/对比度、默认滚动文字、波形、图片融合、暂停图标、旧卡目录、SD 初始化、呈现 CDC、音画同步时间轴、PCM 环形缓冲、JPEG 输入尾部与间隙、顶层异常恢复、HDMI 完成事件，以及媒体自动重载和跳帧追赶。额外的完整 JPEG 软件像素对比本次未重跑。

字幕正常卡/坏卡的读取集成专项另行通过；其相同调用已加入后续 `test.cmd` 测试列表。最终 `check_project.py` 验证工程相对路径、固件及报告 SHA256、08 实板基线和离线依赖散列通过。
