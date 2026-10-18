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
reg [7:0] switches=8'hff;
reg volume_up_n=1,volume_down_n=1,pcm_ack=0;
reg [15:0] pcm_data=0;
reg [31:0] inject_playhead=0,inject_frame=0;
integer commits=0;
wire injected_reset=~reset_n;
always #5 clk=~clk;
always @(posedge clk) if(dut.presentation_submit) commits=commits+1;
tfmedia3_top dut(.clk(clk),.key_reset_n(reset_n),.key_s1_n(volume_up_n),.key_s2_n(volume_down_n),.sw_n(switches),.sd_miso(1'b1));
defparam dut.u_decode.DECODE_TIMEOUT_CLKS=120;
defparam dut.u_volume.STABLE_CLKS=4;
defparam dut.u_scroll_switch.STABLE_CLKS=4;
defparam dut.u_wave_switch.STABLE_CLKS=4;
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
 force dut.audio_raw_ack=pcm_ack;
 force dut.audio_raw_data=pcm_data;
 switches=8'hfe;
 repeat(12) @(negedge clk);
 volume_down_n=0;
 repeat(12) @(negedge clk);
 if(dut.volume!=15 || !dut.u_reader.key_s2_n ||
    dut.u_hdmi_shell.volume_setting!==1'b1 || dut.u_hdmi_shell.volume_level!==5'd15)
     $fatal(1,"top did not route S1 to volume exclusively");
 volume_down_n=1;
 repeat(12) @(negedge clk);
 switches=8'hff;
 repeat(12) @(negedge clk);
 inject_change=1;
 repeat(8) @(negedge clk);
 inject_change=0;
 pcm_data=-16384;pcm_ack=1;
 repeat(8) @(negedge clk);
 if(dut.volume!=15 || dut.audio_sample_data!==16'hc400 || dut.audio_sample_ack_toggle!==1'b1)
     $fatal(1,"top lost gain on exit/media change or forwarded wrong PCM mailbox");
 switches=8'hef;
 repeat(12) @(negedge clk);
 if(!dut.wave_setting || dut.u_hdmi_shell.wave_setting!==1'b1 || dut.volume_mode)
     $fatal(1,"SW4 waveform wiring/independence failed");
 switches=8'hff; repeat(12) @(negedge clk);
 if(dut.wave_setting) $fatal(1,"SW4 did not disable waveform");
 switches=8'h1f; // Reserved SW5..SW7 must not alter volume or mode.
 repeat(12) @(negedge clk);
 if(dut.volume_mode || dut.volume!=15) $fatal(1,"reserved switches affected SW0 function");
 switches=8'hfd;
 repeat(12) @(negedge clk);
 volume_down_n=0;
 repeat(12) @(negedge clk);
 if(!dut.brightness_mode || dut.brightness!=15 || dut.volume!=15 ||
    !dut.u_reader.key_s2_n || dut.u_hdmi_shell.brightness_setting!==1'b1 ||
    dut.u_hdmi_shell.brightness_level!==5'd15)
     $fatal(1,"SW1 brightness mode/wiring/key isolation failed");
 volume_down_n=1;
 switches=8'hff;
 repeat(12) @(negedge clk);
 inject_change=1; repeat(8) @(negedge clk); inject_change=0;
 if(dut.brightness!=15) $fatal(1,"media change lost brightness");
 switches=8'hfb; repeat(12) @(negedge clk);
 volume_up_n=0; repeat(12) @(negedge clk);
 if(!dut.contrast_mode || dut.contrast!=9 || !dut.u_reader.key_s1_n ||
    dut.u_hdmi_shell.contrast_level!==5'd9 || dut.u_hdmi_shell.contrast_setting!==1'b1)
     $fatal(1,"SW2 contrast wiring/isolation failed");
 volume_up_n=1; switches=8'hff; repeat(12) @(negedge clk);
 inject_change=1; repeat(8) @(negedge clk); inject_change=0;
 if(dut.contrast!=9) $fatal(1,"media change lost contrast");
 switches=8'hf7;
 force dut.display_valid=1'b1;
 force dut.media_type=8'd1;
 repeat(12) @(negedge clk);
 if(!dut.scroll_setting || dut.u_hdmi_shell.scroll_setting!==1'b1 ||
    dut.u_hdmi_shell.picture_playing!==1'b1)
     $fatal(1,"SW3 picture marquee wiring failed");
 volume_up_n=0; repeat(12) @(negedge clk);
 if(dut.u_reader.key_s1_n!==1'b0) $fatal(1,"SW3 stole normal next-media key");
 volume_up_n=1;
 force dut.media_type=8'd2;
 repeat(12) @(negedge clk);
 if(!dut.picture_playing || dut.u_hdmi_shell.picture_playing!==1'b1)
     $fatal(1,"video failed to enable marquee");
 force dut.media_type=8'd0;
 repeat(12) @(negedge clk);
 if(dut.picture_playing) $fatal(1,"unsupported media enabled text");
 force dut.media_type=8'd1; inject_change=1;
 repeat(12) @(negedge clk);
 if(dut.picture_playing) $fatal(1,"media transition enabled text");
 inject_change=0; switches=8'hff;
 repeat(12) @(negedge clk);
 if(dut.scroll_setting) $fatal(1,"SW3 OFF did not disable marquee");
 inject_pause=1;
 force dut.player_paused=inject_pause;
 repeat(8) @(negedge clk);
 if(dut.u_hdmi_shell.pause_status!==2'd2 || dut.u_hdmi_shell.display_picture!==1'b1)
     $fatal(1,"picture stopped status missing");
 force dut.media_type=8'd2;repeat(8) @(negedge clk);
 if(dut.u_hdmi_shell.pause_status!==2'd1 || dut.u_hdmi_shell.display_picture!==1'b0)
     $fatal(1,"video pause status/type wiring failed");
 inject_pause=0;repeat(8) @(negedge clk);
 if(dut.u_hdmi_shell.pause_status!==0) $fatal(1,"pause status remained after resume");
 inject_pause=1;inject_change=1;repeat(8) @(negedge clk);
 if(dut.u_hdmi_shell.pause_status!==0) $fatal(1,"pause status shown during media change");
 $display("PASS: picture/video pause status classification, resume and media-change gating");
 $display("PASS: SW3 independent marquee on pictures AND videos, transition/invalid-media gating and normal key passthrough");
 $display("PASS: SW4 independently enables/disables waveform through the actual top and HDMI shell");
 $display("PASS: actual top isolates volume keys, retains gain across media changes and forwards scaled PCM/ACK");
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
                    str(tf/'reset_control.v'),str(tf/'player_volume_control.v'),
                    str(tf/'button_debounce_pulse.v')],check=True)
    result=subprocess.run([str(exe.with_name('vvp.exe')),str(target)],check=True,text=True,capture_output=True)
    print(result.stdout,end='')
    if 'PASS:' not in result.stdout or any(s in result.stdout for s in ('FATAL:','FAIL','ERROR:')):
        raise AssertionError(result.stdout+result.stderr)
