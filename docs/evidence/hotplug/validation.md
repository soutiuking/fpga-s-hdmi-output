# 13 版热插拔验证

生产 RTL 快速回归及热插拔专项全部通过，原始输出见 regression.log；结构化记录、源文件 SHA256、bit SHA256 及时序见 validation.json。

TD 构建 20261019-215059-170，seed 11，保持原时钟和时序约束，布线后显式 fix_hold。最终 SWNS 0.227 ns、HWNS 0.022 ns，STNS/HTNS 均为 0，STA 覆盖率 99.95%。资源 LUT 16950、寄存器 10939、BRAM9K 53、BRAM32K 16、DSP 29、PLL 3；MSlice 4880/4900、LSlice 4876/4900。

专项用两个实际生成的 TFMEDIA3 镜像验证连续无卡重试、上电后插卡、读扇区时拔卡、拒绝损坏超级块和更换无字幕卡。只替换 SD 协议模型，采用生产目录、元数据、字幕、DMA、音频缓冲及 SRAM 控制。顶层和 HDMI shell 故障注入验证媒体复位、静音及 HDMI 复位隔离。其余快速回归含字幕、全部开关、叠加、PCM 时间轴、视频两轮播放与追帧。未额外运行完整 JPEG 软件像素比较。

此前 seed 3 存在布线冲突，seed 7 存在 -0.099 ns 建立违例，未发布。仅 11 的最终通过结果复制为 firmware/13_player_hotplug.bit。板卡实际插拔、电源及 HDMI 连续输出仍待用户实板验收。
