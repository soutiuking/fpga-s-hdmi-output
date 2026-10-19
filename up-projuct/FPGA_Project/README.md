# TFMEDIA3 FPGA 播放器（比赛提交版）

器件：EG4S20BG256。工具：Anlogic Tang Dynasty 6.2.168116。顶层：`tfmedia3_top`。

## 打开与下载

使用 TD 打开 [td_project/TFMEDIA3_Player.al](td_project/TFMEDIA3_Player.al)。项目保持原生相对路径，源码、管脚/时序约束以及引用 IP 都在本目录内。请复制完整目录，不要单独移动 `.al`。

已通过测试的最终文件为 [firmware/13_player_hotplug.bit](firmware/13_player_hotplug.bit)。其 SHA256 和资源/时序结果见 [固件说明](firmware/README.md)。

## 复现编译

在本目录运行：

```powershell
.\build.cmd -Target TFMEDIA3_Player -PlaceSeed 11 -TdRoot 'C:\Anlogic\TD'
```

将 `-TdRoot` 改为实际 TD 安装根目录，也可使用环境变量 `TD_ROOT`。保留的原构建脚本采用布局 seed 11、布线后显式 `fix_hold`，并检查最终时序；新的构建结果写入 `build/` 和 `output/`。TD GUI 默认流程的参数可能不同，复现已验证流程请使用该脚本。本包仅包含主播放器，不包含历史 segtest/hdmitest 目标。

## 功能与操作

媒体规格为 640×480、25 fps，支持图片、视频及 PCM 音频。上位机生成 TF 镜像，支持最多 10 条固定字体点阵字幕。无字幕数据时使用板上默认文字。

| 开关 | 功能 |
| --- | --- |
| SW0 | 音量设置 |
| SW1 | 亮度设置 |
| SW2 | 对比度设置 |
| SW3 | 字幕显示；有自定义字幕且未进入其他设置时，S0 下一条、S1 上一条 |
| SW4 | 音频波形 |
| SW5 | 播放进度条 |
| SW6 | 当前媒体序号 / 总数 |
| SW7 | 已播放时间 / 总时长 |

未进入设置或字幕选择模式时，S0 切换媒体，S1 暂停/继续。SW0～SW2 设置时 S0 增加、S1 减少。开关低电平有效。

无卡上电会等待并重试；读取超时后停止播放、静音并清除旧卡有效状态；重新插入有效卡后从第一项媒体开始。自动恢复保持 HDMI 时钟和输出链路。没有独立卡座检测引脚，暂停且没有读请求时要等下一次实际读取才发现拔卡。

## 原工程 Markdown 文档

- [拨码开关与音量](docs/拨码开关与音量.md)
- [自定义字幕与上位机](docs/自定义字幕与上位机.md)
- [TF 卡热插拔与自动恢复](docs/TF卡热插拔与自动恢复.md)
- [TFMEDIA3 镜像格式](docs/TFMEDIA3_FORMAT.md)
- [资源与扩展建议](docs/资源与扩展建议.md)
- [播放信息与 720p 评估](docs/720p评估与播放信息.md)
- [已有热插拔验证记录](docs/evidence/hotplug/validation.md)

`docs/` 保留了全部原有文档和证据，包含历史版本/开发流程的说明。旧固件、旧测试目标以及本地开发环境不在本提交包内；这些历史引用不作为本包运行依赖。已验证的功能文件未作更改。
