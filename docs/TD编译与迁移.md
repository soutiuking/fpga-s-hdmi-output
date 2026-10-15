# TD 编译与迁移

工程器件为 EG4S20BG256。原验收构建版本是 Tang Dynasty 6.2.168116；请安装对应 EG4 器件支持、许可及 JTAG 驱动。TD 安装程序和授权不随工程分发。

## 推荐：命令行构建

```powershell
.\build.cmd -Target TFMEDIA3_Player -TdRoot 'E:\ANLU-TD'
.\build.cmd -Target hdmitest -TdRoot 'E:\ANLU-TD'
.\build.cmd -Target segtest -TdRoot 'E:\ANLU-TD'
```

`-TdRoot` 指安装根目录，下面应有 `bin/td_commands_prompt.exe`。也可设置环境变量 `TD_ROOT`，或将 TD bin 加入 PATH。脚本另检查常见安装位置。

`td_project/*.al` 为源文件列表的唯一编辑入口。构建脚本从 `.al` 生成本次 `.prj`，结合 `tools/td_flow/<目标>/` 中的已验证流程，在新的 `build/<目标>-<时间戳>/syn_1` 和 `phy_1` 中执行；不需要复制旧 Runs 缓存。跨目录引用按当前位置计算，只有临时构建文件含本机绝对路径。

主播放器使用已验证的 `set_param place seed 2`。脚本检查 TD 日志、bitgen 以及最终 SWNS/HWNS/STNS/HTNS。通过后将 bit 和时序报告复制到新的 `output/<目标>-<时间戳>/`；不覆盖 `firmware/` 中的实板基线。

仅检查文件引用和生成流程，不调用 TD：

```powershell
.\build.cmd -Target TFMEDIA3_Player -PrepareOnly
```

## TD GUI

在 TD 中打开 `td_project/TFMEDIA3_Player.al`，检查顶层 `tfmedia3_top` 和器件。其他两个工程为 `segtest.al`、`hdmitest.al`。所有源文件、IP 配置和管脚/时序约束均包含在包内，工程路径为相对路径。

GUI 可进行源文件浏览、编辑和综合/布局布线。GUI 自己生成的 `*_Runs` 不纳入 Git。GUI 若使用默认 seed，结果可能与命令行基线不同；验收或发布时建议使用上述脚本，以固定 seed 并检查最终时序。修改文件列表后保存 `.al`，再调用脚本。

## 迁移边界

- 拷贝整个目录或 Git clone 后运行 `setup.cmd`，不要单独拷贝 `.al`。
- 运行时和输出不提交 Git，另一台机器会在本地重新生成；离线依赖包随仓库和发布 ZIP 提供。
- 不需要 `D:\hdmi\redesign`、旧 `use`、旧写卡工具或原 `.tools`。
- 原 IP 文件顶部的厂家历史路径注释和原始验证报告中的路径属于来源记录，不是运行依赖。
- 同一板卡接线沿用现有约束；换板卡必须根据原理图修改管脚，不应直接套用。
- 每次构建使用新目录，不自动删除任何历史构建。初始化 `-Refresh` 也使用新目录，旧运行时由用户自行清理。
