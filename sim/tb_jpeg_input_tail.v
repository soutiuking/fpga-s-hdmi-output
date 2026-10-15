`timescale 1ns/1ps
// A legal SOS byte stream, with EOI at each possible 32-bit word alignment.
// Check the real parser emits EOI before acknowledging the final input word.
module tb_jpeg_input_tail;
reg clk=0;
always #5 clk=~clk;
reg rst=1, valid=0, last=0;
reg [31:0] data=0;
reg [3:0] strb=0;
wire accept, entropy_valid, entropy_last;
wire [7:0] entropy_data;
reg data_accept=1;
integer endings=0, words=0, length, pos, lane, tail, stalls=0;
reg [7:0] bytes [0:31];
jpeg_input dut(.clk_i(clk), .rst_i(rst), .inport_valid_i(valid),
    .inport_data_i(data), .inport_strb_i(strb), .inport_last_i(last),
    .dqt_cfg_accept_i(1'b1), .dht_cfg_accept_i(1'b1), .data_accept_i(data_accept),
    .inport_accept_o(accept), .img_start_o(), .img_end_o(),
    .img_width_o(), .img_height_o(), .img_mode_o(),
    .img_dqt_table_y_o(), .img_dqt_table_cb_o(), .img_dqt_table_cr_o(),
    .dqt_cfg_valid_o(), .dqt_cfg_data_o(), .dqt_cfg_last_o(),
    .dht_cfg_valid_o(), .dht_cfg_data_o(), .dht_cfg_last_o(),
    .data_valid_o(entropy_valid), .data_data_o(entropy_data), .data_last_o(entropy_last));
always @(posedge clk) begin
    if (!rst) begin
        if (valid && entropy_last && data_accept) endings=endings+1;
        if (valid && accept) words=words+1;
    end
end
initial begin
    bytes[0]=8'hff; bytes[1]=8'hd8; bytes[2]=8'hff; bytes[3]=8'hda;
    bytes[4]=0; bytes[5]=8;
    bytes[6]=1; bytes[7]=1; bytes[8]=0; bytes[9]=0; bytes[10]=8'h3f; bytes[11]=0;
    for(tail=0;tail<4;tail=tail+1) begin
        length=16+tail;
        for(pos=12;pos<length-2;pos=pos+1) bytes[pos]=8'h11;
        bytes[length-2]=8'hff; bytes[length-1]=8'hd9;
        @(negedge clk); rst=1; valid=0; last=0; endings=0; words=0;
        repeat(3) @(negedge clk);
        rst=0;
        for(pos=0;pos<length;pos=pos+4) begin
            @(negedge clk);
            data=0; strb=0;
            for(lane=0;lane<4;lane=lane+1)
                if(pos+lane<length) begin
                    data[lane*8+:8]=bytes[pos+lane]; strb[lane]=1;
                end
            valid=1; last=(pos+4>=length);
            @(posedge clk);
            while(!accept) @(posedge clk);
            @(negedge clk); valid=0; last=0;
        end
        repeat(4) @(negedge clk);
        if(endings!=1 || words!=(length+3)/4 || dut.byte_idx_q!==0)
            $fatal(1,"EOI lost for size %% 4=%0d: endings=%0d words=%0d byteidx=%0d",
                      tail,endings,words,dut.byte_idx_q);
    end
    $display("PASS: JPEG EOI consumed for all four final-word byte alignments");
    $finish;
end
initial begin #100000; $fatal(1,"parser tail test timeout"); end
endmodule
