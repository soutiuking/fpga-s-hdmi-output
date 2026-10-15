`timescale 1ns/1ps
// Independent 50-MHz diagnostic: no SD, PLL, SDRAM or HDMI dependency.
// S1 selects 16 wiring hypotheses. S2: 0..7 / one digit per second / segments.
module segtest_top(
    input clk, input key_s1_n, input key_s2_n, input key_reset_n,
    output seg7_sclk, output seg7_rclk, output seg7_dio
);
wire rst, s1, s2;
power_on_reset u_por(clk, key_reset_n, rst);
button_debounce_pulse #(.STABLE_CLKS(250000)) u_s1(
    .clk(clk), .rst(rst), .button_n(key_s1_n), .pressed_pulse(s1), .pressed());
button_debounce_pulse #(.STABLE_CLKS(250000)) u_s2(
    .clk(clk), .rst(rst), .button_n(key_s2_n), .pressed_pulse(s2), .pressed());
reg [3:0] config_bits;
reg [1:0] mode;
reg [25:0] seconds;
reg [2:0] step;
reg [63:0] segments;
integer i;
function [7:0] digit;
input [2:0] n;
begin
    case(n)
    0:digit=8'hc0; 1:digit=8'hf9; 2:digit=8'ha4; 3:digit=8'hb0;
    4:digit=8'h99; 5:digit=8'h92; 6:digit=8'h82; 7:digit=8'hf8;
    endcase
end
endfunction
always @(posedge clk or posedge rst) begin
    if(rst) begin config_bits<=0; mode<=0; seconds<=0; step<=0; end
    else begin
        if(s1) config_bits<=config_bits+1'b1;
        if(s2) begin mode <= (mode==2)?0:mode+1'b1; seconds<=0; step<=0; end
        else if(seconds==49999999) begin seconds<=0; step<=step+1'b1; end
        else seconds<=seconds+1'b1;
    end
end
always @* begin
    segments=64'hffffffffffffffff;
    for(i=0;i<8;i=i+1) begin
        if(mode==0) segments[i*8+:8]=digit(i);
        else if(mode==1 && step==i) segments[i*8+:8]=digit(i);
        else if(mode==2) segments[i*8+:8]=~(8'b1<<step);
    end
end
seg7_serial_8digit #(.CLK_HZ(50000000), .DIGIT_ACTIVE_LOW(0)) u_scan(
    .clk(clk), .rst(rst), .segment_bytes(segments),
    .config_bits(config_bits), .seg7_sclk(seg7_sclk),
    .seg7_rclk(seg7_rclk), .seg7_dio(seg7_dio));
endmodule
