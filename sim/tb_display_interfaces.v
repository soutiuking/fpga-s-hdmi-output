`timescale 1ns/1ps
module tb_display_interfaces;
reg clk = 0;
always #5 clk = ~clk;
reg rst = 1;
reg vs = 0, de = 0;
reg [23:0] rgb = 0;
wire user_out, valid_out, last_out;
wire [23:0] data_out;
video_rgb_to_axis_640x480 axis_dut(clk, rst, vs, de, rgb,
    user_out, valid_out, last_out, data_out);
wire sclk, rclk, dio;
localparam [63:0] SEGMENTS = 64'hF8_82_92_99_B0_A4_F9_C0;
seg7_serial_8digit #(.CLK_HZ(100_000_000), .SHIFT_HZ(10_000_000),
    .DIGIT_ACTIVE_LOW(0)) seg_dut(clk, rst, SEGMENTS, 4'd4, sclk, rclk, dio);
integer pixels = 0, lines = 0, frames = 0, latches = 0;
integer shift_bits = 0;
reg [15:0] chain = 0;
time last_shift;
reg [15:0] expected;
always @(posedge sclk) begin
    chain = {chain[14:0], dio};
    shift_bits = shift_bits + 1;
    last_shift = $time;
end
always @(posedge rclk) begin
    // Calibrated board wiring: segment byte precedes digit-select byte.
    expected = {SEGMENTS[8*(latches % 8) +: 8], 8'b1 << (latches % 8)};
    if (chain !== expected || shift_bits != 16 || $time-last_shift < 50)
        $fatal(1, "595 packet/timing: digit=%0d got=%h expected=%h bits=%0d", latches, chain, expected, shift_bits);
    shift_bits = 0;
    latches = latches + 1;
end
always @(negedge clk) begin
    if (!rst && valid_out) begin
        pixels = pixels + 1;
        if (user_out) begin
            if (pixels != 1 || lines % 480 != 0) $fatal(1, "Wrong SOF");
            frames = frames + 1;
        end
        if (last_out) begin
            if (pixels != 640) $fatal(1, "Wrong EOL at pixel %0d", pixels);
            pixels = 0;
            lines = lines + 1;
        end
    end
end
integer f, y, x;
initial begin
    #21 rst = 0;
    for (f=0; f<2; f=f+1) begin
        @(negedge clk); vs = 1;
        repeat (10) @(negedge clk);
        vs = 0;
        for (y=0; y<480; y=y+1) begin
            for (x=0; x<640; x=x+1) begin
                @(negedge clk); de = 1; rgb = x;
            end
            @(negedge clk); de = 0;
            repeat (159) @(negedge clk);
        end
    end
    repeat (2) @(negedge clk);
    if (lines != 960 || frames != 2 || latches < 16)
        $fatal(1, "Missing line/frame/595 output: %0d/%0d/%0d", lines, frames, latches);
    $display("PASS: 960 lines, 640 pixels/EOL, 2 SOF; %0d 595 packets and latch spacing", latches);
    $finish;
end
initial begin #10000000; $fatal(1, "timeout"); end
endmodule
