"""Generate two real card images and exercise the complete storage retry path."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import media_card


def main():
    exe=Path(sys.argv[1]).resolve()
    tf=ROOT/'user_source/hdl_source/tfmedia3'
    with tempfile.TemporaryDirectory(prefix='tf-hotplug-') as folder:
        work=Path(folder)
        image=work/'source.png';Image.new('RGB',(640,480),'blue').save(image)
        config=work/'subtitles.json'
        config.write_text(json.dumps({'subtitles':[{'text':'First card'},{'text':'Second subtitle','rainbow':True}]}),encoding='utf-8')
        for name,extra in [('first',['--subtitles',str(config)]),('second',[])]:
            subprocess.run([sys.executable,str(ROOT/'tools/media_card.py'),'pack',str(image),'-o',str(work/(name+'.img')),*extra],check=True,capture_output=True)
            media_card.inspect(work/(name+'.img'))
        sources=[tf/n for n in ['reset_control.v','tfmedia3_reader_frontend.v','button_debounce_pulse.v','subtitle_loader.v',
            'tfmedia3_catalog.v','tfmedia3_metadata.v','sd_sector_arbiter4.v','jpeg_sram_dma.v','pcm_audio_buffer.v']]
        sources += [ROOT/'user_source/hdl_source/memory'/n for n in ['sram_arbiter2.v','async_sram16_controller.v']]
        sources += [ROOT/'sim/subtitle_bram_model.v',ROOT/'sim/tb_storage_hotplug.v']
        target=work/'hotplug.vvp'
        subprocess.run([str(exe),'-g2012','-s','tb_storage_hotplug','-o',str(target),*map(str,sources)],check=True)
        result=subprocess.run([str(exe.with_name('vvp.exe')),str(target),'+first='+str(work/'first.img'),'+second='+str(work/'second.img')],check=True,capture_output=True,text=True)
        print(result.stdout,end='',flush=True)
        assert 'PASS:' in result.stdout and not any(s in result.stdout for s in ('FATAL:','ERROR:','FAIL'))


if __name__=='__main__':main()
