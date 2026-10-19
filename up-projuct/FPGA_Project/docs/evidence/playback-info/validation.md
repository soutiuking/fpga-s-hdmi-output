# 播放信息验证记录

日期：2026-10-19。器件 EG4S20BG256，TD 6.2.168116。

- `test.cmd`：通过。包括制卡/检查/CRC、播放信息、音量/亮度/对比度、滚动文字、波形、图片渐变、暂停图标、音画同步、SRAM DMA、JPEG 输入间隙、顶层恢复、HDMI CDC、带音频读卡循环及落后帧追赶。
- 最终 `tb_playback_info_overlay`：通过，额外检查帧中切换开关须等到下一帧生效、源数据在跨域确认前保持不变。日志见 [specialized_rtl.log](specialized_rtl.log)。
- 最终 `check_top_recovery.py`：通过，包含 SW5～SW7 单独及同时启用、消抖和按键模式隔离。日志见 [top_wiring.log](top_wiring.log)。
- 本次没有运行 `test.cmd -Full` 的额外完整 JPEG 软件像素比较；JPEG 解码数据通路保持原实现。
- 标准 `build.cmd` 全新构建 `20261019-134147-651`：通过，seed 3，显式 `fix_hold`；SWNS 1.056 ns、HWNS 0.021 ns，STNS/HTNS 为 0。
- 最终构建报告及校验值见 [固件说明](../../../firmware/README.md)。
- 原生 720p 为架构评估，本次固件保持 640×480；未执行 720p 实板测量。
- 实板验收：待验证。
