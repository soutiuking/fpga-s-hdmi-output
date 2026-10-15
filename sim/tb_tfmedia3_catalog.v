`timescale 1ns / 1ps

module tb_tfmedia3_catalog;

reg clk = 1'b0;
reg rst = 1'b1;
reg sd_init_done = 1'b0;
wire sd_sec_read;
wire [31:0] sd_sec_read_addr;
reg [7:0] sd_sec_read_data = 8'd0;
reg sd_sec_read_data_valid = 1'b0;
reg sd_sec_read_end = 1'b0;
wire catalog_ready;
wire [7:0] error_code;
wire [4:0] entry_count;
wire [31:0] total_sectors;
reg [4:0] entry_select = 5'd0;
wire [7:0] entry_media_type;
wire [7:0] entry_flags;
wire [15:0] entry_media_id;
wire [31:0] entry_metadata_lba;
wire [31:0] entry_data_lba;
wire [31:0] entry_data_bytes;
wire [3:0] debug_state;

reg [7:0] image_header [0:1023];
reg streaming = 1'b0;
reg [31:0] active_lba = 32'd0;
integer stream_index = 0;
integer image_file;
integer bytes_read;
reg [2047:0] image_path;

always #5 clk = ~clk;

tfmedia3_catalog #(
    .READ_TIMEOUT_CLKS(100000)
) dut (
    .clk(clk),
    .rst(rst),
    .sd_init_done(sd_init_done),
    .sd_sec_read(sd_sec_read),
    .sd_sec_read_addr(sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data),
    .sd_sec_read_data_valid(sd_sec_read_data_valid),
    .sd_sec_read_end(sd_sec_read_end),
    .catalog_ready(catalog_ready),
    .error_code(error_code),
    .entry_count(entry_count),
    .total_sectors(total_sectors),
    .entry_select(entry_select),
    .entry_media_type(entry_media_type),
    .entry_flags(entry_flags),
    .entry_media_id(entry_media_id),
    .entry_metadata_lba(entry_metadata_lba),
    .entry_data_lba(entry_data_lba),
    .entry_data_bytes(entry_data_bytes),
    .debug_state(debug_state)
);

always @(posedge clk) begin
    sd_sec_read_data_valid <= 1'b0;
    sd_sec_read_end <= 1'b0;
    if (sd_sec_read && !streaming) begin
        streaming <= 1'b1;
        active_lba <= sd_sec_read_addr;
        stream_index <= 0;
    end else if (streaming) begin
        sd_sec_read_data <= image_header[active_lba * 512 + stream_index];
        sd_sec_read_data_valid <= 1'b1;
        if (stream_index == 511) begin
            streaming <= 1'b0;
            sd_sec_read_end <= 1'b1;
        end else begin
            stream_index <= stream_index + 1;
        end
    end
end

task check_entry;
    input [4:0] select_value;
    input [7:0] expected_type;
    input [31:0] expected_meta;
    input [31:0] expected_data;
    input [31:0] expected_bytes;
    begin
        entry_select = select_value;
        #1;
        wait(catalog_ready);
        #1;
        if ((entry_media_type !== expected_type) ||
            (entry_metadata_lba !== expected_meta) ||
            (entry_data_lba !== expected_data) ||
            (entry_data_bytes !== expected_bytes)) begin
            $display("FAIL entry %0d type=%0d meta=%0d data=%0d bytes=%0d",
                     select_value, entry_media_type, entry_metadata_lba,
                     entry_data_lba, entry_data_bytes);
            $finish;
        end
    end
endtask

initial begin
    if (!$value$plusargs("image=%s",image_path)) $fatal(1,"missing image path");
    image_file = $fopen(image_path, "rb");
    if (image_file == 0) begin
        $fatal(1,"cannot open golden tf_media.img");
    end
    bytes_read = $fread(image_header, image_file);
    $fclose(image_file);
    if (bytes_read != 1024) begin
        $fatal(1,"golden header length=%0d", bytes_read);
    end
    if($test$plusargs("corrupt")) image_header[100]=image_header[100]^1;
    #50 rst = 1'b0;
    #20 sd_init_done = 1'b1;

    wait(catalog_ready || (error_code != 0));
    if($test$plusargs("corrupt")) begin
        if(error_code!=8'h03) $fatal(1,"corrupt CRC accepted or wrong error: %h",error_code);
        $display("PASS: RTL catalog rejects corrupted superblock CRC"); $finish;
    end
    if (error_code != 0) begin
        $fatal(1,"parser error 0x%02x state=%0d", error_code, debug_state);
    end
    if ((entry_count !== 5'd3) || (total_sectors !== 32'd81574)) begin
        $fatal(1,"header entries=%0d sectors=%0d", entry_count, total_sectors);
    end

    check_entry(5'd0, 8'd1, 32'd2,     32'd4,     32'd14357);
    check_entry(5'd1, 8'd2, 32'd33,    32'd56,    32'd36349568);
    check_entry(5'd2, 8'd1, 32'd81500, 32'd81502, 32'd36450);
    $display("PASS TFMEDIA3 catalog parser");
    $finish;
end
initial begin #1000000; $fatal(1,"catalog timeout"); end

endmodule

