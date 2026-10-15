`timescale 1ns/1ps
// Configuration initializes the counter; buttons assert reset asynchronously.
module power_on_reset(input clk, input reset_n, output rst);
reg [17:0] count = 0;
always @(posedge clk or negedge reset_n)
    if (!reset_n) count <= 0;
    else if (!(&count)) count <= count + 1'b1;
assign rst = !(&count) || !reset_n;
endmodule

module reset_sync(input clk, input async_rst, output rst);
reg [2:0] pipe = 3'b111;
always @(posedge clk or posedge async_rst)
    if (async_rst) pipe <= 3'b111;
    else pipe <= {pipe[1:0], 1'b0};
assign rst = pipe[2];
endmodule
