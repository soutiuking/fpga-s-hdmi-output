`timescale 1ns/1ps
// SDRAM burst reader with optional true two-page RGB blending. One old-page
// burst is buffered in a small synchronous RAM; the corresponding new burst
// is mixed into the existing display FIFO. Pages remain owned until fade ACK.
module picture_blend_read #(
    parameter ADDR_BITS=21, BURST_SIZE=128
)(
    input rst, mem_clk, Sdr_init_done, Sdr_init_ref_vld, Sdr_busy,
    input Sdr_rd_en, input [31:0] Sdr_rd_dout, input App_wr_busy,
    output O_rd_busy, output App_rd_en, output [ADDR_BITS-1:0] App_rd_addr,
    input read_req, output reg read_req_ack, output read_finish,
    input [ADDR_BITS-1:0] read_addr_0,read_addr_1,read_addr_2,read_addr_3,
    input [1:0] read_addr_index, input [ADDR_BITS-1:0] read_len,
    input blend_active, input [4:0] blend_level,
    output reg fifo_aclr, input [9:0] wrusedw,
    output mixed_valid, output [31:0] mixed_data
);
localparam IDLE=0,ACK=1,CHECK=2,SETUP=3,ISSUE=4,DRAIN=5,SETTLE=6,NEXT=7,DONE=8;
reg [3:0] state;
reg [2:0] req_sync;
reg [1:0] page_meta,page_sync,page;
reg blend_meta,blend_sync,blend;
reg [4:0] level_meta,level_sync,level;
reg [ADDR_BITS-1:0] length_meta,length_sync,length,offset,address;
reg [8:0] issued,received;
reg old_phase,space_q;
reg [3:0] settle;
wire [1:0] selected_page=old_phase ? (page ^ 2'd1) : page;
wire [ADDR_BITS-1:0] base=selected_page==0 ? read_addr_0 :
    selected_page==1 ? read_addr_1 : selected_page==2 ? read_addr_2 : read_addr_3;
wire returning=Sdr_rd_en && (state==ISSUE || state==DRAIN);
assign App_rd_en=state==ISSUE;
assign App_rd_addr=address;
assign O_rd_busy=state==SETUP || state==ISSUE || state==DRAIN || state==SETTLE;
assign read_finish=state==DONE;
// Unreset synchronous RAM infers BRAM9K rather than thousands of registers.
reg [23:0] old_pixels [0:BURST_SIZE-1];
reg [23:0] old_q,new_q;
reg input_valid;
always @(posedge mem_clk) begin
    if(returning && old_phase) old_pixels[received[6:0]]<=Sdr_rd_dout[31:8];
    old_q<=old_pixels[received[6:0]];
    new_q<=Sdr_rd_dout[31:8];
end
always @(posedge mem_clk or posedge rst)
    if(rst) input_valid<=0;
    else input_valid<=returning && !old_phase;
picture_mix_pipe u_mix(.clk(mem_clk),.rst(rst | fifo_aclr),.valid_in(input_valid),
    .old_rgb(old_q),.new_rgb(new_q),.level(blend ? level : 5'd16),
    .valid_out(mixed_valid),.rgb_out(mixed_data[31:8]));
assign mixed_data[7:0]=0;
always @(posedge mem_clk or posedge rst) begin
    if(rst) begin
        req_sync<=0;page_meta<=0;page_sync<=0;blend_meta<=0;blend_sync<=0;
        level_meta<=16;level_sync<=16;length_meta<=0;length_sync<=0;space_q<=0;
    end else begin
        req_sync<={req_sync[1:0],read_req};
        page_meta<=read_addr_index;page_sync<=page_meta;
        blend_meta<=blend_active;blend_sync<=blend_meta;
        level_meta<=blend_level;level_sync<=level_meta;
        length_meta<=read_len;length_sync<=length_meta;
        space_q<=wrusedw < (512-BURST_SIZE-8);
    end
end
always @(posedge mem_clk or posedge rst) begin
    if(rst) begin
        state<=IDLE;read_req_ack<=0;fifo_aclr<=0;page<=0;blend<=0;level<=16;
        length<=0;offset<=0;address<=0;issued<=0;received<=0;old_phase<=0;settle<=0;
    end else begin
        if(returning) received<=received+1'b1;
        case(state)
            IDLE: if(req_sync[2] && Sdr_init_done) state<=ACK;
            ACK: begin
                read_req_ack<=1;fifo_aclr<=1;
                page<=page_sync;blend<=blend_sync;level<=level_sync;
                length<=length_sync;offset<=0;
                if(!req_sync[2]) begin
                    read_req_ack<=0;fifo_aclr<=0;state<=CHECK;
                end
            end
            CHECK: begin
                if(req_sync[2]) state<=ACK;
                else if(space_q && !App_wr_busy && !Sdr_init_ref_vld && !Sdr_busy) begin
                    old_phase<=blend;state<=SETUP;
                end
            end
            SETUP: begin
                address<=base+offset;issued<=0;received<=0;state<=ISSUE;
            end
            ISSUE: begin
                issued<=issued+1'b1;address<=address+1'b1;
                if(issued==BURST_SIZE-1) state<=DRAIN;
            end
            DRAIN: if(received==BURST_SIZE) begin settle<=0;state<=SETTLE;end
            SETTLE: begin
                settle<=settle+1'b1;
                if(settle==7) begin
                    if(old_phase) begin old_phase<=0;state<=SETUP;end
                    else begin offset<=offset+BURST_SIZE;state<=NEXT;end
                end
            end
            NEXT: begin
                if(req_sync[2]) state<=ACK;
                else if(offset<length) state<=CHECK;
                else state<=DONE;
            end
            DONE: state<=IDLE;
            default: state<=IDLE;
        endcase
    end
end
endmodule

// Shift/add interpolation, no DSP: floor((old*(16-a)+new*a)/16).
// Split arithmetic across registers to preserve the 125 MHz memory clock.
module picture_mix_pipe(
    input clk,rst,valid_in, input [23:0] old_rgb,new_rgb,input [4:0] level,
    output reg valid_out,output reg [23:0] rgb_out
);
reg [2:0] valid_pipe;
reg signed [8:0] delta_q[0:2];
reg [23:0] base_q,new_q;
reg [4:0] level_q;
reg signed [12:0] low_part[0:2],high_part[0:2],base_part[0:2],sum_part[0:2];
reg [23:0] new_d1,new_d2;
reg full_d1,full_d2;
integer c;
reg signed [12:0] delta;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        valid_pipe<=0;valid_out<=0;rgb_out<=0;new_d1<=0;new_d2<=0;full_d1<=0;full_d2<=0;
        base_q<=0;new_q<=0;level_q<=16;
        for(c=0;c<3;c=c+1) begin delta_q[c]<=0;low_part[c]<=0;high_part[c]<=0;base_part[c]<=0;sum_part[c]<=0;end
    end else begin
        valid_pipe<={valid_pipe[1:0],valid_in};valid_out<=valid_pipe[2];
        base_q<=old_rgb;new_q<=new_rgb;level_q<=level;
        new_d1<=new_q;new_d2<=new_d1;full_d1<=level_q>=16;full_d2<=full_d1;
        for(c=0;c<3;c=c+1) begin
            delta_q[c]<=$signed({1'b0,new_rgb[c*8+:8]})-$signed({1'b0,old_rgb[c*8+:8]});
            delta=delta_q[c];
            low_part[c]<=(level_q[0]?delta:13'sd0)+(level_q[1]?(delta<<<1):13'sd0);
            high_part[c]<=(level_q[2]?(delta<<<2):13'sd0)+(level_q[3]?(delta<<<3):13'sd0);
            base_part[c]<=$signed({1'b0,base_q[c*8+:8],4'b0});
            sum_part[c]<=base_part[c]+low_part[c]+high_part[c];
            rgb_out[c*8+:8]<=full_d2 ? new_d2[c*8+:8] : sum_part[c][11:4];
        end
    end
end
endmodule
