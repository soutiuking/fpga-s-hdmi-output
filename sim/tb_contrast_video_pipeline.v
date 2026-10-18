`timescale 1ns/1ps
module tb_contrast_video_pipeline;
reg clk=0,rst=1,vs=0,de=0;
reg [23:0] rgb=0;
reg [4:0] gray=12;
wire cv,cd,ov,od;
wire [23:0] cr,orr;
wire sof,valid,eol;
wire [23:0] axis_rgb;
always #5 clk=~clk;
video_contrast_stage contrast(.clk(clk),.rst(rst),.contrast_gray_async(gray),
    .vs_in(vs),.de_in(de),.rgb_in(rgb),.vs_out(cv),.de_out(cd),.rgb_out(cr));
volume_bar_overlay overlay(.clk(clk),.rst(rst),.enable_async(1'b0),
    .volume_gray_async(5'd24),.brightness_enable_async(1'b0),.brightness_gray_async(5'd24),
    .contrast_enable_async(1'b1),.contrast_gray_async(gray),
    .vs_in(cv),.de_in(cd),.rgb_in(cr),.vs_out(ov),.de_out(od),.rgb_out(orr));
video_rgb_to_axis_640x480 axis(.I_clk(clk),.I_rst(rst),.I_vs(ov),.I_de(od),.I_rgb(orr),
    .O_video_user(sof),.O_video_valid(valid),.O_video_last(eol),.O_video_data(axis_rgb));
function [7:0] reference;
    input integer c,g;
    integer v;
    begin v=128+(((c-128)*g) >>> 3); reference=v<0?0:v>255?255:v; end
endfunction
integer gx=0,gy=0,gain=8;
reg [23:0] expected1,expected2;
reg valid1=0,valid2=0;
integer x1,y1,x2,y2;
integer purple_pixels=0,gray_pixels=0,icon_pixels=0;
always @(posedge clk) begin
    expected1 <= {reference(rgb[23:16],gain),reference(rgb[15:8],gain),reference(rgb[7:0],gain)};
    expected2 <= expected1;
    valid1<=de;valid2<=valid1;
    x1<=gx;y1<=gy;x2<=x1;y2<=y1;
    #1;
    if(!rst && valid2) begin
        if(!od) $fatal(1,"contrast pipeline lost DE");
        if(y2<420 || y2>=468 || x2<8 || x2>=600)
            if(orr!==expected2) $fatal(1,"contrast pipeline pixel mismatch %d/%d: %h expected %h",x2,y2,orr,expected2);
        if(y2==440 && x2>=64 && x2<576) begin
            if(orr==24'hA78BFA || orr==24'hDDD6FE) purple_pixels=purple_pixels+1;
            else if(orr==24'h4B5563) gray_pixels=gray_pixels+1;
            else $fatal(1,"contrast OSD palette");
        end
        if(x2>=24 && x2<40 && y2>=436 && y2<452 && orr==24'hC4B5FD) icon_pixels=icon_pixels+1;
    end
end
integer pixels=0,lines=0,frames=0;
always @(negedge clk) if(!rst && valid) begin
    pixels=pixels+1;
    if(sof) begin
        if(pixels!=1 || lines%480!=0) $fatal(1,"contrast SOF");
        frames=frames+1;
    end
    if(eol) begin
        if(pixels!=640) $fatal(1,"contrast EOL");
        pixels=0;lines=lines+1;
    end
end
integer f,x,y,capture=0;
reg [1023:0] path;
initial begin
    if($value$plusargs("capture=%s",path)) capture=$fopen(path,"w");
    repeat(5) @(negedge clk);rst=0;
    for(f=0;f<2;f=f+1) begin
        de=0;vs=1;gain=f==0?8:16;gray=gain^(gain>>1);
        repeat(5) @(negedge clk);vs=0;repeat(5) @(negedge clk);
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk);de=1;gx=x;gy=y;rgb={x[8:1],y[8:1],8'd160};
            end
            @(negedge clk);de=0;repeat(5) @(negedge clk);
        end
        repeat(5) @(negedge clk);
    end
    if(lines!=960 || frames!=2 || pixels!=0 || purple_pixels==0 || gray_pixels==0 || icon_pixels==0)
        $fatal(1,"contrast pipeline geometry/OSD missing");
    if(capture) $fclose(capture);
    $display("PASS: production contrast -> brightness/OSD -> AXI pipeline, 2 full frames, purple/gray palette and contrast icon");
    $finish;
end
always @(negedge clk) if(capture && od && gain==16) $fwrite(capture,"%06x\n",orr);
initial begin #20000000; $fatal(1,"contrast pipeline timeout"); end
endmodule
