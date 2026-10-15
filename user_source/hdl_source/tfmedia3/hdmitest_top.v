`timescale 1ns/1ps
// Vendor HDMI internal pattern generator. No card, JPEG or SDRAM dependency.
module hdmitest_top(
    input clk,input key_s1_n,input key_s2_n,input key_reset_n,
    output HDMI_CLK_P,output HDMI_D2_P,output HDMI_D1_P,output HDMI_D0_P,
    output seg7_sclk,output seg7_rclk,output seg7_dio
);
wire board_rst,video_rst,pixel_clk,serial_clk;
power_on_reset u_por(clk,key_reset_n,board_rst);
video_pll u_video_pll(.refclk(clk),.reset(1'b0),.clk0_out(pixel_clk),.clk1_out(serial_clk));
reset_sync u_reset(pixel_clk,board_rst,video_rst);
wire trigger,ddc_scl;
tri1 ddc_sda;
wire [9:0] c0,c1,c2,cc;
startup_pulse #(.CNT_MAX(20'd100000)) u_startup(pixel_clk,video_rst,trigger);
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
    .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),.VIDEO_VIC(1),
    .VIDEO_TPG("Enable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)
) u_tx(
    .I_pixel_clk(pixel_clk),.I_rst(video_rst),.I_edid_read_trig(trigger),
    .I_axis_s_user(1'b0),.I_axis_s_valid(1'b0),.I_axis_s_last(1'b0),.I_axis_s_data(24'b0),
    .I_audio_valid(1'b0),.I_audio_left_data(24'b0),.I_audio_right_data(24'b0),
    .I_acr_valid(1'b0),.I_acr_cts(20'b0),.I_acr_n(20'd6144),
    .O_ddc_scl(ddc_scl),.IO_ddc_sda(ddc_sda),
    .O_ch0_tmds_data(c0),.O_ch1_tmds_data(c1),.O_ch2_tmds_data(c2),.O_clk_tmds_data(cc));
hdmi_phy_wrapper #(.DEVICE("EG")) u_phy(
    .I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(video_rst),
    .I_tmds_channel_0(c0),.I_tmds_channel_1(c1),.I_tmds_channel_2(c2),.I_tmds_channel_clk(cc),
    .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
segtest_top u_digits(clk,key_s1_n,key_s2_n,key_reset_n,seg7_sclk,seg7_rclk,seg7_dio);
endmodule
