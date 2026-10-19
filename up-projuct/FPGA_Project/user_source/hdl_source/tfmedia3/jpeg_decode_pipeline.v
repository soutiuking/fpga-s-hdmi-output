`timescale 1ns / 1ps

// Streams a cached JPEG from asynchronous SRAM into core_jpeg, reorders each
// 16-line 4:2:0 MCU stripe into raster order, then writes one linear RGB frame
// to the hard SDRAM frame-buffer interface.
module jpeg_decode_pipeline #(
    parameter integer DECODE_TIMEOUT_CLKS=8000000
)(
    input             clk,
    input             rst,
    input             frame_cached,
    input             cached_slot,
    input      [16:0] cached_bytes,
    input             target_slot,

    output reg        sram_request,
    output reg [18:0] sram_address,
    input      [15:0] sram_read_data,
    input             sram_ready,

    output reg        frame_write_req,
    input             frame_write_req_ack,
    output reg        frame_write_en,
    output reg [31:0] frame_write_data,
    output reg        frame_write_slot,
    input             frame_write_finish,

    output reg        decode_done,
    output            decode_ready,
    output reg        decoded_slot,
    output reg [7:0]  decode_error,
    output reg [3:0]  decode_state,
    // Frozen on error: {all_pixels_queued, jpeg_idle, input_complete,
    // frame_write_completed, last 32-bit JPEG word index[15:0]}.
    output reg [19:0] decode_debug
);

localparam [3:0] S_IDLE       = 4'd0;
localparam [3:0] S_WRITE_REQ  = 4'd1;
localparam [3:0] S_READ_LOW   = 4'd2;
localparam [3:0] S_WAIT_LOW   = 4'd3;
localparam [3:0] S_READ_HIGH  = 4'd4;
localparam [3:0] S_WAIT_HIGH  = 4'd5;
localparam [3:0] S_FEED       = 4'd6;
localparam [3:0] S_DECODE     = 4'd7;
localparam [3:0] S_WAIT_WRITE = 4'd8;
localparam [3:0] S_ERROR      = 4'd15;

localparam [7:0] ERR_NONE       = 8'h00;
localparam [7:0] ERR_REENTRY    = 8'h31;
localparam [7:0] ERR_DIMENSION  = 8'h32;
localparam [7:0] ERR_EMPTY      = 8'h33;

localparam integer STRIPE_PIXELS = 640 * 16;
localparam integer FRAME_PIXELS  = 640 * 480;

reg [3:0] state;
reg [23:0] watchdog;
reg [16:0] jpeg_bytes;
reg [16:0] jpeg_words;
reg [16:0] word_index;
reg [18:0] sram_word_address;
reg [15:0] low_word;
reg [31:0] jpeg_word;
reg        jpeg_word_valid;
reg [3:0]  jpeg_word_strb;
reg        jpeg_word_last;
reg        input_complete;
reg        frame_write_completed;

wire       jpeg_in_accept;
wire       jpeg_out_valid;
wire [15:0] jpeg_width;
wire [15:0] jpeg_height;
wire [15:0] jpeg_x;
wire [15:0] jpeg_y;
wire [7:0] jpeg_r;
wire [7:0] jpeg_g;
wire [7:0] jpeg_b;
wire       jpeg_idle;

reg [13:0] stripe_fill_count;
reg [5:0]  stripe_number;
reg [13:0] drain_address;
reg        drain_primed;
reg [1:0]  stripe_state;
reg        all_pixels_queued;
reg        core_reset;

// Register the per-frame reset: a decoded binary FSM value must not directly
// drive the high-fanout reset tree. Keep reset asserted while no input is fed.
always @(posedge clk or posedge rst) begin
    if (rst) core_reset <= 1'b1;
    else core_reset <= (state == S_IDLE || state == S_WRITE_REQ);
end

assign decode_ready = (state == S_IDLE);

localparam [1:0] STRIPE_FILL  = 2'd0;
localparam [1:0] STRIPE_DRAIN = 2'd1;
localparam [1:0] STRIPE_FLUSH = 2'd2;
localparam [1:0] STRIPE_DONE  = 2'd3;

wire jpeg_out_accept = (stripe_state == STRIPE_FILL);
wire [13:0] stripe_write_address =
    ({10'd0, jpeg_y[3:0]} << 9) +
    ({10'd0, jpeg_y[3:0]} << 7) + jpeg_x[9:0];
wire        stripe_write_enable = jpeg_out_valid && jpeg_out_accept &&
                                  (jpeg_width == 16'd640) &&
                                  (jpeg_height == 16'd480);
wire [23:0] stripe_read_data;

stripe_bram_10240x24 u_stripe_ram (
    .clk(clk), .write_enable(stripe_write_enable),
    .write_address(stripe_write_address),
    .write_data({jpeg_r, jpeg_g, jpeg_b}),
    .read_address(drain_address), .read_data(stripe_read_data)
);

jpeg_core #(.SUPPORT_WRITABLE_DHT(0)) u_jpeg_core (
    // Frames are independent JPEG files. Flush parser/entropy/output state
    // before each input stream, including when switching image or video.
    .clk_i(clk), .rst_i(core_reset),
    .inport_valid_i(jpeg_word_valid), .inport_data_i(jpeg_word),
    .inport_strb_i(jpeg_word_strb), .inport_last_i(jpeg_word_last),
    .outport_accept_i(jpeg_out_accept),
    .inport_accept_o(jpeg_in_accept), .outport_valid_o(jpeg_out_valid),
    .outport_width_o(jpeg_width), .outport_height_o(jpeg_height),
    .outport_pixel_x_o(jpeg_x), .outport_pixel_y_o(jpeg_y),
    .outport_pixel_r_o(jpeg_r), .outport_pixel_g_o(jpeg_g),
    .outport_pixel_b_o(jpeg_b), .idle_o(jpeg_idle)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state              <= S_IDLE;
        watchdog           <= 0;
        decode_state       <= S_IDLE;
        decode_debug       <= 20'd0;
        decode_done        <= 1'b0;
        decoded_slot       <= 1'b0;
        decode_error       <= ERR_NONE;
        sram_request       <= 1'b0;
        sram_address       <= 19'd0;
        frame_write_req    <= 1'b0;
        frame_write_en     <= 1'b0;
        frame_write_data   <= 32'd0;
        frame_write_slot   <= 1'b0;
        jpeg_bytes         <= 17'd0;
        jpeg_words         <= 17'd0;
        word_index         <= 17'd0;
        sram_word_address  <= 19'd0;
        low_word           <= 16'd0;
        jpeg_word          <= 32'd0;
        jpeg_word_valid    <= 1'b0;
        jpeg_word_strb     <= 4'b1111;
        jpeg_word_last     <= 1'b0;
        input_complete     <= 1'b0;
        frame_write_completed <= 1'b0;
        stripe_fill_count  <= 14'd0;
        stripe_number      <= 6'd0;
        drain_address      <= 14'd0;
        drain_primed       <= 1'b0;
        stripe_state       <= STRIPE_FILL;
        all_pixels_queued  <= 1'b0;
    end else begin
        decode_done      <= 1'b0;
        sram_request     <= 1'b0;
        frame_write_en   <= 1'b0;
        // Preserve the actual waiting stage, rather than replacing it with F
        // on the cycle after a timeout. This is observable on the real board.
        if (state != S_ERROR) begin
            decode_state <= state;
            decode_debug <= {all_pixels_queued, jpeg_idle, input_complete,
                             frame_write_completed, word_index[15:0]};
        end

        // SDRAM can finish before the JPEG core returns idle.
        if (frame_write_finish)
            frame_write_completed <= 1'b1;

        if (frame_cached && state != S_IDLE) begin
            decode_error <= ERR_REENTRY;
            state        <= S_ERROR;
        end

        if (jpeg_out_valid && jpeg_out_accept) begin
            if ((jpeg_width != 16'd640) || (jpeg_height != 16'd480)) begin
                decode_error <= ERR_DIMENSION;
                state        <= S_ERROR;
            end else begin
                if (stripe_fill_count == STRIPE_PIXELS - 1) begin
                    stripe_fill_count <= 14'd0;
                    drain_address     <= 14'd0;
                    drain_primed      <= 1'b0;
                    stripe_state      <= STRIPE_DRAIN;
                end else begin
                    stripe_fill_count <= stripe_fill_count + 1'b1;
                end
            end
        end

        case (stripe_state)
            STRIPE_DRAIN: begin
                if (drain_primed) begin
                    frame_write_en   <= 1'b1;
                    frame_write_data <= {stripe_read_data, 8'd0};
                end else begin
                    drain_primed <= 1'b1;
                end
                if (drain_address == STRIPE_PIXELS - 1)
                    stripe_state <= STRIPE_FLUSH;
                else
                    drain_address <= drain_address + 1'b1;
            end

            STRIPE_FLUSH: begin
                frame_write_en   <= 1'b1;
                frame_write_data <= {stripe_read_data, 8'd0};
                drain_primed     <= 1'b0;
                if (stripe_number == 6'd29) begin
                    stripe_state      <= STRIPE_DONE;
                    all_pixels_queued <= 1'b1;
                end else begin
                    stripe_number <= stripe_number + 1'b1;
                    stripe_state  <= STRIPE_FILL;
                end
            end

            default: begin
            end
        endcase

        case (state)
            S_IDLE: begin
                frame_write_req <= 1'b0;
                jpeg_word_valid <= 1'b0;
                if (frame_cached) begin
                    decode_error <= ERR_NONE;
                    if (cached_bytes == 0) begin
                        decode_error <= ERR_EMPTY;
                        state        <= S_ERROR;
                    end else begin
                        jpeg_bytes        <= cached_bytes;
                        jpeg_words        <= (cached_bytes + 3) >> 2;
                        word_index        <= 17'd0;
                        sram_word_address <= cached_slot ? 19'd32768 : 19'd0;
                        frame_write_slot  <= target_slot;
                        frame_write_req   <= 1'b1;
                        input_complete    <= 1'b0;
                        frame_write_completed <= 1'b0;
                        stripe_fill_count <= 14'd0;
                        stripe_number     <= 6'd0;
                        stripe_state      <= STRIPE_FILL;
                        all_pixels_queued <= 1'b0;
                        state             <= S_WRITE_REQ;
                    end
                end
            end

            S_WRITE_REQ: begin
                if (frame_write_req_ack) begin
                    frame_write_req <= 1'b0;
                    state           <= S_READ_LOW;
                end
            end

            S_READ_LOW: begin
                sram_address <= sram_word_address;
                sram_request <= 1'b1;
                state        <= S_WAIT_LOW;
            end

            S_WAIT_LOW: begin
                if (sram_ready) begin
                    low_word <= sram_read_data;
                    state    <= S_READ_HIGH;
                end
            end

            S_READ_HIGH: begin
                sram_address <= sram_word_address + 1'b1;
                sram_request <= 1'b1;
                state        <= S_WAIT_HIGH;
            end

            S_WAIT_HIGH: begin
                if (sram_ready) begin
                    jpeg_word       <= {sram_read_data, low_word};
                    jpeg_word_valid <= 1'b1;
                    jpeg_word_last  <= (word_index + 1'b1 == jpeg_words);
                    if ((word_index + 1'b1 == jpeg_words) &&
                        (jpeg_bytes[1:0] != 0)) begin
                        case (jpeg_bytes[1:0])
                            2'd1: jpeg_word_strb <= 4'b0001;
                            2'd2: jpeg_word_strb <= 4'b0011;
                            default: jpeg_word_strb <= 4'b0111;
                        endcase
                    end else begin
                        jpeg_word_strb <= 4'b1111;
                    end
                    state           <= S_FEED;
                end
            end

            S_FEED: begin
                if (jpeg_word_valid && jpeg_in_accept) begin
                    jpeg_word_valid <= 1'b0;
                    jpeg_word_last  <= 1'b0;
                    if (word_index + 1'b1 == jpeg_words) begin
                        input_complete <= 1'b1;
                        state          <= S_DECODE;
                    end else begin
                        word_index        <= word_index + 1'b1;
                        sram_word_address <= sram_word_address + 2'd2;
                        state             <= S_READ_LOW;
                    end
                end
            end

            S_DECODE: begin
                if (input_complete && jpeg_idle && all_pixels_queued)
                    state <= S_WAIT_WRITE;
            end

            S_WAIT_WRITE: begin
                if (frame_write_completed || frame_write_finish) begin
                    decoded_slot <= frame_write_slot;
                    decode_done  <= 1'b1;
                    state        <= S_IDLE;
                end
            end

            S_ERROR: begin
                frame_write_req <= 1'b0;
                jpeg_word_valid <= 1'b0;
            end

            default: state <= S_ERROR;
        endcase
        if (state == S_IDLE || state == S_ERROR) watchdog <= 0;
        else if (watchdog == DECODE_TIMEOUT_CLKS-1) begin
            state <= S_ERROR; decode_error <= 8'h34;
            jpeg_word_valid <= 0; frame_write_req <= 0;
        end else watchdog <= watchdog + 1'b1;
    end
end

endmodule
