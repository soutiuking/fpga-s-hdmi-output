`timescale 1ns/1ps
// Exercise the real pipeline's watchdog against distinct stalled interfaces.
// The core model never emits pixels; this test concerns error observability.
module jpeg_core #(parameter SUPPORT_WRITABLE_DHT=1)(
    input clk_i, rst_i, inport_valid_i, input [31:0] inport_data_i,
    input [3:0] inport_strb_i, input inport_last_i, outport_accept_i,
    output inport_accept_o, outport_valid_o,
    output [15:0] outport_width_o, outport_height_o,
    output [15:0] outport_pixel_x_o, outport_pixel_y_o,
    output [7:0] outport_pixel_r_o, outport_pixel_g_o, outport_pixel_b_o,
    output idle_o);
reg accept_input;
assign inport_accept_o = accept_input;
assign outport_valid_o = 0;
assign outport_width_o = 640;
assign outport_height_o = 480;
assign outport_pixel_x_o = 0;
assign outport_pixel_y_o = 0;
assign outport_pixel_r_o = 0;
assign outport_pixel_g_o = 0;
assign outport_pixel_b_o = 0;
assign idle_o = 0;
endmodule

module stripe_bram_10240x24(input clk, write_enable,
    input [13:0] write_address, input [23:0] write_data,
    input [13:0] read_address, output [23:0] read_data);
assign read_data=24'd0;
endmodule

module tb_jpeg_timeout_debug;
reg clk=0;
always #5 clk=~clk;
reg rst=1, cached=0, ack_enable=0, ram_enable=0;
reg ready=0;
wire request, write_req;
wire [7:0] error;
wire [3:0] stage;
wire [19:0] detail;
reg finish=0;
jpeg_decode_pipeline #(.DECODE_TIMEOUT_CLKS(120)) dut(
    .clk(clk), .rst(rst), .frame_cached(cached), .cached_slot(1'b0),
    .cached_bytes(17'd12), .target_slot(1'b0), .sram_request(request),
    .sram_address(), .sram_read_data(16'hd8ff), .sram_ready(ready),
    .frame_write_req(write_req), .frame_write_req_ack(write_req && ack_enable),
    .frame_write_en(), .frame_write_data(), .frame_write_slot(),
    .frame_write_finish(finish), .decode_done(), .decode_ready(),
    .decoded_slot(), .decode_error(error), .decode_state(stage),
    .decode_debug(detail));
always @(posedge clk) ready <= request && ram_enable;
task start;
    begin
        @(negedge clk); rst=1; cached=0; finish=0;
        repeat(3) @(negedge clk);
        rst=0;
        @(negedge clk); cached=1;
        @(negedge clk); cached=0;
    end
endtask
task check_frozen;
    input [3:0] expected_stage;
    input [19:0] expected_detail;
    begin
        wait(error != 0);
        @(negedge clk);
        if(error !== 8'h34 || stage !== expected_stage || detail !== expected_detail)
            $fatal(1,"timeout trace: error=%h stage=%h detail=%h expected=%h/%h",
                   error,stage,detail,expected_stage,expected_detail);
        // Completion activity after failure must not rewrite the evidence.
        finish=1;
        repeat(8) @(negedge clk);
        if(stage !== expected_stage || detail !== expected_detail)
            $fatal(1,"timeout evidence changed after error");
    end
endtask
initial begin
    dut.u_jpeg_core.accept_input=0;
    ack_enable=0; ram_enable=0; start(); check_frozen(1,20'h00000);
    ack_enable=1; ram_enable=0; start(); check_frozen(3,20'h00000);
    ram_enable=1; start(); check_frozen(6,20'h00000);
    dut.u_jpeg_core.accept_input=1; start(); check_frozen(7,20'h20002);
    start();
    wait(dut.state == 7);
    @(negedge clk);
    force dut.jpeg_idle=1'b1;
    force dut.all_pixels_queued=1'b1;
    check_frozen(8,20'he0002);
    $display("PASS: timeout freezes write-ACK, SRAM, feed, decode and SDRAM-finish stages/flags/word index");
    $finish;
end
initial begin #100000; $fatal(1,"timeout debug test hung"); end
endmodule
