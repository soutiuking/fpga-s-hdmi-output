`timescale 1ns / 1ps

module tb_jpeg_sram_dma;

reg clk = 1'b0;
reg rst = 1'b1;
always #10 clk = ~clk;

reg         start;
reg         slot_select;
reg [31:0]  data_lba;
reg [31:0]  frame_offset;
reg [31:0]  frame_bytes;
wire        busy;
wire        done;
wire [7:0]  error_code;
wire [16:0] bytes_copied;

wire        sd_sec_read;
wire [31:0] sd_sec_read_addr;
reg  [7:0]  sd_sec_read_data;
reg         sd_sec_read_data_valid;
reg         sd_sec_read_end;

wire        sram_request;
wire        sram_write_enable;
wire [18:0] sram_address;
wire [15:0] sram_write_data;
wire [1:0]  sram_byte_enable;
reg         sram_ready;
wire [3:0]  debug_state;

reg [15:0] memory [0:65535];
reg [2:0]  sram_wait;
reg [18:0] sram_addr_latched;
reg [15:0] sram_data_latched;
reg [1:0]  sram_be_latched;

reg        sd_sending;
reg [3:0]  sd_gap;
reg [9:0]  sd_byte;
reg [31:0] sd_lba_latched;

integer failures;
integer i;

jpeg_sram_dma #(
    .READ_TIMEOUT_CLKS(2_000_000)
) dut (
    .clk(clk), .rst(rst), .start(start), .slot_select(slot_select),
    .data_lba(data_lba), .frame_offset(frame_offset),
    .frame_bytes(frame_bytes), .busy(busy), .done(done),
    .error_code(error_code), .bytes_copied(bytes_copied),
    .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data),
    .sd_sec_read_data_valid(sd_sec_read_data_valid),
    .sd_sec_read_end(sd_sec_read_end), .sram_request(sram_request),
    .sram_write_enable(sram_write_enable), .sram_address(sram_address),
    .sram_write_data(sram_write_data), .sram_byte_enable(sram_byte_enable),
    .sram_ready(sram_ready), .debug_state(debug_state)
);

// Sector source.  Byte value equals its absolute card byte address modulo 256.
always @(posedge clk) begin
    sd_sec_read_data_valid <= 1'b0;
    sd_sec_read_end        <= 1'b0;
    if (rst) begin
        sd_sending     <= 1'b0;
        sd_gap         <= 4'd0;
        sd_byte        <= 10'd0;
        sd_lba_latched <= 32'd0;
    end else if (sd_sec_read && !sd_sending) begin
        sd_sending     <= 1'b1;
        sd_gap         <= 4'd4;
        sd_byte        <= 10'd0;
        sd_lba_latched <= sd_sec_read_addr;
    end else if (sd_sending) begin
        if (sd_gap != 0) begin
            sd_gap <= sd_gap - 1'b1;
        end else if (sd_byte < 10'd512) begin
            sd_sec_read_data       <= sd_byte[7:0];
            sd_sec_read_data_valid <= 1'b1;
            sd_byte                <= sd_byte + 1'b1;
            sd_gap                 <= 4'd7;
        end else begin
            sd_sec_read_end <= 1'b1;
            sd_sending      <= 1'b0;
        end
    end
end

// Two-cycle SRAM write responder with byte-enable behavior.
always @(posedge clk) begin
    sram_ready <= 1'b0;
    if (rst) begin
        sram_wait <= 3'd0;
    end else begin
        if (sram_request && (sram_wait == 0)) begin
            sram_wait         <= 3'd2;
            sram_addr_latched <= sram_address;
            sram_data_latched <= sram_write_data;
            sram_be_latched   <= sram_byte_enable;
        end else if (sram_wait != 0) begin
            sram_wait <= sram_wait - 1'b1;
            if (sram_wait == 1) begin
                if (sram_be_latched[0])
                    memory[sram_addr_latched][7:0] <= sram_data_latched[7:0];
                if (sram_be_latched[1])
                    memory[sram_addr_latched][15:8] <= sram_data_latched[15:8];
                sram_ready <= 1'b1;
            end
        end
    end
end

task launch;
    input        test_slot;
    input [31:0] test_offset;
    input [31:0] test_bytes;
    begin
        @(posedge clk);
        slot_select <= test_slot;
        data_lba    <= 32'd100;
        frame_offset <= test_offset;
        frame_bytes <= test_bytes;
        start       <= 1'b1;
        @(posedge clk);
        start       <= 1'b0;
        wait(done || (error_code != 0));
        @(posedge clk);
        if (error_code != 0) begin
            $display("FAIL: DMA error %02x", error_code);
            failures = failures + 1;
        end
        if (bytes_copied != test_bytes[16:0]) begin
            $display("FAIL: copied %0d expected %0d", bytes_copied, test_bytes);
            failures = failures + 1;
        end
        repeat (3) @(posedge clk);
    end
endtask

initial begin
    start = 1'b0;
    slot_select = 1'b0;
    data_lba = 32'd0;
    frame_offset = 32'd0;
    frame_bytes = 32'd0;
    sd_sec_read_data = 8'd0;
    sd_sec_read_data_valid = 1'b0;
    sd_sec_read_end = 1'b0;
    sram_ready = 1'b0;
    failures = 0;
    for (i = 0; i < 65536; i = i + 1)
        memory[i] = 16'd0;

    repeat (5) @(posedge clk);
    rst = 1'b0;

    // Starts three bytes before a sector boundary and ends on an odd byte.
    launch(1'b0, 32'd509, 32'd513);
    if (memory[0] !== 16'hFEFD) begin
        $display("FAIL: unaligned first word %04x", memory[0]);
        failures = failures + 1;
    end
    if (memory[256] !== 16'h00FD) begin
        $display("FAIL: odd tail word %04x", memory[256]);
        failures = failures + 1;
    end

    // Maximum legal JPEG size in slot 1.
    launch(1'b1, 32'd17, 32'd65536);
    if (memory[32768] !== 16'h1211) begin
        $display("FAIL: slot1 first word %04x", memory[32768]);
        failures = failures + 1;
    end
    if (memory[65535] !== 16'h100F) begin
        $display("FAIL: slot1 last word %04x", memory[65535]);
        failures = failures + 1;
    end

    if (failures == 0)
        $display("PASS: jpeg_sram_dma alignment, odd-tail and 64-KiB cases");
    else
        $display("FAILURES: %0d", failures);
    $finish;
end

endmodule
