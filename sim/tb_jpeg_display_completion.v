`timescale 1ns/1ps
module stripe_bram_10240x24(input clk, input write_enable,
    input [13:0] write_address, input [23:0] write_data,
    input [13:0] read_address, output reg [23:0] read_data);
reg [23:0] mem [0:10239];
always @(posedge clk) begin
    if (write_enable) mem[write_address] <= write_data;
    read_data <= mem[read_address];
end
endmodule

module tb_jpeg_display_completion;
reg clk = 0;
always #12.5 clk = ~clk;
reg rst = 1, cached = 0;
wire request;
wire [18:0] address;
reg [15:0] read_data;
reg ready = 0;
wire write_req, write_en, done, decode_ready;
wire [31:0] write_data;
reg write_ack = 0, finish = 0;
wire [7:0] error;
wire [3:0] state;
reg [15:0] sram [0:32767];
reg [16:0] jpeg_size=14357;
reg [4095:0] jpeg_hex="golden_first_jpeg.hex";
reg [4095:0] first_hex, second_hex="second_jpeg.hex";
reg [16:0] first_size, second_size=0;
integer sequence_mode=0, completed_frames=0;
integer arg_status;
integer pixels = 0;
integer colored_pixels = 0;
integer idle_delay = 0;
integer early_completions = 0;
integer rgb_file;
time started_at;
jpeg_decode_pipeline dut(.clk(clk), .rst(rst), .frame_cached(cached),
    .cached_slot(1'b0), .target_slot(1'b1), .cached_bytes(jpeg_size), .sram_request(request),
    .sram_address(address), .sram_read_data(read_data), .sram_ready(ready),
    .frame_write_req(write_req), .frame_write_req_ack(write_ack),
    .frame_write_en(write_en), .frame_write_data(write_data),
    .frame_write_slot(), .frame_write_finish(finish), .decode_done(done),
    .decode_ready(decode_ready), .decoded_slot(), .decode_error(error),
    .decode_state(state));
always @(posedge clk) begin
    ready <= request;
    if (request) read_data <= sram[address];
    write_ack <= write_req;
    finish <= 0;
    if (idle_delay > 0) begin
        idle_delay = idle_delay - 1;
        if (idle_delay == 0) release dut.jpeg_idle;
    end
    if (write_en) begin
        // Hex avoids an Icarus 10.1 Windows %c bug that writes NUL as 0x10.
        $fwrite(rgb_file,"%06h\n",write_data[31:8]);
        pixels = pixels + 1;
        if (^write_data === 1'bx) $fatal(1, "Unknown pixel at %0d", pixels);
        if (write_data[31:8] != 0) colored_pixels = colored_pixels + 1;
        if (pixels == 300000) force dut.jpeg_idle = 1'b0;
        if (pixels == 307200) begin
            // Exercise delayed decoder retirement: the complete frame is
            // queued, but idle is postponed past the SDRAM completion.
            idle_delay = 10;
            finish <= 1;
        end
    end
    if (finish && dut.state == 4'd7) early_completions = early_completions + 1;
    if (error != 0) $fatal(1, "Decoder error %h stage=%0d pixels=%0d stripe=%0d filled=%0d input=%0d",
                         error,state,pixels,dut.stripe_number,dut.stripe_fill_count,dut.word_index);
    if (done) begin
        if (pixels != 307200 || colored_pixels == 0 || early_completions != 1)
            $fatal(1, "Bad image: %0d pixels, %0d nonblack, %0d early completions", pixels, colored_pixels, early_completions);
        $display("PASS: golden JPEG produces %0d pixels (%0d nonblack), early SDRAM completion retained", pixels, colored_pixels);
        $display("Decode elapsed ns: %0d", $time-started_at);
        $fclose(rgb_file);
        completed_frames=completed_frames+1;
        if (!sequence_mode || completed_frames==3) begin
            if(sequence_mode) $display("PASS: real JPEG A -> B -> A without decoder reset");
            $finish;
        end
    end
end
initial begin
    #2000000;
    if (pixels == 0)
        $fatal(1,"No JPEG header: pipeline=%0d inputword=%0d inputstate=%0d length=%0d byteidx=%0d last=%b",
               dut.state,dut.word_index,dut.u_jpeg_core.u_jpeg_input.state_q,
               dut.u_jpeg_core.u_jpeg_input.length_q,dut.u_jpeg_core.u_jpeg_input.byte_idx_q,dut.jpeg_word_last);
end
initial begin
    rgb_file=$fopen("decoded.hex","w");
    arg_status=$value$plusargs("jpeg_bytes=%d",jpeg_size);
    arg_status=$value$plusargs("jpeg_hex=%s",jpeg_hex);
    arg_status=$value$plusargs("sequence=%d",sequence_mode);
    arg_status=$value$plusargs("second_bytes=%d",second_size);
    arg_status=$value$plusargs("second_hex=%s",second_hex);
    first_size=jpeg_size; first_hex=jpeg_hex;
    $readmemh(jpeg_hex, sram, 0, ((jpeg_size+3)/4)*2-1);
    #51 rst = 0;
    @(negedge clk); cached = 1; started_at=$time;
    @(negedge clk); cached = 0;
    if(sequence_mode) begin
        wait(completed_frames==1);
        @(negedge clk);
        pixels=0; colored_pixels=0; early_completions=0;
        jpeg_size=second_size;
        $readmemh(second_hex,sram,0,((jpeg_size+3)/4)*2-1);
        rgb_file=$fopen("decoded_b.hex","w");
        cached=1; started_at=$time;
        @(negedge clk); cached=0;
        wait(completed_frames==2);
        @(negedge clk);
        pixels=0; colored_pixels=0; early_completions=0;
        jpeg_size=first_size;
        $readmemh(first_hex,sram,0,((jpeg_size+3)/4)*2-1);
        rgb_file=$fopen("decoded_a2.hex","w");
        cached=1; started_at=$time;
        @(negedge clk); cached=0;
    end
end
initial begin
    #200000000;
    $fatal(1, "timeout state=%0d pixels=%0d coreidle=%b stripe=%0d", state, pixels, dut.jpeg_idle, dut.stripe_state);
end
endmodule
