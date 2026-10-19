# 固件与版本

| 固件 | 用途 | 验证状态 |
|---|---|---|
| [01_segtest.bit](01_segtest.bit) | 八位数码管测试 | 历史测试固件 |
| [02_hdmitest.bit](02_hdmitest.bit) | HDMI 连线与显示测试 | 历史测试固件 |
| [08_player_avsync.bit](08_player_avsync.bit) | 音画同步播放器基线 | 已由用户实板验收 |
| [09_player_sw0_sw4.bit](09_player_sw0_sw4.bit) | SW0～SW4 扩展播放器 | RTL 与 TD 时序通过，实板待验收 |
| [13_player_hotplug.bit](13_player_hotplug.bit) | 当前：无卡重试、拔卡超时恢复、保留 HDMI 输出；包含 12 全部功能 | 快速回归、热插拔专项与 TD 时序通过，实板待验收 |
| [12_player_subtitles.bit](12_player_subtitles.bit) | 历史：自定义字幕与全部开关；480p | 快速回归、字幕专项及 TD 时序通过，实板待验收 |
| [11_player_playback_info.bit](11_player_playback_info.bit) | SW0～SW7、播放信息、图片交叉渐变及暂停标志；480p | RTL 与 TD 时序通过，实板待验收 |
| [10_player_picture_blend.bit](10_player_picture_blend.bit) |图片交叉渐变、暂停标志及 SW0～SW4 | RTL 专项与 TD 时序通过，实板待验收 |

09 版沿用 08 的媒体格式和引脚基础，增加音量、亮度、对比度设置，以及顶部彩色滚动文字和左侧音频波形。开关及操作见 [拨码说明](../docs/拨码开关与音量.md)。设置在当前通电期间保持，复位或断电后恢复默认。

所有受管理固件及报告的 SHA256 见 [manifest.json](manifest.json)，`test.cmd` 的工程检查会验证清单。每次发布新增文件名，保留 08 实板基线。报告保留 TD 原始字节，避免换行转换影响校验。

## 13 当前构建结果

增加无卡上电自动重试、读取超时后静音并清空播放状态、换卡重新加载目录/字幕与首项媒体。保持 HDMI 时序、PHY 和 PLL；音量、亮度及对比度保留。无卡初始化最多约 5 秒，单扇区看门狗约 2 秒，恢复等待约 1 秒。无独立卡检测引脚，暂停且无读取时需恢复播放后才检测拔卡。详见 [操作与验证](../docs/TF卡热插拔与自动恢复.md)。

构建 `20261019-215059-170`，seed 11，布线后显式 `fix_hold`；SWNS=0.227 ns、HWNS=0.022 ns，STNS/HTNS=0，STA 覆盖率 99.95%。未放宽原时序约束或降低时钟。

| 资源 | 已用 / 总量 | 剩余 |
|---|---:|---:|
| LUT | 16950 / 19600 | 2650 |
| 寄存器 | 10939 / 19600 | 8661 |
| BRAM9K | 53 / 64 | 11 |
| BRAM32K | 16 / 16 | 0 |
| DSP | 29 / 29 | 0 |
| PLL | 3 / 4 | 1 |
| MSlice | 4880 / 4900 | 20 |
| LSlice | 4876 / 4900 | 24 |

相比 12 版最终多 138 LUT、4 个寄存器，BRAM、DSP、PLL 不变。布局种子和逻辑打包不同，MSlice 数量会变化；剩余布局空间依然很少。

报告：[最终资源](reports/13_player_hotplug/TFMEDIA3_Player_phy.area)、[最终时序](reports/13_player_hotplug/TFMEDIA3_Player_pr.timing)。SHA256：`F1C4E5998E8385385D529E2845D0864043395EBD5CA962037BF6B6D860791E5D`。实板插拔与 HDMI 持续连接待验收，12 版及 08 基线保留。

`test.cmd` 快速回归、热插拔专项与顶层/HDMI CDC 恢复检查全部通过；[验证记录](../docs/evidence/hotplug/validation.md)。

复现构建：`build.cmd -Target TFMEDIA3_Player -PlaceSeed 11`。种子 3 出现一处布线冲突；种子 7 最终建立裕量为 -0.099 ns，均未发布。

## 12 历史构建结果

上位机固定黑体生成最多 10 条、每条 32 字的单色点阵随卡写入，支持逐条选择颜色或炫彩；SW3 ON 时 S0 下一条、S1 上一条，SW0～SW2 设置优先。没有字幕数据时沿用默认文字和原按键。上位机已提供图片预览、静音视频播放及秒数定位。见 [操作说明](../docs/自定义字幕与上位机.md)。

构建 `20261019-202326-253`，seed 3，布线后显式 `fix_hold`；SWNS=0.173 ns，HWNS=0.022 ns，STNS/HTNS=0，STA 覆盖率 99.95%。

| 资源 | 已用 / 总量 | 剩余 |
|---|---:|---:|
| LUT | 16812 / 19600 | 2788 |
| 寄存器 | 10935 / 19600 | 8665 |
| BRAM9K | 53 / 64 | 11 |
| BRAM32K | 16 / 16 | 0 |
| DSP | 29 / 29 | 0 |
| PLL | 3 / 4 | 1 |

相比 11 版净增 311 LUT、484 寄存器、13 BRAM9K。字幕与默认文字共用渲染流水线，时钟图标改为固定点阵，字幕样式放入 RAM，以避免逻辑打包超限。MSlice 4883/4900、LSlice 4863/4900，实际打包余量很小，不能只按 LUT 剩余量判断还能扩展多少。

报告：[最终资源](reports/12_player_subtitles/TFMEDIA3_Player_phy.area)、[最终时序](reports/12_player_subtitles/TFMEDIA3_Player_pr.timing)。SHA256：`2E29E6D99518CD7F1B960FE935F8156218F8B60901A93AE671D2DAA841907AF1`。硬件验收待完成，08 基线与历史固件保留。

## 11 历史构建结果

拨下 SW5 显示进度条、SW6 显示当前媒体/总数、SW7 显示已播放/总时间；各开关独立，可同时启用，不占按键。视频复用音画同步时间轴，图片按三秒轮播计时，暂停冻结。已有 480p TF 卡可继续使用。原生 720p25 未启用，原因及操作见 [720p 评估与播放信息](../docs/720p评估与播放信息.md)。

构建编号 `20261019-134147-651`，TD 6.2.168116，布局 seed 3，布线后显式 `fix_hold`；保持原时序约束。SWNS=1.056 ns、HWNS=0.021 ns、STNS/HTNS=0，STA 覆盖率 99.95%。

| 资源 | 已用 / 总量 | 剩余 |
|---|---:|---:|
| LUT | 16501 / 19600 | 3099 |
| 寄存器 | 10451 / 19600 | 9149 |
| BRAM9K | 40 / 64 | 24 |
| BRAM32K | 16 / 16 | 0 |
| DSP | 29 / 29 | 0 |
| PLL | 3 / 4 | 1 |

相比 10 版最终增加 1368 LUT、595 寄存器，其余以上资源不变。报告：[最终资源](reports/11_player_playback_info/TFMEDIA3_Player_phy.area)、[最终时序](reports/11_player_playback_info/TFMEDIA3_Player_pr.timing)。SHA256：`E7938A5028E902CEECF25CBF6E720DA21B1178F0FD63B91337F3EB42AD573992`。

`test.cmd` 快速回归、最终播放信息专项及顶层开关回归通过；[验证记录](../docs/evidence/playback-info/validation.md)。本次未执行额外的完整 JPEG 软件像素比较。实际显示和按键/开关效果仍待实板验收。

## 10 历史构建结果

只有图片切到图片时才进行约 0.27 秒交叉融合，视频帧和跨类型切换直接呈现。左下角自动区分视频暂停与图片停止轮播；详见 [功能说明](../docs/图片交叉渐变与暂停标志.md)。不增加拨码占用。

构建编号 `20261018-234804-566`，器件 EG4S20BG256，工具 TD 6.2.168116。

| 资源 | 已用 / 总量 | 剩余 |
|---|---:|---:|
| LUT | 15133 / 19600 | 4467 |
| 寄存器 | 9856 / 19600 | 9744 |
| BRAM9K | 40 / 64 | 24 |
| BRAM32K | 16 / 16 | 0 |
| DSP | 29 / 29 | 0 |
| PLL | 3 / 4 | 1 |

相比 09 版增加 452 LUT、402 寄存器和 3 个 BRAM9K，DSP、BRAM32K、PLL 用量不变。最终 SWNS=1.729 ns、HWNS=0.003 ns、STNS/HTNS=0。

报告：[最终时序](reports/10_player_picture_blend/TFMEDIA3_Player_pr.timing)、[最终资源](reports/10_player_picture_blend/TFMEDIA3_Player_phy.area)。SHA256：`52331418584EF189AAA4286D787ADE5F35986CBAC59C486EF884C5B75788A70A`。RTL 专项回归和最终时序均通过，实际 SDRAM 带宽与视觉效果待实板验收。

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
