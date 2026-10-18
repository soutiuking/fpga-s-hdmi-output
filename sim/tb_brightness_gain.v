`timescale 1ns/1ps
module tb_brightness_gain;
reg clk=0, rst=1, vs=0, de=0;
reg [4:0] gray=24;
reg [23:0] rgb=0;
wire [23:0] result;
always #5 clk=~clk;
volume_bar_overlay dut(.clk(clk),.rst(rst),.enable_async(1'b0),
    .volume_gray_async(5'd24),.brightness_enable_async(1'b0),
    .brightness_gray_async(gray),.vs_in(vs),.de_in(de),.rgb_in(rgb),
    .contrast_enable_async(1'b0), .contrast_gray_async(5'd12),
    .vs_out(),.de_out(),.rgb_out(result));
integer level, value;
reg [7:0] red, green, blue;
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(level=0;level<=16;level=level+1) begin
        gray=level^(level>>1); vs=1; de=0;
        repeat(5) @(negedge clk); vs=0;
        repeat(5) @(negedge clk);
        for(value=0;value<256;value=value+1) begin
            rgb={value[7:0],8'd255-value[7:0],value[6:0],1'b0}; de=1;
            red=value*level/16;
            green=(255-value)*level/16;
            blue=((value%128)*2)*level/16;
            @(posedge clk); #1;
            if(result!=={red,green,blue})
                $fatal(1,"RGB gain at level %d value %d got %h expected %h",level,value,result,{red,green,blue});
            @(negedge clk);
        end
    end
    $display("PASS: all 17 brightness levels and 256 RGB input values, including first pixel after gain changes");
    $finish;
end
endmodule
