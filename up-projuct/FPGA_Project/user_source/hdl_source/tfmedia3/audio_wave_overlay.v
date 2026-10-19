`timescale 1ns/1ps

// 32 display frames of signed PCM min/max envelopes (about 0.53 s at 60 Hz).
// Tap the existing video-domain HDMI audio receiver, without another audio
// clock crossing or any backpressure on playback. Commit one envelope only
// at frame start so the history stays stable throughout the active scan.
module audio_wave_overlay (
    input clk, rst,
    input enable_async,
    input sample_valid,
    input [23:0] sample_data,
    input vs_in, de_in,
    input [23:0] rgb_in,
    output reg vs_out, de_out,
    output reg [23:0] rgb_out
);
reg enable_meta, enable_sync, frame_enable;
reg vs_d, de_d, frame_arm;
reg [9:0] x;
reg [8:0] y;
reg have_sample;
reg signed [7:0] bin_min, bin_max;
wire signed [7:0] pcm = sample_data[23:16];
wire signed [7:0] next_min = !have_sample || pcm<bin_min ? pcm : bin_min;
wire signed [7:0] next_max = !have_sample || pcm>bin_max ? pcm : bin_max;
reg [15:0] history [0:31];
integer i;
wire frame_start = de_in && frame_arm;
// Oldest at left, newest at right; four horizontal pixels per audio bin.
wire [4:0] column = x[6:2] - 5'd4;
wire [4:0] history_index = 5'd31 - column;
wire [15:0] envelope = history[history_index];
wire [8:0] wave_top = 9'd232 - {envelope[7],envelope[7:0]};
wire [8:0] wave_bottom = 9'd232 - {envelope[15],envelope[15:8]};
wire panel = x>=8 && x<152 && y>=88 && y<376;
wire border = panel && (x==8 || x==151 || y==88 || y==375);
wire graph = x>=16 && x<144 && y>=104 && y<=360;
wire grid = graph && (y==104 || y==168 || y==232 || y==296 || y==360 || x[4:0]==16);
wire waveform = graph && y>=wave_top && y<=wave_bottom;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        enable_meta<=0; enable_sync<=0; frame_enable<=0;
        vs_d<=0;de_d<=0;frame_arm<=1;x<=0;y<=0;
        have_sample<=0;bin_min<=0;bin_max<=0;
        vs_out<=0;de_out<=0;rgb_out<=0;
        for(i=0;i<32;i=i+1) history[i]<=0;
    end else begin
        enable_meta<=enable_async;enable_sync<=enable_meta;
        vs_d<=vs_in;de_d<=de_in;
        vs_out<=vs_in;de_out<=de_in;rgb_out<=rgb_in;
        if(sample_valid) begin
            have_sample<=1;
            bin_min<=next_min;bin_max<=next_max;
        end
        if(vs_d!=vs_in) begin frame_arm<=1;x<=0;y<=0;end
        else if(de_in) begin
            x<=x+1'b1;
            if(frame_start) begin
                frame_arm<=0;frame_enable<=enable_sync;
                if(have_sample || sample_valid) begin
                    history[0]<=sample_valid ? {next_min,next_max} : {bin_min,bin_max};
                    for(i=1;i<32;i=i+1) history[i]<=history[i-1];
                end
                have_sample<=0;bin_min<=0;bin_max<=0;
            end
        end else begin x<=0;if(de_d) y<=y+1'b1;end
        if(de_in && frame_enable) begin
            if(panel) rgb_out<={2'b00,rgb_in[23:18],2'b00,rgb_in[15:10],2'b00,rgb_in[7:2]};
            if(grid) rgb_out<= y==232 ? 24'h64748B : 24'h263A50;
            if(waveform) rgb_out<= (y==wave_top || y==wave_bottom) ? 24'hA7F3D0 : 24'h2DD4BF;
            if(border) rgb_out<=24'h38BDF8;
        end
    end
end
endmodule
