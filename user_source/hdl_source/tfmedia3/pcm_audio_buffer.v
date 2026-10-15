`timescale 1ns / 1ps

// SD-to-BRAM PCM streamer.  The producer fills a 28-KiB ring a sector at a
// time.  The 48-kHz audio domain requests one sample through a toggle mailbox;
// samples are held stable until the acknowledgement crosses back.
module pcm_audio_buffer(
    input             clk,
    input             rst,
    input             configure,
    input      [31:0] audio_lba,
    input      [31:0] audio_bytes,
    input             playback_enable,

    output reg        sd_sec_read,
    output reg [31:0] sd_sec_read_addr,
    input      [7:0]  sd_sec_read_data,
    input             sd_sec_read_data_valid,
    input             sd_sec_read_end,

    input             sample_request_toggle,
    output reg        sample_ack_toggle,
    output reg [15:0] sample_data,
    output reg        underflow,
    output            sample_consumed,
    output            playback_done,
    output reg [15:0] buffered_bytes
);

localparam [14:0] LAST_ADDRESS = 15'd28671;
localparam [15:0] CAPACITY     = 16'd28672;
localparam [2:0] R_IDLE        = 3'd0;
localparam [2:0] R_LOW_ADDR    = 3'd1;
localparam [2:0] R_LOW_WAIT    = 3'd2;
localparam [2:0] R_HIGH_ADDR   = 3'd3;
localparam [2:0] R_HIGH_WAIT   = 3'd4;

reg        configured;
reg        sector_busy;
reg [31:0] base_lba;
reg [31:0] byte_limit;
reg [31:0] bytes_loaded;
reg [31:0] bytes_played;
reg [31:0] sector_index;
reg [9:0]  sector_byte_count;
reg [14:0] write_pointer;
reg [14:0] read_pointer;
reg [14:0] bram_read_address;
reg [7:0]  sample_low;
reg [2:0]  read_state;
reg        request_sync1;
reg        request_sync2;
reg        request_seen;
reg        bram_write_enable;
reg [14:0] bram_write_address;
reg [7:0]  bram_write_data;
wire [7:0] bram_read_data;
wire       store_byte = sector_busy && sd_sec_read_data_valid &&
                        (bytes_loaded < byte_limit);
wire       consume_sample = (read_state == R_HIGH_WAIT);
assign sample_consumed = consume_sample;
assign playback_done = configured && (bytes_played == byte_limit);

pcm_bram_28672x8 u_pcm_ram (
    .clk(clk), .write_enable(bram_write_enable),
    .write_address(bram_write_address), .write_data(bram_write_data),
    .read_address(bram_read_address), .read_data(bram_read_data)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        configured          <= 1'b0;
        sector_busy         <= 1'b0;
        base_lba            <= 32'd0;
        byte_limit          <= 32'd0;
        bytes_loaded        <= 32'd0;
        bytes_played        <= 32'd0;
        sector_index        <= 32'd0;
        sector_byte_count   <= 10'd0;
        write_pointer       <= 15'd0;
        read_pointer        <= 15'd0;
        bram_read_address   <= 15'd0;
        sample_low          <= 8'd0;
        read_state          <= R_IDLE;
        request_sync1       <= 1'b0;
        request_sync2       <= 1'b0;
        request_seen        <= 1'b0;
        sample_ack_toggle   <= 1'b0;
        sample_data         <= 16'd0;
        underflow           <= 1'b0;
        buffered_bytes      <= 16'd0;
        sd_sec_read         <= 1'b0;
        sd_sec_read_addr    <= 32'd0;
        bram_write_enable   <= 1'b0;
        bram_write_address  <= 15'd0;
        bram_write_data     <= 8'd0;
    end else begin
        sd_sec_read       <= 1'b0;
        bram_write_enable <= 1'b0;
        request_sync1     <= sample_request_toggle;
        request_sync2     <= request_sync1;

        if (configure) begin
            configured        <= (audio_bytes != 0);
            sector_busy       <= 1'b0;
            base_lba          <= audio_lba;
            byte_limit        <= audio_bytes;
            bytes_loaded      <= 32'd0;
            bytes_played      <= 32'd0;
            sector_index      <= 32'd0;
            sector_byte_count <= 10'd0;
            write_pointer     <= 15'd0;
            read_pointer      <= 15'd0;
            bram_read_address <= 15'd0;
            read_state        <= R_IDLE;
            request_seen      <= request_sync2;
            sample_ack_toggle <= request_sync2;
            sample_data       <= 16'd0;
            underflow         <= 1'b0;
            buffered_bytes    <= 16'd0;
        end else begin
            // Reserve one whole sector before requesting it, preventing an
            // in-flight transfer from wrapping into unread audio.
            if (configured && !sector_busy &&
                (bytes_loaded < byte_limit) &&
                (buffered_bytes <= CAPACITY - 16'd512)) begin
                sd_sec_read_addr  <= base_lba + sector_index;
                sd_sec_read       <= 1'b1;
                sector_byte_count <= 10'd0;
                sector_busy       <= 1'b1;
            end

            if (store_byte) begin
                bram_write_enable  <= 1'b1;
                bram_write_address <= write_pointer;
                bram_write_data    <= sd_sec_read_data;
                bytes_loaded       <= bytes_loaded + 1'b1;
                sector_byte_count  <= sector_byte_count + 1'b1;
                if (write_pointer == LAST_ADDRESS)
                    write_pointer <= 15'd0;
                else
                    write_pointer <= write_pointer + 1'b1;
            end

            if (sd_sec_read_end && sector_busy) begin
                sector_busy  <= 1'b0;
                sector_index <= sector_index + 1'b1;
            end

            case (read_state)
                R_IDLE: begin
                    if (request_sync2 != request_seen) begin
                        request_seen <= request_sync2;
                        if (playback_enable && (buffered_bytes >= 2)) begin
                            bram_read_address <= read_pointer;
                            read_state <= R_LOW_ADDR;
                        end else begin
                            sample_data       <= 16'd0;
                            sample_ack_toggle <= request_sync2;
                            if (playback_enable && configured && !playback_done)
                                underflow <= 1'b1;
                            else if (playback_done) underflow <= 1'b0;
                        end
                    end
                end
                R_LOW_ADDR: begin
                    read_state <= R_LOW_WAIT;
                end
                R_LOW_WAIT: begin
                    sample_low <= bram_read_data;
                    if (read_pointer == LAST_ADDRESS)
                        bram_read_address <= 15'd0;
                    else
                        bram_read_address <= read_pointer + 1'b1;
                    read_state <= R_HIGH_ADDR;
                end
                R_HIGH_ADDR: begin
                    read_state <= R_HIGH_WAIT;
                end
                R_HIGH_WAIT: begin
                    bytes_played      <= bytes_played + 2'd2;
                    sample_data       <= {bram_read_data, sample_low};
                    sample_ack_toggle <= request_seen;
                    underflow         <= 1'b0;
                    if (read_pointer >= LAST_ADDRESS - 1'b1)
                        read_pointer <= 15'd0;
                    else
                        read_pointer <= read_pointer + 2'd2;
                    read_state <= R_IDLE;
                end
                default: read_state <= R_IDLE;
            endcase

            case ({store_byte, consume_sample})
                2'b10: buffered_bytes <= buffered_bytes + 1'b1;
                2'b01: buffered_bytes <= buffered_bytes - 2'd2;
                2'b11: buffered_bytes <= buffered_bytes - 1'b1;
                default: ;
            endcase
        end
    end
end

endmodule
