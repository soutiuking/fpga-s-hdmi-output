`timescale 1ns/1ps
// Bundled-data mailbox. Source holds page/valid until acknowledged.
// Apply a new page only before a new SDRAM read request; acknowledge after
// that request has reset the read FIFO and latched the new page in mem_clk.
module frame_present_cdc #(parameter ENABLE_BLEND=0)(
    input reader_clk, input reader_rst,
    input submit, input submit_slot, input submit_valid,
    input submit_picture,
    output busy, output presented,
    input video_clk, input video_rst,
    input frame_boundary, input read_ack,
    output reg video_slot, output reg video_valid,
    output reg blend_active, output reg [4:0] blend_level
);
reg request_toggle;
reg held_slot, held_valid;
reg held_picture,video_picture;
reg [2:0] ack_sync;
reg ack_seen;
reg [2:0] req_sync;
reg [1:0] read_ack_sync;
reg acknowledge_toggle;
reg waiting_ack, applied_toggle;
assign busy = request_toggle != ack_sync[2];
assign presented = ack_sync[2] != ack_seen;
always @(posedge reader_clk or posedge reader_rst) begin
    if (reader_rst) begin
        request_toggle <= 0; held_slot <= 0; held_valid <= 0;held_picture<=0;
        ack_sync <= 0; ack_seen <= 0;
    end else begin
        ack_sync <= {ack_sync[1:0], acknowledge_toggle};
        ack_seen <= ack_sync[2];
        if (submit && !busy) begin
            held_slot <= submit_slot;
            held_valid <= submit_valid;
            held_picture <= submit_picture;
            request_toggle <= ~request_toggle;
        end
    end
end
always @(posedge video_clk or posedge video_rst) begin
    if (video_rst) begin
        req_sync <= 0; read_ack_sync <= 0; acknowledge_toggle <= 0;
        video_slot <= 0; video_valid <= 0;
        waiting_ack <= 0; applied_toggle <= 0;
        video_picture<=0;blend_active<=0;blend_level<=16;
    end else begin
        req_sync <= {req_sync[1:0], request_toggle};
        read_ack_sync <= {read_ack_sync[0], read_ack};
        if (frame_boundary && !waiting_ack &&
            req_sync[2] != acknowledge_toggle) begin
            video_slot <= held_slot;
            video_valid <= held_valid;
            video_picture <= held_picture;
            if(ENABLE_BLEND && video_picture && held_picture && video_valid && held_valid) begin
                blend_active<=1;blend_level<=1;
            end
            applied_toggle <= req_sync[2];
            waiting_ack <= 1;
        end
        if(frame_boundary && blend_active) begin
            if(blend_level<16) blend_level<=blend_level+1'b1;
            else blend_active<=0;
        end
        if (waiting_ack && read_ack_sync[1] && !blend_active) begin
            acknowledge_toggle <= applied_toggle;
            waiting_ack <= 0;
        end
    end
end
endmodule
