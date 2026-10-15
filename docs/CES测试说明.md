# CES 素材测试

> 本文为原 CES 素材验证记录。以下 `D:/hdmi` 路径仅用于追溯，不属于独立包运行依赖；私人原始素材和完整 CES 镜像未打入本包。当前固件为 `firmware/08_player_avsync.bit`，通用测试镜像为 `demo/bringup.img`，实际操作以根目录 README 和 `测试流程.md` 为准。

输入目录：`D:/hdmi/CES`。源文件未修改。
生成镜像：`D:/hdmi/redesign/output/ces_test.img`，33,030,656 字节，64,513 扇区。

播放顺序：

1. `【哲风壁纸】中二病-小鸟游六花.jpg`，转为 640×480、32,582 字节 JPEG，显示约 3 秒。
2. `屏幕截图 2026-10-13 161908.png`，35,294 字节 JPEG，显示约 3 秒。
3. `jizeruwei-logo-final.png`，14,178 字节 JPEG，显示约 3 秒。
4. `抖音20261011-979547.mp4`，转为 640×480、25 fps、1,393 帧，约 55.72 秒，之后循环。

图片保持比例加黑边。视频每帧预算 28,000 字节，实际最大 27,993 字节。
本轮采用脚本默认无音轨，先验证图片/视频显示。
上板连续 25 fps 仍取决于卡延迟及解码耗时，需要实测。

建议先只下载本轮修复后的播放器，保留现有 TF 卡验证，避免同时改变两个条件。
当前验收文件：`D:/hdmi/redesign/output/08_player_avsync.bit`。
07 已由用户确认连续视频与切换流畅，但后半段声音领先画面；08 使用 PCM 样本主时间轴、未来帧等待及过期帧追赶，详见 `音画同步.md`。2026-10-15，用户实板测试 08 后反馈“我很满意”，据此记录验收；实际帧率及音画偏差尚未定量测量。
05 实板仍黑屏，读数 `346000A0` / `346000A5`，表示停在输入握手。
06 将每帧复位寄存，并使用标准 Huffman 固定表以移除动态表加载/查找通路。它仍需实板验证。
CES 镜像所有 1396 帧及旧工具镜像所有 1395 帧均通过新增标准表格式检查；已有镜像无需因这次固定表修改而重新生成。
06 固定表真实核的视频首帧 → logo → 视频首帧连续解码与三幅 RGB 比较全部通过，日志 `sim/fixed_huffman_sequence.log`。该仿真使用 SRAM/SDRAM 行为应答，不替代实板验证。
06 用户反馈视频先动几帧，随后 `32350229`，声音继续且无法自动切换。定位到旧视频零基第 4 帧字节 18672 的 `C0 xx xx FF` 字：输入 VALID=0 时解析器错误组合出 `FF C0` 并清除尺寸。07 给标记判断增加 VALID 条件，SOF/长度寄存器只在字节接收时更新。`sim/legacy_frame4_parser_before.log` 复现尺寸 0/0，`sim/legacy_frame4_parser_after.log` 修复后保持 640×480。
`sim/jpeg_gap_fix_quick.log` 增加带音频 SD 竞争的六帧播放与末帧自动重载检查。
板上 S0 请求下一媒体，S1 暂停/继续，RESET 重新开始。
需要使用新镜像时，在管理员 PowerShell 中先核对物理磁盘号：

```powershell
python D:/hdmi/redesign/tools/media_card.py disks
python D:/hdmi/redesign/tools/media_card.py inspect D:/hdmi/redesign/output/ces_test.img
# N 替换成 TF 卡的物理磁盘号；写入会覆盖该卡原分区和数据。
python D:/hdmi/redesign/tools/media_card.py write D:/hdmi/redesign/output/ces_test.img --disk N --confirm-disk N
```

镜像应写入物理盘，不能仅复制成普通文件；Windows 提示格式化时取消。
当前未执行物理写卡。

回归记录：`sim/ces_pack.log` 包含全部 JPEG 的软件解码检查。
`sim/ces_picture_rtl.log` 和 `sim/ces_video_rtl.log` 分别记录新镜像首张图片、视频首帧的真实 RTL 解码和软件像素对比。
其中 `ces_picture_rtl.log` 为最初严格 MAE<1 失败记录；当前四种尾部对齐完整验证通过记录为 `sim/ces_alignments_fixed.log`。
`sim/ces_sequence_reset.log` 用于检查 logo → 壁纸 → logo 的连续解码和像素结果。

JPEG 尾字节问题修复位于 `third_party/core_jpeg/src_v/jpeg_input.v`。
修复后，最后一字按 strobe 依次接收有效字节，到最后有效字节才结束，避免丢弃 JPEG 的 FF D9 结束标记。
每帧输入前还会清理解码核状态；若已超时，按 S0 可清除失败解码器并继续下一媒体。
`sim/jpeg_final_quick.log` 已通过目录、SD 首请求、DMA、帧页、末字节四种对齐、超时冻结、换媒体恢复及视频调度检查。
图片 RGB 曾因严格的 MAE < 1 阈值失败，但完整像素数正确。核采用近似整数 IDCT，改用与核一致的最近邻色度参考后，自然图片 MAE=1.426634/255、PSNR=43.353 dB；均已如实记录，不将其宣称为逐像素完全相同。
