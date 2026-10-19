`timescale 1ns/1ps
// sim/check_hdmi_cdc.py supplies inert peripheral shells to exercise the
// actual CDC registers in the production HDMI shell.
module tb_frame_finish_cdc;
reg reader_clk = 0, mem_clk = 0, rst = 1, completion = 0, media_reset=0,audio_enable=1;
always #12.5 reader_clk = ~reader_clk;
always #4 mem_clk = ~mem_clk;
wire finish;
integer received = 0;
reg previous = 0;
tfmedia3_hdmi_shell dut(.clk(reader_clk), .reader_clk(reader_clk),
    .mem_clk(mem_clk), .rst(rst), .media_reset(media_reset),.audio_enable(audio_enable),.frame_write_finish(finish),
    .volume_setting(1'b0), .volume_level(5'd16),
    .brightness_setting(1'b0), .brightness_level(5'd16),
    .contrast_setting(1'b0), .contrast_level(5'd8),
    .scroll_setting(1'b0), .picture_playing(1'b0), .wave_setting(1'b0),
    .display_picture(1'b0),.pause_status(2'd0));
always @(posedge reader_clk) begin
    if (!rst) begin
        if (finish && previous) $fatal(1, "Completion wider than one cycle");
        if (finish) received = received + 1;
        previous <= finish;
    end
end
integer i;
initial begin
    force dut.audio_pll_lock = 1'b1;
    force dut.video_clk = reader_clk;
    force dut.frame_write_finish_mem = completion;
    #51 rst = 0;
    wait(!dut.rst_reader && !dut.rst_mem);
    repeat(4) @(negedge reader_clk);
    // 8 ns events sweep all relative phases of the two clocks.
    for (i=0; i<25; i=i+1) begin
        @(negedge mem_clk); completion = 1;
        @(negedge mem_clk); completion = 0;
        #200;
    end
    #200;
    if (received != 25) $fatal(1, "Lost CDC completions: %0d/25", received);
    $display("PASS: all 25 eight-ns completion events cross 125 MHz to 40 MHz exactly once");
    @(negedge reader_clk);media_reset=1;audio_enable=0;
    repeat(5)@(negedge reader_clk);
    if(!dut.media_rst_mem || !dut.media_rst_reader || !dut.media_rst_video || dut.rst_all || dut.rst_mem || dut.rst_reader)
        $fatal(1,"media retry reset leaked into HDMI/global reset or failed to clear page CDC");
    if(dut.audio_enable_sync!=0 || dut.frame_write_finish_toggle!=0 || dut.frame_write_finish_sync!=0 || finish)
        $fatal(1,"retry did not mute or clear completion events");
    media_reset=0;
    repeat(8)@(negedge reader_clk);
    if(dut.media_rst_mem || dut.media_rst_reader || dut.media_rst_video || finish || received!=25)
        $fatal(1,"retry release generated stale completion/reset");
    @(negedge mem_clk);completion=1;
    @(negedge mem_clk);completion=0;
    repeat(8)@(negedge reader_clk);
    if(received!=26)$fatal(1,"new-card completion lost after retry");
    $display("PASS: production HDMI shell resets storage/page CDC and mutes without resetting video timing, PHY or clocks; new completions survive");
    $finish;
end
endmodule
