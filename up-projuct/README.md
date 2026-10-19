# 比赛作品上传工程

本目录整理自 2026-10-19 用户确认测试通过的版本。仅整理目录、补充提交说明与校验清单，未修改 FPGA 源码、约束、IP、已验证 bit 或上位机功能文件。

## 文件入口

| 内容 | 入口 |
| --- | --- |
| 安路 TD 原生工程 | [TFMEDIA3_Player.al](FPGA_Project/td_project/TFMEDIA3_Player.al) |
| 工程说明、编译与文档索引 | [FPGA_Project/README.md](FPGA_Project/README.md) |
| 最终下载文件 | [13_player_hotplug.bit](FPGA_Project/firmware/13_player_hotplug.bit) |
| Windows x64 上位机 | `TF_Media_Tool/FPGA_TF_Media_Tool.exe` |
| 上位机操作说明 | [使用说明.txt](TF_Media_Tool/使用说明.txt) |
| 提交文件 SHA256 清单 | [SUBMISSION_MANIFEST.json](SUBMISSION_MANIFEST.json) |

请先完整解压再打开工程或运行程序；保持各目录相对位置。建议将工程放在较短的英文路径下。

上位机包含独立 Python、Tk、Pillow、FFmpeg 运行环境，无需另行安装 Python。请完整保留 `TF_Media_Tool` 文件夹，包括隐藏目录 `.runtime`。支持图片及视频预览、媒体排序、最多 10 条固定字体字幕、颜色/炫彩选择、TF 卡识别与镜像写入。实际写卡使用该目录内的“以管理员身份运行.bat”；写入将覆盖所选卡的数据，请按容量、型号及磁盘编号核对。

工程目录去除了编译缓存、旧 Runs、历史 bit、无关测试工程及本机开发环境。需要的厂家加密 IP、JPEG 解码源代码和许可证均已保留。安路 TD 软件、授权及 JTAG 驱动需自行安装。

原工程文档和验证记录按原文保留，其中的“待实板验收”、旧版本、旧路径及旧开发脚本说明属于生成当时的历史记录；本次用户已确认文件测试通过。当前提交范围与入口以本文件及 FPGA_Project/README.md 为准，未重新执行功能测试或编译。
