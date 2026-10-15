`timescale 1ns / 1ps

// 28 KiB byte-addressed PCM ring storage.  Seven native 32K BRAMs are used
// so the remaining large BRAM capacity is dedicated to audio buffering.
module pcm_bram_28672x8(
    input             clk,
    input             write_enable,
    input      [14:0] write_address,
    input      [7:0]  write_data,
    input      [14:0] read_address,
    output reg [7:0]  read_data
);

wire [7:0] bank_q [0:6];
reg  [2:0] read_bank_q;

always @(posedge clk)
    read_bank_q <= read_address[14:12];

always @* begin
    case (read_bank_q)
        3'd0: read_data = bank_q[0];
        3'd1: read_data = bank_q[1];
        3'd2: read_data = bank_q[2];
        3'd3: read_data = bank_q[3];
        3'd4: read_data = bank_q[4];
        3'd5: read_data = bank_q[5];
        3'd6: read_data = bank_q[6];
        default: read_data = 8'd0;
    endcase
end

genvar bank;
generate
    for (bank = 0; bank < 7; bank = bank + 1) begin : g_bank
        wire [7:0] unused_a;
        wire       bank_we = write_enable &&
                             (write_address[14:12] == bank);

        EG_LOGIC_BRAM #(
            .DATA_WIDTH_A(8), .DATA_WIDTH_B(8),
            .ADDR_WIDTH_A(12), .ADDR_WIDTH_B(12),
            .DATA_DEPTH_A(4096), .DATA_DEPTH_B(4096),
            .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
            .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
            .WRITEMODE_A("NORMAL"), .WRITEMODE_B("READBEFOREWRITE"),
            .RESETMODE("SYNC"), .IMPLEMENT("32K")
        ) u_ram (
            .dia(write_data), .addra(write_address[11:0]),
            .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(bank_we),
            .rsta(1'b0), .bea(1'b1), .doa(unused_a),
            .dib(8'd0), .addrb(read_address[11:0]),
            .ceb(1'b1), .oceb(1'b1), .clkb(clk), .web(1'b0),
            .rstb(1'b0), .beb(1'b1), .dob(bank_q[bank])
        );
    end
endgenerate

endmodule
