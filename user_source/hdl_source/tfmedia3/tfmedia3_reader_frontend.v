`timescale 1ns / 1ps

// TFMEDIA3 storage-side integration.  This is intentionally independent of
// the JPEG decoder: it owns SD, parses the catalog/metadata, schedules frames
// and fills alternating 64-KiB SRAM slots.  The decoder can consume a slot
// only after frame_cached pulses.
module tfmedia3_reader_frontend #(
    parameter integer CLK_HZ = 50_000_000
)(
    input             clk,
    input             rst,
    input             key_s1_n,
    input             key_s2_n,

    output            sd_ncs,
    output            sd_dclk,
    output            sd_mosi,
    input             sd_miso,

    output     [18:0] sram_addr,
    inout      [15:0] sram_dq,
    output            sram_ce_n,
    output            sram_we_n,
    output            sram_oe_n,
    output            sram_lb_n,
    output            sram_ub_n,

    input             decode_sram_request,
    input      [18:0] decode_sram_address,
    output     [15:0] decode_sram_read_data,
    output            decode_sram_ready,
    input             decode_ready,
    input             frame_presented,

    input             audio_playback_enable,
    input             audio_sample_request_toggle,
    output            audio_sample_ack_toggle,
    output     [15:0] audio_sample_data,
    output            audio_underflow,

    output reg        paused,
    output reg        frame_cached,
    output reg        frame_tick,
    output reg        cached_slot,
    output reg [16:0] cached_bytes,
    output reg [31:0] cached_frame_number,
    output     [31:0] playback_frame_number,
    output            timeline_active,
    output reg [4:0]  media_index,
    output reg [31:0] frame_number,
    output     [7:0]  media_type,
    output reg [7:0]  player_error,
    output reg [3:0]  player_state,
    output reg        media_changing,
    output subtitle_ram_we, output [12:0] subtitle_ram_address, output [15:0] subtitle_ram_data,
    output [3:0] subtitle_count,input [3:0] subtitle_style_index,output [30:0] subtitle_style_data,
    output [31:0] info_position, info_length, info_rate,
    output [4:0] info_media_count,
    output info_valid,
    output            sd_initialized,
    output            storage_busy
);

localparam [3:0] P_WAIT_CATALOG = 4'd0;
localparam [3:0] P_LOAD_META    = 4'd1;
localparam [3:0] P_META_LOW     = 4'd2;
localparam [3:0] P_WAIT_META    = 4'd3;
localparam [3:0] P_REQ_FRAME    = 4'd4;
localparam [3:0] P_WAIT_FRAME   = 4'd5;
localparam [3:0] P_START_DMA    = 4'd6;
localparam [3:0] P_WAIT_DMA     = 4'd7;
localparam [3:0] P_PLAY         = 4'd8;
localparam [3:0] P_WAIT_ACCEPT  = 4'd9;
localparam [3:0] P_WAIT_PRESENT = 4'd10;
localparam [3:0] P_ERROR        = 4'd15;

localparam integer FRAME_PERIOD_CLKS = CLK_HZ / 25;
localparam integer IMAGE_PERIOD_CLKS = CLK_HZ * 3;

wire s1_pulse;
wire s2_pulse;
wire s1_pressed_unused;
wire s2_pressed_unused;

wire        sd_init_done;
wire        sd_bus_read;
wire [31:0] sd_bus_addr;
wire [7:0]  sd_bus_data;
wire        sd_bus_data_valid;
wire        sd_bus_end;

wire        cat_read;
wire [31:0] cat_addr;
wire        cat_valid;
wire        cat_end;
wire        catalog_ready;
wire [7:0]  catalog_error;
wire [4:0]  entry_count;
wire [31:0] total_sectors_unused;
wire [7:0]  entry_media_type;
wire [7:0]  entry_flags_unused;
wire [15:0] entry_media_id_unused;
wire [31:0] entry_metadata_lba;
wire [31:0] entry_data_lba;
wire [31:0] entry_data_bytes;
wire [3:0]  catalog_debug_unused;

reg         load_media;
reg         frame_request;
wire        meta_read;
wire [31:0] meta_addr;
wire        meta_valid;
wire        meta_end;
wire        metadata_ready;
wire [7:0]  metadata_error;
wire [31:0] frame_index_lba_unused;
wire [31:0] frame_count;
wire [31:0] audio_lba;
wire [31:0] audio_bytes;
wire [31:0] duration_num_unused;
wire [31:0] duration_den_unused;
wire [31:0] fps_num_unused;
wire [31:0] fps_den_unused;
wire        frame_ready;
wire [31:0] frame_offset;
wire [31:0] frame_bytes;
wire [3:0]  metadata_debug_unused;

reg         dma_start;
reg         dma_slot;
wire        dma_read;
wire [31:0] dma_addr;
wire        dma_valid;
wire        dma_end;
wire        dma_busy_unused;
wire        dma_done;
wire [7:0]  dma_error;
wire [16:0] dma_bytes_copied;
wire        sram_request;
wire        sram_write_enable;
wire [18:0] sram_address;
wire [15:0] sram_write_data;
wire [1:0]  sram_byte_enable;
wire        sram_ready;
wire [15:0] sram_read_data_unused;
wire [3:0]  dma_debug_unused;
wire        physical_sram_request;
wire        physical_sram_write_enable;
wire [18:0] physical_sram_address;
wire [15:0] physical_sram_write_data;
wire [1:0]  physical_sram_byte_enable;
wire        physical_sram_ready;
wire [15:0] physical_sram_read_data;

wire [7:0]  arbiter_data;
wire [1:0]  arbiter_client_unused;
wire        arbiter_busy_unused;

reg         audio_configure;
wire        audio_read;
wire [31:0] audio_addr;
wire        audio_valid;
wire        audio_end;
wire [15:0] audio_buffered_bytes_unused;

reg [31:0] play_timer;
wire       timeline_complete;
wire       timeline_tick;
wire       audio_sample_consumed;
reg        switch_pending;
reg [4:0]  last_media_index;
reg [31:0] last_frame_number;
reg [27:0] init_wait_count;

assign info_position = entry_media_type==1 ? play_timer :
                       timeline_complete ? frame_count : playback_frame_number;
assign info_length = entry_media_type==1 ? IMAGE_PERIOD_CLKS : frame_count;
assign info_rate = entry_media_type==1 ? CLK_HZ : 25;
assign info_media_count = entry_count;
assign info_valid = metadata_ready && !media_changing && !switch_pending &&
                    player_error==0 && (player_state>=P_REQ_FRAME && player_state<=P_WAIT_PRESENT);
assign media_type    = entry_media_type;
assign sd_initialized = sd_init_done;
assign storage_busy = arbiter_busy_unused;

tfmedia3_playback_clock #(.CLK_HZ(CLK_HZ)) u_playback_clock (
    .clk(clk), .rst(rst || load_media),
    .start(frame_presented && entry_media_type == 2 && !timeline_active),
    .paused(paused || switch_pending || media_changing),
    .use_audio(audio_bytes != 0), .sample_consumed(audio_sample_consumed),
    .frame_count(frame_count), .active(timeline_active),
    .frame_number(playback_frame_number), .complete(timeline_complete),
    .frame_tick(timeline_tick)
);

button_debounce_pulse #(.STABLE_CLKS(CLK_HZ / 200)) u_s1 (
    .clk(clk), .rst(rst), .button_n(key_s1_n),
    .pressed_pulse(s1_pulse), .pressed(s1_pressed_unused)
);

button_debounce_pulse #(.STABLE_CLKS(CLK_HZ / 200)) u_s2 (
    .clk(clk), .rst(rst), .button_n(key_s2_n),
    .pressed_pulse(s2_pulse), .pressed(s2_pressed_unused)
);

sd_card_top #(
    .SPI_LOW_SPEED_DIV(248),
    .SPI_HIGH_SPEED_DIV(0)
) u_sd (
    .clk(clk), .rst(rst),
    .SD_nCS(sd_ncs), .SD_DCLK(sd_dclk), .SD_MOSI(sd_mosi), .SD_MISO(sd_miso),
    .sd_init_done(sd_init_done),
    .sd_sec_read(sd_bus_read), .sd_sec_read_addr(sd_bus_addr),
    .sd_sec_read_data(sd_bus_data),
    .sd_sec_read_data_valid(sd_bus_data_valid), .sd_sec_read_end(sd_bus_end),
    .sd_sec_write(1'b0), .sd_sec_write_addr(32'd0), .sd_sec_write_data(8'd0),
    .sd_sec_write_data_req(), .sd_sec_write_end()
);

wire [31:0] subtitle_lba;
wire sub_done,sub_read;wire [31:0] sub_addr;wire [3:0] loaded_sub_count;
wire shared_valid,shared_end;
wire subtitle_loading=catalog_ready && !sub_done;
assign cat_valid=shared_valid && !subtitle_loading;
assign cat_end=shared_end && !subtitle_loading;
assign subtitle_count=sub_done ? loaded_sub_count : 4'd0;
subtitle_loader #(.TIMEOUT_CLKS(CLK_HZ*2)) u_subtitles(
 .clk(clk),.rst(rst),.start(catalog_ready),.base_lba(subtitle_lba),.total_sectors(total_sectors_unused),
 .sd_read(sub_read),.sd_addr(sub_addr),.sd_data(arbiter_data),
 .sd_valid(shared_valid && subtitle_loading),.sd_end(shared_end && subtitle_loading),
 .done(sub_done),.count(loaded_sub_count),.style_index(subtitle_style_index),.style_data(subtitle_style_data),
 .ram_we(subtitle_ram_we),.ram_address(subtitle_ram_address),.ram_data(subtitle_ram_data));
sd_sector_arbiter4 u_arbiter (
    .clk(clk), .rst(rst),
    .c0_read(subtitle_loading ? sub_read : cat_read), .c0_addr(subtitle_loading ? sub_addr : cat_addr),
    .c0_data_valid(shared_valid), .c0_read_end(shared_end),
    .c1_read(meta_read), .c1_addr(meta_addr),
    .c1_data_valid(meta_valid), .c1_read_end(meta_end),
    .c2_read(dma_read), .c2_addr(dma_addr),
    .c2_data_valid(dma_valid), .c2_read_end(dma_end),
    .c3_read(audio_read), .c3_addr(audio_addr),
    .c3_data_valid(audio_valid), .c3_read_end(audio_end),
    .sd_read(sd_bus_read), .sd_addr(sd_bus_addr),
    .sd_data(sd_bus_data), .sd_data_valid(sd_bus_data_valid),
    .sd_read_end(sd_bus_end), .client_data(arbiter_data),
    .active_client(arbiter_client_unused), .busy(arbiter_busy_unused)
);

tfmedia3_catalog #(.READ_TIMEOUT_CLKS(CLK_HZ * 2)) u_catalog (
    .clk(clk), .rst(rst), .sd_init_done(sd_init_done),
    .sd_sec_read(cat_read), .sd_sec_read_addr(cat_addr),
    .sd_sec_read_data(arbiter_data),
    .sd_sec_read_data_valid(cat_valid), .sd_sec_read_end(cat_end),
    .catalog_ready(catalog_ready), .error_code(catalog_error),
    .entry_count(entry_count), .total_sectors(total_sectors_unused),.subtitle_lba(subtitle_lba),
    .entry_select(media_index), .entry_media_type(entry_media_type),
    .entry_flags(entry_flags_unused), .entry_media_id(entry_media_id_unused),
    .entry_metadata_lba(entry_metadata_lba), .entry_data_lba(entry_data_lba),
    .entry_data_bytes(entry_data_bytes), .debug_state(catalog_debug_unused)
);

tfmedia3_metadata #(.READ_TIMEOUT_CLKS(CLK_HZ * 2)) u_metadata (
    .clk(clk), .rst(rst), .load_media(load_media),
    .metadata_lba(entry_metadata_lba), .metadata_ready(metadata_ready),
    .error_code(metadata_error), .frame_index_lba(frame_index_lba_unused),
    .frame_count(frame_count), .audio_lba(audio_lba),
    .audio_bytes(audio_bytes), .duration_num(duration_num_unused),
    .duration_den(duration_den_unused), .fps_num(fps_num_unused),
    .fps_den(fps_den_unused), .frame_request(frame_request),
    .frame_number(frame_number), .frame_ready(frame_ready),
    .frame_offset(frame_offset), .frame_bytes(frame_bytes),
    .sd_sec_read(meta_read), .sd_sec_read_addr(meta_addr),
    .sd_sec_read_data(arbiter_data), .sd_sec_read_data_valid(meta_valid),
    .sd_sec_read_end(meta_end), .debug_state(metadata_debug_unused)
);

jpeg_sram_dma #(.READ_TIMEOUT_CLKS(CLK_HZ * 2)) u_dma (
    .clk(clk), .rst(rst), .start(dma_start), .slot_select(dma_slot),
    .data_lba(entry_data_lba), .frame_offset(frame_offset),
    .frame_bytes(frame_bytes), .busy(dma_busy_unused), .done(dma_done),
    .error_code(dma_error), .bytes_copied(dma_bytes_copied),
    .sd_sec_read(dma_read), .sd_sec_read_addr(dma_addr),
    .sd_sec_read_data(arbiter_data), .sd_sec_read_data_valid(dma_valid),
    .sd_sec_read_end(dma_end), .sram_request(sram_request),
    .sram_write_enable(sram_write_enable), .sram_address(sram_address),
    .sram_write_data(sram_write_data), .sram_byte_enable(sram_byte_enable),
    .sram_ready(sram_ready), .debug_state(dma_debug_unused)
);

pcm_audio_buffer u_audio_buffer (
    .clk(clk), .rst(rst), .configure(audio_configure),
    .audio_lba(audio_lba), .audio_bytes(audio_bytes),
    .playback_enable(audio_playback_enable && timeline_active &&
                     !switch_pending && !media_changing),
    .sd_sec_read(audio_read), .sd_sec_read_addr(audio_addr),
    .sd_sec_read_data(arbiter_data),
    .sd_sec_read_data_valid(audio_valid), .sd_sec_read_end(audio_end),
    .sample_request_toggle(audio_sample_request_toggle),
    .sample_ack_toggle(audio_sample_ack_toggle),
    .sample_data(audio_sample_data), .underflow(audio_underflow),
    .sample_consumed(audio_sample_consumed), .playback_done(),
    .buffered_bytes(audio_buffered_bytes_unused)
);

sram_arbiter2 u_sram_arbiter (
    .clk(clk), .rst(rst),
    .c0_request(sram_request), .c0_write_enable(sram_write_enable),
    .c0_address(sram_address), .c0_write_data(sram_write_data),
    .c0_byte_enable(sram_byte_enable), .c0_read_data(sram_read_data_unused),
    .c0_ready(sram_ready),
    .c1_request(decode_sram_request), .c1_write_enable(1'b0),
    .c1_address(decode_sram_address), .c1_write_data(16'd0),
    .c1_byte_enable(2'b11), .c1_read_data(decode_sram_read_data),
    .c1_ready(decode_sram_ready),
    .mem_request(physical_sram_request),
    .mem_write_enable(physical_sram_write_enable),
    .mem_address(physical_sram_address),
    .mem_write_data(physical_sram_write_data),
    .mem_byte_enable(physical_sram_byte_enable),
    .mem_read_data(physical_sram_read_data), .mem_ready(physical_sram_ready)
);

async_sram16_controller u_sram (
    .clk(clk), .rst(rst), .request(physical_sram_request),
    .write_enable(physical_sram_write_enable), .address(physical_sram_address),
    .write_data(physical_sram_write_data), .byte_enable(physical_sram_byte_enable),
    .read_data(physical_sram_read_data), .ready(physical_sram_ready),
    .sram_addr(sram_addr), .sram_dq(sram_dq), .sram_ce_n(sram_ce_n),
    .sram_we_n(sram_we_n), .sram_oe_n(sram_oe_n),
    .sram_lb_n(sram_lb_n), .sram_ub_n(sram_ub_n)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        paused       <= 1'b0;
        frame_cached <= 1'b0;
        frame_tick   <= 1'b0;
        cached_slot  <= 1'b0;
        cached_bytes <= 17'd0;
        cached_frame_number <= 32'd0;
        media_index  <= 5'd0;
        frame_number <= 32'd0;
        player_error <= 8'd0;
        player_state <= P_WAIT_CATALOG;
        load_media   <= 1'b0;
        frame_request <= 1'b0;
        dma_start    <= 1'b0;
        dma_slot     <= 1'b0;
        play_timer   <= 32'd0;
        last_media_index <= 5'd0;
        last_frame_number <= 32'd0;
        audio_configure <= 1'b0;
        media_changing <= 1'b0;
        switch_pending <= 1'b0;
        init_wait_count <= 0;
    end else begin
        load_media    <= 1'b0;
        frame_request <= 1'b0;
        dma_start     <= 1'b0;
        frame_cached  <= 1'b0;
        frame_tick    <= 1'b0;
        audio_configure <= 1'b0;
        media_changing <= switch_pending;

        if (s2_pulse)
            paused <= ~paused;
        if (s1_pulse) begin
            switch_pending <= 1'b1;
            media_changing <= 1'b1;
        end

        if (timeline_tick) frame_tick <= 1'b1;

        case (player_state)
            P_WAIT_CATALOG: begin
                if (catalog_error != 0) begin
                    player_error <= catalog_error;
                    player_state <= P_ERROR;
                end else if (catalog_ready && sub_done) begin
                    media_index  <= 5'd0;
                    last_media_index <= (entry_count == 0) ? 5'd0 :
                                        (entry_count - 1'b1);
                    player_state <= P_LOAD_META;
                end else if (!sd_init_done) begin
                    if (init_wait_count == CLK_HZ*5-1) begin
                        player_error <= 8'h07;
                        player_state <= P_ERROR;
                    end else init_wait_count <= init_wait_count + 1'b1;
                end
            end

            P_LOAD_META: begin
              if (catalog_error != 0) begin
                player_error <= catalog_error;
                player_state <= P_ERROR;
              end else if (catalog_ready) begin
                load_media   <= 1'b1;
                media_changing <= 1'b1;
                frame_number <= 32'd0;
                dma_slot     <= 1'b0;
                play_timer   <= 32'd0;
                player_state <= P_META_LOW;
              end
            end

            P_META_LOW: begin
                if (!metadata_ready)
                    player_state <= P_WAIT_META;
            end

            P_WAIT_META: begin
                if (metadata_error != 0) begin
                    player_error <= metadata_error;
                    player_state <= P_ERROR;
                end else if (metadata_ready) begin
                    last_frame_number <= (frame_count == 0) ? 32'd0 :
                                         (frame_count - 1'b1);
                    if (fps_num_unused != 25 || fps_den_unused != 1) begin
                        player_error <= 8'h18;
                        player_state <= P_ERROR;
                    end else begin
                        audio_configure <= 1'b1;
                        player_state <= P_REQ_FRAME;
                    end
                end
            end

            P_REQ_FRAME: begin
                // Index directly into the current timeline when storage has
                // fallen behind. Preload one frame ahead of the playhead.
                if (entry_media_type == 2 && timeline_active &&
                    frame_number <= playback_frame_number &&
                    frame_number < last_frame_number) begin
                    frame_number <= (playback_frame_number < last_frame_number) ?
                                    playback_frame_number + 1'b1 : last_frame_number;
                end else begin
                    frame_request <= 1'b1;
                    player_state  <= P_WAIT_FRAME;
                end
            end

            P_WAIT_FRAME: begin
                if (metadata_error != 0) begin
                    player_error <= metadata_error;
                    player_state <= P_ERROR;
                end else if (frame_ready) begin
                    if ({1'b0,frame_offset}+{1'b0,frame_bytes} > {1'b0,entry_data_bytes}) begin
                        player_error <= 8'h19;
                        player_state <= P_ERROR;
                    end else player_state <= P_START_DMA;
                end
            end

            P_START_DMA: begin
                dma_start    <= 1'b1;
                player_state <= P_WAIT_DMA;
            end

            P_WAIT_DMA: begin
                if (dma_error != 0) begin
                    player_error <= dma_error;
                    player_state <= P_ERROR;
                end else if (dma_done) begin
                    cached_slot  <= dma_slot;
                    cached_bytes <= dma_bytes_copied;
                    player_state <= P_WAIT_ACCEPT;
                end
            end

            P_WAIT_ACCEPT: begin
                if (switch_pending && decode_ready) begin
                    if (media_index == last_media_index)
                        media_index <= 5'd0;
                    else
                        media_index <= media_index + 1'b1;
                    switch_pending <= 1'b0;
                    player_error <= 8'd0;
                    player_state <= P_LOAD_META;
                end else if (decode_ready && entry_media_type == 2 && timeline_active &&
                             playback_frame_number > frame_number &&
                             playback_frame_number - frame_number > 1 &&
                             frame_number < last_frame_number) begin
                    // The cached JPEG has missed more than one frame period.
                    // Reuse its unsubmitted SRAM slot for an up-to-date frame.
                    frame_number <= (playback_frame_number < last_frame_number) ?
                                    playback_frame_number + 1'b1 : last_frame_number;
                    player_state <= P_REQ_FRAME;
                end else if (decode_ready) begin
                    frame_cached <= 1'b1;
                    cached_frame_number <= frame_number;
                    if (!timeline_active) frame_tick <= 1'b1;
                    // Cache the next compressed frame while this one decodes.
                    // decode_ready includes presentation ownership, so the next
                    // decoder submission cannot overwrite an unconsumed page.
                    if (entry_media_type == 2 && frame_number < last_frame_number) begin
                        frame_number <= frame_number + 1'b1;
                        dma_slot <= ~cached_slot;
                        player_state <= P_REQ_FRAME;
                    end else player_state <= P_WAIT_PRESENT;
                end
            end

            P_WAIT_PRESENT: begin
                if (frame_presented) begin
                    player_state <= P_PLAY;
                end
                if (switch_pending && decode_ready) begin
                    media_index <= (media_index == last_media_index) ? 0 : media_index+1'b1;
                    switch_pending <= 0;
                    player_state <= P_LOAD_META;
                end
            end

            P_PLAY: begin
                if ((s1_pulse || switch_pending) && decode_ready) begin
                    if (media_index == last_media_index)
                        media_index <= 5'd0;
                    else
                        media_index <= media_index + 1'b1;
                    switch_pending <= 1'b0;
                    player_error <= 8'd0;
                    player_state <= P_LOAD_META;
                end else if (!paused) begin
                    if (entry_media_type == 8'd1) begin
                        if (play_timer == IMAGE_PERIOD_CLKS - 1) begin
                            play_timer <= 32'd0;
                            if (media_index == last_media_index)
                                media_index <= 5'd0;
                            else
                                media_index <= media_index + 1'b1;
                            player_state <= P_LOAD_META;
                        end else begin
                            play_timer <= play_timer + 1'b1;
                        end
                    end else begin
                        if (timeline_complete) begin
                            play_timer <= 32'd0;
                            if (media_index == last_media_index)
                                media_index <= 5'd0;
                            else media_index <= media_index + 1'b1;
                            player_state <= P_LOAD_META;
                        end
                    end
                end
            end

            default: begin
                player_state <= P_ERROR;
            end
        endcase
    end
end

endmodule

// 48,000 PCM samples / 25 frames = exactly 1,920 samples per frame.
// Only consumed PCM advances an audio clip. Silent clips use reader_clk.
// Pause stops new PCM reads; count an already-in-flight sample that finishes
// at the pause edge, including the last sample, so EOF cannot lose one count.
module tfmedia3_playback_clock #(
    parameter integer CLK_HZ = 40_000_000
)(
    input clk, rst, start, paused, use_audio, sample_consumed,
    input [31:0] frame_count,
    output reg active,
    output reg [31:0] frame_number,
    output reg complete,
    output reg frame_tick
);
reg [10:0] samples_in_frame;
reg [31:0] clock_in_frame;
wire period_end = use_audio ? (sample_consumed && samples_in_frame == 1919) :
                             (clock_in_frame == CLK_HZ/25 - 1);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        active <= 0; frame_number <= 0; complete <= 0; frame_tick <= 0;
        samples_in_frame <= 0; clock_in_frame <= 0;
    end else begin
        frame_tick <= 0;
        if(start && !active) begin
            active <= 1; frame_number <= 0; complete <= 0;
            samples_in_frame <= 0; clock_in_frame <= 0;
        end else if(active && !complete && (!paused || (use_audio && sample_consumed))) begin
            if(period_end) begin
                samples_in_frame <= 0; clock_in_frame <= 0;
                frame_tick <= 1;
                if(frame_number + 1 >= frame_count) complete <= 1;
                else frame_number <= frame_number + 1'b1;
            end else if(use_audio) begin
                if(sample_consumed) samples_in_frame <= samples_in_frame + 1'b1;
            end else clock_in_frame <= clock_in_frame + 1'b1;
        end
    end
end
endmodule
