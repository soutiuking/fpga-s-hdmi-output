`timescale 1ns / 1ps

// Two-client transaction arbiter for the single asynchronous SRAM port.
// Each client keeps at most one request outstanding until its ready pulse.
module sram_arbiter2(
    input             clk,
    input             rst,

    input             c0_request,
    input             c0_write_enable,
    input      [18:0] c0_address,
    input      [15:0] c0_write_data,
    input      [1:0]  c0_byte_enable,
    output reg [15:0] c0_read_data,
    output reg        c0_ready,

    input             c1_request,
    input             c1_write_enable,
    input      [18:0] c1_address,
    input      [15:0] c1_write_data,
    input      [1:0]  c1_byte_enable,
    output reg [15:0] c1_read_data,
    output reg        c1_ready,

    output reg        mem_request,
    output reg        mem_write_enable,
    output reg [18:0] mem_address,
    output reg [15:0] mem_write_data,
    output reg [1:0]  mem_byte_enable,
    input      [15:0] mem_read_data,
    input             mem_ready
);

reg        c0_pending;
reg        c1_pending;
reg        c0_we_latched;
reg        c1_we_latched;
reg [18:0] c0_addr_latched;
reg [18:0] c1_addr_latched;
reg [15:0] c0_data_latched;
reg [15:0] c1_data_latched;
reg [1:0]  c0_be_latched;
reg [1:0]  c1_be_latched;
reg [1:0]  owner;
reg        prefer_c1;

localparam [1:0] OWN_NONE = 2'd0;
localparam [1:0] OWN_C0   = 2'd1;
localparam [1:0] OWN_C1   = 2'd2;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        c0_pending      <= 1'b0;
        c1_pending      <= 1'b0;
        c0_ready        <= 1'b0;
        c1_ready        <= 1'b0;
        c0_read_data    <= 16'd0;
        c1_read_data    <= 16'd0;
        mem_request     <= 1'b0;
        mem_write_enable <= 1'b0;
        mem_address     <= 19'd0;
        mem_write_data  <= 16'd0;
        mem_byte_enable <= 2'b11;
        owner           <= OWN_NONE;
        prefer_c1       <= 1'b0;
    end else begin
        c0_ready    <= 1'b0;
        c1_ready    <= 1'b0;
        mem_request <= 1'b0;

        if (c0_request && !c0_pending && owner != OWN_C0) begin
            c0_pending      <= 1'b1;
            c0_we_latched   <= c0_write_enable;
            c0_addr_latched <= c0_address;
            c0_data_latched <= c0_write_data;
            c0_be_latched   <= c0_byte_enable;
        end
        if (c1_request && !c1_pending && owner != OWN_C1) begin
            c1_pending      <= 1'b1;
            c1_we_latched   <= c1_write_enable;
            c1_addr_latched <= c1_address;
            c1_data_latched <= c1_write_data;
            c1_be_latched   <= c1_byte_enable;
        end

        if (owner == OWN_NONE) begin
            if (c1_pending && (!c0_pending || prefer_c1)) begin
                mem_write_enable <= c1_we_latched;
                mem_address      <= c1_addr_latched;
                mem_write_data   <= c1_data_latched;
                mem_byte_enable  <= c1_be_latched;
                mem_request      <= 1'b1;
                owner            <= OWN_C1;
            end else if (c0_pending) begin
                mem_write_enable <= c0_we_latched;
                mem_address      <= c0_addr_latched;
                mem_write_data   <= c0_data_latched;
                mem_byte_enable  <= c0_be_latched;
                mem_request      <= 1'b1;
                owner            <= OWN_C0;
            end
        end else if (mem_ready) begin
            if (owner == OWN_C0) begin
                c0_read_data <= mem_read_data;
                c0_ready     <= 1'b1;
                c0_pending   <= 1'b0;
                prefer_c1    <= 1'b1;
            end else begin
                c1_read_data <= mem_read_data;
                c1_ready     <= 1'b1;
                c1_pending   <= 1'b0;
                prefer_c1    <= 1'b0;
            end
            owner <= OWN_NONE;
        end
    end
end

endmodule
