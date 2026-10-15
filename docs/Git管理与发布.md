# Git 管理与发布

`useing` 是独立 Git 仓库。源码、约束、TD 工程、文档、离线依赖、精简回归样本和三个有用途的固件纳入管理。构建数据库、Runs、运行时、波形、临时日志、用户媒体、生成镜像和发布压缩包被 `.gitignore` 排除；少量验收证据日志为明确保留项。

仓库不需要 Git LFS 和子模块。离线依赖压缩后作为必要分发文件管理，避免克隆后依赖原机器安装。调整依赖时同步更新 `vendor/manifest.json` 的来源、版本和 SHA256，不提交解压出的 `.runtime`。

## 日常操作

```powershell
git status --short
git diff
git add README.md tools user_source td_project docs sim
git diff --cached --stat
git commit -m 'Describe the change'
```

添加文件前检查暂存内容；通常不需要 `git add -f`。不要执行 `git clean`、`git reset --hard` 或自动清理脚本。被忽略的文件仍留在本地，由用户决定是否清理。

## 配置远程仓库

尚未提供远程地址，因此交付时只初始化本地 Git，不创建外部仓库或推送文件。用户准备好空远程仓库后执行：

```powershell
git remote add origin <你的仓库地址>
git push -u origin main
git push origin --tags
```

另一台 Windows x64 机器：

```powershell
git clone <你的仓库地址> useing
cd useing
.\setup.cmd
.\test.cmd
.\media.cmd inspect .\demo\bringup.img
.\build.cmd -TdRoot 'C:\Anlogic\TD'
```

硬件编译仍需安装 TD 及许可；播放已提供的固件则只需下载器及驱动。

## 制作交付压缩包

```powershell
.\package.cmd
```

打包器从当前 Git HEAD 导出受管理文件，拒绝工作区已跟踪文件的未提交修改及未忽略的新文件，避免遗漏更改。ZIP 使用统一顶层目录 `useing/`，内含提交号、清单和 SHA256 校验信息，不包含 `.git`、运行时或编译缓存。输出到 `dist/`，文件名带时间戳；已有包不会被删除或覆盖。

源码 ZIP 解压后可直接使用；若要继续版本管理，在解压目录运行 `git init -b main` 并自行提交，或直接 Git clone 以保留原提交历史。ZIP 和 clone 的功能文件一致，ZIP 额外包含该次打包的文件清单。

## 版本原则

`firmware/08_player_avsync.bit` 为实板验收基线，变更前保留旧文件，并使用新的文件名保存新固件。仅软件回归通过不等于新固件已实板验收；提交信息与测试记录应明确验证范围。
