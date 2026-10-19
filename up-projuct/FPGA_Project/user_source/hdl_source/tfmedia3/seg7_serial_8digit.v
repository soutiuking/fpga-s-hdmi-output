`timescale 1ns / 1ps

// Two cascaded 74HC595s: digit-select byte first, segment byte second, MSB first.
// segment_bytes contains eight active-low segment bytes; digit 0 is bits 7:0.
module seg7_serial_8digit #(
    parameter integer CLK_HZ      = 50_000_000,
    parameter integer SHIFT_HZ    = 1_000_000,
    parameter integer SEGMENT_ACTIVE_LOW = 1,
    parameter integer DIGIT_ACTIVE_LOW = 1
)(
    input             clk,
    input             rst,
    input      [63:0] segment_bytes,
    input      [3:0] config_bits, // bit0 digit invert, bit1 segment invert,
                                 // bit2 byte swap, bit3 reverse segment bits
    output reg        seg7_sclk,
    output reg        seg7_rclk,
    output reg        seg7_dio
);

localparam integer DIVIDER = (CLK_HZ / (SHIFT_HZ * 2));
localparam integer DIV_BITS = (DIVIDER < 2) ? 1 : $clog2(DIVIDER);

// The deployed 40-MHz/1-MHz configuration has DIVIDER=20.  Keeping these
// counters at their actual required widths avoids wasting scarce slices.
reg [DIV_BITS-1:0] div_count;
reg [3:0]  bit_count;
reg [2:0]  digit_index;
reg [15:0] shift_word;
localparam [2:0] LOAD = 0, DATA = 1, CLOCK = 2, LATCH = 3, HOLD = 4;
reg [2:0]  state;
reg [7:0]  selected_segments;
reg [7:0]  digit_select;
reg [7:0] reversed_segments;
integer k;
wire       shift_tick = (div_count == DIVIDER - 1);

always @(*) begin
    case (digit_index)
        3'd0: selected_segments = segment_bytes[7:0];
        3'd1: selected_segments = segment_bytes[15:8];
        3'd2: selected_segments = segment_bytes[23:16];
        3'd3: selected_segments = segment_bytes[31:24];
        3'd4: selected_segments = segment_bytes[39:32];
        3'd5: selected_segments = segment_bytes[47:40];
        3'd6: selected_segments = segment_bytes[55:48];
        default: selected_segments = segment_bytes[63:56];
    endcase
    digit_select = ~(8'b0000_0001 << digit_index);
    if (!DIGIT_ACTIVE_LOW)
        digit_select = ~digit_select;
    if (!SEGMENT_ACTIVE_LOW)
        selected_segments = ~selected_segments;
    if (config_bits[0]) digit_select = ~digit_select;
    if (config_bits[1]) selected_segments = ~selected_segments;
    for (k=0;k<8;k=k+1) reversed_segments[k]=selected_segments[7-k];
    if (config_bits[3]) selected_segments = reversed_segments;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        div_count   <= 0;
        bit_count   <= 4'd0;
        digit_index <= 3'd0;
        shift_word  <= 16'hFFFF;
        state       <= LOAD;
        seg7_sclk   <= 1'b0;
        seg7_rclk   <= 1'b0;
        seg7_dio    <= 1'b1;
    end else begin
        if (shift_tick) begin
            div_count <= 0;
            case (state)
                LOAD: begin
                    seg7_sclk <= 1'b0;
                    seg7_rclk <= 1'b0;
                    shift_word <= config_bits[2] ? {selected_segments,digit_select} :
                                                  {digit_select,selected_segments};
                    bit_count <= 4'd0;
                    state <= DATA;
                end
                DATA: begin
                    seg7_sclk <= 1'b0;
                    seg7_dio <= shift_word[15];
                    state <= CLOCK;
                end
                CLOCK: begin
                    seg7_sclk <= 1'b1;
                    shift_word <= {shift_word[14:0], 1'b1};
                    if (bit_count == 4'd15)
                        state <= LATCH;
                    else begin
                        bit_count <= bit_count + 1'b1;
                        state <= DATA;
                    end
                end
                LATCH: begin
                    // The final shift edge precedes the latch by half a
                    // serial period, instead of racing the 595 shift chain.
                    seg7_sclk <= 1'b0;
                    seg7_rclk <= 1'b1;
                    state <= HOLD;
                end
                HOLD: begin
                    seg7_rclk <= 1'b0;
                    digit_index <= digit_index + 1'b1;
                    state <= LOAD;
                end
                default: state <= LOAD;
            endcase
        end else begin
            div_count <= div_count + 1'b1;
        end
    end
end

endmodule

