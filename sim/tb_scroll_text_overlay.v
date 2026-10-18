`timescale 1ns/1ps
module tb_scroll_text_overlay;
reg clk=0,rst=1,vs=0,de=0,enable=0,picture=1;
reg [23:0] rgb=24'h406080;
wire ov,od;
wire [23:0] pixel;
always #5 clk=~clk;
scroll_text_overlay #(.SCROLL_STEP(256)) dut(
    .clk(clk),.rst(rst),.enable_async(enable),.picture_async(picture),
    .vs_in(vs),.de_in(de),.rgb_in(rgb),.vs_out(ov),.de_out(od),.rgb_out(pixel));
wire sof,valid,eol;
wire [23:0] axis_rgb;
video_rgb_to_axis_640x480 axis(.I_clk(clk),.I_rst(rst),.I_vs(ov),.I_de(od),.I_rgb(pixel),
    .O_video_user(sof),.O_video_valid(valid),.O_video_last(eol),.O_video_data(axis_rgb));
integer pixels=0,lines=0,frames=0;
reg checking=0;
always @(negedge clk) if(checking && valid) begin
    pixels=pixels+1;
    if(sof) begin
        if(pixels!=1 || lines%480!=0) $fatal(1,"text SOF");
        frames=frames+1;
    end
    if(eol) begin
        if(pixels!=640) $fatal(1,"text EOL");
        pixels=0;lines=lines+1;
    end
end
task blank;
    begin
        @(negedge clk);de=0;vs=1;
        repeat(5) @(negedge clk);vs=0;
        repeat(5) @(negedge clk);
    end
endtask
task tick;
    begin
        blank;de=1;@(negedge clk);de=0;
        repeat(4) @(negedge clk);
    end
endtask
integer x,y,lit,count_lit,fh=0;
reg [1023:0] path;
reg [23:0] original;
integer glyph_cell, palette_index, colored_lit;
reg [23:0] glyph_color;
reg [6:0] color_before;
function [23:0] reference_color;
    input integer index;
    begin
        case(index%8)
            0: reference_color=24'hFDE68A;
            1: reference_color=24'hFDBA74;
            2: reference_color=24'hFDA4AF;
            3: reference_color=24'hF0ABFC;
            4: reference_color=24'hC4B5FD;
            5: reference_color=24'h93C5FD;
            6: reference_color=24'h67E8F9;
            7: reference_color=24'h6EE7B7;
        endcase
    end
endfunction
task scan;
    input on;
    input integer expected_phase;
    input capture;
    begin
        blank;checking=1;count_lit=0;colored_lit=0;
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) begin
                @(negedge clk);de=1;original={x[8:1],y[8:1],8'd128};rgb=original;
                @(posedge clk);#1;
                if(!od || ov) $fatal(1,"text sync latency");
                if(dut.phase!=expected_phase || dut.frame_enable!==on) $fatal(1,"text phase/enable");
                glyph_cell=(((x+expected_phase+384)%1024)/32);
                palette_index=(dut.color_phase/16)+glyph_cell;
                glyph_color=((glyph_cell>=4 && glyph_cell<=7) || (glyph_cell>=9 && glyph_cell<=11)) ?
                    reference_color(palette_index) : 24'hFDE68A;
                if(!on || y<12 || y>=60) begin
                    if(pixel!==original) $fatal(1,"text modified image outside band");
                end else if(pixel==glyph_color) begin
                    count_lit=count_lit+1;
                    if(glyph_color!=24'hFDE68A) colored_lit=colored_lit+1;
                end
                else if(pixel!=={1'b0,original[23:17],1'b0,original[15:9],1'b0,original[7:1]})
                    $fatal(1,"text panel mismatch");
                if(capture && fh) $fwrite(fh,"%06x\n",pixel);
            end
            @(negedge clk);de=0;repeat(5) @(negedge clk);
        end
        repeat(5) @(negedge clk);checking=0;
        if(on && expected_phase==512 && count_lit<1000) $fatal(1,"missing text bitmap");
        if(on && expected_phase==512 && colored_lit<500) $fatal(1,"missing multicolor Chinese glyphs");
    end
endtask
initial begin
    if($value$plusargs("capture=%s",path)) fh=$fopen(path,"w");
    repeat(5) @(negedge clk);rst=0;
    scan(0,0,0);
    enable=1;tick; // Starts outside right edge at phase zero.
    if(dut.phase!=0 || !dut.frame_enable) $fatal(1,"text start");
    tick;if(dut.phase!=256) $fatal(1,"scroll step");
    scan(1,512,1); // Phrase fully visible, starts at x=128.
    color_before=dut.color_phase;
    repeat(16) tick;
    if(dut.color_phase!=color_before+16 || dut.phase!=512)
        $fatal(1,"Chinese color animation did not advance with display frames");
    scan(1,768,0); // Check the new colors after the palette time step.
    // Setting changes during a frame must wait for its boundary.
    enable=0;repeat(5) @(negedge clk);
    if(!dut.frame_enable || dut.phase!=768) $fatal(1,"text mid-frame tear");
    color_before=dut.color_phase;
    repeat(5) @(negedge clk);
    if(dut.color_phase!=color_before) $fatal(1,"color changed inside a frame");
    scan(0,0,0);
    enable=1;picture=0;tick;
    if(dut.frame_enable) $fatal(1,"video must suppress picture marquee");
    picture=1;tick;
    if(!dut.frame_enable || dut.phase!=0) $fatal(1,"picture reentry did not restart");
    tick;tick;tick;tick;
    if(dut.phase!=0) $fatal(1,"marquee wrap");
    if(lines!=1920 || frames!=4 || pixels!=0) $fatal(1,"text AXI geometry");
    if(fh) $fclose(fh);
    $display("PASS: media marquee, changing Chinese colors, gold Latin/punctuation, frame-held color/position, scroll/wrap/restart and 4 full 640x480 AXI frames");
    $finish;
end
initial begin #30000000;$fatal(1,"text test timeout");end
endmodule
