`timescale 1ns/1ps
module tb_subtitle_select;
reg clk=0,rst=1;always #5 clk=~clk;
reg [3:0] count=0;reg [59:0] lengths=0;reg [239:0] colors=0;reg [9:0] rainbow=0;
reg next=0,prev=0,ack=0;wire toggle;wire [35:0] packet;wire [3:0] selected;
reg [30:0] style;
always @(posedge clk)style<={rainbow[selected],colors[selected*24+:24],lengths[selected*6+:6]};
subtitle_select dut(clk,rst,count,style,next,prev,ack,toggle,packet,selected);
integer i;reg [35:0] held;
task press;input backwards;begin @(negedge clk);next=!backwards;prev=backwards;@(negedge clk);next=0;prev=0;repeat(3)@(negedge clk);end endtask
task receive;begin repeat(4)@(negedge clk);ack=toggle;repeat(6)@(negedge clk);end endtask
initial begin
 for(i=0;i<10;i=i+1)begin lengths[i*6+:6]=i+1;colors[i*24+:24]=24'h102030+i;rainbow[i]=i%2;end
 repeat(3)@(negedge clk);rst=0;count=10;repeat(5)@(negedge clk);
 held=packet;
 press(1);if(selected!=9 || packet!==held)$fatal(1,"wrap/mailbox held");
 receive;receive;
 if(packet!=={1'b1,1'b1,24'h102039,6'd10,4'd9})$fatal(1,"wrong selected style");
 press(0);if(selected!=0)$fatal(1,"next wrap");receive;receive;
 for(i=0;i<7;i=i+1)press(0);
 receive;receive;if(packet[3:0]!=7 || selected!=7)$fatal(1,"latest rapid selection lost");
 count=0;receive;receive;if(packet[35]!=0 || selected!=0)$fatal(1,"fallback invalid packet");
 $display("PASS: ten subtitle selections, wrap both ways, stable CDC mailbox and latest rapid selection");$finish;
end
endmodule
