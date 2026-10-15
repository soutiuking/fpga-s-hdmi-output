`timescale 1ns/1ps
// A slow decoder lets the preloaded frame go stale. The real reader must
// replace it by a direct index lookup and preserve both SRAM slot owners.
module tb_reader_catchup;
reg clk=0,rst=1;always #12.5 clk=~clk;
reg ready=1,presented=0;
reg [31:0] playhead=0;
wire [18:0] address;wire [15:0] dq;
wire ce,we,oe,lb,ub,cached,slot;
wire [16:0] bytes;
wire [31:0] number;
wire [7:0] error;
reg [15:0] memory[0:65535];
integer submissions=0;
assign dq=(!ce && !oe && we)?memory[address]:16'bz;
always @(posedge we) if(!ce) begin
 if(!lb) memory[address][7:0]=dq[7:0];
 if(!ub) memory[address][15:8]=dq[15:8];
end
tfmedia3_reader_frontend #(.CLK_HZ(100000)) dut(
 .clk(clk),.rst(rst),.key_s1_n(1'b1),.key_s2_n(1'b1),.sd_miso(1'b1),
 .sram_addr(address),.sram_dq(dq),.sram_ce_n(ce),.sram_we_n(we),
 .sram_oe_n(oe),.sram_lb_n(lb),.sram_ub_n(ub),
 .decode_sram_request(1'b0),.decode_sram_address(19'b0),.decode_ready(ready),
 .frame_presented(presented),.audio_playback_enable(1'b0),.audio_sample_request_toggle(1'b0),
 .frame_cached(cached),.cached_slot(slot),.cached_bytes(bytes),
 .cached_frame_number(number),.player_error(error));
always @(posedge clk) if(!rst) begin
 if(error) $fatal(1,"catchup reader error %h",error);
 if(cached) begin
  if(submissions==0 && (number!=0 || slot!=0)) $fatal(1,"bad first frame");
  if(submissions==1 && (number!=9 || slot!=1)) $fatal(1,"stale frame not replaced by frame 9 in spare slot: frame=%0d slot=%0d",number,slot);
  if(submissions==2 && (number!=10 || slot!=0)) $fatal(1,"one-period late prefetch not retained: frame=%0d slot=%0d",number,slot);
  if(submissions==3 && (number!=11 || slot!=1)) $fatal(1,"last frame not clamped/retained: frame=%0d slot=%0d",number,slot);
  if(memory[slot?32768:0]!==16'hd8ff || bytes==0) $fatal(1,"catchup JPEG cache corrupt");
  submissions=submissions+1;
  ready<=0;
 end
end
initial begin
 #101 rst=0;
 wait(submissions==1);
 wait(dut.player_state==9 && dut.frame_number==1);
 @(negedge clk);presented=1;
 @(negedge clk);presented=0;
 force dut.playback_frame_number=playhead;
 playhead=8;
 repeat(50) @(negedge clk);
 if(submissions!=1) $fatal(1,"reader reused decoder-owned SRAM");
 ready=1;
 wait(submissions==2);
 @(negedge clk);playhead=11;
 wait(dut.player_state==9 && dut.frame_number==10);
 @(negedge clk);ready=1;
 wait(submissions==3);
 wait(dut.player_state==9 && dut.frame_number==11);
 @(negedge clk);ready=1;
 wait(submissions==4);
 $display("PASS: late cached frame discarded, direct seek 1 -> 9, spare SRAM ownership and last-frame clamp preserved");
 $finish;
end
initial begin #100000000;$fatal(1,"catchup timeout state=%h frame=%0d submissions=%0d",dut.player_state,dut.frame_number,submissions);end
endmodule
