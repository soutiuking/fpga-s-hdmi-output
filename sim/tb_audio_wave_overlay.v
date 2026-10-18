`timescale 1ns/1ps
module tb_audio_wave_overlay;
reg clk=0,rst=1,enable=0,sv=0,vs=0,de=0;
reg [23:0] sample=0,rgb=24'h406080;
wire ov,od; wire [23:0] pixel;
always #5 clk=~clk;
audio_wave_overlay dut(.clk(clk),.rst(rst),.enable_async(enable),
    .sample_valid(sv),.sample_data(sample),.vs_in(vs),.de_in(de),.rgb_in(rgb),
    .vs_out(ov),.de_out(od),.rgb_out(pixel));
wire sof,valid,eol; wire [23:0] axis_rgb;
video_rgb_to_axis_640x480 axis(.I_clk(clk),.I_rst(rst),.I_vs(ov),.I_de(od),.I_rgb(pixel),
    .O_video_user(sof),.O_video_valid(valid),.O_video_last(eol),.O_video_data(axis_rgb));
integer pixels=0,lines=0,frames=0;
reg checking=0;
always @(negedge clk) if(checking && valid) begin
    pixels=pixels+1;
    if(sof) begin
        if(pixels!=1 || lines%480!=0) $fatal(1,"wave SOF");
        frames=frames+1;
    end
    if(eol) begin
        if(pixels!=640) $fatal(1,"wave EOL");
        pixels=0;lines=lines+1;
    end
end
task send_sample;
    input integer value;
    begin
        @(negedge clk);sv=1;sample=value*65536;
        @(negedge clk);sv=0;
    end
endtask
task blank;
    begin
        @(negedge clk);de=0;vs=1;
        repeat(5) @(negedge clk);vs=0;
        repeat(5) @(negedge clk);
    end
endtask
task commit;
    begin
        blank;
        de=1;@(negedge clk);de=0;
        repeat(4) @(negedge clk);
    end
endtask
integer x,y,j,k,amp,idx,lo,hi,fh=0;
reg [15:0] frozen;
reg [23:0] expected;
reg [1023:0] path;
task scan;
    input on;
    input capture;
    begin
        blank;checking=1;
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk);de=1;
                rgb={x[8:1],y[8:1],8'd128};
                @(posedge clk);#1;
                if(!od || ov || dut.frame_enable!==on) $fatal(1,"wave sync/enable");
                expected=rgb;
                if(on) begin
                    if(x>=8 && x<152 && y>=88 && y<376)
                        expected={2'b00,rgb[23:18],2'b00,rgb[15:10],2'b00,rgb[7:2]};
                    if(x>=16 && x<144 && y>=104 && y<=360) begin
                        if(y==104 || y==168 || y==232 || y==296 || y==360 || x%32==16)
                            expected=y==232 ? 24'h64748B : 24'h263A50;
                        idx=31-(x-16)/4;
                        lo=$signed(dut.history[idx][15:8]);
                        hi=$signed(dut.history[idx][7:0]);
                        if(y>=232-hi && y<=232-lo)
                            expected=(y==232-hi || y==232-lo) ? 24'hA7F3D0 : 24'h2DD4BF;
                    end
                    if(x>=8 && x<152 && y>=88 && y<376 && (x==8 || x==151 || y==88 || y==375))
                        expected=24'h38BDF8;
                end
                if(pixel!==expected) $fatal(1,"wave pixel %0d,%0d got %h expected %h",x,y,pixel,expected);
                if(capture && fh) $fwrite(fh,"%06x\n",pixel);
            end
            @(negedge clk);de=0;repeat(5) @(negedge clk);
        end
        repeat(5) @(negedge clk);checking=0;
    end
endtask
initial begin
    if($value$plusargs("capture=%s",path)) fh=$fopen(path,"w");
    repeat(5) @(negedge clk);rst=0;
    send_sample(-128);
    for(j=1;j<47;j=j+1) send_sample(0);
    if(dut.history[0]!==0 || !dut.have_sample) $fatal(1,"history changed outside frame boundary");
    send_sample(127);
    commit;
    if(dut.history[0]!==16'h807f || dut.have_sample) $fatal(1,"signed extrema/last sample");
    repeat(100) @(negedge clk);
    if(dut.history[0]!==16'h807f) $fatal(1,"shift without sample");
    for(j=0;j<32;j=j+1) begin
        amp=8+((j<16 ? j : 31-j)*6);
        for(k=0;k<48;k=k+1) send_sample(k%2 ? amp : -amp);
        commit;
    end
    if(dut.history[0]!==16'hf808 || dut.history[31]!==16'hf808 || dut.history[16]!==16'h9e62)
        $fatal(1,"history order/32 bin rollover");
    scan(0,0);
    enable=1;scan(1,1);
    frozen=dut.history[0];
    for(j=0;j<48;j=j+1) send_sample(0);
    if(dut.history[0]!==frozen || !dut.have_sample) $fatal(1,"frame history changed during audio update");
    scan(1,0);
    if(dut.history[0]!==0) $fatal(1,"history not refreshed");
    for(j=0;j<32;j=j+1) begin send_sample(0);commit;end
    scan(1,0);
    for(j=0;j<32;j=j+1) if(dut.history[j]!==0) $fatal(1,"silence history");
    enable=0;scan(0,0);
    if(lines!=5*480 || frames!=5 || pixels!=0) $fatal(1,"wave AXI frame dimensions");
    send_sample(-128);
    blank;de=1;sv=1;sample=24'h7f0000;
    @(posedge clk);#1;
    if(dut.history[0]!==16'h807f) $fatal(1,"sample coincident with frame commit lost");
    @(negedge clk);de=0;sv=0;
    if(fh) $fclose(fh);
    $display("PASS: waveform signed extrema, frame bins, 32-bin history, stable scans, silence, pixel rendering, enable and AXI alignment");
    $finish;
end
endmodule
