`timescale 1ns/1ps
// One shared restoring divider in reader_clk; no DSP or block RAM. The
// published packet stays stable until the video domain acknowledges it.
module playback_info_overlay(
    input reader_clk, reader_rst,
    input [31:0] position, length, ticks_per_second,
    input [4:0] media_index, media_count,
    input valid,
    input clk, rst,
    input [2:0] enable_async,
    input vs_in, de_in, input [23:0] rgb_in,
    output reg vs_out, de_out, output reg [23:0] rgb_out
);
reg [3:0] phase;
reg running;
reg [5:0] bit_count;
reg [40:0] quotient;
reg [31:0] remainder, divisor;
wire [32:0] trial = {remainder, quotient[40]};
wire subtract = trial >= {1'b0,divisor};
wire [40:0] next_quotient = {quotient[39:0],subtract};
reg [31:0] pos_hold,len_hold,rate_hold;
reg [31:0] elapsed_seconds,total_seconds;
reg [6:0] elapsed_minutes,total_minutes;
reg [5:0] elapsed_remainder,total_remainder;
reg [8:0] progress;
reg [31:0] digits;
reg [15:0] ids;
reg valid_hold;
reg publish;
reg [57:0] packet;
reg ack_meta,ack_sync;
reg ack;
// 41-bit numerator permits (position << 9) without overflowing long clips.
task divide;
    input [40:0] numerator;
    input [31:0] denominator;
    begin
        quotient<=numerator; divisor<=denominator==0 ? 32'd1 : denominator;
        remainder<=0; bit_count<=0; running<=1;
    end
endtask
function [7:0] id_digits;
    input [5:0] number;
    reg [5:0] ones;
    begin
        ones=number>=20 ? number-20 : number>=10 ? number-10 : number;
        if(number>=20) id_digits={4'd2,ones[3:0]};
        else if(number>=10) id_digits={4'd1,ones[3:0]};
        else id_digits={4'd0,number[3:0]};
    end
endfunction
always @(posedge reader_clk or posedge reader_rst) begin
    if(reader_rst) begin
        phase<=0;running<=0;bit_count<=0;quotient<=0;remainder<=0;divisor<=1;
        pos_hold<=0;len_hold<=0;rate_hold<=1;elapsed_seconds<=0;total_seconds<=0;
        elapsed_minutes<=0;total_minutes<=0;
        elapsed_remainder<=0;total_remainder<=0;progress<=0;digits<=0;ids<=0;
        valid_hold<=0;publish<=0;packet<=0;ack_meta<=0;ack_sync<=0;
    end else begin
        ack_meta<=ack;ack_sync<=ack_meta;
        if(running) begin
            quotient<=next_quotient;
            remainder<=subtract ? trial-{1'b0,divisor} : trial[31:0];
            if(bit_count==40) begin running<=0;phase<=phase+1'b1;end
            else bit_count<=bit_count+1'b1;
        end else case(phase)
            0: if(ack_sync==publish) begin
                pos_hold<=position>length ? length : position;
                len_hold<=length;rate_hold<=ticks_per_second;
                ids<={id_digits({1'b0,media_index}+6'd1),id_digits({1'b0,media_count})};
                valid_hold<=valid && length!=0 && ticks_per_second!=0;
                divide({position>length ? length : position,9'b0},length);
            end
            1: begin
                progress<=quotient>=512 ? 9'd511 : quotient[8:0];
                divide({9'd0,pos_hold},rate_hold);
            end
            2: begin elapsed_seconds<=quotient>5999 ? 32'd5999 : quotient[31:0];
                divide({9'd0,len_hold},rate_hold);end
            3: begin
                total_seconds<=quotient>5999 ? 32'd5999 : quotient[31:0];
                divide({9'd0,elapsed_seconds},32'd60);
            end
            4: begin
                elapsed_minutes<=quotient[6:0];elapsed_remainder<=remainder[5:0];
                divide({9'd0,total_seconds},32'd60);
            end
            5: begin
                total_minutes<=quotient[6:0];total_remainder<=remainder[5:0];
                divide({34'd0,elapsed_minutes},32'd10);
            end
            6: begin digits[31:24]<={quotient[3:0],remainder[3:0]};
                divide({35'd0,elapsed_remainder},32'd10);end
            7: begin digits[23:16]<={quotient[3:0],remainder[3:0]};
                divide({34'd0,total_minutes},32'd10);end
            8: begin digits[15:8]<={quotient[3:0],remainder[3:0]};
                divide({35'd0,total_remainder},32'd10);end
            9: begin
                packet<={valid_hold,progress,ids,digits[31:8],quotient[3:0],remainder[3:0]};
                publish<=~publish;phase<=0;
            end
            default: phase<=0;
        endcase
    end
end

reg pub_meta,pub_sync;
reg [57:0] pending,frame_packet;
reg [2:0] enable_meta,enable_sync,frame_enable;
reg vs_d,de_d,frame_arm;
reg [9:0] x;
reg [8:0] y;
// 3x5 numeric font, rendered at 2x. Punctuation codes: A colon, B slash.
function [14:0] glyph;
    input [3:0] code;
    begin case(code)
        0:glyph=15'b111_101_101_101_111; 1:glyph=15'b010_110_010_010_111;
        2:glyph=15'b111_001_111_100_111; 3:glyph=15'b111_001_111_001_111;
        4:glyph=15'b101_101_111_001_001; 5:glyph=15'b111_100_111_001_111;
        6:glyph=15'b111_100_111_101_111; 7:glyph=15'b111_001_010_010_010;
        8:glyph=15'b111_101_111_101_111; 9:glyph=15'b111_101_111_001_111;
        10:glyph=15'b000_010_000_010_000;11:glyph=15'b001_001_010_100_100;
        default:glyph=0;
    endcase end
endfunction
reg [3:0] code;
wire id_panel=x>=512 && x<560 && y>=352 && y<368;
wire time_panel=x>=448 && x<560 && y>=376 && y<392;
wire progress_panel=x>=64 && x<576 && y>=404 && y<412;
wire film_panel=x>=492 && x<508 && y>=352 && y<368;
wire clock_panel=x>=428 && x<444 && y>=376 && y<392;
wire play_icon=(x>=48 && x<60 && y>=400 && y<416 &&
    (x-48 >= (y-400)>>1) && (x-48 < 12-((y-400)>>1)));
wire film_icon=film_panel && (x==493 || x==506 || y==353 || y==366 ||
    ((x>=496 && x<=503) && (y==358 || y==361)));
// A 16x16 icon ROM avoids wide pixel-coordinate squarers.
reg [15:0] clock_row;
always @* begin
 case(y[3:0]-4'd8)
  4'd0:clock_row=16'h0000;
  4'd1:clock_row=16'h0fe0;
  4'd2:clock_row=16'h1830;
  4'd3:clock_row=16'h2388;
  4'd4:clock_row=16'h4384;
  4'd5:clock_row=16'hc386;
  4'd6:clock_row=16'h8382;
  4'd7:clock_row=16'h8382;
  4'd8:clock_row=16'hbf82;
  4'd9:clock_row=16'hbf02;
  4'd10:clock_row=16'hbf02;
  4'd11:clock_row=16'hc006;
  4'd12:clock_row=16'h4004;
  4'd13:clock_row=16'h2008;
  4'd14:clock_row=16'h1830;
  4'd15:clock_row=16'h0fe0;
 endcase
end
wire clock_icon=clock_panel && clock_row[x[3:0]-4'd12];
wire [9:0] text_x=id_panel ? x-512 : x-448;
wire [8:0] text_y=id_panel ? y-354 : y-378;
wire [3:0] char_index=text_x[6:3];
reg [14:0] bitmap;
reg ink;
always @* begin
    code=15;
    if(id_panel) case(char_index)
        0:code=frame_packet[47:44];1:code=frame_packet[43:40];2:code=11;
        3:code=frame_packet[39:36];4:code=frame_packet[35:32];
        default:code=15;
    endcase
    else case(char_index)
        0:code=frame_packet[31:28];1:code=frame_packet[27:24];2:code=10;
        3:code=frame_packet[23:20];4:code=frame_packet[19:16];5:code=11;
        6:code=frame_packet[15:12];7:code=frame_packet[11:8];8:code=10;
        9:code=frame_packet[7:4];10:code=frame_packet[3:0];
        default:code=15;
    endcase
    bitmap=glyph(code);
    ink=0;
    if(text_x[2:1]<3 && text_y<10)
        ink=bitmap[14-(text_y[3:1]*3+text_x[2:1])];
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        pub_meta<=0;pub_sync<=0;ack<=0;pending<=0;frame_packet<=0;
        enable_meta<=0;enable_sync<=0;frame_enable<=0;
        vs_d<=0;de_d<=0;frame_arm<=1;x<=0;y<=0;
        vs_out<=0;de_out<=0;rgb_out<=0;
    end else begin
        pub_meta<=publish;pub_sync<=pub_meta;
        if(pub_sync!=ack) begin pending<=packet;ack<=pub_sync;end
        enable_meta<=enable_async;enable_sync<=enable_meta;
        vs_d<=vs_in;de_d<=de_in;
        vs_out<=vs_in;de_out<=de_in;rgb_out<=rgb_in;
        if(vs_in!=vs_d) begin frame_arm<=1;x<=0;y<=0;end
        else if(de_in) begin
            x<=x+1'b1;
            if(frame_arm) begin frame_arm<=0;frame_packet<=pending;frame_enable<=enable_sync;end
        end else begin x<=0;if(de_d)y<=y+1'b1;end
        if(de_in && frame_packet[57]) begin
            if(frame_enable[1] && film_icon) rgb_out<=24'h67E8F9;
            if(frame_enable[2] && clock_icon) rgb_out<=24'hFBBF24;
            if((frame_enable[1] && id_panel) || (frame_enable[2] && time_panel)) begin
                rgb_out<={2'b0,rgb_in[23:18],2'b0,rgb_in[15:10],2'b0,rgb_in[7:2]};
                if(ink)rgb_out<=24'hE2E8F0;
            end
            if(frame_enable[0] && progress_panel)
                rgb_out<=(frame_packet[56:48]==511 || x-64<{1'b0,frame_packet[56:48]}) ? 24'h22D3EE : 24'h475569;
            if(frame_enable[0] && play_icon) rgb_out<=24'h22D3EE;
        end
    end
end
endmodule
