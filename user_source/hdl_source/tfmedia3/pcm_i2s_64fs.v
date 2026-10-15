`timescale 1ns / 1ps

// 48-kHz stereo I2S-compatible serializer driven by the existing 12.288-MHz
// audio PLL.  A mono PCM16 mailbox sample is sign-extended to 24 bits and
// duplicated to left and right channels.
module pcm_i2s_64fs(
    input             mclk,
    input             rst,
    output reg        sample_request_toggle,
    input             sample_ack_toggle,
    input      [15:0] sample_data,
    output reg        i2s_bclk,
    output reg        i2s_lrck,
    output reg        i2s_dout
);

reg [5:0]  bit_count;
reg [63:0] shift_register;
reg [23:0] current_sample;
reg [23:0] next_sample;
reg        ack_sync1;
reg        ack_sync2;
reg        ack_seen;

always @(posedge mclk or posedge rst) begin
    if (rst) begin
        sample_request_toggle <= 1'b0;
        i2s_bclk              <= 1'b0;
        i2s_lrck              <= 1'b0;
        i2s_dout              <= 1'b0;
        bit_count             <= 6'd0;
        shift_register        <= 64'd0;
        current_sample        <= 24'd0;
        next_sample           <= 24'd0;
        ack_sync1             <= 1'b0;
        ack_sync2             <= 1'b0;
        ack_seen              <= 1'b0;
    end else begin
        ack_sync1 <= sample_ack_toggle;
        ack_sync2 <= ack_sync1;
        if (ack_sync2 != ack_seen) begin
            ack_seen    <= ack_sync2;
            next_sample <= {sample_data, 8'd0};
        end

        i2s_bclk <= ~i2s_bclk;
        if (i2s_bclk) begin
            i2s_dout       <= shift_register[63];
            shift_register <= {shift_register[62:0], 1'b0};
            if (bit_count == 6'd63) begin
                bit_count <= 6'd0;
                if (!i2s_lrck) begin
                    i2s_lrck       <= 1'b1;
                    shift_register <= {current_sample, 40'd0};
                end else begin
                    i2s_lrck              <= 1'b0;
                    current_sample        <= next_sample;
                    shift_register        <= {next_sample, 40'd0};
                    sample_request_toggle <= ~sample_request_toggle;
                end
            end else begin
                bit_count <= bit_count + 1'b1;
            end
        end
    end
end

endmodule
