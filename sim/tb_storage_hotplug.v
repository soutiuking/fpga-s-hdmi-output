`timescale 1ns/1ps
// Only the card's wire protocol is modeled. All storage parsers, SRAM DMA,
// subtitle loader and retry/watchdog logic are production RTL.
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248,SPI_HIGH_SPEED_DIV=0)(
 input clk,rst, output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,
 output reg sd_init_done,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid,
 output reg sd_sec_read_end,input sd_sec_write,input [31:0] sd_sec_write_addr,
 input [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end);
assign {SD_nCS,SD_DCLK,SD_MOSI}=3'b101;
assign {sd_sec_write_data_req,sd_sec_write_end}=0;
reg present=0,second_card=0,corrupt=0,active=0;
integer first_file,second_file,handle,code,index,value,gap;
reg [31:0] lba;
reg [1023:0] first_path,second_path;
initial begin
 if(!$value$plusargs("first=%s",first_path) || !$value$plusargs("second=%s",second_path))$fatal(1,"missing images");
 first_file=$fopen(first_path,"rb");second_file=$fopen(second_path,"rb");
 if(!first_file || !second_file)$fatal(1,"cannot open card fixtures");
end
always @(posedge clk)begin
 sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
 if(rst)begin sd_init_done<=0;active<=0;index=0;gap=0;end
 else if(present)begin
  sd_init_done<=1;
  if(sd_sec_read)begin
   if(active)$fatal(1,"overlapping read");
   handle=second_card ? second_file : first_file;lba=sd_sec_read_addr;
   code=$fseek(handle,lba*512,0);active<=1;index=0;gap=0;
  end else if(active && gap==0)begin
   value=$fgetc(handle);if(value<0)$fatal(1,"sector past EOF");
   sd_sec_read_data<=corrupt && lba==0 && index==0 ? value^8'h01 : value;
   sd_sec_read_data_valid<=1;gap=15;
   if(index==511)begin active<=0;sd_sec_read_end<=1;end
   else index=index+1;
  end else if(active)gap=gap-1;
 end
 // With the card removed, init_done can remain high and a read can hang.
end
endmodule

module pcm_bram_28672x8(input clk,write_enable,input [14:0] write_address,
 input [7:0] write_data,input [14:0] read_address,output reg [7:0] read_data);
reg [7:0] mem[0:28671];
always @(posedge clk)begin
 if(write_enable)mem[write_address]<=write_data;read_data<=mem[read_address];
end
endmodule

module tb_storage_hotplug;
reg clk=0,rst=1;always #5 clk=~clk;
wire recovering,busy,cached;wire [7:0] error;wire [3:0] count;
wire [4:0] media_index;wire [18:0] address;wire [15:0] dq;
wire ce,we,oe,lb,ub;
reg [15:0] memory[0:65535];
integer retries=0;
wire storage_rst=rst|recovering;
storage_recovery #(.TIMEOUT_CLKS(10000),.RETRY_CLKS(200)) supervisor(
 .clk(clk),.rst(rst),.fault(error!=0),.sector_busy(busy),.recovering(recovering));
tfmedia3_reader_frontend #(.CLK_HZ(20000)) dut(
 .clk(clk),.rst(storage_rst),.key_s1_n(1'b1),.key_s2_n(1'b1),.sd_miso(1'b1),
 .decode_sram_request(1'b0),.decode_sram_address(19'd0),.decode_ready(1'b1),
 .frame_presented(1'b1),.audio_playback_enable(1'b0),.audio_sample_request_toggle(1'b0),
 .sram_addr(address),.sram_dq(dq),.sram_ce_n(ce),.sram_we_n(we),.sram_oe_n(oe),.sram_lb_n(lb),.sram_ub_n(ub),
 .frame_cached(cached),.player_error(error),.media_index(media_index),
 .subtitle_count(count),.subtitle_style_index(4'd0),.storage_busy(busy));
defparam dut.u_subtitles.TIMEOUT_CLKS=200000;
assign dq=(!ce && !oe && we)?memory[address]:16'bz;
always @(posedge we)if(!ce)begin
 if(!lb)memory[address][7:0]=dq[7:0];if(!ub)memory[address][15:8]=dq[15:8];
end
always @(posedge recovering)retries=retries+1;
task check_cleared;
 begin
  repeat(3)@(negedge clk);
  if(count!==0 || dut.catalog_ready!==0 || dut.metadata_ready!==0 || cached!==0 || media_index!==0 || dut.audio_sample_data!==0)
    $fatal(1,"stale card state survived retry");
 end
endtask
initial begin
 #31 rst=0;
 wait(retries==2);check_cleared();
 $display("PASS: absent card retries repeatedly without manual reset; catalog/subtitle/audio/cache invalidated");
 dut.u_sd.present=1;
 wait(cached);@(negedge clk);
 if(count!==2 || media_index!==0 || memory[0]!==16'hd8ff)$fatal(1,"late card did not load media and subtitles");
 $display("PASS: late insertion loads validated card and two custom subtitles from media zero");
 // Remove mid-sector while the card controller still claims initialized.
 wait(dut.sd_bus_read);@(negedge clk);dut.u_sd.present=0;
 wait(recovering);check_cleared();
 $display("PASS: hung sector after removal triggers watchdog and clears the full reader chain");
 dut.u_sd.second_card=1;dut.u_sd.corrupt=1;dut.u_sd.present=1;
 wait(!recovering);wait(error!=0);
 if(cached)$fatal(1,"corrupt superblock displayed media");
 wait(recovering);check_cleared();
 $display("PASS: corrupt replacement rejected and retry continues");
 dut.u_sd.corrupt=0;
 wait(!recovering);wait(cached);@(negedge clk);
 if(count!==0 || media_index!==0 || memory[0]!==16'hd8ff)$fatal(1,"new empty-subtitle card reused old data");
 $display("PASS: replacement starts first media with default subtitle fallback, no old-card subtitle leakage");
 repeat(1000)@(negedge clk);
 if(recovering || error)$fatal(1,"healthy card spuriously reset");
 $finish;
end
initial begin #20000000;$fatal(1,"hotplug test timed out state=%h error=%h retries=%d subtitles=%d",dut.player_state,error,retries,count);end
endmodule
