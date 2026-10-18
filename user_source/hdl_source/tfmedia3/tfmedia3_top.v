`timescale 1ns / 1ps

// AC201 carrier / AC601 core-board TFMEDIA3 media player.
module tfmedia3_top #(
    parameter integer TEST_PATTERN = 0,
    // Board feedback: four wiring-select presses from reset => config 4.
    // Active-high digit select, active-low segments, segment byte first.
    parameter [3:0] SEG_CONFIG = 4'd4
)(
    input  wire clk,
    input  wire key_s1_n,
    input  wire key_s2_n,
    input  wire key_reset_n,
    input  wire [7:0] sw_n,

    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P,

    output wire sd_ncs,
    output wire sd_dclk,
    output wire sd_mosi,
    input  wire sd_miso,

    output wire seg7_sclk,
    output wire seg7_rclk,
    output wire seg7_dio,

    output wire [18:0] sram_addr,
    inout  wire [15:0] sram_dq,
    output wire        sram_ce_n,
    output wire        sram_we_n,
    output wire        sram_oe_n,
    output wire        sram_lb_n,
    output wire        sram_ub_n
);

wire       ddc_scl_unused;
tri1       ddc_sda_pullup;
wire       reader_clk;
wire board_rst, reader_rst;
power_on_reset u_por(.clk(clk), .reset_n(key_reset_n), .rst(board_rst));
reset_sync u_reader_reset(.clk(reader_clk), .async_rst(board_rst), .rst(reader_rst));
wire presentation_busy, frame_presented;
reg presentation_submit;
wire reader_decode_ready = decode_ready && !decode_done &&
                           !decoded_pending && !presentation_busy && !presentation_submit;
wire target_slot = ~display_slot;
wire       reader_pll_clk_unused;
wire       reader_mem_clk;
wire       reader_mem_clk_sft;

wire       player_paused;
wire       frame_cached;
wire       frame_tick;
wire       cached_slot;
wire [16:0] cached_bytes;
wire [31:0] cached_frame_number, playback_frame_number;
wire timeline_active;
wire [4:0] media_index;
wire [31:0] frame_number;
wire [7:0] media_type;
wire [7:0] player_error;
wire [7:0] debug_error;
wire [3:0] player_state;
wire       sd_initialized;
wire [63:0] debug_segments;
wire       decode_sram_request;
wire [18:0] decode_sram_address;
wire [15:0] decode_sram_read_data;
wire       decode_sram_ready;
wire       frame_write_req;
wire       frame_write_req_ack;
wire       frame_write_en;
wire [31:0] frame_write_data;
wire       frame_write_slot;
wire       frame_write_finish;
wire       decode_done;
wire       decode_ready;
wire       decoded_slot;
wire [7:0] decode_error;
wire [3:0] decode_state;
wire [19:0] decode_debug;
reg decode_recover;
wire       media_changing;
wire       audio_sample_request_toggle;
wire       audio_sample_ack_toggle;
wire [15:0] audio_sample_data;
wire audio_raw_ack;
wire [15:0] audio_raw_data;
wire next_key_n, pause_key_n, volume_mode;
wire [4:0] volume;
wire brightness_mode;
wire [4:0] brightness;
wire contrast_mode;
wire [4:0] contrast;
wire scroll_setting;
wire wave_setting;
button_debounce_pulse #(.STABLE_CLKS(200_000)) u_wave_switch (
    .clk(reader_clk), .rst(reader_rst), .button_n(sw_n[4]),
    .pressed(wave_setting), .pressed_pulse()
);
reg picture_playing;
reg [1:0] pause_status;
button_debounce_pulse #(.STABLE_CLKS(200_000)) u_scroll_switch (
    .clk(reader_clk), .rst(reader_rst), .button_n(sw_n[3]),
    .pressed(scroll_setting), .pressed_pulse()
);
always @(posedge reader_clk or posedge reader_rst) begin
    if(reader_rst) begin picture_playing <= 0;pause_status<=0;end
    else begin
        picture_playing <= display_valid &&
            (media_type == 8'd1 || media_type == 8'd2) && !media_changing;
        pause_status<=display_valid && player_paused && !media_changing ?
            (media_type==8'd1 ? 2'd2 : media_type==8'd2 ? 2'd1 : 2'd0) : 2'd0;
    end
end
player_volume_control u_volume (
    .clk(reader_clk), .rst(reader_rst), .sw0_n(sw_n[0]), .sw1_n(sw_n[1]), .sw2_n(sw_n[2]),
    .key_up_n(key_s1_n), .key_down_n(key_s2_n),
    .next_key_n(next_key_n), .pause_key_n(pause_key_n),
    .volume_mode(volume_mode), .volume(volume),
    .brightness_mode(brightness_mode), .brightness(brightness),
    .contrast_mode(contrast_mode), .contrast(contrast),
    .sample_ack_in(audio_raw_ack), .sample_in(audio_raw_data),
    .sample_ack_out(audio_sample_ack_toggle), .sample_out(audio_sample_data)
);
wire       audio_underflow;
wire       audio_playback_enable;
reg        display_valid;
reg        display_slot;
reg        decoded_pending;
reg        pending_decoded_slot;
reg [31:0] decoding_frame_number, pending_frame_number;

// Digit 7..0: error byte, decoder state, frame nibble, paused, media type,
// selected media and player state.  This remains useful before HDMI decode.
function [7:0] hex_segment;
    input [3:0] value;
    begin
        case (value)
            4'h0: hex_segment = 8'b1_1000000;
            4'h1: hex_segment = 8'b1_1111001;
            4'h2: hex_segment = 8'b1_0100100;
            4'h3: hex_segment = 8'b1_0110000;
            4'h4: hex_segment = 8'b1_0011001;
            4'h5: hex_segment = 8'b1_0010010;
            4'h6: hex_segment = 8'b1_0000010;
            4'h7: hex_segment = 8'b1_1111000;
            4'h8: hex_segment = 8'b1_0000000;
            4'h9: hex_segment = 8'b1_0010000;
            4'hA: hex_segment = 8'b1_0001000;
            4'hB: hex_segment = 8'b1_0000011;
            4'hC: hex_segment = 8'b1_1000110;
            4'hD: hex_segment = 8'b1_0100001;
            4'hE: hex_segment = 8'b1_0000110;
            default: hex_segment = 8'b1_0001110;
        endcase
    end
endfunction

// Timeout display: 34 S F WWWW. The decoder freezes the pre-error state,
// four completion flags and input-word index for board diagnosis.
assign debug_segments = (debug_error == 8'h34) ? {
    hex_segment(4'h3), hex_segment(4'h4), hex_segment(decode_state),
    hex_segment(decode_debug[19:16]), hex_segment(decode_debug[15:12]),
    hex_segment(decode_debug[11:8]), hex_segment(decode_debug[7:4]),
    hex_segment(decode_debug[3:0])
} : volume_mode ? {
    8'hff, 8'hff, 8'hff, 8'hff, 8'hc1, 8'hc7,
    hex_segment({3'd0, volume[4]}), hex_segment(volume[3:0])
} : {
    hex_segment(debug_error[7:4]),
    hex_segment(debug_error[3:0]),
    hex_segment(decode_state),
    hex_segment(frame_number[3:0]),
    hex_segment({3'd0, player_paused}),
    hex_segment(media_type[3:0]),
    hex_segment(media_index[3:0]),
    hex_segment(player_state)
};

// Reuse the reference system PLL. CLKC3 supplies the timing-closed 40-MHz
// reader/JPEG domain; CLKC1/2 retain the SDRAM clock pair.
sys_pll u_reader_pll (
    .refclk(clk),
    .clk0_out(reader_pll_clk_unused),
    .clk1_out(reader_mem_clk),
    .clk2_out(reader_mem_clk_sft),
    .clk3_out(reader_clk),
    .reset(1'b0)
);

// The fourth output of the existing system PLL is 40 MHz.  Post-route timing
// showed this is the fastest closed setting for the JPEG Huffman datapath.
assign debug_error = (player_error != 0) ? player_error :
                     (decode_error != 0) ? decode_error :
                     (audio_underflow ? 8'h41 : 8'h00);
assign audio_playback_enable = display_valid && (media_type == 8'd2) &&
                               !player_paused;

// The HDMI wrapper contains the verified clock/PHY/audio chain and the
// SDRAM-backed 640x480 display path. It does not instantiate a FAT reader.
tfmedia3_hdmi_shell #(.TEST_PATTERN(TEST_PATTERN)) u_hdmi_shell (
    .clk          (clk),
    .rst          (board_rst),
    .reader_clk   (reader_clk),
    .mem_clk      (reader_mem_clk),
    .mem_clk_sft  (reader_mem_clk_sft),
    .frame_write_req(frame_write_req),
    .frame_write_req_ack(frame_write_req_ack),
    .frame_write_en(frame_write_en),
    .frame_write_data(frame_write_data),
    .frame_write_slot(frame_write_slot),
    .frame_write_finish(frame_write_finish),
    .display_valid(display_valid),
    .display_slot(display_slot),
    .display_submit(presentation_submit),
    .presentation_busy(presentation_busy), .frame_presented(frame_presented),
    .audio_sample_request_toggle(audio_sample_request_toggle),
    .audio_sample_ack_toggle(audio_sample_ack_toggle),
    .audio_sample_data(audio_sample_data),
    .volume_setting(volume_mode), .volume_level(volume),
    .brightness_setting(brightness_mode), .brightness_level(brightness),
    .contrast_setting(contrast_mode), .contrast_level(contrast),
    .scroll_setting(scroll_setting), .picture_playing(picture_playing),
    .wave_setting(wave_setting),
    .display_picture(media_type==8'd1),.pause_status(pause_status),
    .HDMI_CLK_P   (HDMI_CLK_P),
    .HDMI_D2_P    (HDMI_D2_P),
    .HDMI_D1_P    (HDMI_D1_P),
    .HDMI_D0_P    (HDMI_D0_P),
    .ddc_scl      (ddc_scl_unused),
    .ddc_sda      (ddc_sda_pullup)
);

// The storage path owns the physical TF pins and fills the external SRAM.
tfmedia3_reader_frontend #(.CLK_HZ(40_000_000)) u_reader (
    .clk           (reader_clk),
    .rst           (reader_rst),
    .key_s1_n      (next_key_n),
    .key_s2_n      (pause_key_n),
    .sd_ncs        (sd_ncs),
    .sd_dclk       (sd_dclk),
    .sd_mosi       (sd_mosi),
    .sd_miso       (sd_miso),
    .sram_addr     (sram_addr),
    .sram_dq       (sram_dq),
    .sram_ce_n     (sram_ce_n),
    .sram_we_n     (sram_we_n),
    .sram_oe_n     (sram_oe_n),
    .sram_lb_n     (sram_lb_n),
    .sram_ub_n     (sram_ub_n),
    .decode_sram_request(decode_sram_request),
    .decode_sram_address(decode_sram_address),
    .decode_sram_read_data(decode_sram_read_data),
    .decode_sram_ready(decode_sram_ready),
    .decode_ready  (reader_decode_ready), .frame_presented(frame_presented),
    .audio_playback_enable(audio_playback_enable),
    .audio_sample_request_toggle(audio_sample_request_toggle),
    .audio_sample_ack_toggle(audio_raw_ack),
    .audio_sample_data(audio_raw_data),
    .audio_underflow(audio_underflow),
    .paused        (player_paused),
    .frame_cached  (frame_cached),
    .frame_tick    (frame_tick),
    .cached_slot   (cached_slot),
    .cached_bytes  (cached_bytes),
    .cached_frame_number(cached_frame_number),
    .playback_frame_number(playback_frame_number), .timeline_active(timeline_active),
    .media_index   (media_index),
    .frame_number  (frame_number),
    .media_type    (media_type),
    .player_error  (player_error),
    .player_state  (player_state),
    .media_changing(media_changing),
    .sd_initialized(sd_initialized)
);

// A failed decode must not keep a user media-switch request waiting forever
// for decode_ready. Register the reset request to avoid a combinational loop
// through decode_error. The frontend already holds media_changing while the
// debounced next-media request is pending and resets the write FIFO on retry.
always @(posedge reader_clk or posedge reader_rst) begin
    if (reader_rst) decode_recover <= 1'b0;
    else decode_recover <= media_changing && (decode_error != 0);
end

jpeg_decode_pipeline u_decode (
    .clk(reader_clk), .rst(reader_rst | decode_recover),
    .frame_cached(frame_cached), .cached_slot(cached_slot),
    .cached_bytes(cached_bytes), .target_slot(target_slot), .sram_request(decode_sram_request),
    .sram_address(decode_sram_address),
    .sram_read_data(decode_sram_read_data), .sram_ready(decode_sram_ready),
    .frame_write_req(frame_write_req),
    .frame_write_req_ack(frame_write_req_ack),
    .frame_write_en(frame_write_en), .frame_write_data(frame_write_data),
    .frame_write_slot(frame_write_slot),
    .frame_write_finish(frame_write_finish), .decode_done(decode_done),
    .decode_ready(decode_ready),
    .decoded_slot(decoded_slot), .decode_error(decode_error),
    .decode_state(decode_state), .decode_debug(decode_debug)
);

// A frame is exposed only when both its decode and its presentation deadline
// have occurred.  This freezes the selected SDRAM page while paused.
always @(posedge reader_clk or posedge reader_rst) begin
    if (reader_rst) begin
        presentation_submit <= 1'b0;
        display_valid        <= 1'b0;
        display_slot         <= 1'b0;
        decoded_pending      <= 1'b0;
        pending_decoded_slot <= 1'b0;
        decoding_frame_number <= 0;
        pending_frame_number <= 0;
    end else if (media_changing) begin
        presentation_submit <= 1'b0;
        display_valid        <= 1'b0;
        decoded_pending      <= 1'b0;
        pending_decoded_slot <= 1'b0;
        decoding_frame_number <= 0;
        pending_frame_number <= 0;
    end else begin
        presentation_submit <= 1'b0;
        if (frame_cached) decoding_frame_number <= cached_frame_number;
        if (decode_done) begin
            decoded_pending      <= 1'b1;
            pending_decoded_slot <= decoded_slot;
            pending_frame_number <= decoding_frame_number;
        end
        if ((media_type != 2 || !timeline_active ||
             playback_frame_number >= (decode_done ? decoding_frame_number : pending_frame_number)) &&
            (decoded_pending || decode_done) && !player_paused &&
            !presentation_busy && !presentation_submit) begin
            presentation_submit <= 1'b1;
            display_valid   <= 1'b1;
            display_slot    <= decode_done ? decoded_slot : pending_decoded_slot;
            decoded_pending <= 1'b0;
        end
    end
end

seg7_serial_8digit #(
    .CLK_HZ(40_000_000),
    .DIGIT_ACTIVE_LOW(0),
    .SEGMENT_ACTIVE_LOW(1)
) u_seg7 (
    .clk           (reader_clk),
    .rst           (reader_rst),
    .segment_bytes (debug_segments), .config_bits(SEG_CONFIG),
    .seg7_sclk     (seg7_sclk),
    .seg7_rclk     (seg7_rclk),
    .seg7_dio      (seg7_dio)
);

endmodule

