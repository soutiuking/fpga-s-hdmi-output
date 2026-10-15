
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name board_clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给当前 tfmedia3_top 层次内的 PLL 输出命名
# ------------------------------------------------------------
rename_clock -name {reader_clk}  -source [get_ports {clk}] -master_clock {board_clk} [get_pins {u_reader_pll/pll_inst.clkc[3]}]
rename_clock -name {mem_clk}     -source [get_ports {clk}] -master_clock {board_clk} [get_pins {u_reader_pll/pll_inst.clkc[1]}]
rename_clock -name {mem_clk_sft} -source [get_ports {clk}] -master_clock {board_clk} [get_pins {u_reader_pll/pll_inst.clkc[2]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {board_clk} [get_pins {u_hdmi_shell/u_video_pll/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {board_clk} [get_pins {u_hdmi_shell/u_video_pll/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {board_clk} [get_pins {u_hdmi_shell/u_audio_pll/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk reader_clk mem_clk mem_clk_sft]

# 存储/按键/数码管域与 HDMI 像素域之间没有同步数据通路；后续接入帧缓冲时
# 必须通过异步 FIFO 或场同步握手，不能依赖本约束掩盖直接跨域。
set_clock_groups -asynchronous \
    -group [get_clocks {reader_clk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk mem_clk mem_clk_sft]

# Both frame-buffer FIFOs contain Gray-code synchronizers; their source and
# destination clocks are intentionally asynchronous.
set_clock_groups -asynchronous \
    -group [get_clocks {video_clk} hdmi_5x_clk] \
    -group [get_clocks {mem_clk} mem_clk_sft]

# The encrypted hard-SDRAM wrapper exposes internal pad timing arcs between
# its normal and 180-degree clocks.  Those arcs are implementation models, not
# user-register paths; the vendor controller owns their phase relationship.
set_false_path -from [get_clocks {mem_clk}] -to [get_clocks {mem_clk_sft}]
set_false_path -from [get_clocks {mem_clk_sft}] -to [get_clocks {mem_clk}]

# Explicit pairwise CDC cuts are kept as well because this TD release merges
# overlapping set_clock_groups statements instead of accumulating every pair.
set_false_path -from [get_clocks {reader_clk}] -to [get_clocks {audio_mclk}]
set_false_path -from [get_clocks {audio_mclk}] -to [get_clocks {reader_clk}]
set_false_path -from [get_clocks {reader_clk}] -to [get_clocks {mem_clk}]
set_false_path -from [get_clocks {mem_clk}] -to [get_clocks {reader_clk}]
set_false_path -from [get_clocks {video_clk}] -to [get_clocks {mem_clk}]
set_false_path -from [get_clocks {mem_clk}] -to [get_clocks {video_clk}]

# board_clk drives only the POR counter. Its output is an asynchronous reset
# assertion; reset_sync releases separately in each destination clock domain.
# Recovery/removal of the POR assertion is not a synchronous data transfer.
set_false_path -from [get_clocks {board_clk}] -to [get_clocks {reader_clk mem_clk mem_clk_sft video_clk hdmi_5x_clk audio_mclk}]

# ------------------------------------------------------------
# 6. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------
