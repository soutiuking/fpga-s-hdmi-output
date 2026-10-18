`timescale 1ns/1ps
module tb_picture_present_blend;
reg rclk=0,vclk=0,rst=1,submit=0,slot=0,picture=0;
reg boundary=0,ack=0;
wire busy,presented,video_slot,video_valid,blend;
wire [4:0] level;
always #12.5 rclk=~rclk;
always #20 vclk=~vclk;
frame_present_cdc #(.ENABLE_BLEND(1)) dut(
    .reader_clk(rclk),.reader_rst(rst),.submit(submit),.submit_slot(slot),
    .submit_valid(1'b1),.submit_picture(picture),.busy(busy),.presented(presented),
    .video_clk(vclk),.video_rst(rst),.frame_boundary(boundary),.read_ack(ack),
    .video_slot(video_slot),.video_valid(video_valid),.blend_active(blend),.blend_level(level));
integer completed=0,i;
reg saved_slot;
always @(posedge rclk) if(presented) completed=completed+1;
task frame;
    begin
        @(negedge vclk);boundary=1;
        @(negedge vclk);boundary=0;
        repeat(4) @(negedge vclk);ack=1;
        repeat(4) @(negedge vclk);ack=0;
        repeat(8) @(negedge vclk);
    end
endtask
task post;
    input pic;
    begin
        @(negedge rclk);slot=~slot;picture=pic;submit=1;
        @(negedge rclk);submit=0;
        repeat(8) @(negedge vclk);
        if(!busy || video_slot==slot) $fatal(1,"early page release");
    end
endtask
initial begin
    #111 rst=0;
    post(1);frame;
    if(blend || busy || completed!=1) $fatal(1,"first image faded");
    post(1);frame;
    if(!blend || level!=1 || !busy) $fatal(1,"image-to-image fade not started");
    // A subsequent media request must not replace the held page/type while
    // the old picture is still being read by the blend engine.
    saved_slot=slot;
    @(negedge rclk);slot=~slot;picture=0;submit=1;
    @(negedge rclk);submit=0;slot=saved_slot;picture=1;
    repeat(8) @(negedge vclk);
    if(video_slot!==saved_slot || dut.held_picture!==1'b1 || !busy)
        $fatal(1,"busy mailbox lost picture page/type ownership");
    // Mailbox must hold both pages for every blended frame, despite read ACKs.
    for(i=2;i<=16;i=i+1) begin
        frame;
        if(!blend || level!=i || !busy || completed!=1) $fatal(1,"fade alpha/ownership");
    end
    frame;
    if(blend || busy || completed!=2) $fatal(1,"fade not retired after final frame");
    post(0);frame;
    if(blend || busy) $fatal(1,"picture-to-video faded");
    repeat(4) begin post(0);frame;if(blend || busy) $fatal(1,"video frame faded");end
    post(1);frame;
    if(blend || busy || completed!=8) $fatal(1,"video-to-picture faded");
    $display("PASS: only picture-to-picture blends, first picture and video frames/transitions bypass, page ownership held through 16 levels");
    $finish;
end
initial begin #1000000;$fatal(1,"picture presentation timeout");end
endmodule
