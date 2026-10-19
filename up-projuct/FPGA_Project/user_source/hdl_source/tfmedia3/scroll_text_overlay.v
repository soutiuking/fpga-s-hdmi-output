`timescale 1ns/1ps

// SW3 media marquee, 12 fixed 32x32 cells, moving right to left.
// A 384-pixel phrase plus a 640-pixel viewport gives a 1024-pixel wrap.
module scroll_text_overlay #(
    parameter [9:0] SCROLL_STEP = 10'd2
)(
    input clk, rst,
    input enable_async, picture_async,
    input vs_in, de_in,
    input [23:0] rgb_in,
    output reg vs_out, de_out,
    output reg [23:0] rgb_out
);
reg enable_meta, enable_sync, picture_meta, picture_sync;
reg frame_enable, frame_arm, vs_d, de_d;
reg [9:0] x, phase;
reg [8:0] y;
reg [6:0] color_phase;
wire frame_start = de_in && frame_arm;
wire requested = enable_sync && picture_sync;
wire [9:0] text_x = x + phase + 10'd384;
wire [4:0] text_y = y - 9'd20;
wire [7:0] font_address = {text_x[8:5], text_y[4:1]};
wire [15:0] font_row;
scroll_text_font u_font(.address(font_address), .row_bits(font_row));
wire text_band = y >= 20 && y < 52;
wire text_pixel = text_band && text_x < 384 && font_row[15-text_x[4:1]];
wire panel = y >= 12 && y < 60;
// Stagger neighboring Chinese glyphs through a bright palette. Latin letters
// and punctuation retain the original gold; color updates only per frame.
wire [3:0] cell_index = text_x[8:5];
wire chinese_cell = (cell_index >= 4 && cell_index <= 7) ||
                    (cell_index >= 9 && cell_index <= 11);
wire [2:0] color_index = color_phase[6:4] + cell_index[2:0];
function [23:0] palette;
    input [2:0] index;
    begin
        case(index)
            0: palette=24'hFDE68A;
            1: palette=24'hFDBA74;
            2: palette=24'hFDA4AF;
            3: palette=24'hF0ABFC;
            4: palette=24'hC4B5FD;
            5: palette=24'h93C5FD;
            6: palette=24'h67E8F9;
            7: palette=24'h6EE7B7;
        endcase
    end
endfunction
wire [23:0] text_color = chinese_cell ? palette(color_index) : 24'hFDE68A;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        enable_meta <= 0; enable_sync <= 0;
        picture_meta <= 0; picture_sync <= 0;
        frame_enable <= 0; frame_arm <= 1;
        vs_d <= 0; de_d <= 0;
        x <= 0; y <= 0; phase <= 0;
        color_phase <= 0;
        vs_out <= 0; de_out <= 0; rgb_out <= 0;
    end else begin
        enable_meta <= enable_async; enable_sync <= enable_meta;
        picture_meta <= picture_async; picture_sync <= picture_meta;
        vs_d <= vs_in; de_d <= de_in;
        vs_out <= vs_in; de_out <= de_in;
        rgb_out <= rgb_in;
        if (de_in && frame_enable) begin
            if(panel) rgb_out <= {1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
            if(text_pixel) rgb_out <= text_color;
        end
        if(vs_d != vs_in) begin
            frame_arm <= 1;
            x <= 0; y <= 0;
        end else if(de_in) begin
            x <= x + 1'b1;
            if(frame_start) begin
                frame_arm <= 0;
                frame_enable <= requested;
                if(!requested || !frame_enable) begin
                    phase <= 0;
                    color_phase <= 0;
                end else begin
                    phase <= phase + SCROLL_STEP;
                    color_phase <= color_phase + 1'b1;
                end
            end
        end else begin
            x <= 0;
            if(de_d) y <= y + 1'b1;
        end
    end
end
endmodule
