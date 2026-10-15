`timescale 1ns/1ps
// A legal header followed by stuffed entropy. The word C0 22 33 FF
// must not turn into a synthetic FF C0 marker while input valid is low.
module tb_jpeg_input_gaps;
reg clk=0; always #5 clk=~clk;
reg rst=1,valid=0,last=0;
reg [31:0] data=0;
reg [3:0] strb=15;
wire accept;
wire [15:0] width,height;
reg [7:0] bytes[0:65535];
reg [1023:0] jpeg_hex;
reg header_seen=0;
integer pos,lane,length=44,arg_status;
jpeg_input dut(.clk_i(clk),.rst_i(rst),.inport_valid_i(valid),
 .inport_data_i(data),.inport_strb_i(strb),.inport_last_i(last),
 .dqt_cfg_accept_i(1'b1),.dht_cfg_accept_i(1'b1),.data_accept_i(1'b1),
 .inport_accept_o(accept),.img_width_o(width),.img_height_o(height));
initial begin
 bytes[0]=255;bytes[1]='hd8;bytes[2]=255;bytes[3]='hc0;
 bytes[4]=0;bytes[5]=17;
 bytes[6]=8;bytes[7]=1;bytes[8]='he0;bytes[9]=2;bytes[10]='h80;
 bytes[11]=3;bytes[12]=1;bytes[13]='h22;bytes[14]=0;
 bytes[15]=2;bytes[16]='h11;bytes[17]=1;
 bytes[18]=3;bytes[19]='h11;bytes[20]=1;
 bytes[21]=255;bytes[22]='hda;bytes[23]=0;bytes[24]=12;
 bytes[25]=3;bytes[26]=1;bytes[27]=0;bytes[28]=2;bytes[29]='h11;
 bytes[30]=3;bytes[31]='h11;bytes[32]=0;bytes[33]='h3f;bytes[34]=0;
 bytes[35]='h11;bytes[36]='hc0;bytes[37]='h22;bytes[38]='h33;
 bytes[39]=255;bytes[40]=0;bytes[41]='h11;bytes[42]=255;bytes[43]='hd9;
 arg_status=$value$plusargs("jpeg_bytes=%d",length);
 if($value$plusargs("jpeg_hex=%s",jpeg_hex)) $readmemh(jpeg_hex,bytes,0,length-1);
 repeat(3) @(negedge clk);rst=0;
 for(pos=0;pos<length;pos=pos+4) begin
  @(negedge clk);
  data=0;strb=0;
  for(lane=0;lane<4;lane=lane+1) if(pos+lane<length) begin
   data[lane*8+:8]=bytes[pos+lane];strb[lane]=1;
  end
  valid=1;last=(pos+4>=length);
  @(posedge clk);while(!accept) @(posedge clk);
  @(negedge clk);valid=0;last=0;
  repeat(12) @(negedge clk);
  if(width===640 && height===480) header_seen=1;
  if(header_seen && (width!==640 || height!==480))
   $fatal(1,"input gap corrupted dimensions after word byte %0d: width=%h height=%h",pos,width,height);
 end
 if(!header_seen) $fatal(1,"JPEG dimensions never captured");
 $display("PASS: JPEG dimensions survive SRAM input gaps and FF-stuffed word rollover");$finish;
end
initial begin #10000000;$fatal(1,"gap test timeout");end
endmodule
