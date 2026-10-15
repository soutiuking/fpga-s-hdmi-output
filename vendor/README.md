# 离线工具依赖

所有包由 `setup.cmd` 检查 SHA256 后解压到本地 `.runtime/`。来源及精确散列见 [manifest.json](manifest.json)。初始化无需网络和 pip。

| 组件 | 来源 / 用途 | 许可信息 |
|---|---|---|
| Python 3.12.10 Windows x64 embed | python.org 官方嵌入式分发，执行主机脚本 | 包内 Python 许可 |
| Pillow 11.3.0 cp312 win_amd64 | PyPI wheel，缩放/编码/检查图像 | wheel 内 dist-info/licenses |
| imageio-ffmpeg 0.6.0 Windows x64 | PyPI wheel，提供 FFmpeg 7.1 可执行文件，视频和 PCM 转码 | wrapper BSD；FFmpeg 另按其构建许可，见 wheel 中 binaries/README 和 FFmpeg `-L`、`-buildconf` |
| Icarus 10.1 / Windows 工具包 1.1.1 | 原本机使用的 FPGAwars/toolchain-iverilog 发行工具，保留 bin/lib/vlib/share/include | GPL-2.0-or-later；许可见 `IVERILOG_COPYING.txt`，发行来源 https://github.com/FPGAwars/toolchain-iverilog/releases，对应上游源码 https://github.com/steveicarus/iverilog/tree/v10_1 |

这些组件是可离线运行所需的分发依赖，因此纳入 Git；解压后的可执行文件和环境不纳入 Git。更换版本需重新验证转码格式、像素差及 RTL 回归。

TD 是独立安装的厂家 EDA 软件，不包含在这些依赖中。整个工程未附加统一开源许可；各第三方组件沿用自己的许可和署名。
