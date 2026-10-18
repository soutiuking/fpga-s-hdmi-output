`timescale 1ns/1ps

// 640x480 video-domain OSD. Control arrives as registered Gray code from the
// reader domain. Synchronize it, then change the OSD only at frame boundaries.
// RGB, DE and VS all acquire exactly one pixel clock of latency.
module volume_bar_overlay #(
    parameter [9:0] ANIMATION_STEP = 10'd8
)(
    input clk, rst,
    input enable_async,
    input [4:0] volume_gray_async,
    input brightness_enable_async,
    input [4:0] brightness_gray_async,
    input contrast_enable_async,
    input [4:0] contrast_gray_async,
    input vs_in, de_in,
    input [23:0] rgb_in,
    output reg vs_out, de_out,
    output reg [23:0] rgb_out
);
reg enable_meta, enable_sync;
reg [4:0] gray_meta, gray_sync;
reg bright_meta, bright_sync, frame_brightness;
reg contrast_meta, contrast_sync, frame_contrast;
reg [4:0] contrast_gray_meta, contrast_gray_sync;
wire [4:0] contrast_level = {contrast_gray_sync[4], ^contrast_gray_sync[4:3],
    ^contrast_gray_sync[4:2], ^contrast_gray_sync[4:1], ^contrast_gray_sync};
reg [4:0] bright_gray_meta, bright_gray_sync;
reg [4:0] frame_gain;
wire [4:0] bright_level;
assign bright_level = {bright_gray_sync[4], ^bright_gray_sync[4:3],
    ^bright_gray_sync[4:2], ^bright_gray_sync[4:1], ^bright_gray_sync};
wire [4:0] level;
assign level[4] = gray_sync[4];
assign level[3] = ^gray_sync[4:3];
assign level[2] = ^gray_sync[4:2];
assign level[1] = ^gray_sync[4:1];
assign level[0] = ^gray_sync;
wire [4:0] selected_level = enable_sync ? level : bright_sync ? bright_level : contrast_level;
wire [9:0] target_width = (selected_level <= 16) ? {selected_level, 5'd0} : 10'd512;
wire setting_enable = enable_sync || bright_sync || contrast_sync;
wire setting_brightness = !enable_sync && bright_sync;
wire setting_contrast = !enable_sync && !bright_sync && contrast_sync;
function [7:0] dim_channel;
    input [7:0] channel;
    input [4:0] gain;
    reg [12:0] extended, product;
    begin
        extended = {5'd0, channel};
        product = (gain[0] ? extended : 13'd0)
            + (gain[1] ? (extended << 1) : 13'd0)
            + (gain[2] ? (extended << 2) : 13'd0)
            + (gain[3] ? (extended << 3) : 13'd0)
            + (gain[4] ? (extended << 4) : 13'd0);
        dim_channel = product[11:4];
    end
endfunction
wire [4:0] pixel_gain = (de_in && frame_arm) ?
    (bright_level <= 16 ? bright_level : 5'd16) : frame_gain;
wire [23:0] dimmed_rgb = {dim_channel(rgb_in[23:16],pixel_gain),
    dim_channel(rgb_in[15:8],pixel_gain), dim_channel(rgb_in[7:0],pixel_gain)};

reg vs_d, de_d, frame_arm, frame_enable;
reg [9:0] x;
reg [8:0] y;
reg [9:0] fill_width;
reg [8:0] shine;
wire frame_start = de_in && frame_arm;
wire [9:0] fill_end = 10'd64 + fill_width;
wire panel = (x >= 8 && x < 600 && y >= 420 && y < 468);
// Small 16x16 glyphs implemented as constant rows, no font memory needed.
function [15:0] icon_row;
    input sun;
    input [3:0] row;
    begin
        if (sun) case(row)
            0,1,14,15: icon_row=16'h0180;
            2,13: icon_row=16'h2184;
            3,12: icon_row=16'h1248;
            4,11: icon_row=16'h03C0;
            5,10: icon_row=16'h0660;
            6,9: icon_row=16'h0C30;
            7,8: icon_row=16'hEC37;
        endcase
        else case(row)
            0,15: icon_row=16'h0000;
            1,14: icon_row=16'h0108;
            2,13: icon_row=16'h0304;
            3,12: icon_row=16'h0702;
            4,11: icon_row=16'h0F22;
            5,10: icon_row=16'h7F12;
            6,9: icon_row=16'h7F0A;
            7,8: icon_row=16'h7F0A;
        endcase
    end
endfunction
function [15:0] contrast_icon;
    input [3:0] row;
    begin
        case(row)
            0,15: contrast_icon=16'h07E0;
            1,14: contrast_icon=16'h1F98;
            2,13: contrast_icon=16'h3F84;
            3,12: contrast_icon=16'h7F82;
            default: contrast_icon=16'hFF81;
        endcase
    end
endfunction
wire [15:0] glyph = frame_contrast ? contrast_icon(y[3:0]-4'd4) :
    icon_row(frame_brightness, y[3:0]-4'd4);
wire [3:0] icon_x = x[3:0] - 4'd8;
wire icon_pixel = x>=24 && x<40 && y>=436 && y<452 && glyph[15-icon_x];
wire border = (x >= 62 && x < 578 && y >= 434 && y < 454);
wire track = (x >= 64 && x < 576 && y >= 436 && y < 452);
wire filled = (x < fill_end);
// Modulo-512 subtraction wraps the highlight naturally along the track.
wire [8:0] shine_distance = x[8:0] - 9'd64 - shine;
wire ticks = (x >= 64 && x <= 576 && y >= 458 && y < 461 && x[4:0] == 0);
reg [23:0] composed_rgb;
always @* begin
    composed_rgb = dimmed_rgb;
    if (frame_enable && de_in) begin
        if (panel)
            composed_rgb = {1'b0,dimmed_rgb[23:17],1'b0,dimmed_rgb[15:9],1'b0,dimmed_rgb[7:1]};
        if (icon_pixel) composed_rgb = frame_contrast ? 24'hC4B5FD : frame_brightness ? 24'hFBBF24 : 24'hE2E8F0;
        if (ticks) composed_rgb = 24'h94A3B8;
        if (border) composed_rgb = 24'h64748B;
        if (track) begin
            composed_rgb = (frame_brightness || frame_contrast) ? 24'h4B5563 : 24'h172B40;
            if (filled)
                composed_rgb = frame_contrast ?
                    ((shine_distance < 32) ? 24'hDDD6FE : 24'hA78BFA) : frame_brightness ?
                    ((shine_distance < 32) ? 24'hFDE68A : 24'hFBBF24) :
                    ((shine_distance < 32) ? 24'hA7F3D0 : 24'h2DD4BF);
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        enable_meta <= 0; enable_sync <= 0;
        gray_meta <= 0; gray_sync <= 0;
        bright_meta <= 0; bright_sync <= 0; frame_brightness <= 0;
        bright_gray_meta <= 5'b11000; bright_gray_sync <= 5'b11000;
        frame_gain <= 16;
        contrast_meta <= 0; contrast_sync <= 0; frame_contrast <= 0;
        contrast_gray_meta <= 12; contrast_gray_sync <= 12;
        vs_d <= 0; de_d <= 0; frame_arm <= 1; frame_enable <= 0;
        x <= 0; y <= 0; fill_width <= 0; shine <= 0;
        vs_out <= 0; de_out <= 0; rgb_out <= 0;
    end else begin
        enable_meta <= enable_async; enable_sync <= enable_meta;
        gray_meta <= volume_gray_async; gray_sync <= gray_meta;
        bright_meta <= brightness_enable_async; bright_sync <= bright_meta;
        bright_gray_meta <= brightness_gray_async; bright_gray_sync <= bright_gray_meta;
        contrast_meta <= contrast_enable_async; contrast_sync <= contrast_meta;
        contrast_gray_meta <= contrast_gray_async; contrast_gray_sync <= contrast_gray_meta;
        vs_d <= vs_in; de_d <= de_in;
        vs_out <= vs_in; de_out <= de_in; rgb_out <= composed_rgb;
        if (vs_d != vs_in) begin
            frame_arm <= 1;
            x <= 0; y <= 0;
        end else if (de_in) begin
            x <= x + 1'b1;
            if (frame_start) begin
                frame_arm <= 0;
                frame_enable <= setting_enable;
                frame_brightness <= setting_brightness;
                frame_contrast <= setting_contrast;
                frame_gain <= bright_level <= 16 ? bright_level : 5'd16;
                shine <= shine + 9'd4;
                if (!setting_enable || (frame_brightness != setting_brightness) ||
                    (frame_contrast != setting_contrast)) fill_width <= 0;
                else if (fill_width < target_width) begin
                    if (target_width - fill_width <= ANIMATION_STEP) fill_width <= target_width;
                    else fill_width <= fill_width + ANIMATION_STEP;
                end else if (fill_width > target_width) begin
                    if (fill_width - target_width <= ANIMATION_STEP) fill_width <= target_width;
                    else fill_width <= fill_width - ANIMATION_STEP;
                end
            end
        end else begin
            x <= 0;
            if (de_d) y <= y + 1'b1;
        end
    end
end
endmodule

// One registered pixel stage keeps contrast arithmetic off the brightness
// critical path. Contrast is centered on 128, with saturating output.
module video_contrast_stage(
    input clk, rst,
    input [4:0] contrast_gray_async,
    input vs_in, de_in,
    input [23:0] rgb_in,
    output reg vs_out, de_out,
    output reg [23:0] rgb_out
);
reg [4:0] gray_meta, gray_sync, frame_level;
reg vs_d, frame_arm;
wire [4:0] decoded_level = {gray_sync[4], ^gray_sync[4:3],
    ^gray_sync[4:2], ^gray_sync[4:1], ^gray_sync};
wire [4:0] safe_level = decoded_level <= 16 ? decoded_level : 5'd8;
wire [4:0] pixel_level = de_in && frame_arm ? safe_level : frame_level;
function [7:0] contrast_channel;
    input [7:0] channel;
    input [4:0] gain;
    reg signed [13:0] centered, product, adjusted;
    begin
        centered = $signed({1'b0,channel}) - 14'sd128;
        product = (gain[0] ? centered : 14'sd0)
            + (gain[1] ? (centered <<< 1) : 14'sd0)
            + (gain[2] ? (centered <<< 2) : 14'sd0)
            + (gain[3] ? (centered <<< 3) : 14'sd0)
            + (gain[4] ? (centered <<< 4) : 14'sd0);
        adjusted = (product >>> 3) + 14'sd128;
        if (adjusted < 0) contrast_channel = 0;
        else if (adjusted > 255) contrast_channel = 255;
        else contrast_channel = adjusted[7:0];
    end
endfunction
always @(posedge clk or posedge rst) begin
    if (rst) begin
        gray_meta <= 12; gray_sync <= 12; frame_level <= 8;
        vs_d <= 0; frame_arm <= 1;
        vs_out <= 0; de_out <= 0; rgb_out <= 0;
    end else begin
        gray_meta <= contrast_gray_async; gray_sync <= gray_meta;
        vs_d <= vs_in;
        if (vs_d != vs_in) frame_arm <= 1;
        else if (de_in && frame_arm) begin
            frame_arm <= 0;
            frame_level <= safe_level;
        end
        vs_out <= vs_in; de_out <= de_in;
        rgb_out <= {contrast_channel(rgb_in[23:16],pixel_level),
            contrast_channel(rgb_in[15:8],pixel_level),
            contrast_channel(rgb_in[7:0],pixel_level)};
    end
end
endmodule
