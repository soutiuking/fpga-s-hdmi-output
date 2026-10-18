`timescale 1ns/1ps
module tb_contrast_gain;
reg clk=0, rst=1, vs=0, de=0;
reg [4:0] gray=12;
reg [23:0] rgb=0;
wire out_vs, out_de;
wire [23:0] result;
always #5 clk=~clk;
video_contrast_stage dut(.clk(clk),.rst(rst),.contrast_gray_async(gray),
    .vs_in(vs),.de_in(de),.rgb_in(rgb),.vs_out(out_vs),.de_out(out_de),.rgb_out(result));
function [7:0] reference;
    input integer channel, level;
    integer adjusted;
    begin
        adjusted=128+(((channel-128)*level) >>> 3);
        reference=adjusted<0 ? 0 : adjusted>255 ? 255 : adjusted;
    end
endfunction
integer level, value;
reg [23:0] expected;
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(level=0;level<=16;level=level+1) begin
        gray=level^(level>>1); vs=1; de=0;
        repeat(5) @(negedge clk); vs=0;
        repeat(5) @(negedge clk);
        for(value=0;value<256;value=value+1) begin
            rgb={value[7:0],8'd255-value[7:0],value[6:0],1'b0}; de=1;
            expected={reference(value,level),reference(255-value,level),reference((value%128)*2,level)};
            @(posedge clk); #1;
            if(result!==expected || !out_de || out_vs)
                $fatal(1,"contrast level=%d value=%d got=%h expected=%h",level,value,result,expected);
            @(negedge clk);
        end
        // Settings must remain fixed for the rest of this frame.
        gray=0; repeat(5) @(negedge clk);
        @(posedge clk); #1;
        if(result!==expected) $fatal(1,"contrast tore within a frame");
        @(negedge clk);
    end
    $display("PASS: all 17 contrast levels x 256 RGB inputs, saturation, unity, first pixel and frame-held settings");
    $finish;
end
endmodule
