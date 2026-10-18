# 固件与版本

| 固件 | 用途 | 验证状态 |
|---|---|---|
| [01_segtest.bit](01_segtest.bit) | 八位数码管测试 | 历史测试固件 |
| [02_hdmitest.bit](02_hdmitest.bit) | HDMI 连线与显示测试 | 历史测试固件 |
| [08_player_avsync.bit](08_player_avsync.bit) | 音画同步播放器基线 | 已由用户实板验收 |
| [09_player_sw0_sw4.bit](09_player_sw0_sw4.bit) | 当前 SW0～SW4 扩展播放器 | RTL 与 TD 时序通过，实板待验收 |

09 版沿用 08 的媒体格式和引脚基础，增加音量、亮度、对比度设置，以及顶部彩色滚动文字和左侧音频波形。开关及操作见 [拨码说明](../docs/拨码开关与音量.md)。设置在当前通电期间保持，复位或断电后恢复默认。

所有受管理固件及 09 报告的 SHA256 见 [manifest.json](manifest.json)，`test.cmd` 的工程检查会验证清单。每次发布新增文件名，保留 08 实板基线。报告保留 TD 原始字节，避免换行转换影响校验。

## 09 构建结果

器件 EG4S20BG256，工具 TD 6.2.168116，主工程 `td_project/TFMEDIA3_Player.al`。本次构建编号 `20261018-115830-770`。

| 资源 | 已用 / 总量 | 剩余 |
|---|---:|---:|
| LUT | 14681 / 19600 | 4919 |
| 寄存器 | 9454 / 19600 | 10146 |
| BRAM9K | 37 / 64 | 27 |
| BRAM32K | 16 / 16 | 0 |
| DSP | 29 / 29 | 0 |
| PLL | 3 / 4 | 1 |

最终建立裕量 0.923 ns、保持裕量 0.004 ns，STNS/HTNS 均为 0。报告：[最终时序](reports/09_player_sw0_sw4/TFMEDIA3_Player_pr.timing)、[最终资源](reports/09_player_sw0_sw4/TFMEDIA3_Player_phy.area)。DSP 和 BRAM32K 已满，后续扩展应检查布局和时序，不能只依据单项剩余量。

```powershell
.\setup.cmd
.\test.cmd -Full
.\build.cmd -Target TFMEDIA3_Player -TdRoot 'E:\ANLU-TD'
```

新的构建输出自动包含 bit、时序及资源报告，位于独立的 `output/` 子目录。发布时选择通过时序检查的结果，新增固件及报告，更新校验清单与验证记录。字体 Verilog 已提交，常规构建不需要字体文件；只有重新生成字模才使用 `tools/generate_scroll_font.py --font <字体路径>`。
