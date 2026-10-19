`timescale 1ns / 1ps

// 10,240 x 24 single-clock dual-port RAM built from nine EG4 32K BRAMs.
// Three 4K banks cover one 640 x 16 MCU stripe; each bank uses three byte
// lanes so no LUT/distributed RAM is consumed.
module stripe_bram_10240x24(
    input             clk,
    input             write_enable,
    input      [13:0] write_address,
    input      [23:0] write_data,
    input      [13:0] read_address,
    output reg [23:0] read_data
);

wire [23:0] bank0_q;
wire [23:0] bank1_q;
wire [23:0] bank2_q;
reg  [1:0]  read_bank_q;

always @(posedge clk)
    read_bank_q <= read_address[13:12];

always @* begin
    case (read_bank_q)
        2'd0: read_data = bank0_q;
        2'd1: read_data = bank1_q;
        2'd2: read_data = bank2_q;
        default: read_data = 24'd0;
    endcase
end

genvar bank;
genvar lane;
generate
    for (bank = 0; bank < 3; bank = bank + 1) begin : g_bank
        for (lane = 0; lane < 3; lane = lane + 1) begin : g_lane
            wire [7:0] unused_a;
            wire [7:0] lane_q;
            wire bank_we = write_enable && (write_address[13:12] == bank);

            EG_LOGIC_BRAM #(
                .DATA_WIDTH_A(8), .DATA_WIDTH_B(8),
                .ADDR_WIDTH_A(12), .ADDR_WIDTH_B(12),
                .DATA_DEPTH_A(4096), .DATA_DEPTH_B(4096),
                .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
                .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
                .WRITEMODE_A("NORMAL"), .WRITEMODE_B("READBEFOREWRITE"),
                .RESETMODE("SYNC"), .IMPLEMENT("32K")
            ) u_ram (
                .dia(write_data[lane*8 +: 8]), .addra(write_address[11:0]),
                .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(bank_we),
                .rsta(1'b0), .bea(1'b1), .doa(unused_a),
                .dib(8'd0), .addrb(read_address[11:0]),
                .ceb(1'b1), .oceb(1'b1), .clkb(clk), .web(1'b0),
                .rstb(1'b0), .beb(1'b1), .dob(lane_q)
            );

            if (bank == 0) begin : g_q0
                assign bank0_q[lane*8 +: 8] = lane_q;
            end else if (bank == 1) begin : g_q1
                assign bank1_q[lane*8 +: 8] = lane_q;
            end else begin : g_q2
                assign bank2_q[lane*8 +: 8] = lane_q;
            end
        end
    end
endgenerate

endmodule
