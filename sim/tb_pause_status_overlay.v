`timescale 1ns/1ps
module tb_pause_status_overlay;
reg clk=0,rst=1,vs=0,de=0;
reg [1:0] status=0;
reg [23:0] rgb;
wire ov,od;wire [23:0] pixel;
always #5 clk=~clk;
pause_status_overlay dut(.clk(clk),.rst(rst),.status_async(status),
    .vs_in(vs),.de_in(de),.rgb_in(rgb),.vs_out(ov),.de_out(od),.rgb_out(pixel));
wire valid,sof,eol;wire [23:0] axis_rgb;
video_rgb_to_axis_640x480 axis(.I_clk(clk),.I_rst(rst),.I_vs(ov),.I_de(od),.I_rgb(pixel),
    .O_video_user(sof),.O_video_valid(valid),.O_video_last(eol),.O_video_data(axis_rgb));
integer pixels=0,lines=0,frames=0;
reg checking=0;
always @(negedge clk) if(checking && valid) begin
    pixels=pixels+1;
    if(sof) begin if(pixels!=1 || lines%480!=0) $fatal(1,"pause SOF");frames=frames+1;end
    if(eol) begin if(pixels!=640) $fatal(1,"pause EOL");pixels=0;lines=lines+1;end
end
integer x,y,lit,fh=0;
reg [1023:0] path;
reg [23:0] expected;
reg ink;
task scan;
    input [1:0] mode;
    input capture;
    begin
        @(negedge clk);status=mode;vs=1;de=0;
        repeat(6) @(negedge clk);vs=0;
        repeat(6) @(negedge clk);checking=1;lit=0;
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk);de=1;rgb={x[8:1],y[8:1],8'd128};
                // Changing the asynchronous status during the scan must not
                // tear or hide an icon until the following frame.
                if(x==300 && y==240) status=0;
                @(posedge clk);#1;
                if(!od || ov || dut.frame_status!==mode) $fatal(1,"pause sync/frame latch");
                expected=rgb;ink=0;
                if(mode!=0 && x>=8 && x<72 && y>=384 && y<416) begin
                    expected={2'b0,rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2]};
                    if(mode==1) ink=y>=392 && y<408 && ((x>=24 && x<32)||(x>=40 && x<48));
                    if(mode==2) ink=(x>=16 && x<40 && ((y>=392 && y<394)||(y>=406 && y<408))) ||
                        (y>=392 && y<408 && ((x>=16 && x<18)||(x>=38 && x<40))) ||
                        (x>=32 && x<36 && y>=394 && y<398) ||
                        (y>=400 && y<402 && x>=24 && x<28) ||
                        (y>=402 && y<406 && x>=20 && x<36) ||
                        (y>=392 && y<408 && ((x>=48 && x<52)||(x>=60 && x<64)));
                    if(ink) begin expected=mode==1 ? 24'h67E8F9 : 24'hFBBF24;lit=lit+1;end
                end
                if(pixel!==expected) $fatal(1,"pause pixel %0d,%0d",x,y);
                if(capture && fh) $fwrite(fh,"%06x\n",pixel);
            end
            @(negedge clk);de=0;repeat(5) @(negedge clk);
        end
        repeat(5) @(negedge clk);checking=0;
        if(mode!=0 && lit<100) $fatal(1,"missing pause icon");
    end
endtask
initial begin
    if($value$plusargs("capture=%s",path)) fh=$fopen(path,"w");
    repeat(5) @(negedge clk);rst=0;
    scan(0,0);scan(1,1);scan(2,1);scan(0,0);
    if(lines!=1920 || frames!=4 || pixels!=0) $fatal(1,"pause AXI dimensions");
    if(fh) $fclose(fh);
    $display("PASS: video pause and slideshow stopped icons, frame-latched status, outside pixels and four full AXI frames");
    $finish;
end
endmodule
