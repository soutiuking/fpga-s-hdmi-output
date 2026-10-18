`timescale 1ns / 1ps

// Known-good HDMI/audio IP wrapped around a 640x480 AXI test source.  The
// storage/JPEG path will replace only the test source, so SD is not duplicated
// and the old FAT/BMP reader is no longer part of the active hierarchy.
module tfmedia3_hdmi_shell #(
    parameter integer TEST_PATTERN=0
)(
    input  wire clk,
    input  wire rst,
    input  wire reader_clk,
    input  wire mem_clk,
    input  wire mem_clk_sft,
    input  wire frame_write_req,
    output wire frame_write_req_ack,
    input  wire frame_write_en,
    input  wire [31:0] frame_write_data,
    input  wire frame_write_slot,
    output wire frame_write_finish,
    input  wire display_valid,
    input  wire display_slot,
    input  wire display_submit,
    output wire presentation_busy,
    output wire frame_presented,
    output wire audio_sample_request_toggle,
    input  wire audio_sample_ack_toggle,
    input  wire [15:0] audio_sample_data,
    input  wire volume_setting,
    input  wire [4:0] volume_level,
    input  wire brightness_setting,
    input  wire [4:0] brightness_level,
    input  wire contrast_setting,
    input  wire [4:0] contrast_level,
    input  wire scroll_setting,
    input  wire picture_playing,
    input  wire wave_setting,
    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P,
    output wire ddc_scl,
    inout  wire ddc_sda
);

wire video_clk;
wire hdmi_5x_clk;
wire audio_pll_lock;
wire audio_mclk;
wire rst_async = rst | ~audio_pll_lock;
wire rst_all, rst_mem, rst_reader;
reset_sync u_video_reset(.clk(video_clk), .async_rst(rst_async), .rst(rst_all));
reset_sync u_mem_reset(.clk(mem_clk), .async_rst(rst_async), .rst(rst_mem));
reset_sync u_reader_reset(.clk(reader_clk), .async_rst(rst_async), .rst(rst_reader));
wire visible_slot, visible_valid;
wire        video_read_req;
wire        video_read_req_ack;
reg video_read_req_d, video_read_req_d2;
always @(posedge video_clk or posedge rst_all)
    if(rst_all) begin video_read_req_d<=0; video_read_req_d2<=0; end
    else begin video_read_req_d<=video_read_req; video_read_req_d2<=video_read_req_d; end
// read_req first rises here, before the 3-stage mem-domain request capture.
frame_present_cdc u_present(
    .reader_clk(reader_clk), .reader_rst(rst_reader),
    .submit(display_submit), .submit_slot(display_slot), .submit_valid(display_valid),
    .busy(presentation_busy), .presented(frame_presented),
    .video_clk(video_clk), .video_rst(rst_all),
    .frame_boundary(video_read_req && !video_read_req_d),
    .read_ack(video_read_req_ack), .video_slot(visible_slot), .video_valid(visible_valid));

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        sdr_init_done;
wire        sdr_init_ref_vld;
wire        sdr_busy;
wire        app_rd_en;
wire [20:0] app_rd_addr;
wire        sdr_rd_en;
wire [31:0] sdr_rd_dout;
wire        app_wr_en;
wire [20:0] app_wr_addr;
wire [31:0] app_wr_din;
wire [3:0]  app_wr_dm;
wire        video_read_en;
wire [31:0] video_read_data;
wire        frame_write_req_ack_mem;
wire        frame_write_finish_mem;
reg [2:0]   frame_write_ack_sync;
reg [2:0]   frame_write_finish_sync;
reg         frame_write_finish_toggle;
reg         frame_write_finish_seen;
wire        video_hs;
wire        video_vs;
wire        video_de;
wire        delayed_hs;
wire        delayed_vs;
wire        delayed_de;
wire [23:0] framebuffer_rgb;
wire osd_vs, osd_de;
wire [23:0] osd_rgb;
reg [4:0] volume_gray;
reg [4:0] brightness_gray;
reg [4:0] contrast_gray;
always @(posedge reader_clk or posedge rst_reader) begin
    if (rst_reader) begin
        volume_gray <= 5'b11000;
        brightness_gray <= 5'b11000;
        contrast_gray <= 5'b01100;
    end else begin
        volume_gray <= volume_level ^ (volume_level >> 1);
        brightness_gray <= brightness_level ^ (brightness_level >> 1);
        contrast_gray <= contrast_level ^ (contrast_level >> 1);
    end
end

wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        edid_trig;
wire        edid_valid_unused;
wire [7:0]  edid_data_unused;
wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

assign frame_write_req_ack = frame_write_ack_sync[2];
// Transfer the 8-ns memory completion as an event to the 25-ns reader clock.
assign frame_write_finish = frame_write_finish_sync[2] ^ frame_write_finish_seen;

always @(posedge mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_finish_toggle <= 1'b0;
    else if (frame_write_finish_mem)
        frame_write_finish_toggle <= ~frame_write_finish_toggle;
end

always @(posedge reader_clk or posedge rst_reader) begin
    if (rst_reader) begin
        frame_write_ack_sync    <= 3'b000;
        frame_write_finish_sync <= 3'b000;
        frame_write_finish_seen <= 1'b0;
    end else begin
        frame_write_ack_sync    <= {frame_write_ack_sync[1:0],
                                    frame_write_req_ack_mem};
        frame_write_finish_sync <= {frame_write_finish_sync[1:0],
                                    frame_write_finish_toggle};
        frame_write_finish_seen <= frame_write_finish_sync[2];
    end
end

video_pll u_video_pll (
    .refclk(clk), .clk0_out(video_clk), .clk1_out(hdmi_5x_clk),
    .reset(1'b0)
);

PLL_HDMI_AUDIO u_audio_pll (
    .refclk(clk), .reset(1'b0), .extlock(audio_pll_lock),
    .clk0_out(), .clk1_out(), .clk2_out(audio_mclk)
);

video_timing_data u_video_timing (
    .video_clk(video_clk), .rst(rst_all),
    .read_req(video_read_req), .read_req_ack(video_read_req_ack),
    .hs(video_hs), .vs(video_vs), .de(video_de)
);

video_delay u_video_delay (
    .video_clk(video_clk), .rst(rst_all), .read_en(video_read_en),
    .read_data(video_read_data[31:8]), .hs(video_hs), .vs(video_vs),
    .de(video_de), .hs_r(delayed_hs), .vs_r(delayed_vs),
    .de_r(delayed_de), .vout_data(framebuffer_rgb)
);

wire contrast_vs, contrast_de;
wire [23:0] contrast_rgb;
video_contrast_stage u_contrast (
    .clk(video_clk), .rst(rst_all), .contrast_gray_async(contrast_gray),
    .vs_in(delayed_vs), .de_in(delayed_de),
    .rgb_in(visible_valid ? framebuffer_rgb : 24'h000000),
    .vs_out(contrast_vs), .de_out(contrast_de), .rgb_out(contrast_rgb)
);
volume_bar_overlay u_volume_osd (
    .clk(video_clk), .rst(rst_all),
    .enable_async(volume_setting), .volume_gray_async(volume_gray),
    .brightness_enable_async(brightness_setting), .brightness_gray_async(brightness_gray),
    .contrast_enable_async(contrast_setting), .contrast_gray_async(contrast_gray),
    .vs_in(contrast_vs), .de_in(contrast_de),
    .rgb_in(contrast_rgb),
    .vs_out(osd_vs), .de_out(osd_de), .rgb_out(osd_rgb)
);

wire text_vs, text_de;
wire [23:0] text_rgb;
scroll_text_overlay u_scroll_text (
    .clk(video_clk), .rst(rst_all),
    .enable_async(scroll_setting), .picture_async(picture_playing),
    .vs_in(osd_vs), .de_in(osd_de), .rgb_in(osd_rgb),
    .vs_out(text_vs), .de_out(text_de), .rgb_out(text_rgb)
);
wire wave_vs, wave_de;
wire [23:0] wave_rgb;
audio_wave_overlay u_audio_wave (
    .clk(video_clk), .rst(rst_all), .enable_async(wave_setting),
    .sample_valid(audio_valid), .sample_data(audio_left_data),
    .vs_in(text_vs), .de_in(text_de), .rgb_in(text_rgb),
    .vs_out(wave_vs), .de_out(wave_de), .rgb_out(wave_rgb)
);
video_rgb_to_axis_640x480 u_video_axis (
    .I_clk(video_clk), .I_rst(rst_all), .I_vs(wave_vs),
    .I_de(wave_de),
    .I_rgb(wave_rgb),
    .O_video_user(axis_s_user), .O_video_valid(axis_s_valid),
    .O_video_last(axis_s_last), .O_video_data(axis_s_data)
);

frame_read_write #(
    .WRITE_V_FLIP(0), .FRAME_WIDTH(640), .FRAME_HEIGHT(480)
) u_framebuffer (
    .rst(rst_mem), .mem_clk(mem_clk), .Sdr_init_done(sdr_init_done),
    .Sdr_init_ref_vld(sdr_init_ref_vld), .Sdr_busy(sdr_busy),
    .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
    .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_dout),
    .read_clk(video_clk), .read_req(video_read_req_d2),
    .read_req_ack(video_read_req_ack), .read_finish(),
    .read_addr_0(21'd0), .read_addr_1(21'd307200),
    .read_addr_2(21'd0), .read_addr_3(21'd0),
    .read_addr_index({1'b0, visible_slot}), .read_len(21'd307200),
    .read_en(video_read_en), .read_data(video_read_data),
    .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
    .App_wr_din(app_wr_din), .App_wr_dm(app_wr_dm),
    .write_clk(reader_clk), .write_req(frame_write_req),
    .write_req_ack(frame_write_req_ack_mem),
    .write_finish(frame_write_finish_mem),
    .write_addr_0(21'd0), .write_addr_1(21'd307200),
    .write_addr_2(21'd0), .write_addr_3(21'd0),
    .write_addr_index({1'b0, frame_write_slot}),
    .write_len(21'd307200), .write_en(frame_write_en),
    .write_data(frame_write_data)
);

sdram u_sdram (
    .Clk(mem_clk), .Clk_sft(mem_clk_sft), .Rst(rst_mem),
    .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_init_ref_vld),
    .Sdr_busy(sdr_busy), .App_wr_en(app_wr_en),
    .App_wr_addr(app_wr_addr), .App_wr_dm(app_wr_dm),
    .App_wr_din(app_wr_din), .App_rd_en(app_rd_en),
    .App_rd_addr(app_rd_addr), .Sdr_rd_en(sdr_rd_en),
    .Sdr_rd_dout(sdr_rd_dout)
);

pcm_i2s_64fs u_audio_source (
    .mclk(audio_mclk), .rst(rst_all),
    .sample_request_toggle(audio_sample_request_toggle),
    .sample_ack_toggle(audio_sample_ack_toggle),
    .sample_data(audio_sample_data),
    .i2s_bclk(audio_i2s_bclk), .i2s_lrck(audio_i2s_lrck),
    .i2s_dout(audio_i2s_dout)
);

I2S_receiver u_i2s_receiver (
    .I_clk(video_clk), .I_rst(rst_all), .I_i2s_BCLK(audio_i2s_bclk),
    .I_i2s_LRCK(audio_i2s_lrck), .I_i2s_DOUT(audio_i2s_dout),
    .O_audio_valid(audio_valid), .O_audio_left_data(audio_left_data),
    .O_audio_right_data(audio_right_data)
);

audio_arc_calculate #(.ACR_N(6144)) u_acr (
    .I_clk(video_clk), .I_rst(rst_all), .I_audio_valid(audio_valid),
    .O_acr_valid(acr_valid), .O_acr_cts(acr_cts), .O_acr_n(acr_n)
);

startup_pulse #(.CNT_MAX(20'd100000)) u_startup_pulse (
    .I_clk(video_clk), .I_rst(rst_all), .O_pulse(edid_trig)
);

hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"),
    .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
    .VTOTAL(525), .VSA(2), .VFP(10), .VBP(33), .VACTIVE(480),
    .VIDEO_VIC(1), .VIDEO_TPG(TEST_PATTERN ? "Enable" : "Disable"), .VIDEO_FORMAT("RGB"),
    .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(250)
) u_hdmi_tx (
    .I_pixel_clk(video_clk), .I_rst(rst_all),
    .I_edid_read_trig(edid_trig), .O_edid_read_valid(edid_valid_unused),
    .O_edid_read_data(edid_data_unused), .I_axis_s_user(axis_s_user),
    .I_axis_s_valid(axis_s_valid), .I_axis_s_last(axis_s_last),
    .I_axis_s_data(axis_s_data), .O_axis_s_ready(axis_s_ready),
    .I_audio_valid(audio_valid), .I_audio_left_data(audio_left_data),
    .I_audio_right_data(audio_right_data), .I_acr_valid(acr_valid),
    .I_acr_cts(acr_cts), .I_acr_n(acr_n), .O_video_locked(),
    .O_ddc_scl(ddc_scl), .IO_ddc_sda(ddc_sda),
    .O_ch0_tmds_data(tmds_ch0_data), .O_ch1_tmds_data(tmds_ch1_data),
    .O_ch2_tmds_data(tmds_ch2_data), .O_clk_tmds_data(tmds_clk_data)
);

hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy (
    .I_pixel_clk(video_clk), .I_serial_clk(hdmi_5x_clk), .I_rst(rst_all),
    .I_tmds_channel_0(tmds_ch0_data), .I_tmds_channel_1(tmds_ch1_data),
    .I_tmds_channel_2(tmds_ch2_data), .I_tmds_channel_clk(tmds_clk_data),
    .O_tmds_ch0_p(HDMI_D0_P), .O_tmds_ch1_p(HDMI_D1_P),
    .O_tmds_ch2_p(HDMI_D2_P), .O_tmds_clk_p(HDMI_CLK_P)
);

endmodule
