`timescale 1ns / 1ps

// Active-low push-button synchronizer/debouncer.  pressed_pulse is emitted
// once after the input has remained low for STABLE_CLKS clocks.
module button_debounce_pulse #(
    parameter integer STABLE_CLKS = 250_000
)(
    input      clk,
    input      rst,
    input      button_n,
    output reg pressed_pulse,
    output reg pressed
);

reg sync0;
reg sync1;
reg [31:0] stable_count;
reg debounced_n;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sync0        <= 1'b1;
        sync1        <= 1'b1;
        stable_count <= 32'd0;
        debounced_n  <= 1'b1;
        pressed      <= 1'b0;
        pressed_pulse <= 1'b0;
    end else begin
        sync0 <= button_n;
        sync1 <= sync0;
        pressed_pulse <= 1'b0;

        if (sync1 == debounced_n) begin
            stable_count <= 32'd0;
        end else if (stable_count == STABLE_CLKS - 1) begin
            stable_count <= 32'd0;
            debounced_n  <= sync1;
            pressed      <= ~sync1;
            if (!sync1)
                pressed_pulse <= 1'b1;
        end else begin
            stable_count <= stable_count + 1'b1;
        end
    end
end

endmodule
