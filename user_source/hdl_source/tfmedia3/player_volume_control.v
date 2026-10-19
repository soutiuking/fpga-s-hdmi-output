`timescale 1ns / 1ps

// SW0 down/ON closes to ground. Keep all controls in the reader domain;
// forward a scaled mailbox with its acknowledgement to the existing I2S CDC.
module player_volume_control #(
    parameter integer STABLE_CLKS = 200_000
)(
    input clk, rst,
    input sw0_n, sw1_n, sw2_n, key_up_n, key_down_n,
    input subtitle_mode,
    output subtitle_next,subtitle_prev,
    input sample_ack_in,
    input [15:0] sample_in,
    output reg sample_ack_out,
    output reg [15:0] sample_out,
    output next_key_n, pause_key_n,
    output volume_mode,
    output brightness_mode,
    output contrast_mode,
    output reg [4:0] contrast,
    output reg [4:0] brightness,
    output reg [4:0] volume
);
wire up_pulse, down_pulse, up_pressed, down_pressed;
wire brightness_switch;
wire contrast_switch;
assign contrast_mode = contrast_switch && !volume_mode && !brightness_mode;
assign brightness_mode = brightness_switch && !volume_mode;
wire subtitle_active = subtitle_mode === 1'b1;
wire [3:0] setting_mode = {subtitle_active,contrast_mode, brightness_mode, volume_mode};
button_debounce_pulse #(.STABLE_CLKS(STABLE_CLKS)) u_contrast_mode (
    .clk(clk), .rst(rst), .button_n(sw2_n),
    .pressed(contrast_switch), .pressed_pulse());
button_debounce_pulse #(.STABLE_CLKS(STABLE_CLKS)) u_brightness_mode (
    .clk(clk), .rst(rst), .button_n(sw1_n),
    .pressed(brightness_switch), .pressed_pulse());
button_debounce_pulse #(.STABLE_CLKS(STABLE_CLKS)) u_mode (
    .clk(clk), .rst(rst), .button_n(sw0_n),
    .pressed(volume_mode), .pressed_pulse());
button_debounce_pulse #(.STABLE_CLKS(STABLE_CLKS)) u_up (
    .clk(clk), .rst(rst), .button_n(key_up_n),
    .pressed(up_pressed), .pressed_pulse(up_pulse));
button_debounce_pulse #(.STABLE_CLKS(STABLE_CLKS)) u_down (
    .clk(clk), .rst(rst), .button_n(key_down_n),
    .pressed(down_pressed), .pressed_pulse(down_pulse));

reg [3:0] mode_seen;
reg armed;
// After changing modes, require both buttons to be released. A held button
// cannot turn into a next-media/pause command when leaving volume mode.
assign next_key_n = !(armed && setting_mode == 0 && mode_seen == 0 && up_pressed);
assign pause_key_n = !(armed && setting_mode == 0 && mode_seen == 0 && down_pressed);
assign subtitle_next=armed && setting_mode==mode_seen && subtitle_active &&
    !volume_mode && !brightness_mode && !contrast_mode && up_pulse && !down_pressed;
assign subtitle_prev=armed && setting_mode==mode_seen && subtitle_active &&
    !volume_mode && !brightness_mode && !contrast_mode && down_pulse && !up_pressed;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        volume <= 5'd16;
        brightness <= 5'd16;
        contrast <= 5'd8;
        mode_seen <= 0;
        armed <= 0;
    end else begin
        mode_seen <= setting_mode;
        if (setting_mode != mode_seen) armed <= 0;
        else if (!up_pressed && !down_pressed && key_up_n && key_down_n)
            armed <= 1;
        if (armed && setting_mode == mode_seen && volume_mode) begin
            if (up_pulse && !down_pressed && volume < 16) volume <= volume + 1'b1;
            else if (down_pulse && !up_pressed && volume != 0) volume <= volume - 1'b1;
        end
        if (armed && setting_mode == mode_seen && brightness_mode) begin
            if (up_pulse && !down_pressed && brightness < 16) brightness <= brightness + 1'b1;
            else if (down_pulse && !up_pressed && brightness != 0) brightness <= brightness - 1'b1;
        end
        if (armed && setting_mode == mode_seen && contrast_mode) begin
            if (up_pulse && !down_pressed && contrast < 16) contrast <= contrast + 1'b1;
            else if (down_pulse && !up_pressed && contrast != 0) contrast <= contrast - 1'b1;
        end
    end
end

// Signed PCM * volume / 16, implemented without a multiplier/DSP.
// 21 bits hold the entire signed product, including -32768 * 16.
wire signed [20:0] pcm = {{5{sample_in[15]}}, sample_in};
wire signed [20:0] product = (volume[0] ? pcm : 21'sd0)
    + (volume[1] ? (pcm <<< 1) : 21'sd0)
    + (volume[2] ? (pcm <<< 2) : 21'sd0)
    + (volume[3] ? (pcm <<< 3) : 21'sd0)
    + (volume[4] ? (pcm <<< 4) : 21'sd0);
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sample_ack_out <= 0;
        sample_out <= 0;
    end else if (sample_ack_in != sample_ack_out) begin
        sample_out <= product >>> 4;
        sample_ack_out <= sample_ack_in;
    end
end
endmodule
