`timescale 1ns/1ps
// Source mailbox holds an entire style/selection packet until acknowledged.
module subtitle_select(input clk,rst,input [3:0] count,input [30:0] style_data,
 input next_pulse,prev_pulse,
 input ack_async,output reg toggle,output reg [35:0] packet,output reg [3:0] selected);
reg ack_meta,ack_sync;reg [3:0] selected_d;
wire valid=count!=0;
wire [35:0] desired={valid,valid ? style_data : 31'd0,selected};
always @(posedge clk or posedge rst)begin
 if(rst)begin selected_d<=0;selected<=0;toggle<=0;packet<=0;ack_meta<=0;ack_sync<=0;end
 else begin
  selected_d<=selected;ack_meta<=ack_async;ack_sync<=ack_meta;
  if(!valid)selected<=0;
  else if(next_pulse && !prev_pulse)selected<=selected+1>=count ? 4'd0 : selected+1'b1;
  else if(prev_pulse && !next_pulse)selected<=selected==0 ? count-1'b1 : selected-1'b1;
  if(toggle==ack_sync && selected_d==selected && packet!=desired)begin packet<=desired;toggle<=~toggle;end
 end
end
endmodule
