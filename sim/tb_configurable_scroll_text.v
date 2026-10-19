`timescale 1ns/1ps
module tb_configurable_scroll_text;
reg clk=0,reader_clk=0,rst=1;always #5 clk=~clk;always #7 reader_clk=~reader_clk;
reg en=1,pic=1,we=0;reg [12:0] wa=0;reg [15:0] wd=0;
reg [35:0] packet=0;reg toggle=0;wire ack;
reg vs=0,de=0;reg [23:0] input_rgb=24'h8090a0;wire ovs,ode;wire [23:0] rgb;
configurable_scroll_text dut(clk,rst,reader_clk,en,pic,we,wa,wd,packet,toggle,ack,vs,de,input_rgb,ovs,ode,rgb);
wire user,last,axis_valid;wire [23:0] axis_rgb;
video_rgb_to_axis_640x480 axis(clk,rst,ovs,ode,rgb,user,axis_valid,last,axis_rgb);
integer i,xx,yy,offset,pixels=0,lines=0,starts=0,painted=0;reg [15:0] expected;
reg [1:0] history_de=0,history_vs=0;reg [23:0] history_rgb[0:1];
always @(negedge clk)if(!rst)begin
 if(ode!==history_de[1] || ovs!==history_vs[1])$fatal(1,"subtitle pipeline sync alignment");
 history_de={history_de[0],de};history_vs={history_vs[0],vs};
 if(axis_valid)begin pixels=pixels+1;if(last)lines=lines+1;if(user)starts=starts+1;end
end
task style;input [3:0] slot;input [5:0] n;input colorful;
 begin packet={1'b1,colorful,24'h22d3ee,n,slot};toggle=~toggle;wait(ack==toggle);repeat(4)@(negedge clk);end
endtask
task frame;input check_ink;input colorful;
 begin
  @(posedge clk);#1;vs=1;de=0;repeat(4)@(posedge clk);#1;vs=0;repeat(4)@(posedge clk);
  pixels=0;lines=0;starts=0;painted=0;
  for(yy=0;yy<480;yy=yy+1)begin
   for(xx=0;xx<640;xx=xx+1)begin
    #1;de=1;@(posedge clk);
    if(check_ink && xx>=3 && yy>=20 && yy<52 && xx<28)begin
     // Force a known phase at line start; x-2 is the output pixel.
     #1;
     offset=xx-1+dut.phase-640;
     expected=16'ha55a ^ (4608+(offset/32)*16+(yy-20)/2);
     if(!colorful && rgb!==(expected[15-(offset%32)/2] ? 24'h22d3ee : 24'h404850))
       $fatal(1,"custom glyph row/bit/color pipeline at %d,%d rgb=%h",xx,yy,rgb);
     if(rgb!=input_rgb)painted=painted+1;
    end
   end
   #1;de=0;repeat(6)@(posedge clk);
  end
  #1;de=0;repeat(8)@(posedge clk);#1;
  if(pixels!=307200 || lines!=480 || starts!=1)$fatal(1,"subtitle AXI geometry %d/%d/%d",pixels,lines,starts);
  if(check_ink && painted==0)$fatal(1,"custom bitmap invisible");
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 // Distinct rows exercise character, row and bit ordering in the last bank.
 for(i=4608;i<5120;i=i+1)begin @(negedge reader_clk);we=1;wa=i;wd=16'ha55a ^ i;end
 @(negedge reader_clk);we=0;
 style(9,32,0);frame(0,0);
 force dut.phase=11'd640;frame(1,0);release dut.phase;
 style(9,1,1);frame(0,1);force dut.phase=11'd640;frame(1,1);release dut.phase;
 // No custom data means the original ROM phrase, with matching geometry.
 packet=0;toggle=~toggle;wait(ack==toggle);frame(0,0);
 if(dut.frame_config[35]!==0)$fatal(1,"legacy fallback not selected");
 en=0;frame(0,0);if(dut.frame_enable!==0)$fatal(1,"SW3 disable");
 $display("PASS: custom subtitle RAM bank9, fixed/rainbow styles, 1/32 glyphs, default fallback and 640x480 AXI alignment");$finish;
end
initial begin #30000000;$fatal(1,"subtitle overlay timed out");end
endmodule
