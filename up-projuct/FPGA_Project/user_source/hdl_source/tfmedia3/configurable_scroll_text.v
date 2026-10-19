`timescale 1ns/1ps
module configurable_scroll_text(
 input clk,rst,reader_clk,
 input enable_async,picture_async,
 input ram_we,input [12:0] ram_address,input [15:0] ram_data,
 input [35:0] config_packet,input config_toggle,output reg config_ack,
 input vs_in,de_in,input [23:0] rgb_in,
 output reg vs_out,de_out,output reg [23:0] rgb_out
);
reg req_meta,req_sync;reg [35:0] pending,frame_config;
reg en_meta,en_sync,pic_meta,pic_sync,frame_enable;
reg vs_d,de_d,arm;reg [9:0] x;reg [8:0] y;reg [10:0] phase;reg [6:0] color_phase;
wire [10:0] width=frame_config[35] ? {frame_config[9:4],5'd0} : 11'd384;
wire [11:0] sum={2'd0,x}+{1'b0,phase};
wire [10:0] local_x=sum-12'd640;
wire [12:0] address={frame_config[3:0],local_x[9:5],y[4:1]-4'd10};
wire [15:0] row;
subtitle_bram u_ram(.write_clk(reader_clk),.write_enable(ram_we),.write_address(ram_address),
 .write_data(ram_data),.read_clk(clk),.read_address(address),.read_data(row));
wire [15:0] default_row;
reg [15:0] default_row_q;
scroll_text_font u_default_font(.address({local_x[8:5],y[4:1]-4'd10}),.row_bits(default_row));
wire [3:0] default_cell=local_x[8:5];
wire default_chinese=(default_cell>=4 && default_cell<=7)||(default_cell>=9 && default_cell<=11);
function [23:0] palette;
 input [2:0] n;
 begin case(n)
 0:palette=24'hFDE68A;1:palette=24'hFDBA74;2:palette=24'hFDA4AF;3:palette=24'hF0ABFC;
 4:palette=24'hC4B5FD;5:palette=24'h93C5FD;6:palette=24'h67E8F9;7:palette=24'h6EE7B7;
 endcase end
endfunction
reg pixel_panel,pixel_ink,pixel_custom;reg [3:0] bit_index;reg [23:0] base_rgb,color;
reg sync_vs,sync_de;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  req_meta<=0;req_sync<=0;pending<=0;frame_config<=0;config_ack<=0;
  en_meta<=0;en_sync<=0;pic_meta<=0;pic_sync<=0;frame_enable<=0;
  vs_d<=0;de_d<=0;arm<=1;x<=0;y<=0;phase<=0;color_phase<=0;
  default_row_q<=0;pixel_panel<=0;pixel_ink<=0;pixel_custom<=0;bit_index<=0;base_rgb<=0;color<=0;
  sync_vs<=0;sync_de<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  req_meta<=config_toggle;req_sync<=req_meta;
  if(req_sync!=config_ack)begin pending<=config_packet;config_ack<=req_sync;end
  en_meta<=enable_async;en_sync<=en_meta;pic_meta<=picture_async;pic_sync<=pic_meta;
  vs_d<=vs_in;de_d<=de_in;
  if(vs_in!=vs_d)begin arm<=1;x<=0;y<=0;end
  else if(de_in)begin
   x<=x+1'b1;
   if(arm)begin
    arm<=0;frame_config<=pending;frame_enable<=en_sync && pic_sync;
    if(frame_config!=pending || !en_sync || !pic_sync || !frame_enable)begin phase<=0;color_phase<=0;end
    else begin phase<=phase+2>=width+640 ? 11'd0 : phase+2;color_phase<=color_phase+1'b1;end
   end
  end else begin x<=0;if(de_d)y<=y+1'b1;end
  sync_vs<=vs_in;sync_de<=de_in;base_rgb<=rgb_in;
  pixel_custom<=frame_config[35];default_row_q<=default_row;
  pixel_panel<=de_in && frame_enable && y>=12 && y<60;
  pixel_ink<=de_in && frame_enable && y>=20 && y<52 && sum>=640 && sum<width+640;
  bit_index<=15-local_x[4:1];
  color<=frame_config[35] ? (frame_config[34] ? palette(color_phase[6:4]+local_x[7:5]) : frame_config[33:10]) : (default_chinese ? palette(color_phase[6:4]+local_x[7:5]) : 24'hFDE68A);
  vs_out<=sync_vs;de_out<=sync_de;rgb_out<=base_rgb;
  if(pixel_panel)rgb_out<={1'b0,base_rgb[23:17],1'b0,base_rgb[15:9],1'b0,base_rgb[7:1]};
  if(pixel_ink && (pixel_custom ? row[bit_index] : default_row_q[bit_index]))rgb_out<=color;
 end
end
endmodule
