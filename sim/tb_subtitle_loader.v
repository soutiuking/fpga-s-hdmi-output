`timescale 1ns/1ps
module tb_subtitle_loader;
reg clk=0,rst=1,start=0;always #5 clk=~clk;
reg [31:0] base=4,total=30;wire request;wire [31:0] address;
reg [7:0] data=0;reg valid=0,ending=0;wire done;wire [3:0] count;
reg [3:0] style_index=0;wire [30:0] style_data;
wire we;wire [12:0] wa;wire [15:0] wd;
subtitle_loader #(.TIMEOUT_CLKS(2000)) dut(.clk(clk),.rst(rst),.start(start),.base_lba(base),.total_sectors(total),
 .sd_read(request),.sd_addr(address),.sd_data(data),.sd_valid(valid),.sd_end(ending),.done(done),.count(count),
 .style_index(style_index),.style_data(style_data),.ram_we(we),.ram_address(wa),.ram_data(wd));
reg [7:0] bytes[0:11263];reg [7:0] expected[0:10239];
reg [2047:0] path;integer writes=0,reads=0,i,j,k,mode=0,timeout_count;
always @(negedge clk)if(we)begin
 if(wa!==writes || (mode!=2 && wd!=={expected[writes*2+1],expected[writes*2]}))$fatal(1,"subtitle RAM mismatch at %d",writes);
 writes=writes+1;
end
task reset;
 begin rst=1;start=0;valid=0;ending=0;repeat(3)@(negedge clk);rst=0;writes=0;reads=0;end
endtask
task serve;
 begin
 timeout_count=0;
 while(!done)begin
  @(negedge clk);timeout_count=timeout_count+1;
  if(timeout_count>40000)$fatal(1,"loader stuck");
  if(request && mode!=3)begin
   if(address!==base+reads)$fatal(1,"wrong SD address");
   for(j=0;j<512;j=j+1)begin
    data=bytes[reads*512+j];
    if((mode==1 && reads==0 && j==100)||(mode==2 && reads==8 && j==12))data=data^1;
    valid=1;@(negedge clk);
   end
   valid=0;ending=1;@(negedge clk);ending=0;reads=reads+1;
  end
 end
 end
endtask
initial begin
 if(!$value$plusargs("blob=%s",path))$fatal(1,"missing blob");$readmemh(path,bytes);
 k=0;for(i=1;i<22;i=i+1)for(j=0;j<504;j=j+1)if(k<10240)begin expected[k]=bytes[i*512+j];k=k+1;end
 reset;start=1;serve;
 if(count!=10 || reads!=22 || writes!=5120)$fatal(1,"successful load count/read/write mismatch");
 for(i=0;i<10;i=i+1)begin
  style_index=i;repeat(3)@(negedge clk);
  if(style_data!=={bytes[17+i*8][0],bytes[18+i*8],bytes[19+i*8],bytes[20+i*8],bytes[16+i*8][5:0]})$fatal(1,"metadata mismatch");
 end
 // Corrupt sectors must hide all custom text, even after some RAM writes.
 for(mode=1;mode<=3;mode=mode+1)begin
  reset;start=1;
  serve;
  if(count!=0)$fatal(1,"corrupt/timeout subtitle did not fall back");
 end
 reset;base=0;start=1;serve;if(count!=0 || reads!=0)$fatal(1,"legacy card fallback");
 reset;base=12;start=1;serve;if(count!=0 || reads!=0)$fatal(1,"range fallback");
 $display("PASS: subtitle loader, 5120 bitmap words, ten styles, CRC errors, timeout and legacy/range fallbacks");$finish;
end
initial begin #2000000;$fatal(1,"loader test timed out");end
endmodule
