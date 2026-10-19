# 最终提交固件

使用 `13_player_hotplug.bit`，目标 EG4S20BG256，TD 6.2.168116，构建 20261019-215059-170，布局 seed 11。

SHA256：`F1C4E5998E8385385D529E2845D0864043395EBD5CA962037BF6B6D860791E5D`

| 指标 | 最终结果 |
| --- | --- |
| LUT | 16950 / 19600 |
| 寄存器 | 10939 / 19600 |
| BRAM9K | 53 / 64 |
| BRAM32K | 16 / 16 |
| DSP | 29 / 29 |
| PLL | 3 / 4 |
| MSlice | 4880 / 4900 |
| LSlice | 4876 / 4900 |
| SWNS / HWNS | 0.227 ns / 0.022 ns |
| STNS / HTNS | 0 ns / 0 ns |

报告：[资源](reports/13_player_hotplug/TFMEDIA3_Player_phy.area)、[时序](reports/13_player_hotplug/TFMEDIA3_Player_pr.timing)。

提交整理前用户确认全部文件测试通过。本次仅校验复制完整性和路径，不重新编译或改变已验证版本。历史版本固件未收录。
