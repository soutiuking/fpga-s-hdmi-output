"""Exercise the production HDMI completion CDC with inert peripheral shells.

The bundled Icarus predates -i (ignore missing modules). Generate named-port
shells explicitly; only reset_control and the actual HDMI CDC are exercised.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
tf = root / 'user_source/hdl_source/tfmedia3'
exe = Path(sys.argv[1]).resolve()
source = (tf / 'tfmedia3_hdmi_shell.v').read_text()
names = ['frame_present_cdc', 'video_pll', 'PLL_HDMI_AUDIO', 'video_timing_data',
         'video_delay', 'frame_read_write', 'sdram', 'pcm_i2s_64fs', 'I2S_receiver',
         'audio_arc_calculate', 'startup_pulse', 'hdmi_1_4b_transmitter_core_wrapper',
         'hdmi_phy_wrapper']
with tempfile.TemporaryDirectory(prefix='tfmedia3-hdmi-cdc-') as temp:
    work = Path(temp)
    stubs = []
    for name in names:
        inst = re.search(r'(?m)^' + name + r'\s*(?:#\(([\s\S]*?)\)\s*)?\w+\s*\(([\s\S]*?)\);', source)
        assert inst, name
        params = re.findall(r'\.(\w+)\s*\(', inst[1] or '')
        ports = re.findall(r'\.(\w+)\s*\(', inst[2])
        param = (' #(' + ','.join('parameter ' + p + '=0' for p in params) + ')') if params else ''
        stubs.append('module ' + name + param + '(' + ','.join('input ' + p for p in ports) + '); endmodule')
    (work / 'stubs.v').write_text('\n'.join(stubs))
    target = work / 'frame_finish.vvp'
    compiled = subprocess.run([str(exe), '-g2012', '-s', 'tb_frame_finish_cdc', '-o', str(target),
        str(root / 'sim/tb_frame_finish_cdc.v'), str(tf / 'tfmedia3_hdmi_shell.v'),
        str(tf / 'reset_control.v'), str(tf / 'volume_bar_overlay.v'),
        str(tf / 'scroll_text_overlay.v'), str(tf / 'scroll_text_font.v'),
        str(tf / 'audio_wave_overlay.v'),
        str(root / 'user_source/hdl_source/video_rgb_to_axis_640x480.v'), str(work / 'stubs.v')],
        capture_output=True, text=True)
    # Scalar inert-shell ports deliberately cause width warnings.
    if compiled.returncode:
        raise AssertionError(compiled.stdout + compiled.stderr)
    result = subprocess.run([str(exe.with_name('vvp.exe' if sys.platform == 'win32' else 'vvp')), str(target)],
                            capture_output=True, text=True)
    print(result.stdout, end='')
    if result.returncode or 'PASS:' not in result.stdout or any(s in result.stdout for s in ('FATAL:', 'FAIL', 'ERROR:')):
        raise AssertionError(result.stdout + result.stderr)
