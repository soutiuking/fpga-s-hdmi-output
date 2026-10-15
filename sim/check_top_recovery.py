"""Fault-inject the real top/pipeline to test next-media timeout recovery.

Clock, storage and HDMI wrappers are replaced by inert shells; the actual top
level wiring and registered recovery reset remain under test.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import sys

root=Path(__file__).resolve().parents[1]
tf=root/'user_source/hdl_source/tfmedia3'
exe=Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='tfmedia3-recovery-') as temp:
    work=Path(temp)
    shells=[]
    for name in ['tfmedia3_reader_frontend','tfmedia3_hdmi_shell']:
        source=(tf/(name+'.v')).read_text()
        header=re.search(r'\bmodule\s+'+name+r'\b[\s\S]*?\);',source).group()
        header=re.sub(r'\breg\b','wire',header)
        outputs=re.findall(r'output\s+(?:(?:wire|reg)\s+)?(?:\[[^\]]+\]\s*)?(\w+)',header)
        shells.append(header+'\n'+''.join(f'assign {port}=0;\n' for port in outputs)+'endmodule\n')
    shells.append('''module sys_pll(input refclk,reset, output clk0_out,clk1_out,clk2_out,clk3_out);
assign {clk0_out,clk1_out,clk2_out,clk3_out}={4{refclk}}; endmodule
''')
    (work/'shells.v').write_text('\n'.join(shells))
    (work/'recovery.v').write_text('''`timescale 1ns/1ps
module tb_top_recovery;
reg clk=0,reset_n=0,inject_cached=0,inject_change=0;
reg inject_done=0,inject_pause=0;
reg [31:0] inject_playhead=0,inject_frame=0;
integer commits=0;
wire injected_reset=~reset_n;
always #5 clk=~clk;
always @(posedge clk) if(dut.presentation_submit) commits=commits+1;
tfmedia3_top dut(.clk(clk),.key_reset_n(reset_n),.key_s1_n(1'b1),.key_s2_n(1'b1),.sd_miso(1'b1));
defparam dut.u_decode.DECODE_TIMEOUT_CLKS=120;
integer retries;
initial begin
 force dut.frame_cached=inject_cached;
 force dut.cached_bytes=17'd12;
 force dut.cached_slot=1'b0;
 force dut.media_changing=inject_change;
 force dut.frame_write_req_ack=dut.frame_write_req;
 force dut.board_rst=injected_reset;
 force dut.decode_sram_read_data=16'hd8ff;
 force dut.decode_sram_ready=dut.decode_sram_request;
 dut.u_decode.u_jpeg_core.accept_input=1;
 #21 reset_n=1;
 repeat(8) @(negedge clk);
 for(retries=0;retries<2;retries=retries+1) begin
   if(!dut.decode_ready) $fatal(1,"decoder not ready for a new media");
   inject_cached=1;
   @(negedge clk); inject_cached=0;
 wait(dut.decode_error==8'h34);
   repeat(8) @(negedge clk);
   if(dut.decode_ready) $fatal(1,"error was cleared without switch request");
   inject_change=1;
   repeat(8) @(negedge clk);
   inject_change=0;
   repeat(4) @(negedge clk);
   if(dut.decode_error!=0 || !dut.reader_decode_ready)
       $fatal(1,"next-media request failed to reset stalled decoder");
 end
 $display("PASS: actual top clears stalled JPEG on media change and accepts subsequent media twice");
 force dut.decode_ready=1'b1;
 force dut.decode_error=8'd0;
 force dut.decode_done=inject_done;
 force dut.decoded_slot=1'b1;
 force dut.media_type=8'd2;
 force dut.timeline_active=1'b1;
 force dut.playback_frame_number=inject_playhead;
 force dut.cached_frame_number=inject_frame;
 force dut.player_paused=inject_pause;
 force dut.presentation_busy=1'b0;
 @(negedge clk);inject_playhead=3;inject_frame=7;inject_cached=1;
 @(negedge clk);inject_cached=0;
 repeat(3) @(negedge clk);
 inject_done=1;@(negedge clk);inject_done=0;
 repeat(10) @(negedge clk);
 if(commits!=0 || !dut.decoded_pending) $fatal(1,"future video frame was presented before its PCM deadline");
 inject_pause=1;inject_playhead=7;
 repeat(8) @(negedge clk);
 if(commits!=0) $fatal(1,"video page changed while paused");
 inject_pause=0;
 repeat(8) @(negedge clk);
 if(commits!=1 || !dut.display_valid || !dut.display_slot)
     $fatal(1,"due frame did not submit exactly once");
 inject_frame=8;inject_cached=1;
 @(negedge clk);inject_cached=0;
 repeat(2) @(negedge clk);inject_done=1;
 @(negedge clk);inject_done=0;
 repeat(4) @(negedge clk);inject_change=1;
 repeat(3) @(negedge clk);inject_change=0;inject_playhead=9;
 repeat(8) @(negedge clk);
 if(commits!=1 || dut.display_valid) $fatal(1,"media switch leaked a pending previous frame");
 $display("PASS: actual top holds future frames until PCM playhead, respects pause and clears pending pages on media switch");
 $finish;
end
initial begin #100000; $fatal(1,"top recovery hung"); end
endmodule
''')
    target=work/'recovery.vvp'
    subprocess.run([str(exe),'-g2012','-s','tb_top_recovery','-o',str(target),
                    str(work/'shells.v'),str(work/'recovery.v'),
                    str(root/'sim/tb_jpeg_timeout_debug.v'),str(tf/'tfmedia3_top.v'),
                    str(tf/'jpeg_decode_pipeline.v'),str(tf/'seg7_serial_8digit.v'),
                    str(tf/'reset_control.v')],check=True)
    result=subprocess.run([str(exe.with_name('vvp.exe')),str(target)],check=True,text=True,capture_output=True)
    print(result.stdout,end='')
    if 'PASS:' not in result.stdout or any(s in result.stdout for s in ('FATAL:','FAIL','ERROR:')):
        raise AssertionError(result.stdout+result.stderr)
