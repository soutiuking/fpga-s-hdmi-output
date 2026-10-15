`timescale 1ns/1ps
// Storage model replaces the wire protocol only. Real catalog, metadata,
// arbiters, DMA and SRAM controller run against a generated three-frame card.
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248,SPI_HIGH_SPEED_DIV=0)(
 input clk,rst, output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output reg sd_init_done,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid,
 output reg sd_sec_read_end,input sd_sec_write,input [31:0] sd_sec_write_addr,
 input [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end);
assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
integer file_handle,code,index,gap,value;
reg active;
reg [1023:0] image_path;
initial begin
 if(!$value$plusargs("image=%s",image_path)) $fatal(1,"missing image");
 file_handle=$fopen(image_path,"rb");
 if(!file_handle) $fatal(1,"cannot open image");
end
always @(posedge clk) begin
 sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
 if(rst) begin sd_init_done<=0;active<=0;index=0;gap=0; end
 else begin
  sd_init_done<=1;
  if(sd_sec_read) begin
   if(active) $fatal(1,"overlapping sector requests");
   code=$fseek(file_handle,sd_sec_read_addr*512,0);active<=1;index=0;gap=0;
  end else if(active) begin
   if(gap==0) begin
    value=$fgetc(file_handle);
    if(value<0) $fatal(1,"sector past EOF");
    sd_sec_read_data<=value;sd_sec_read_data_valid<=1;gap=31;
    if(index==511) begin active<=0;sd_sec_read_end<=1; end
    else index=index+1;
   end else gap=gap-1;
  end
 end
end
endmodule

module pcm_bram_28672x8(input clk,write_enable,input [14:0] write_address,
 input [7:0] write_data,input [14:0] read_address,output reg [7:0] read_data);
reg [7:0] mem[0:28671];
always @(posedge clk) begin
 if(write_enable) mem[write_address]<=write_data;
 read_data<=mem[read_address];
end
endmodule

module tb_reader_lifecycle;
reg clk=0,rst=1;always #12.5 clk=~clk;
reg s1=1,s2=1;
wire [18:0] address;wire [15:0] dq;
wire ce,we,oe,lb,ub,paused,cached,tick,slot;
wire [16:0] bytes;
wire [7:0] error;
wire [3:0] state;
wire [31:0] frame_number;
reg ready=1,presented=0,pending=0,due=0;
reg audio_request=0;
integer audio_divider=0;
wire audio_ack;
integer decode_delay=0,submissions=0,presentations=0;
reg [15:0] memory[0:65535];
assign dq=(!ce && !oe && we)?memory[address]:16'bz;
always @(posedge we) if(!ce) begin
 if(!lb) memory[address][7:0]=dq[7:0];
 if(!ub) memory[address][15:8]=dq[15:8];
end
tfmedia3_reader_frontend #(.CLK_HZ(100000)) dut(
 .clk(clk),.rst(rst),.key_s1_n(s1),.key_s2_n(s2),.sd_miso(1'b1),
 .sram_addr(address),.sram_dq(dq),.sram_ce_n(ce),.sram_we_n(we),
 .sram_oe_n(oe),.sram_lb_n(lb),.sram_ub_n(ub),
 .decode_sram_request(1'b0),.decode_sram_address(19'b0),.decode_ready(ready),
 .frame_presented(presented),.audio_playback_enable(presentations!=0 && !paused),
 .audio_sample_request_toggle(audio_request),.audio_sample_ack_toggle(audio_ack),
 .paused(paused),.frame_cached(cached),.frame_tick(tick),.cached_slot(slot),
 .cached_bytes(bytes),.frame_number(frame_number),.player_error(error),.player_state(state));
always @(posedge clk) begin
 presented<=0;
 if(!rst) begin
  // Keep audio consuming while storage prefetch and video presentation run.
  // A sample every 100 clocks leaves enough modeled SD bandwidth for video.
  if(audio_divider==99) begin
   audio_divider=0;
   if(audio_request==audio_ack) audio_request<=~audio_request;
  end else audio_divider=audio_divider+1;
  if(error) $fatal(1,"reader error %h state %h",error,state);
  if(tick) due<=1;
  if(cached) begin
   if(!ready || slot!==((submissions%3)%2)) $fatal(1,"slot ownership violation");
   if(memory[slot?32768:0]!==16'hd8ff || bytes==0) $fatal(1,"bad cached JPEG");
   submissions=submissions+1;ready<=0;pending<=1;decode_delay=7000;
  end
  if(decode_delay>0) decode_delay=decode_delay-1;
  if(pending && decode_delay==0 && (due || tick) && !paused) begin
   pending<=0;due<=0;presented<=1;ready<=1;presentations=presentations+1;
   if(presentations==3) begin
    if(submissions!=3) $fatal(1,"last frame skipped");
    $display("PASS: 3 video frames cached/presented in order, final frame retained");
   end
   if(presentations==6) begin
    if(submissions!=6) $fatal(1,"second loop frame skipped");
    $display("PASS: automatic video completion/reload and six frame presentations with audio SD traffic");$finish;
   end
  end
 end
end
initial begin #101 rst=0; #100000000; $fatal(1,"reader lifecycle timeout state=%h submissions=%0d",state,submissions); end
integer paused_count;
initial begin
 wait(presentations==1);
 @(negedge clk);s2=0;
 wait(paused);
 @(negedge clk);s2=1;
 repeat(1000) @(negedge clk);
 paused_count=presentations;
 repeat(400000) @(negedge clk);
 if(presentations!=paused_count) $fatal(1,"video advanced while paused");
 s2=0;wait(!paused);
 @(negedge clk);s2=1;
 $display("PASS: pause holds presentation while next frame is cached");
end
endmodule
