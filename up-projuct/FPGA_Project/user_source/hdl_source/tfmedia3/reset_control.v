`timescale 1ns/1ps
// Configuration initializes the counter; buttons assert reset asynchronously.
module power_on_reset(input clk, input reset_n, output rst);
reg [17:0] count = 0;
always @(posedge clk or negedge reset_n)
    if (!reset_n) count <= 0;
    else if (!(&count)) count <= count + 1'b1;
assign rst = !(&count) || !reset_n;
endmodule

// One counter serves both a sector watchdog and the retry reset interval.
// This supervisor is reset only by the board, never by its own retry output.
module storage_recovery #(
    parameter integer TIMEOUT_CLKS=80_000_000,
    parameter integer RETRY_CLKS=40_000_000
)(input clk,rst,input fault,sector_busy,output reg recovering);
localparam integer COUNTER_BITS=$clog2(TIMEOUT_CLKS>RETRY_CLKS ? TIMEOUT_CLKS : RETRY_CLKS);
reg [COUNTER_BITS-1:0] count;
always @(posedge clk or posedge rst) begin
    if(rst) begin count<=0;recovering<=0;end
    else if(recovering) begin
        if(count==RETRY_CLKS-1) begin count<=0;recovering<=0;end
        else count<=count+1'b1;
    end else if(fault || (sector_busy && count==TIMEOUT_CLKS-1)) begin
        count<=0;recovering<=1;
    end else if(sector_busy) count<=count+1'b1;
    else count<=0;
end
endmodule

module reset_sync(input clk, input async_rst, output rst);
reg [2:0] pipe = 3'b111;
always @(posedge clk or posedge async_rst)
    if (async_rst) pipe <= 3'b111;
    else pipe <= {pipe[1:0], 1'b0};
assign rst = pipe[2];
endmodule
