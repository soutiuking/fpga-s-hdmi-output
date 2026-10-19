`timescale 1ns/1ps
// 5120 x 16 bits, ten 9K dual-clock blocks. Written once before playback.
module subtitle_bram(input write_clk,write_enable,input [12:0] write_address,
 input [15:0] write_data,input read_clk,input [12:0] read_address,output [15:0] read_data);
wire [159:0] q;reg [3:0] bank_q;
always @(posedge read_clk)bank_q<=read_address[12:9];
assign read_data=bank_q<10 ? q[bank_q*16+:16] : 16'd0;
genvar b;
generate for(b=0;b<10;b=b+1)begin:g_bank
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
 .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
 .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
 .WRITEMODE_B("READBEFOREWRITE"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) ram(
 .dia(write_data),.addra(write_address[8:0]),.cea(1'b1),.ocea(1'b1),.clka(write_clk),
 .wea(write_enable && write_address[12:9]==b),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(16'd0),.addrb(read_address[8:0]),.ceb(1'b1),.oceb(1'b1),.clkb(read_clk),
 .web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(q[b*16+:16]));
end endgenerate
endmodule

// One small synchronous style table replaces 310 registers and their muxes.
module subtitle_style_bram(input clk,write_enable,input [3:0] write_address,
 input [30:0] write_data,input [3:0] read_address,output [30:0] read_data);
wire [31:0] q;
assign read_data=q[30:0];
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(8),.ADDR_WIDTH_B(8),
 .DATA_DEPTH_A(256),.DATA_DEPTH_B(256),.BYTE_ENABLE(0),.BYTE_A(1),.BYTE_B(1),
 .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
 .WRITEMODE_B("READBEFOREWRITE"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) ram(
 .dia({1'b0,write_data}),.addra({4'd0,write_address}),.cea(1'b1),.ocea(1'b1),.clka(clk),
 .wea(write_enable),.rsta(1'b0),.bea(1'b1),.doa(),
 .dib(32'd0),.addrb({4'd0,read_address}),.ceb(1'b1),.oceb(1'b1),.clkb(clk),
 .web(1'b0),.rstb(1'b0),.beb(1'b1),.dob(q));
endmodule
