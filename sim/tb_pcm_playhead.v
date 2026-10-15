`timescale 1ns/1ps
module tb_pcm_playhead;
reg clk=0;always #5 clk=~clk;
reg rst=1,configure=0,play=0,request=0;
wire read,ack,consumed,ended,underflow;
wire [31:0] address;
wire [15:0] value,buffered;
reg valid=0,done=0;
reg [7:0] data;
reg reading=0;
integer sector_byte=0,base_byte=0,played=0,index;
pcm_audio_buffer dut(.clk(clk),.rst(rst),.configure(configure),
 .audio_lba(32'd100),.audio_bytes(32'd38400),.playback_enable(play),
 .sd_sec_read(read),.sd_sec_read_addr(address),.sd_sec_read_data(data),
 .sd_sec_read_data_valid(valid),.sd_sec_read_end(done),
 .sample_request_toggle(request),.sample_ack_toggle(ack),.sample_data(value),
 .underflow(underflow),.sample_consumed(consumed),.playback_done(ended),.buffered_bytes(buffered));
always @(posedge clk) begin
 valid<=0;done<=0;
 if(read) begin
  if(reading) $fatal(1,"overlapping PCM sector reads");
  reading<=1;sector_byte=0;base_byte=(address-100)*512;
 end else if(reading) begin
  valid<=1;data<=(base_byte+sector_byte)%256;
  if(sector_byte==511) begin reading<=0;done<=1;end
  else sector_byte=sector_byte+1;
 end
 if(!rst && consumed) played=played+1;
end
initial begin
 repeat(3) @(negedge clk);rst=0;configure=1;
 @(negedge clk);configure=0;
 wait(buffered>=1024);@(negedge clk);play=1;
 for(index=0;index<19200;index=index+1) begin
  request=~request;wait(ack==request);@(negedge clk);
  if(value!=={8'((2*index+1)%256),8'((2*index)%256)})
   $fatal(1,"PCM sample order mismatch at %0d value=%h",index,value);
  if(underflow) $fatal(1,"unexpected PCM underflow");
  if(index==5000) begin
   play=0;repeat(100) @(negedge clk);
   if(played!=index+1) $fatal(1,"paused PCM consumed bytes");
   play=1;
  end
 end
 if(!ended || played!=19200) $fatal(1,"missing exact PCM EOF count played=%0d",played);
 repeat(10) begin
  request=~request;wait(ack==request);@(negedge clk);
  if(underflow || value!=0 || played!=19200) $fatal(1,"EOF was treated as underflow or consumed extra samples");
 end
 $display("PASS: PCM ring wrap/sample ordering, exact consumed playhead, pause and clean EOF");$finish;
end
initial begin #10000000;$fatal(1,"PCM test timeout");end
endmodule
