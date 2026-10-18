`timescale 1ns/1ps
module tb_frame_present_cdc;
reg reader_clk=0,video_clk=0;
always #12.5 reader_clk=~reader_clk;
always #20 video_clk=~video_clk;
reg rst=1,submit=0,slot=0,valid=0,boundary=0,read_ack=0;
wire busy,presented,video_slot,video_valid;
integer acknowledgements=0;
frame_present_cdc dut(.reader_clk(reader_clk),.reader_rst(rst),
    .submit(submit),.submit_slot(slot),.submit_valid(valid),.submit_picture(1'b0),.busy(busy),.presented(presented),
    .video_clk(video_clk),.video_rst(rst),.frame_boundary(boundary),.read_ack(read_ack),
    .video_slot(video_slot),.video_valid(video_valid));
always @(posedge reader_clk) if(presented) acknowledgements=acknowledgements+1;
task commit;
input new_slot;
begin
    @(negedge reader_clk); slot=new_slot;valid=1;submit=1;
    @(negedge reader_clk);submit=0;
    repeat(8) @(negedge video_clk);
    if(!busy || video_slot==new_slot) $fatal(1,"page changed before vblank");
    boundary=1;
    @(negedge video_clk); boundary=0;
    repeat(3) @(negedge video_clk);
    if(video_slot!=new_slot || !video_valid || !busy) $fatal(1,"bad vblank apply/early ACK");
    read_ack=1;
    repeat(4) @(negedge video_clk);
    read_ack=0;
    repeat(8) @(negedge reader_clk);
    if(busy) $fatal(1,"missing cross-domain ACK");
end
endtask
initial begin
    #111 rst=0;
    commit(1); commit(0); commit(1); commit(0);
    if(acknowledgements!=4) $fatal(1,"lost/duplicated presentation");
    $display("PASS: 4 pages change only at vblank and retire after SDRAM read ACK"); $finish;
end
initial begin #100000; $fatal(1,"timeout"); end
endmodule
