`timescale 1ns/1ps
module subtitle_bram(input write_clk,write_enable,input [12:0] write_address,
 input [15:0] write_data,input read_clk,input [12:0] read_address,output reg [15:0] read_data);
reg [15:0] memory[0:5119];
always @(posedge write_clk) if(write_enable && write_address<5120)memory[write_address]<=write_data;
always @(posedge read_clk)read_data<=read_address<5120 ? memory[read_address] : 16'd0;
endmodule

module subtitle_style_bram(input clk,write_enable,input [3:0] write_address,
 input [30:0] write_data,input [3:0] read_address,output reg [30:0] read_data);
reg [30:0] memory[0:15];
always @(posedge clk)begin
 if(write_enable)memory[write_address]<=write_data;
 read_data<=memory[read_address];
end
endmodule
