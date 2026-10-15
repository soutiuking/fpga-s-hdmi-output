`timescale 1ns / 1ps

// Copies one arbitrarily aligned JPEG byte range from SD into one of two
// 64-KiB SRAM slots.  Bytes are packed little-endian into the 16-bit SRAM.
// The SD SPI byte interval is much longer than one SRAM transaction; an
// overrun is nevertheless detected instead of silently corrupting the frame.
module jpeg_sram_dma #(
    parameter integer MAX_JPEG_BYTES    = 65_536,
    parameter integer READ_TIMEOUT_CLKS = 100_000_000
)(
    input             clk,
    input             rst,

    input             start,
    input             slot_select,
    input      [31:0] data_lba,
    input      [31:0] frame_offset,
    input      [31:0] frame_bytes,
    output reg        busy,
    output reg        done,
    output reg [7:0]  error_code,
    output reg [16:0] bytes_copied,

    output reg        sd_sec_read,
    output reg [31:0] sd_sec_read_addr,
    input      [7:0]  sd_sec_read_data,
    input             sd_sec_read_data_valid,
    input             sd_sec_read_end,

    output reg        sram_request,
    output reg        sram_write_enable,
    output reg [18:0] sram_address,
    output reg [15:0] sram_write_data,
    output reg [1:0]  sram_byte_enable,
    input             sram_ready,

    output reg [3:0]  debug_state
);

localparam [3:0] S_IDLE       = 4'd0;
localparam [3:0] S_REQ_SECTOR = 4'd1;
localparam [3:0] S_READ       = 4'd2;
localparam [3:0] S_DRAIN      = 4'd3;
localparam [3:0] S_DONE       = 4'd4;
localparam [3:0] S_ERROR      = 4'd15;

localparam [7:0] ERR_NONE       = 8'h00;
localparam [7:0] ERR_BAD_SIZE   = 8'h21;
localparam [7:0] ERR_TIMEOUT    = 8'h22;
localparam [7:0] ERR_SD_OVERRUN = 8'h23;
localparam [7:0] ERR_SHORT_READ = 8'h24;

reg [3:0]  state;
reg [31:0] next_lba;
reg [8:0]  sector_skip;
reg [9:0]  sector_byte;
reg [31:0] frame_size_latched;
reg [18:0] destination_word;
reg [7:0]  low_byte;
reg        low_byte_valid;
reg        write_pending;
reg        data_complete;
reg [31:0] timeout_count;

wire byte_in_range = (sector_byte >= {1'b0, sector_skip}) &&
                     (bytes_copied < frame_size_latched);
wire last_frame_byte = (bytes_copied + 1'b1 == frame_size_latched);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state              <= S_IDLE;
        busy               <= 1'b0;
        done               <= 1'b0;
        error_code         <= ERR_NONE;
        bytes_copied       <= 17'd0;
        sd_sec_read        <= 1'b0;
        sd_sec_read_addr   <= 32'd0;
        sram_request       <= 1'b0;
        sram_write_enable  <= 1'b1;
        sram_address       <= 19'd0;
        sram_write_data    <= 16'd0;
        sram_byte_enable   <= 2'b11;
        debug_state        <= S_IDLE;
        next_lba           <= 32'd0;
        sector_skip        <= 9'd0;
        sector_byte        <= 10'd0;
        frame_size_latched <= 32'd0;
        destination_word   <= 19'd0;
        low_byte           <= 8'd0;
        low_byte_valid     <= 1'b0;
        write_pending      <= 1'b0;
        data_complete      <= 1'b0;
        timeout_count      <= 32'd0;
    end else begin
        sd_sec_read  <= 1'b0;
        sram_request <= 1'b0;
        done         <= 1'b0;
        debug_state  <= state;

        if (write_pending && sram_ready)
            write_pending <= 1'b0;

        if (state == S_READ) begin
            if (timeout_count < READ_TIMEOUT_CLKS)
                timeout_count <= timeout_count + 1'b1;
            else begin
                error_code <= ERR_TIMEOUT;
                state      <= S_ERROR;
                busy       <= 1'b0;
            end
        end else begin
            timeout_count <= 32'd0;
        end

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    error_code <= ERR_NONE;
                    if ((frame_bytes == 0) || (frame_bytes > MAX_JPEG_BYTES)) begin
                        error_code <= ERR_BAD_SIZE;
                        state      <= S_ERROR;
                    end else begin
                        busy               <= 1'b1;
                        bytes_copied       <= 17'd0;
                        frame_size_latched <= frame_bytes;
                        next_lba           <= data_lba + (frame_offset >> 9);
                        sector_skip        <= frame_offset[8:0];
                        destination_word   <= slot_select ? 19'd32768 : 19'd0;
                        low_byte_valid     <= 1'b0;
                        write_pending      <= 1'b0;
                        data_complete      <= 1'b0;
                        state              <= S_REQ_SECTOR;
                    end
                end
            end

            S_REQ_SECTOR: begin
                sd_sec_read      <= 1'b1;
                sd_sec_read_addr <= next_lba;
                sector_byte      <= 10'd0;
                state            <= S_READ;
            end

            S_READ: begin
                if (sd_sec_read_data_valid) begin
                    sector_byte <= sector_byte + 1'b1;
                    if (byte_in_range) begin
                        if (write_pending) begin
                            error_code <= ERR_SD_OVERRUN;
                            busy       <= 1'b0;
                            state      <= S_ERROR;
                        end else begin
                            bytes_copied <= bytes_copied + 1'b1;
                            if (low_byte_valid) begin
                                sram_address      <= destination_word;
                                sram_write_data   <= {sd_sec_read_data, low_byte};
                                sram_byte_enable  <= 2'b11;
                                sram_write_enable <= 1'b1;
                                sram_request      <= 1'b1;
                                write_pending     <= 1'b1;
                                destination_word  <= destination_word + 1'b1;
                                low_byte_valid    <= 1'b0;
                            end else if (last_frame_byte) begin
                                sram_address      <= destination_word;
                                sram_write_data   <= {8'd0, sd_sec_read_data};
                                sram_byte_enable  <= 2'b01;
                                sram_write_enable <= 1'b1;
                                sram_request      <= 1'b1;
                                write_pending     <= 1'b1;
                                destination_word  <= destination_word + 1'b1;
                                low_byte_valid    <= 1'b0;
                            end else begin
                                low_byte       <= sd_sec_read_data;
                                low_byte_valid <= 1'b1;
                            end
                            if (last_frame_byte)
                                data_complete <= 1'b1;
                        end
                    end
                end

                if (sd_sec_read_end) begin
                    next_lba    <= next_lba + 1'b1;
                    sector_skip <= 9'd0;
                    state       <= S_DRAIN;
                end
            end

            S_DRAIN: begin
                if (!write_pending) begin
                    if (data_complete) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_DONE;
                    end else if (sector_byte != 10'd512) begin
                        error_code <= ERR_SHORT_READ;
                        busy       <= 1'b0;
                        state      <= S_ERROR;
                    end else begin
                        state <= S_REQ_SECTOR;
                    end
                end
            end

            S_DONE: begin
                if (!start)
                    state <= S_IDLE;
            end

            default: begin
                busy <= 1'b0;
                if (!start)
                    state <= S_IDLE;
            end
        endcase
    end
end

endmodule
