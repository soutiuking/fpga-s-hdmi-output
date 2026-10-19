`timescale 1ns/1ps
module tb_player_volume_control;
reg clk=0, rst=1, sw=1, up=1, down=1, ack=0;
reg sw1=1;
reg sw2=1;
reg subtitle_mode=0;wire subtitle_next,subtitle_prev;
integer subtitle_next_count=0,subtitle_prev_count=0;
always @(posedge clk)begin
 if(subtitle_next)subtitle_next_count=subtitle_next_count+1;
 if(subtitle_prev)subtitle_prev_count=subtitle_prev_count+1;
end
wire contrast_mode;
wire [4:0] contrast;
wire bright_mode;
wire [4:0] brightness;
reg [15:0] pcm=0;
wire out_ack, next_n, pause_n, mode;
wire [15:0] out_pcm;
wire [4:0] volume;
always #5 clk=~clk;
player_volume_control #(.STABLE_CLKS(4)) dut (
    .clk(clk), .rst(rst), .sw0_n(sw), .sw1_n(sw1), .key_up_n(up), .key_down_n(down),
    .brightness_mode(bright_mode), .brightness(brightness),
    .sw2_n(sw2), .contrast_mode(contrast_mode), .contrast(contrast),
    .subtitle_mode(subtitle_mode),.subtitle_next(subtitle_next),.subtitle_prev(subtitle_prev),
    .sample_ack_in(ack), .sample_in(pcm), .sample_ack_out(out_ack),
    .sample_out(out_pcm), .next_key_n(next_n), .pause_key_n(pause_n),
    .volume_mode(mode), .volume(volume));
task settle; begin repeat(12) @(negedge clk); end endtask
task quieter; begin down=0; settle; down=1; settle; end endtask
task louder; begin up=0; settle; up=1; settle; end endtask
task sample;
    input integer value;
    integer expected;
    begin
        pcm=value; ack=~ack;
        expected=value*$signed({1'b0,volume});
        expected=expected >>> 4;
        repeat(3) @(negedge clk);
        if(out_ack!==ack || $signed(out_pcm)!==expected)
            $fatal(1,"PCM gain/sign/ack failed: level=%d value=%d actual=%d expected=%d",volume,value,$signed(out_pcm),expected);
        pcm=16'h1234; // changing the mailbox without ACK must not affect output
        repeat(3) @(negedge clk);
        if($signed(out_pcm)!==expected) $fatal(1,"output changed without ACK");
    end
endtask
integer level, i;
initial begin
    settle; rst=0; settle;
    if(volume!=16 || mode) $fatal(1,"reset defaults");
    up=0; settle;
    if(next_n || !pause_n || volume!=16) $fatal(1,"normal S0 routing");
    up=1; settle; down=0; settle;
    if(pause_n || !next_n) $fatal(1,"normal S1 routing");
    down=1; settle;
    // Short SW bounce must not enter settings.
    sw=0; @(negedge clk); sw=1; settle;
    if(mode) $fatal(1,"switch bounce");
    sw=0; settle;
    for(level=16;level>=0;level=level-1) begin
        if(volume!=level) $fatal(1,"volume decrement");
        sample(32767); sample(-32768); sample(12345); sample(-12345); sample(0);
        if(!next_n || !pause_n) $fatal(1,"volume key leaked into player");
        quieter;
    end
    if(volume!=0) $fatal(1,"minimum wrapped");
    for(i=0;i<20;i=i+1) louder;
    if(volume!=16) $fatal(1,"maximum wrapped");
    up=0; down=0; settle;
    if(volume!=16) $fatal(1,"simultaneous keys changed volume");
    up=1; down=1; settle;
    // A held button acts once, and must be released across mode changes.
    down=0; settle; settle;
    if(volume!=15) $fatal(1,"held button repeated");
    sw=1; settle;
    if(!pause_n || !next_n || volume!=15) $fatal(1,"exit settings leaked held key or lost volume");
    sample(-32768);
    down=1; settle; down=0; settle;
    if(pause_n || volume!=15) $fatal(1,"normal keys did not resume");
    // Enter settings while holding a key: require release before adjusting.
    sw=0; settle;
    if(volume!=15) $fatal(1,"entry held key changed volume");
    down=1; settle; quieter;
    if(volume!=14) $fatal(1,"settings did not rearm");
    sw=1; settle; sw=0; settle;
    if(volume!=14) $fatal(1,"mode change lost saved volume");
    sw=1; sw1=0; settle;
    if(!bright_mode || mode || brightness!=16) $fatal(1,"SW1 mode/default");
    for(i=0;i<20;i=i+1) quieter;
    if(brightness!=0 || volume!=14 || !pause_n || !next_n) $fatal(1,"brightness minimum or key isolation");
    for(i=0;i<20;i=i+1) louder;
    if(brightness!=16) $fatal(1,"brightness maximum");
    quieter;
    sw1=1; settle;
    if(bright_mode || brightness!=15) $fatal(1,"brightness not retained on exit");
    sw=0; sw1=0; settle;
    if(!mode || bright_mode) $fatal(1,"SW0 priority");
    quieter;
    if(volume!=13 || brightness!=15) $fatal(1,"simultaneous switches changed wrong setting");
    down=0; settle; sw=1; settle;
    if(!bright_mode || brightness!=15 || !pause_n) $fatal(1,"held key leaked across settings");
    down=1; settle; quieter;
    if(brightness!=14) $fatal(1,"brightness did not rearm");
    sw=1; sw1=1; sw2=0; settle;
    if(!contrast_mode || contrast!=8) $fatal(1,"SW2 mode/default");
    for(i=0;i<20;i=i+1) louder;
    if(contrast!=16 || brightness!=14 || volume!=12) $fatal(1,"contrast maximum/independence");
    for(i=0;i<20;i=i+1) quieter;
    if(contrast!=0 || !pause_n || !next_n) $fatal(1,"contrast minimum/isolation");
    louder; sw2=1; settle;
    if(contrast_mode || contrast!=1) $fatal(1,"contrast retention");
    sw1=0; sw2=0; settle;
    if(contrast_mode || !bright_mode) $fatal(1,"brightness priority over contrast");
    down=0; settle; sw1=1; settle;
    if(!contrast_mode || contrast!=1) $fatal(1,"held key crossed into contrast");
    down=1; settle; louder;
    if(contrast!=2) $fatal(1,"contrast rearm");
    rst=1; settle; rst=0; settle;
    if(contrast!=8) $fatal(1,"contrast reset default");
    if(brightness!=16) $fatal(1,"brightness reset");
    if(volume!=16) $fatal(1,"reset failed");
    sw=1;sw1=1;sw2=1;up=1;down=1;settle;
    subtitle_mode=1;settle;louder;quieter;
    if(subtitle_next_count!=1 || subtitle_prev_count!=1 || !next_n || !pause_n)
        $fatal(1,"subtitle keys did not isolate next-media/pause");
    up=0;settle;settle;
    if(subtitle_next_count!=2)$fatal(1,"subtitle held key repeated");
    subtitle_mode=0;settle;if(!next_n)$fatal(1,"held subtitle key leaked on exit");
    up=1;settle;up=0;settle;if(next_n)$fatal(1,"normal next key did not rearm");
    subtitle_mode=1;settle;up=1;settle;sw=0;settle;quieter;
    if(volume!=15 || subtitle_prev_count!=1)$fatal(1,"volume priority over subtitle keys");
    $display("PASS: subtitle S0/S1 debounce, held-key release, normal-key isolation and SW0 priority");
    $display("PASS: volume mode, debounce, key isolation, retention, bounds and signed PCM gain at all 17 levels");
    $finish;
end
initial begin #1000000; $fatal(1,"volume test timed out"); end
endmodule
