`timescale 1ns / 1ps

// Reads and validates the TFMEDIA3 superblock and its first index sector.
// The current writer allows at most 20 entries, so one 512-byte index sector
// is sufficient. Only the selected entry is cached; wait for catalog_ready
// after changing entry_select before consuming it.
module tfmedia3_catalog #(
    parameter integer MAX_ENTRIES       = 20,
    parameter integer READ_TIMEOUT_CLKS = 100_000_000
)(
    input              clk,
    input              rst,

    input              sd_init_done,
    output reg         sd_sec_read,
    output reg [31:0]  sd_sec_read_addr,
    input      [7:0]   sd_sec_read_data,
    input              sd_sec_read_data_valid,
    input              sd_sec_read_end,

    output             catalog_ready,
    output reg [7:0]   error_code,
    output reg [4:0]   entry_count,
    output reg [31:0]  total_sectors,

    input      [4:0]   entry_select,
    output reg [7:0]   entry_media_type,
    output reg [7:0]   entry_flags,
    output reg [15:0]  entry_media_id,
    output reg [31:0]  entry_metadata_lba,
    output reg [31:0]  entry_data_lba,
    output reg [31:0]  entry_data_bytes,

    output reg [3:0]   debug_state
);

localparam [3:0] S_WAIT_INIT  = 4'd0;
localparam [3:0] S_REQ_SUPER  = 4'd1;
localparam [3:0] S_READ_SUPER = 4'd2;
localparam [3:0] S_CHECK_SUPER = 4'd3;
localparam [3:0] S_REQ_INDEX   = 4'd4;
localparam [3:0] S_READ_INDEX  = 4'd5;
localparam [3:0] S_CHECK_INDEX = 4'd6;
localparam [3:0] S_READY       = 4'd7;
localparam [3:0] S_ERROR      = 4'd15;

localparam [7:0] ERR_NONE          = 8'h00;
localparam [7:0] ERR_SUPER_MAGIC   = 8'h01;
localparam [7:0] ERR_SUPER_FORMAT  = 8'h02;
localparam [7:0] ERR_SUPER_CRC     = 8'h03;
localparam [7:0] ERR_ENTRY_COUNT   = 8'h04;
localparam [7:0] ERR_READ_TIMEOUT  = 8'h05;
localparam [7:0] ERR_SECTOR_LENGTH = 8'h06;

reg [3:0] state;
reg [9:0] byte_count;
reg [31:0] timeout_count;

reg        magic_ok;
reg [15:0] version;
reg [15:0] header_bytes;
reg [15:0] entry_size;
reg [15:0] entry_count_raw;
reg [31:0] index_lba;
reg [31:0] index_sectors;
reg [15:0] width;
reg [15:0] height;
reg [31:0] fps_num;
reg [31:0] fps_den;
reg [15:0] audio_channels;
reg [15:0] audio_bits;
reg [31:0] audio_rate;
reg [31:0] stored_crc;
reg [31:0] crc_state;

// Cache only the current directory entry. Switching media re-reads one
// 512-byte index sector, saving >2400 resettable FFs and large mux trees.
reg [4:0] loaded_select;
assign catalog_ready = (state==S_READY) && (loaded_select==entry_select);

function [31:0] crc32_next;
    input [31:0] crc;
    input [7:0] data;
    integer bit_index;
    reg [31:0] value;
    begin
        value = crc ^ {24'd0, data};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            if (value[0])
                value = (value >> 1) ^ 32'hEDB8_8320;
            else
                value = value >> 1;
        end
        crc32_next = value;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state              <= S_WAIT_INIT;
        debug_state        <= S_WAIT_INIT;
        sd_sec_read        <= 1'b0;
        sd_sec_read_addr   <= 32'd0;

        error_code         <= ERR_NONE;
        entry_count        <= 5'd0;
        total_sectors      <= 32'd0;
        byte_count         <= 10'd0;
        timeout_count      <= 32'd0;
        magic_ok           <= 1'b1;
        version            <= 16'd0;
        header_bytes       <= 16'd0;
        entry_size         <= 16'd0;
        entry_count_raw    <= 16'd0;
        index_lba          <= 32'd0;
        index_sectors      <= 32'd0;
        width              <= 16'd0;
        height             <= 16'd0;
        fps_num            <= 32'd0;
        fps_den            <= 32'd0;
        audio_channels     <= 16'd0;
        audio_bits         <= 16'd0;
        audio_rate         <= 32'd0;
        stored_crc         <= 32'd0;
        crc_state          <= 32'hFFFF_FFFF;
        loaded_select <= 0;
        entry_media_type <= 0;
        entry_flags <= 0;
        entry_media_id <= 0;
        entry_metadata_lba <= 0;
        entry_data_lba <= 0;
        entry_data_bytes <= 0;
    end else begin
        sd_sec_read <= 1'b0;
        debug_state <= state;

        if ((state == S_READ_SUPER) || (state == S_READ_INDEX)) begin
            if (timeout_count < READ_TIMEOUT_CLKS)
                timeout_count <= timeout_count + 1'b1;
            else begin
                error_code <= ERR_READ_TIMEOUT;
                state <= S_ERROR;
            end
        end else begin
            timeout_count <= 32'd0;
        end

        case (state)
            S_WAIT_INIT: begin

                if (sd_init_done)
                    state <= S_REQ_SUPER;
            end

            S_REQ_SUPER: begin
                sd_sec_read      <= 1'b1;
                sd_sec_read_addr <= 32'd0;
                byte_count       <= 10'd0;
                magic_ok         <= 1'b1;
                crc_state        <= 32'hFFFF_FFFF;
                stored_crc       <= 32'd0;
                state            <= S_READ_SUPER;
            end

            S_READ_SUPER: begin
                if (sd_sec_read_data_valid) begin
                    if (byte_count < 10'd508)
                        crc_state <= crc32_next(crc_state, sd_sec_read_data);

                    case (byte_count)
                        10'd0: if (sd_sec_read_data != "T") magic_ok <= 1'b0;
                        10'd1: if (sd_sec_read_data != "F") magic_ok <= 1'b0;
                        10'd2: if (sd_sec_read_data != "M") magic_ok <= 1'b0;
                        10'd3: if (sd_sec_read_data != "E") magic_ok <= 1'b0;
                        10'd4: if (sd_sec_read_data != "D") magic_ok <= 1'b0;
                        10'd5: if (sd_sec_read_data != "I") magic_ok <= 1'b0;
                        10'd6: if (sd_sec_read_data != "A") magic_ok <= 1'b0;
                        10'd7: if (sd_sec_read_data != "3") magic_ok <= 1'b0;
                        10'd8:  version[7:0]          <= sd_sec_read_data;
                        10'd9:  version[15:8]         <= sd_sec_read_data;
                        10'd10: header_bytes[7:0]     <= sd_sec_read_data;
                        10'd11: header_bytes[15:8]    <= sd_sec_read_data;
                        10'd12: entry_size[7:0]       <= sd_sec_read_data;
                        10'd13: entry_size[15:8]      <= sd_sec_read_data;
                        10'd14: entry_count_raw[7:0]  <= sd_sec_read_data;
                        10'd15: entry_count_raw[15:8] <= sd_sec_read_data;
                        10'd16: index_lba[7:0]        <= sd_sec_read_data;
                        10'd17: index_lba[15:8]       <= sd_sec_read_data;
                        10'd18: index_lba[23:16]      <= sd_sec_read_data;
                        10'd19: index_lba[31:24]      <= sd_sec_read_data;
                        10'd20: index_sectors[7:0]    <= sd_sec_read_data;
                        10'd21: index_sectors[15:8]   <= sd_sec_read_data;
                        10'd22: index_sectors[23:16]  <= sd_sec_read_data;
                        10'd23: index_sectors[31:24]  <= sd_sec_read_data;
                        10'd24: width[7:0]            <= sd_sec_read_data;
                        10'd25: width[15:8]           <= sd_sec_read_data;
                        10'd26: height[7:0]           <= sd_sec_read_data;
                        10'd27: height[15:8]          <= sd_sec_read_data;
                        10'd28: fps_num[7:0]          <= sd_sec_read_data;
                        10'd29: fps_num[15:8]         <= sd_sec_read_data;
                        10'd30: fps_num[23:16]        <= sd_sec_read_data;
                        10'd31: fps_num[31:24]        <= sd_sec_read_data;
                        10'd32: fps_den[7:0]          <= sd_sec_read_data;
                        10'd33: fps_den[15:8]         <= sd_sec_read_data;
                        10'd34: fps_den[23:16]        <= sd_sec_read_data;
                        10'd35: fps_den[31:24]        <= sd_sec_read_data;
                        10'd36: audio_channels[7:0]   <= sd_sec_read_data;
                        10'd37: audio_channels[15:8]  <= sd_sec_read_data;
                        10'd38: audio_bits[7:0]       <= sd_sec_read_data;
                        10'd39: audio_bits[15:8]      <= sd_sec_read_data;
                        10'd40: audio_rate[7:0]       <= sd_sec_read_data;
                        10'd41: audio_rate[15:8]      <= sd_sec_read_data;
                        10'd42: audio_rate[23:16]     <= sd_sec_read_data;
                        10'd43: audio_rate[31:24]     <= sd_sec_read_data;
                        10'd48: total_sectors[7:0]    <= sd_sec_read_data;
                        10'd49: total_sectors[15:8]   <= sd_sec_read_data;
                        10'd50: total_sectors[23:16]  <= sd_sec_read_data;
                        10'd51: total_sectors[31:24]  <= sd_sec_read_data;
                        10'd508: stored_crc[7:0]      <= sd_sec_read_data;
                        10'd509: stored_crc[15:8]     <= sd_sec_read_data;
                        10'd510: stored_crc[23:16]    <= sd_sec_read_data;
                        10'd511: stored_crc[31:24]    <= sd_sec_read_data;
                        default: ;
                    endcase
                    byte_count <= byte_count + 1'b1;
                end

                if (sd_sec_read_end)
                    state <= S_CHECK_SUPER;
            end

            // Validation is deliberately one clock after sd_sec_read_end so
            // the final CRC byte and byte counter have already been latched.
            S_CHECK_SUPER: begin
                    if (byte_count != 10'd512) begin
                        error_code <= ERR_SECTOR_LENGTH;
                        state <= S_ERROR;
                    end else if (!magic_ok) begin
                        error_code <= ERR_SUPER_MAGIC;
                        state <= S_ERROR;
                    end else if ((version != 16'd3) ||
                                 (header_bytes != 16'd512) ||
                                 (entry_size != 16'd16) ||
                                 (index_sectors != 32'd1) ||
                                 (width != 16'd640) ||
                                 (height != 16'd480) ||
                                 (fps_num != 32'd25) ||
                                 (fps_den != 32'd1) ||
                                 (audio_channels != 16'd1) ||
                                 (audio_bits != 16'd16) ||
                                 (audio_rate != 32'd48000)) begin
                        error_code <= ERR_SUPER_FORMAT;
                        state <= S_ERROR;
                    end else if ((~crc_state) != stored_crc) begin
                        error_code <= ERR_SUPER_CRC;
                        state <= S_ERROR;
                    end else if ((entry_count_raw == 0) ||
                                 (entry_count_raw > MAX_ENTRIES)) begin
                        error_code <= ERR_ENTRY_COUNT;
                        state <= S_ERROR;
                    end else begin
                        entry_count <= entry_count_raw[4:0];
                        state <= S_REQ_INDEX;
                    end
            end

            S_REQ_INDEX: begin
                loaded_select <= entry_select;
                sd_sec_read      <= 1'b1;
                sd_sec_read_addr <= index_lba;
                byte_count       <= 10'd0;
                state            <= S_READ_INDEX;
            end

            S_READ_INDEX: begin
                if (sd_sec_read_data_valid) begin
                    if (byte_count[8:4] == loaded_select) begin
                        case (byte_count[3:0])
                            4'd0:  entry_media_type       <= sd_sec_read_data;
                            4'd1:  entry_flags            <= sd_sec_read_data;
                            4'd2:  entry_media_id[7:0]    <= sd_sec_read_data;
                            4'd3:  entry_media_id[15:8]   <= sd_sec_read_data;
                            4'd4:  entry_metadata_lba[7:0]   <= sd_sec_read_data;
                            4'd5:  entry_metadata_lba[15:8]  <= sd_sec_read_data;
                            4'd6:  entry_metadata_lba[23:16] <= sd_sec_read_data;
                            4'd7:  entry_metadata_lba[31:24] <= sd_sec_read_data;
                            4'd8:  entry_data_lba[7:0]    <= sd_sec_read_data;
                            4'd9:  entry_data_lba[15:8]   <= sd_sec_read_data;
                            4'd10: entry_data_lba[23:16]  <= sd_sec_read_data;
                            4'd11: entry_data_lba[31:24]  <= sd_sec_read_data;
                            4'd12: entry_data_bytes[7:0]   <= sd_sec_read_data;
                            4'd13: entry_data_bytes[15:8]  <= sd_sec_read_data;
                            4'd14: entry_data_bytes[23:16] <= sd_sec_read_data;
                            4'd15: entry_data_bytes[31:24] <= sd_sec_read_data;
                        endcase
                    end
                    byte_count <= byte_count + 1'b1;
                end
                if (sd_sec_read_end)
                    state <= S_CHECK_INDEX;
            end

            S_CHECK_INDEX: begin
                    if (byte_count != 10'd512) begin
                        error_code <= ERR_SECTOR_LENGTH;
                        state <= S_ERROR;
                    end else if (loaded_select >= entry_count ||
                                 (entry_media_type != 1 && entry_media_type != 2) ||
                                 entry_metadata_lba >= total_sectors ||
                                 entry_data_lba >= total_sectors || entry_data_bytes == 0) begin
                        error_code <= ERR_SUPER_FORMAT;
                        state <= S_ERROR;
                    end else begin
                        state <= S_READY;
                    end
            end

            S_READY: begin
                if (entry_select != loaded_select) state <= S_REQ_INDEX;
            end

            default: begin

                state <= S_ERROR;
            end
        endcase
    end
end

endmodule

