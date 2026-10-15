`timescale 1ns / 1ps

// Controller for the AC601 IS61WV51216 asynchronous SRAM (512K x 16).
// One request is accepted in IDLE. The controller deliberately uses several
// 50 MHz cycles per access, leaving comfortable margin around the 10 ns SRAM.
module async_sram16_controller(
    input              clk,
    input              rst,

    input              request,
    input              write_enable,
    input      [18:0]  address,
    input      [15:0]  write_data,
    input      [1:0]   byte_enable,
    output reg [15:0]  read_data,
    output reg         ready,

    output reg [18:0]  sram_addr,
    inout      [15:0]  sram_dq,
    output reg         sram_ce_n,
    output reg         sram_we_n,
    output reg         sram_oe_n,
    output reg         sram_lb_n,
    output reg         sram_ub_n
);

localparam [2:0] S_IDLE       = 3'd0;
localparam [2:0] S_READ_WAIT  = 3'd1;
localparam [2:0] S_READ_LATCH = 3'd2;
localparam [2:0] S_WRITE_WAIT = 3'd3;
localparam [2:0] S_WRITE_END  = 3'd4;

reg [2:0] state;
reg [15:0] write_latch;
reg        drive_dq;

assign sram_dq = drive_dq ? write_latch : 16'hZZZZ;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state       <= S_IDLE;
        read_data   <= 16'd0;
        ready       <= 1'b0;
        sram_addr   <= 19'd0;
        write_latch <= 16'd0;
        drive_dq    <= 1'b0;
        sram_ce_n   <= 1'b1;
        sram_we_n   <= 1'b1;
        sram_oe_n   <= 1'b1;
        sram_lb_n   <= 1'b1;
        sram_ub_n   <= 1'b1;
    end else begin
        ready <= 1'b0;
        case (state)
            S_IDLE: begin
                drive_dq  <= 1'b0;
                sram_ce_n <= 1'b1;
                sram_we_n <= 1'b1;
                sram_oe_n <= 1'b1;
                sram_lb_n <= 1'b1;
                sram_ub_n <= 1'b1;
                if (request) begin
                    sram_addr   <= address;
                    write_latch <= write_data;
                    sram_lb_n   <= ~byte_enable[0];
                    sram_ub_n   <= ~byte_enable[1];
                    sram_ce_n   <= 1'b0;
                    if (write_enable) begin
                        drive_dq  <= 1'b1;
                        sram_we_n <= 1'b0;
                        state <= S_WRITE_WAIT;
                    end else begin
                        sram_oe_n <= 1'b0;
                        state <= S_READ_WAIT;
                    end
                end
            end

            S_READ_WAIT: begin
                state <= S_READ_LATCH;
            end

            S_READ_LATCH: begin
                read_data <= sram_dq;
                sram_ce_n <= 1'b1;
                sram_oe_n <= 1'b1;
                sram_lb_n <= 1'b1;
                sram_ub_n <= 1'b1;
                ready <= 1'b1;
                state <= S_IDLE;
            end

            S_WRITE_WAIT: begin
                sram_we_n <= 1'b1;
                state <= S_WRITE_END;
            end

            S_WRITE_END: begin
                drive_dq  <= 1'b0;
                sram_ce_n <= 1'b1;
                sram_lb_n <= 1'b1;
                sram_ub_n <= 1'b1;
                ready <= 1'b1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule

