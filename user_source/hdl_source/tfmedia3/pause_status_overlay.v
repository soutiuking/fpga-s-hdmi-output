`timescale 1ns/1ps
// Video pause: cyan double bar. Slideshow stopped: amber picture + double bar.
// Both controls are registered in reader_clk and sampled only at frame start.
module pause_status_overlay(
    input clk,rst,input [1:0] status_async,
    input vs_in,de_in,input [23:0] rgb_in,
    output reg vs_out,de_out,output reg [23:0] rgb_out
);
reg [1:0] status_meta,status_sync,frame_status;
reg vs_d,de_d,frame_arm;
reg [9:0] x;reg [8:0] y;
// Use aligned coordinate slices for the small bitmap: comparisons remain
// narrow and do not consume long carry chains on this nearly full device.
wire panel=x[9:7]==0 && x[6:3]>=1 && x[6:3]<=8 && y[8:5]==12;
wire icon_rows=y[4:3]==1 || y[4:3]==2;
wire video_bars=icon_rows && (x[6:3]==3 || x[6:3]==5);
wire picture_outline=(x[6:3]>=2 && x[6:3]<=4 && (y[4:1]==4 || y[4:1]==11)) ||
    (icon_rows && (x[6:1]==8 || x[6:1]==19));
wire picture_sun=x[6:2]==8 && (y[4:1]==5 || y[4:1]==6);
wire picture_mountain=(y[4:1]==8 && x[6:2]==6) ||
    ((y[4:1]==9 || y[4:1]==10) && (x[6:2]==5 || x[6:2]==6 || x[6:2]==7 || x[6:2]==8));
wire picture_bars=icon_rows && (x[6:2]==12 || x[6:2]==15);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        status_meta<=0;status_sync<=0;frame_status<=0;vs_d<=0;de_d<=0;
        frame_arm<=1;x<=0;y<=0;vs_out<=0;de_out<=0;rgb_out<=0;
    end else begin
        status_meta<=status_async;status_sync<=status_meta;
        vs_d<=vs_in;de_d<=de_in;
        vs_out<=vs_in;de_out<=de_in;rgb_out<=rgb_in;
        if(vs_in!=vs_d) begin frame_arm<=1;x<=0;y<=0;end
        else if(de_in) begin
            x<=x+1'b1;
            if(frame_arm) begin frame_arm<=0;frame_status<=status_sync;end
        end else begin x<=0;if(de_d) y<=y+1'b1;end
        if(de_in && frame_status!=0 && panel) begin
            rgb_out<={2'b0,rgb_in[23:18],2'b0,rgb_in[15:10],2'b0,rgb_in[7:2]};
            if(frame_status==1 && video_bars) rgb_out<=24'h67E8F9;
            if(frame_status==2 && (picture_outline || picture_sun || picture_mountain || picture_bars))
                rgb_out<=24'hFBBF24;
        end
    end
end
endmodule
