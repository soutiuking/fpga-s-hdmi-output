`timescale 1ns/1ps
// Boot-only optional data. Any corruption or timeout falls back to the ROM
// phrase without preventing normal media playback. No SD traffic after done.
module subtitle_loader #(parameter TIMEOUT_CLKS=80000000)(
 input clk,rst,start,input [31:0] base_lba,total_sectors,
 output reg sd_read,output reg [31:0] sd_addr,
 input [7:0] sd_data,input sd_valid,sd_end,
 output reg done,output reg [3:0] count,
 input [3:0] style_index,output [30:0] style_data,
 output reg ram_we,output reg [12:0] ram_address,output reg [15:0] ram_data
);
reg [2:0] state;
reg [4:0] sector;
reg [9:0] byte_count;
reg [13:0] payload_bytes;
reg [7:0] low_byte;
reg [31:0] crc,stored_crc,timer;
reg format_ok;
function [31:0] crc_next;
 input [31:0] previous;input [7:0] b;
 reg [31:0] v;integer k;
 begin v=previous^{24'd0,b};for(k=0;k<8;k=k+1) v=v[0]?(v>>1)^32'hEDB88320:v>>1;crc_next=v;end
endfunction
wire [3:0] entry=(byte_count-16)>>3;
reg [5:0] entry_length;reg entry_rainbow;reg [15:0] entry_rg;
wire style_we=state==2 && sd_valid && sector==0 && byte_count>=16 && byte_count<96 && byte_count[2:0]==4;
subtitle_style_bram u_styles(.clk(clk),.write_enable(style_we),.write_address(entry),
 .write_data({entry_rainbow,entry_rg,sd_data,entry_length}),.read_address(style_index),.read_data(style_data));
always @(posedge clk or posedge rst) begin
 if(rst)begin
  state<=0;sector<=0;byte_count<=0;payload_bytes<=0;low_byte<=0;crc<=0;stored_crc<=0;timer<=0;
  entry_length<=0;entry_rainbow<=0;entry_rg<=0;format_ok<=1;sd_read<=0;sd_addr<=0;done<=0;count<=0;
  ram_we<=0;ram_address<=0;ram_data<=0;
 end else begin
  sd_read<=0;ram_we<=0;
  case(state)
   0:if(start)begin
      if(base_lba==0 || total_sectors<22 || base_lba>total_sectors-22)begin done<=1;state<=4;end
      else begin sd_addr<=base_lba;state<=1;end
   end
   1:begin sd_read<=1;byte_count<=0;crc<=32'hffffffff;stored_crc<=0;timer<=0;state<=2;end
   2:begin
    timer<=timer+1'b1;
    if(sd_valid)begin
     byte_count<=byte_count+1'b1;
     if(byte_count<508)crc<=crc_next(crc,sd_data);
     case(byte_count)
      508:stored_crc[7:0]<=sd_data;509:stored_crc[15:8]<=sd_data;
      510:stored_crc[23:16]<=sd_data;511:stored_crc[31:24]<=sd_data;
      default:;
     endcase
     if(byte_count>=512) format_ok<=0;
     if(sector==0)begin
      case(byte_count)
       0:if(sd_data!="T")format_ok<=0;1:if(sd_data!="F")format_ok<=0;
       2:if(sd_data!="S")format_ok<=0;3:if(sd_data!="U")format_ok<=0;
       4:if(sd_data!="B")format_ok<=0;5:if(sd_data!="1")format_ok<=0;
       6,7:if(sd_data!=0)format_ok<=0;
       8:if(sd_data!=1)format_ok<=0;
       9:begin count<=sd_data[3:0];if(sd_data==0 || sd_data>10)format_ok<=0;end
       10:if(sd_data!=32)format_ok<=0;11:if(sd_data!=16)format_ok<=0;
       default:;
      endcase
      if(byte_count>=16 && byte_count<96)case(byte_count[2:0])
       0:begin entry_length<=sd_data[5:0];if(entry<count && (sd_data==0 || sd_data>32))format_ok<=0;end
       1:begin entry_rainbow<=sd_data[0];if(sd_data>1)format_ok<=0;end
       2:entry_rg[15:8]<=sd_data;
       3:entry_rg[7:0]<=sd_data;
       default:;
      endcase
     end else if(byte_count<504 && payload_bytes<10240)begin
      payload_bytes<=payload_bytes+1'b1;
      if(!payload_bytes[0]) low_byte<=sd_data;
      else begin ram_we<=1;ram_address<=payload_bytes[13:1];ram_data<={sd_data,low_byte};end
     end
    end
    if(sd_end)state<=3;
    if(timer>=TIMEOUT_CLKS)begin count<=0;done<=1;state<=4;end
   end
   3:begin
    if(byte_count!=512 || ~crc!=stored_crc || !format_ok)begin count<=0;done<=1;state<=4;end
    else if(sector==21)begin done<=1;state<=4;end
    else begin sector<=sector+1'b1;sd_addr<=sd_addr+1'b1;state<=1;end
   end
   default:;
  endcase
 end
end
endmodule
