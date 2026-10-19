`timescale 1ns/1ps
module tb_playback_info_overlay;
reg reader_clk=0,clk=0,reader_rst=1,rst=1;
always #7 reader_clk=~reader_clk;
always #11 clk=~clk;
reg [31:0] position=1875,length=3750,rate=25;
reg [4:0] index=9,count=20;
reg valid=1;
reg [2:0] enable=0;
reg vs=0,de=0;
wire ovs,ode;wire [23:0] rgb;
playback_info_overlay dut(.reader_clk(reader_clk),.reader_rst(reader_rst),
    .position(position),.length(length),.ticks_per_second(rate),
    .media_index(index),.media_count(count),.valid(valid),
    .clk(clk),.rst(rst),.enable_async(enable),.vs_in(vs),.de_in(de),
    .rgb_in(24'h8090A0),.vs_out(ovs),.de_out(ode),.rgb_out(rgb));
wire user,last,axis_valid;wire [23:0] axis_rgb;
video_rgb_to_axis_640x480 axis(.I_clk(clk),.I_rst(rst),.I_vs(ovs),.I_de(ode),.I_rgb(rgb),
    .O_video_user(user),.O_video_last(last),.O_video_valid(axis_valid),.O_video_data(axis_rgb));
reg [57:0] previous_packet=0;
reg previous_publish=0;
always @(negedge reader_clk) begin
    if(!reader_rst && previous_publish==dut.publish && dut.publish!=dut.ack_sync && dut.packet!==previous_packet)
        $fatal(1,"source packet changed before CDC acknowledgement");
    previous_packet=dut.packet;previous_publish=dut.publish;
end
integer pixels=0,lines=0,starts=0;
always @(negedge clk) if(axis_valid) begin
    pixels=pixels+1;if(last)lines=lines+1;if(user)starts=starts+1;
end
task settle;
    begin repeat(1300)@(negedge reader_clk);repeat(10)@(negedge clk);end
endtask
task stats;
    input [31:0] expected_time;
    input [8:0] expected_progress;
    begin
        settle;
        if(dut.pending[31:0]!==expected_time || dut.pending[56:48]!==expected_progress)
            $fatal(1,"stats got time=%h progress=%d expected=%h/%d",dut.pending[31:0],dut.pending[56:48],expected_time,expected_progress);
    end
endtask
integer xx,yy,changed,ink_pixels;
reg inside_panel;
task frame;
    input [2:0] mask;
    begin
        enable=mask;repeat(8)@(negedge clk);
        vs=1;repeat(4)@(negedge clk);vs=0;repeat(4)@(negedge clk);
        pixels=0;lines=0;starts=0;changed=0;ink_pixels=0;
        for(yy=0;yy<480;yy=yy+1) begin
            if(mask==7 && yy==100) enable=0; // Must take effect next frame.
            for(xx=0;xx<640;xx=xx+1)begin
                de=1;@(posedge clk);#1;
                if(ode!==1 || ovs!==0)$fatal(1,"video controls misaligned");
                inside_panel=(mask[0] && xx>=64 && xx<576 && yy>=404 && yy<412) ||
                    (mask[0] && xx>=48 && xx<60 && yy>=400 && yy<416) ||
                    (mask[1] && xx>=512 && xx<560 && yy>=352 && yy<368) ||
                    (mask[1] && xx>=492 && xx<508 && yy>=352 && yy<368) ||
                    (mask[2] && xx>=448 && xx<560 && yy>=376 && yy<392) ||
                    (mask[2] && xx>=428 && xx<444 && yy>=376 && yy<392);
                if(rgb!=24'h8090A0)begin
                    changed=changed+1;
                    if(!inside_panel)$fatal(1,"pixel changed outside enabled panel %d/%d",xx,yy);
                end
                if(rgb==24'hE2E8F0)ink_pixels=ink_pixels+1;
                if(mask[0] && yy==405 && xx==64 && rgb!=24'h22D3EE)$fatal(1,"missing progress fill");
                if(mask[0] && yy==405 && xx==575 && rgb!=24'h475569)$fatal(1,"wrong progress end");
                @(negedge clk);
            end
            de=0;repeat(8)@(negedge clk);
        end
        repeat(8)@(negedge clk);
        if(pixels!=307200 || lines!=480 || starts!=1)
            $fatal(1,"AXI frame damaged pixels=%d lines=%d starts=%d",pixels,lines,starts);
        if(mask==0 && changed!=0)$fatal(1,"disabled overlay changed image");
        if(mask!=0 && changed==0)$fatal(1,"enabled overlay missing");
        if((mask[1] || mask[2]) && ink_pixels<40)$fatal(1,"digits not rendered");
    end
endtask
initial begin
    #37;reader_rst=0;rst=0;
    stats(32'h01150230,9'd256);
    if(dut.pending[47:32]!=16'h1020 || !dut.pending[57])$fatal(1,"media count/valid");
    frame(0);frame(1);frame(2);frame(4);frame(7);
    // Holding the source playhead is exactly what the paused scheduler does.
    stats(32'h01150230,9'd256);
    position=0;index=0;stats(32'h00000230,0);
    position=3750;stats(32'h02300230,511);
    position=4000;stats(32'h02300230,511);
    // Image timer is in reader clock ticks, not video frames.
    position=60000000;length=120000000;rate=40000000;
    stats(32'h00010003,256);
    // Large frame counters exercise the 41-bit progress numerator and clamp.
    position=32'h40000000;length=32'h80000000;rate=25;
    stats(32'h99599959,256);
    length=0;rate=0;position=0;settle;
    if(dut.pending[57])$fatal(1,"empty metadata marked valid");
    length=100;rate=25;valid=0;settle;
    if(dut.pending[57])$fatal(1,"media change did not invalidate packet");
    $display("PASS: playback info arithmetic, coherent CDC, pause/seek/switch, image/video time, individual switches and AXI alignment");
    $finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
