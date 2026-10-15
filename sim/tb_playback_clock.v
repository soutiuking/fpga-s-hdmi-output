`timescale 1ns/1ps
module tb_playback_clock;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,paused=0,use_audio=1,sample=0;
reg [31:0] count=1393;
wire active,complete,tick;
wire [31:0] frame;
integer index,expected,saved;
tfmedia3_playback_clock #(.CLK_HZ(2500)) dut(
 .clk(clk),.rst(rst),.start(start),.paused(paused),.use_audio(use_audio),
 .sample_consumed(sample),.frame_count(count),.active(active),
 .frame_number(frame),.complete(complete),.frame_tick(tick));
task reset_start;
begin
 @(negedge clk);rst=1;start=0;sample=0;paused=0;
 repeat(3) @(negedge clk);rst=0;
 repeat(20) @(negedge clk);
 if(active || frame || complete) $fatal(1,"timeline ran before first presented frame");
 start=1;@(negedge clk);start=0;
end
endtask
initial begin
 reset_start();
 for(index=0;index<1393*1920;index=index+1) begin
  sample=1;@(negedge clk);sample=0;
  expected=(index+1)/1920;
  if(expected>=1393) expected=1392;
  if(frame!=expected) $fatal(1,"audio clock drift sample=%0d frame=%0d expected=%0d",index+1,frame,expected);
  if(complete != (index+1==1393*1920)) $fatal(1,"incorrect audio completion");
  if(index==1930) begin
   paused=1;saved=frame;sample=0;
   repeat(4000) @(negedge clk);
   if(frame!=saved) $fatal(1,"timeline advanced while paused");
   paused=0;sample=0;
  end
  // Irregular FIFO/SD stalls must not advance media time.
  if(index%10000==0) begin
   saved=frame;repeat(200) @(negedge clk);
   if(frame!=saved) $fatal(1,"audio underrun advanced the video clock");
  end
  @(negedge clk);
 end
 $display("PASS: 55.72-second/1393-frame audio timeline has zero accumulated sample drift, pause and stalled PCM hold time");
 count=1;reset_start();sample=1;
 repeat(1919) @(negedge clk);
 sample=0;paused=1;
 repeat(10) @(negedge clk);
 if(complete) $fatal(1,"PCM ended early while paused");
 sample=1;@(negedge clk);sample=0;
 if(!complete) $fatal(1,"last in-flight sample was lost at pause, EOF would hang");
 $display("PASS: last in-flight PCM sample is counted at pause edge so EOF cannot hang");
 use_audio=0;count=5;reset_start();
 for(index=0;index<500;index=index+1) begin
  @(negedge clk);expected=(index+1)/100;
  if(expected>=5) expected=4;
  if(frame!=expected || complete!=(index==499)) $fatal(1,"silent timeline mismatch at %0d",index);
 end
 $display("PASS: silent video uses 25-fps reader clock and completes after its last full period");
 $finish;
end
initial begin #100000000;$fatal(1,"playback clock test timeout");end
endmodule
