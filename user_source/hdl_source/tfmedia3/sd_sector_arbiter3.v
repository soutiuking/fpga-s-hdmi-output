`timescale 1ns / 1ps

// Three-client, read-only arbiter for the single-sector SD controller.
// Requests may be one clock wide.  They are latched until granted, so a
// request coincident with another client is not lost.
module sd_sector_arbiter3(
    input             clk,
    input             rst,

    input             c0_read,
    input      [31:0] c0_addr,
    output            c0_data_valid,
    output            c0_read_end,

    input             c1_read,
    input      [31:0] c1_addr,
    output            c1_data_valid,
    output            c1_read_end,

    input             c2_read,
    input      [31:0] c2_addr,
    output            c2_data_valid,
    output            c2_read_end,

    output reg        sd_read,
    output reg [31:0] sd_addr,
    input      [7:0]  sd_data,
    input             sd_data_valid,
    input             sd_read_end,

    output     [7:0]  client_data,
    output reg [1:0]  active_client,
    output reg        busy
);

reg        pending0;
reg        pending1;
reg        pending2;
reg [31:0] pending_addr0;
reg [31:0] pending_addr1;
reg [31:0] pending_addr2;

assign client_data   = sd_data;
assign c0_data_valid = busy && (active_client == 2'd0) && sd_data_valid;
assign c1_data_valid = busy && (active_client == 2'd1) && sd_data_valid;
assign c2_data_valid = busy && (active_client == 2'd2) && sd_data_valid;
assign c0_read_end   = busy && (active_client == 2'd0) && sd_read_end;
assign c1_read_end   = busy && (active_client == 2'd1) && sd_read_end;
assign c2_read_end   = busy && (active_client == 2'd2) && sd_read_end;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pending0      <= 1'b0;
        pending1      <= 1'b0;
        pending2      <= 1'b0;
        pending_addr0 <= 32'd0;
        pending_addr1 <= 32'd0;
        pending_addr2 <= 32'd0;
        sd_read       <= 1'b0;
        sd_addr       <= 32'd0;
        active_client <= 2'd0;
        busy          <= 1'b0;
    end else begin
        sd_read <= 1'b0;

        if (c0_read) begin
            pending0      <= 1'b1;
            pending_addr0 <= c0_addr;
        end
        if (c1_read) begin
            pending1      <= 1'b1;
            pending_addr1 <= c1_addr;
        end
        if (c2_read) begin
            pending2      <= 1'b1;
            pending_addr2 <= c2_addr;
        end

        if (busy) begin
            if (sd_read_end)
                busy <= 1'b0;
        end else if (pending0 || c0_read) begin
            active_client <= 2'd0;
            sd_addr       <= c0_read ? c0_addr : pending_addr0;
            sd_read       <= 1'b1;
            pending0      <= 1'b0;
            busy          <= 1'b1;
        end else if (pending1 || c1_read) begin
            active_client <= 2'd1;
            sd_addr       <= c1_read ? c1_addr : pending_addr1;
            sd_read       <= 1'b1;
            pending1      <= 1'b0;
            busy          <= 1'b1;
        end else if (pending2 || c2_read) begin
            active_client <= 2'd2;
            sd_addr       <= c2_read ? c2_addr : pending_addr2;
            sd_read       <= 1'b1;
            pending2      <= 1'b0;
            busy          <= 1'b1;
        end
    end
end

endmodule
