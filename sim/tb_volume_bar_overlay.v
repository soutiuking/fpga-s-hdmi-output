`timescale 1ns/1ps
module tb_volume_bar_overlay;
reg clk=0, rst=1, enable=0, vs=0, de=0;
reg [4:0] gray=5'b11000;
reg bright_enable=0;
reg [4:0] bright_gray=5'b11000;
reg [23:0] rgb=24'h3868A0;
wire out_vs, out_de;
wire [23:0] out_rgb;
always #5 clk=~clk;
volume_bar_overlay dut(.clk(clk),.rst(rst),.enable_async(enable),
    .volume_gray_async(gray),.vs_in(vs),.de_in(de),.rgb_in(rgb),
    .brightness_enable_async(bright_enable),.brightness_gray_async(bright_gray),
    .contrast_enable_async(1'b0), .contrast_gray_async(5'd12),
    .vs_out(out_vs),.de_out(out_de),.rgb_out(out_rgb));
wire sof, valid, eol;
wire [23:0] axis_rgb;
video_rgb_to_axis_640x480 axis_dut(.I_clk(clk),.I_rst(rst),
    .I_vs(out_vs),.I_de(out_de),.I_rgb(out_rgb),
    .O_video_user(sof),.O_video_valid(valid),.O_video_last(eol),.O_video_data(axis_rgb));
integer count_pixels=0, count_lines=0, count_frames=0;
reg checking_axis=0;
always @(negedge clk) if(checking_axis && valid) begin
    count_pixels=count_pixels+1;
    if(sof) begin
        if(count_pixels!=1 || count_lines%480!=0) $fatal(1,"OSD shifted SOF");
        count_frames=count_frames+1;
    end
    if(eol) begin
        if(count_pixels!=640) $fatal(1,"OSD shifted EOL");
        count_pixels=0; count_lines=count_lines+1;
    end
end
task blank;
    begin
        @(negedge clk); de=0; vs=1;
        repeat(5) @(negedge clk);
        vs=0; repeat(5) @(negedge clk);
    end
endtask
task control;
    input integer level;
    input setting;
    begin
        @(negedge clk); gray=level^(level>>1); enable=setting;
        repeat(5) @(negedge clk);
    end
endtask
// A short synthetic frame advances animation without needing to scan pixels.
task tick_frame;
    begin
        blank;
        de=1;
        @(negedge clk); de=0;
        repeat(3) @(negedge clk);
    end
endtask
integer px,py,green_count, capture_file=0;
reg [1023:0] capture_path;
reg [23:0] original;
reg [23:0] expected_rgb;
integer gain=16;
function [7:0] reference_dim;
    input [7:0] value;
    input integer level;
    begin reference_dim=(value*level)/16; end
endfunction
task scan_frame;
    input integer width;
    input setting;
    input capture;
    begin
        blank;
        checking_axis=1;
        green_count=0;
        for(py=0;py<480;py=py+1) begin
            for(px=0;px<640;px=px+1) begin
                @(negedge clk); de=1;
                // Recognizable RGB gradient to expose passthrough/alignment errors.
                original={8'd48,px[8:1],py[8:1]}; rgb=original;
                expected_rgb={reference_dim(original[23:16],gain),reference_dim(original[15:8],gain),reference_dim(original[7:0],gain)};
                @(posedge clk); #1;
                if(!out_de || out_vs) $fatal(1,"OSD DE/VS misalignment");
                if(!setting || px<8 || px>=600 || py<420 || py>=468)
                    if(out_rgb!==expected_rgb) $fatal(1,"RGB brightness/passthrough at %d/%d: %h expected %h",px,py,out_rgb,expected_rgb);
                if(setting && px==31 && py==440 && out_rgb!==(bright_enable ? 24'hFBBF24 : 24'hE2E8F0))
                    $fatal(1,"missing speaker/sun glyph");
                if(setting && py==440 && px>=64 && px<576) begin
                    if(bright_enable) begin
                        if(out_rgb==24'hFBBF24 || out_rgb==24'hFDE68A) green_count=green_count+1;
                        else if(out_rgb!==24'h4B5563) $fatal(1,"brightness track must be gray");
                    end else begin
                        if(out_rgb==24'h2DD4BF || out_rgb==24'hA7F3D0) green_count=green_count+1;
                        else if(out_rgb!==24'h172B40) $fatal(1,"invalid track color");
                    end
                end
                if(capture && capture_file) $fwrite(capture_file,"%06x\n",out_rgb);
            end
            @(negedge clk); de=0;
            repeat(3) @(negedge clk);
        end
        repeat(5) @(negedge clk);
        checking_axis=0;
        if(setting && green_count!=width) $fatal(1,"fill width=%d expected=%d",green_count,width);
    end
endtask
integer i;
initial begin
    if($value$plusargs("capture=%s",capture_path)) capture_file=$fopen(capture_path,"w");
    repeat(5) @(negedge clk); rst=0;
    scan_frame(0,0,0);
    control(8,1);
    scan_frame(8,1,0); // First animation step, rather than an abrupt jump.
    for(i=0;i<30;i=i+1) tick_frame;
    scan_frame(256,1,1);
    control(7,1); tick_frame;
    if(dut.fill_width!=248) $fatal(1,"volume decrease did not animate by 8 pixels/frame");
    // Input changes mid-frame must not tear the bar.
    control(0,0);
    if(!dut.frame_enable || dut.fill_width!=248) $fatal(1,"control changed active frame");
    scan_frame(0,0,0);
    control(16,1);
    for(i=0;i<64;i=i+1) tick_frame;
    scan_frame(512,1,0);
    control(0,1);
    for(i=0;i<64;i=i+1) tick_frame;
    scan_frame(0,1,0);
    if(capture_file) begin $fclose(capture_file); capture_file=0; end
    control(0,0); bright_enable=1; bright_gray=5'b01100; gain=8;
    for(i=0;i<34;i=i+1) tick_frame;
    if($value$plusargs("brightness_capture=%s",capture_path)) capture_file=$fopen(capture_path,"w");
    scan_frame(256,1,1);
    bright_enable=0; repeat(5) @(negedge clk);
    scan_frame(0,0,0); // Brightness stays set after hiding the panel.
    bright_gray=0; gain=0; repeat(5) @(negedge clk);
    scan_frame(0,0,0); // Minimum brightness, with no OSD.
    if(count_lines!=9*480 || count_frames!=9 || count_pixels!=0)
        $fatal(1,"OSD AXI geometry changed: %d lines %d frames",count_lines,count_frames);
    if(capture_file) $fclose(capture_file);
    $display("PASS: volume OSD smooth increase/decrease, mute/full range, frame-latched visibility, RGB passthrough and 640x480 AXI alignment");
    $finish;
end
initial begin #50000000; $fatal(1,"OSD simulation timeout"); end
endmodule
