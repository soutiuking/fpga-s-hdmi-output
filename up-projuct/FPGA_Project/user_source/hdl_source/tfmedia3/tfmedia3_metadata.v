`timescale 1ns / 1ps

// Reads one TFMETA3 sector and individual 8-byte frame index records.
// A frame index sector contains 64 records, so record N lives at
// frame_index_lba + N/64 and byte offset (N%64)*8.
module tfmedia3_metadata #(
    parameter integer MAX_FRAMES        = 24'hFF_FFFF,
    parameter integer MAX_JPEG_BYTES    = 65_536,
    parameter integer READ_TIMEOUT_CLKS = 100_000_000
)(
    input              clk,
    input              rst,

    input              load_media,
    input      [31:0]  metadata_lba,
    output reg         metadata_ready,
    output reg [7:0]   error_code,
    output reg [31:0]  frame_index_lba,
    output reg [31:0]  frame_count,
    output reg [31:0]  audio_lba,
    output reg [31:0]  audio_bytes,
    output reg [31:0]  duration_num,
    output reg [31:0]  duration_den,
    output reg [31:0]  fps_num,
    output reg [31:0]  fps_den,

    input              frame_request,
    input      [31:0]  frame_number,
    output reg         frame_ready,
    output reg [31:0]  frame_offset,
    output reg [31:0]  frame_bytes,

    output reg         sd_sec_read,
    output reg [31:0]  sd_sec_read_addr,
    input      [7:0]   sd_sec_read_data,
    input              sd_sec_read_data_valid,
    input              sd_sec_read_end,

    output reg [3:0]   debug_state
);

localparam [3:0] S_IDLE        = 4'd0;
localparam [3:0] S_REQ_META    = 4'd1;
localparam [3:0] S_READ_META   = 4'd2;
localparam [3:0] S_CHECK_META  = 4'd3;
localparam [3:0] S_READY       = 4'd4;
localparam [3:0] S_REQ_FRAME   = 4'd5;
localparam [3:0] S_READ_FRAME  = 4'd6;
localparam [3:0] S_CHECK_FRAME = 4'd7;
localparam [3:0] S_ERROR       = 4'd15;

localparam [7:0] ERR_NONE          = 8'h00;
localparam [7:0] ERR_META_MAGIC    = 8'h11;
localparam [7:0] ERR_META_CRC      = 8'h12;
localparam [7:0] ERR_FRAME_COUNT   = 8'h13;
localparam [7:0] ERR_FRAME_RANGE   = 8'h14;
localparam [7:0] ERR_FRAME_SIZE    = 8'h15;
localparam [7:0] ERR_READ_TIMEOUT  = 8'h16;
localparam [7:0] ERR_SECTOR_LENGTH = 8'h17;

reg [3:0]  state;
reg [9:0]  byte_count;
reg [31:0] timeout_count;
reg        magic_ok;
reg [31:0] crc_state;
reg [31:0] stored_crc;
reg [31:0] requested_frame;
reg [8:0]  wanted_byte_base;

function [31:0] crc32_next;
    input [31:0] crc;
    input [7:0] data;
    integer bit_index;
    reg [31:0] value;
    begin
        value = crc ^ {24'd0, data};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            if (value[0]) value = (value >> 1) ^ 32'hEDB8_8320;
            else          value = value >> 1;
        end
        crc32_next = value;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state           <= S_IDLE;
        debug_state     <= S_IDLE;
        sd_sec_read     <= 1'b0;
        sd_sec_read_addr <= 32'd0;
        metadata_ready  <= 1'b0;
        frame_ready     <= 1'b0;
        error_code      <= ERR_NONE;
        frame_index_lba <= 32'd0;
        frame_count     <= 32'd0;
        audio_lba       <= 32'd0;
        audio_bytes     <= 32'd0;
        duration_num    <= 32'd0;
        duration_den    <= 32'd0;
        fps_num         <= 32'd0;
        fps_den         <= 32'd0;
        frame_offset    <= 32'd0;
        frame_bytes     <= 32'd0;
        byte_count      <= 10'd0;
        timeout_count   <= 32'd0;
        magic_ok        <= 1'b1;
        crc_state       <= 32'hFFFF_FFFF;
        stored_crc      <= 32'd0;
        requested_frame <= 32'd0;
        wanted_byte_base <= 9'd0;
    end else begin
        sd_sec_read <= 1'b0;
        frame_ready <= 1'b0;
        debug_state <= state;

        if ((state == S_READ_META) || (state == S_READ_FRAME)) begin
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
            S_IDLE: begin
                metadata_ready <= 1'b0;
                if (load_media) begin
                    error_code <= ERR_NONE;
                    state <= S_REQ_META;
                end
            end

            S_REQ_META: begin
                sd_sec_read <= 1'b1;
                sd_sec_read_addr <= metadata_lba;
                byte_count <= 10'd0;
                magic_ok <= 1'b1;
                crc_state <= 32'hFFFF_FFFF;
                stored_crc <= 32'd0;
                metadata_ready <= 1'b0;
                state <= S_READ_META;
            end

            S_READ_META: begin
                if (sd_sec_read_data_valid) begin
                    if (byte_count < 10'd508)
                        crc_state <= crc32_next(crc_state, sd_sec_read_data);
                    case (byte_count)
                        10'd0: if (sd_sec_read_data != "T") magic_ok <= 1'b0;
                        10'd1: if (sd_sec_read_data != "F") magic_ok <= 1'b0;
                        10'd2: if (sd_sec_read_data != "M") magic_ok <= 1'b0;
                        10'd3: if (sd_sec_read_data != "E") magic_ok <= 1'b0;
                        10'd4: if (sd_sec_read_data != "T") magic_ok <= 1'b0;
                        10'd5: if (sd_sec_read_data != "A") magic_ok <= 1'b0;
                        10'd6: if (sd_sec_read_data != "3") magic_ok <= 1'b0;
                        10'd7: if (sd_sec_read_data != 8'd0) magic_ok <= 1'b0;
                        10'd8:  frame_index_lba[7:0]    <= sd_sec_read_data;
                        10'd9:  frame_index_lba[15:8]   <= sd_sec_read_data;
                        10'd10: frame_index_lba[23:16]  <= sd_sec_read_data;
                        10'd11: frame_index_lba[31:24]  <= sd_sec_read_data;
                        10'd12: frame_count[7:0]        <= sd_sec_read_data;
                        10'd13: frame_count[15:8]       <= sd_sec_read_data;
                        10'd14: frame_count[23:16]      <= sd_sec_read_data;
                        10'd15: frame_count[31:24]      <= sd_sec_read_data;
                        10'd16: audio_lba[7:0]          <= sd_sec_read_data;
                        10'd17: audio_lba[15:8]         <= sd_sec_read_data;
                        10'd18: audio_lba[23:16]        <= sd_sec_read_data;
                        10'd19: audio_lba[31:24]        <= sd_sec_read_data;
                        10'd20: audio_bytes[7:0]        <= sd_sec_read_data;
                        10'd21: audio_bytes[15:8]       <= sd_sec_read_data;
                        10'd22: audio_bytes[23:16]      <= sd_sec_read_data;
                        10'd23: audio_bytes[31:24]      <= sd_sec_read_data;
                        10'd24: duration_num[7:0]       <= sd_sec_read_data;
                        10'd25: duration_num[15:8]      <= sd_sec_read_data;
                        10'd26: duration_num[23:16]     <= sd_sec_read_data;
                        10'd27: duration_num[31:24]     <= sd_sec_read_data;
                        10'd28: duration_den[7:0]       <= sd_sec_read_data;
                        10'd29: duration_den[15:8]      <= sd_sec_read_data;
                        10'd30: duration_den[23:16]     <= sd_sec_read_data;
                        10'd31: duration_den[31:24]     <= sd_sec_read_data;
                        10'd32: fps_num[7:0]            <= sd_sec_read_data;
                        10'd33: fps_num[15:8]           <= sd_sec_read_data;
                        10'd34: fps_num[23:16]          <= sd_sec_read_data;
                        10'd35: fps_num[31:24]          <= sd_sec_read_data;
                        10'd36: fps_den[7:0]            <= sd_sec_read_data;
                        10'd37: fps_den[15:8]           <= sd_sec_read_data;
                        10'd38: fps_den[23:16]          <= sd_sec_read_data;
                        10'd39: fps_den[31:24]          <= sd_sec_read_data;
                        10'd508: stored_crc[7:0]        <= sd_sec_read_data;
                        10'd509: stored_crc[15:8]       <= sd_sec_read_data;
                        10'd510: stored_crc[23:16]      <= sd_sec_read_data;
                        10'd511: stored_crc[31:24]      <= sd_sec_read_data;
                        default: ;
                    endcase
                    byte_count <= byte_count + 1'b1;
                end
                if (sd_sec_read_end)
                    state <= S_CHECK_META;
            end

            S_CHECK_META: begin
                if (byte_count != 10'd512) begin
                    error_code <= ERR_SECTOR_LENGTH;
                    state <= S_ERROR;
                end else if (!magic_ok) begin
                    error_code <= ERR_META_MAGIC;
                    state <= S_ERROR;
                end else if ((~crc_state) != stored_crc) begin
                    error_code <= ERR_META_CRC;
                    state <= S_ERROR;
                end else if ((frame_count == 0) || (frame_count > MAX_FRAMES)) begin
                    error_code <= ERR_FRAME_COUNT;
                    state <= S_ERROR;
                end else begin
                    metadata_ready <= 1'b1;
                    state <= S_READY;
                end
            end

            S_READY: begin
                metadata_ready <= 1'b1;
                if (load_media) begin
                    metadata_ready <= 1'b0;
                    state <= S_REQ_META;
                end else if (frame_request) begin
                    if (frame_number >= frame_count) begin
                        error_code <= ERR_FRAME_RANGE;
                        state <= S_ERROR;
                    end else begin
                        requested_frame <= frame_number;
                        wanted_byte_base <= {frame_number[5:0], 3'b000};
                        state <= S_REQ_FRAME;
                    end
                end
            end

            S_REQ_FRAME: begin
                sd_sec_read <= 1'b1;
                sd_sec_read_addr <= frame_index_lba + (requested_frame >> 6);
                byte_count <= 10'd0;
                frame_offset <= 32'd0;
                frame_bytes <= 32'd0;
                state <= S_READ_FRAME;
            end

            S_READ_FRAME: begin
                if (sd_sec_read_data_valid) begin
                    if (byte_count[8:0] == wanted_byte_base + 9'd0) frame_offset[7:0]   <= sd_sec_read_data;
                    if (byte_count[8:0] == wanted_byte_base + 9'd1) frame_offset[15:8]  <= sd_sec_read_data;
                    if (byte_count[8:0] == wanted_byte_base + 9'd2) frame_offset[23:16] <= sd_sec_read_data;
                    if (byte_count[8:0] == wanted_byte_base + 9'd3) frame_offset[31:24] <= sd_sec_read_data;
                    if (byte_count[8:0] == wanted_byte_base + 9'd4) frame_bytes[7:0]    <= sd_sec_read_data;
                    if (byte_count[8:0] == wanted_byte_base + 9'd5) frame_bytes[15:8]   <= sd_sec_read_data;
                    if (byte_count[8:0] == wanted_byte_base + 9'd6) frame_bytes[23:16]  <= sd_sec_read_data;
                    if (byte_count[8:0] == wanted_byte_base + 9'd7) frame_bytes[31:24]  <= sd_sec_read_data;
                    byte_count <= byte_count + 1'b1;
                end
                if (sd_sec_read_end)
                    state <= S_CHECK_FRAME;
            end

            S_CHECK_FRAME: begin
                if (byte_count != 10'd512) begin
                    error_code <= ERR_SECTOR_LENGTH;
                    state <= S_ERROR;
                end else if ((frame_bytes == 0) || (frame_bytes > MAX_JPEG_BYTES)) begin
                    error_code <= ERR_FRAME_SIZE;
                    state <= S_ERROR;
                end else begin
                    frame_ready <= 1'b1;
                    state <= S_READY;
                end
            end

            default: begin
                metadata_ready <= 1'b0;
                state <= S_ERROR;
            end
        endcase
    end
end

endmodule

