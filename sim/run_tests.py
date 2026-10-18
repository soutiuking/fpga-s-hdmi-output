"""Run real RTL tests with Icarus; optional --quick skips full JPEG decode."""
from pathlib import Path
import argparse
import importlib.util
import shutil
import subprocess
import sys
import tempfile
import struct

ROOT=Path(__file__).resolve().parents[1]
HDL=ROOT/'user_source/hdl_source'
SIM=ROOT/'sim'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--iverilog',default=shutil.which('iverilog'))
    parser.add_argument('--quick',action='store_true')
    args=parser.parse_args()
    if not args.iverilog: parser.error('Icarus missing; pass --iverilog PATH')
    exe=Path(args.iverilog).resolve()
    vvp=exe.with_name('vvp.exe' if sys.platform=='win32' else 'vvp')
    spec=importlib.util.spec_from_file_location('card',ROOT/'tools/media_card.py')
    sys.path.insert(0,str(ROOT/'tools'))
    card=importlib.util.module_from_spec(spec);spec.loader.exec_module(card)
    from PIL import Image
    import io
    # The fixed-table decoder must reject legal JPEGs encoded with custom
    # Huffman tables, and streams requiring unsupported restart handling.
    probe=Image.new('RGB',(640,480),'blue')
    encoded=io.BytesIO();probe.save(encoded,'JPEG',subsampling=2,optimize=True)
    try: card.jpeg_check(encoded.getvalue())
    except ValueError as error:
        assert 'Huffman' in str(error), str(error)
    else: raise AssertionError('Optimized Huffman JPEG accepted')
    encoded=io.BytesIO();probe.save(encoded,'JPEG',subsampling=2,optimize=False)
    standard=encoded.getvalue();card.jpeg_check(standard)
    restart=standard[:2]+bytes.fromhex('ffdd00040001')+standard[2:]
    try: card.jpeg_check(restart)
    except ValueError as error:
        assert 'restart' in str(error), str(error)
    else: raise AssertionError('Restart interval JPEG accepted')
    print('PASS: fixed Huffman profile accepts standard tables, rejects optimized tables/restart intervals',flush=True)
    with tempfile.TemporaryDirectory(prefix='tfmedia3-tests-') as tmp:
        work=Path(tmp)
        image=work/'bars.png'
        im=Image.new('RGB',(640,480),'blue')
        for x,c in enumerate(['red','green','blue','white','yellow','cyan','magenta','black']):
            im.paste(c,(x*80,0,(x+1)*80,480))
        im.save(image)
        packed=work/'pictures.img'
        subprocess.run([sys.executable,str(ROOT/'tools/media_card.py'),'pack',str(image),'-o',str(packed)],check=True)
        report=card.inspect(packed)
        assert report['media'][0]['frames']==1
        corrupt=work/'corrupt.img'
        data=bytearray(packed.read_bytes());data[24]^=1;corrupt.write_bytes(data)
        try: card.inspect(corrupt)
        except ValueError: pass
        else: raise AssertionError('CRC corruption accepted')
        # A small, compatible 3-frame video for lifecycle tests, with no audio.
        data=bytearray(packed.read_bytes())
        _,_,_,mlba,dlba,size=struct.unpack_from('<BBHIII',data,512)
        flba=struct.unpack_from('<I',data,mlba*512+8)[0]
        jpeg=bytes(data[dlba*512:dlba*512+size])
        data=data[:dlba*512]+bytearray(jpeg*3)
        data+=bytes(-len(data)%512)
        struct.pack_into('<BBHIII',data,512,2,0,0,mlba,dlba,size*3)
        struct.pack_into('<I',data,48,len(data)//512)
        data[:512]=card.crc_sector(data[:512])
        meta=bytearray(data[mlba*512:(mlba+1)*512])
        struct.pack_into('<I',meta,12,3)
        data[mlba*512:(mlba+1)*512]=card.crc_sector(meta)
        for i in range(3):struct.pack_into('<II',data,flba*512+i*8,size*i,size)
        # Include PCM so lifecycle coverage exercises competing audio sectors
        # and the automatic reload after presenting the last video frame.
        audio_lba=len(data)//512
        audio_size=3*3840
        data+=bytes(audio_size)+bytes(-audio_size%512)
        struct.pack_into('<I',data,48,len(data)//512)
        data[:512]=card.crc_sector(data[:512])
        meta=bytearray(data[mlba*512:(mlba+1)*512])
        struct.pack_into('<II',meta,16,audio_lba,audio_size)
        data[mlba*512:(mlba+1)*512]=card.crc_sector(meta)
        movie=work/'three.img';movie.write_bytes(data);card.inspect(movie)
        data=bytearray(packed.read_bytes())[:dlba*512]+bytearray(jpeg*12)
        data+=bytes(-len(data)%512)
        struct.pack_into('<BBHIII',data,512,2,0,0,mlba,dlba,size*12)
        struct.pack_into('<I',data,48,len(data)//512)
        data[:512]=card.crc_sector(data[:512])
        meta=bytearray(data[mlba*512:(mlba+1)*512])
        struct.pack_into('<I',meta,12,12)
        struct.pack_into('<II',meta,24,12,25)
        data[mlba*512:(mlba+1)*512]=card.crc_sector(meta)
        for i in range(12):struct.pack_into('<II',data,flba*512+i*8,size*i,size)
        catchup_movie=work/'twelve.img';catchup_movie.write_bytes(data);card.inspect(catchup_movie)
        def rtl(top,sources,extra=()):
            target=work/(top+'.vvp')
            subprocess.run([str(exe),'-g2012','-s',top,'-o',str(target),str(SIM/(top+'.v')),
                            *map(str,sources)],cwd=work,check=True)
            result=subprocess.run([str(vvp),str(target),*extra],cwd=work,check=True,capture_output=True,text=True)
            print(result.stdout,end='',flush=True)
            if 'PASS' not in result.stdout or any(t in result.stdout for t in ['FATAL:','FAIL','ERROR:']):
                raise AssertionError(f'{top}: simulation did not pass\n{result.stderr}')
        tf=HDL/'tfmedia3'
        rtl('tb_player_volume_control',[tf/'player_volume_control.v',tf/'button_debounce_pulse.v'])
        rtl('tb_volume_bar_overlay',[tf/'volume_bar_overlay.v',HDL/'video_rgb_to_axis_640x480.v'])
        rtl('tb_brightness_gain',[tf/'volume_bar_overlay.v'])
        rtl('tb_contrast_gain',[tf/'volume_bar_overlay.v'])
        rtl('tb_contrast_video_pipeline',[tf/'volume_bar_overlay.v',HDL/'video_rgb_to_axis_640x480.v'])
        rtl('tb_scroll_text_overlay',[tf/'scroll_text_overlay.v',tf/'scroll_text_font.v',HDL/'video_rgb_to_axis_640x480.v'])
        rtl('tb_audio_wave_overlay',[tf/'audio_wave_overlay.v',HDL/'video_rgb_to_axis_640x480.v'])
        golden=SIM/'fixtures/legacy_frames.img'
        # Older Windows Icarus cannot open Unicode file names.
        ascii_golden=work/'golden_catalog.bin';shutil.copyfile(SIM/'fixtures/legacy_catalog.bin',ascii_golden)
        rtl('tb_tfmedia3_catalog',[tf/'tfmedia3_catalog.v'],['+image='+str(ascii_golden)])
        rtl('tb_tfmedia3_catalog',[tf/'tfmedia3_catalog.v'],['+image='+str(ascii_golden),'+corrupt'])
        rtl('tb_sd_init_ready',[HDL/'SD/sd_card_sec_read_write.v'])
        rtl('tb_frame_present_cdc',[tf/'frame_present_cdc.v'])
        rtl('tb_playback_clock',[tf/'tfmedia3_reader_frontend.v'])
        rtl('tb_pcm_playhead',[tf/'pcm_audio_buffer.v',SIM/'tb_reader_lifecycle.v'])
        rtl('tb_display_interfaces',[tf/'seg7_serial_8digit.v',HDL/'video_rgb_to_axis_640x480.v'])
        rtl('tb_jpeg_sram_dma',[tf/'jpeg_sram_dma.v'])
        rtl('tb_jpeg_timeout_debug',[tf/'jpeg_decode_pipeline.v'])
        rtl('tb_jpeg_input_tail',[ROOT/'third_party/core_jpeg/src_v/jpeg_input.v'])
        rtl('tb_jpeg_input_gaps',[ROOT/'third_party/core_jpeg/src_v/jpeg_input.v'])
        from check_frame import read_frame
        late_frame=read_frame(golden,1,4)
        gap_vector=work/'video_frame4_bytes.hex'
        gap_vector.write_text(''.join(f'{value:02x}\n' for value in late_frame))
        rtl('tb_jpeg_input_gaps',[ROOT/'third_party/core_jpeg/src_v/jpeg_input.v'],
            [f'+jpeg_bytes={len(late_frame)}','+jpeg_hex='+str(gap_vector)])
        subprocess.run([sys.executable,str(SIM/'check_top_recovery.py'),str(exe)],check=True)
        subprocess.run([sys.executable,str(SIM/'check_hdmi_cdc.py'),str(exe)],check=True)
        reader_sources=([tf/n for n in ['tfmedia3_reader_frontend.v','button_debounce_pulse.v',
             'tfmedia3_catalog.v','tfmedia3_metadata.v','sd_sector_arbiter4.v','jpeg_sram_dma.v','pcm_audio_buffer.v']]+
             [HDL/'memory'/n for n in ['sram_arbiter2.v','async_sram16_controller.v']])
        rtl('tb_reader_lifecycle',reader_sources,['+image='+str(movie)])
        rtl('tb_reader_catchup',reader_sources+[SIM/'tb_reader_lifecycle.v'],['+image='+str(catchup_movie)])
        if not args.quick:
            subprocess.run([sys.executable,str(SIM/'extract_first_jpeg.py'),str(golden),str(work/'golden_first_jpeg.hex')],check=True)
            rtl('tb_jpeg_display_completion',[tf/'jpeg_decode_pipeline.v',*sorted((ROOT/'third_party/core_jpeg/src_v').glob('*.v'))])
            rgb=bytes.fromhex((work/'decoded.hex').read_text())
            assert len(rgb)==640*480*3
            decoded=Image.frombytes('RGB',(640,480),rgb)
            decoded.save(SIM/'decoded_golden.png')
            # Independent software decoder checks pixel order and colors.
            import io
            from PIL import ImageChops,ImageStat
            with golden.open('rb') as stream:
                stream.seek(512);_,_,_,mlba,dlba,_=struct.unpack('<BBHIII',stream.read(16))
                stream.seek(mlba*512+8);ilba=struct.unpack('<I',stream.read(4))[0]
                stream.seek(ilba*512);offset,length=struct.unpack('<II',stream.read(8))
                stream.seek(dlba*512+offset);reference=Image.open(io.BytesIO(stream.read(length))).convert('RGB')
            mean_error=sum(ImageStat.Stat(ImageChops.difference(decoded,reference)).mean)/3
            assert mean_error<1, f'Pixel mismatch against software JPEG: MAE={mean_error}'
            print(f'PASS: pixel comparison against software JPEG, MAE={mean_error:.6f}/255')
        print('PASS: host pack/inspect, CRC rejection and requested RTL tests')

if __name__=='__main__':main()
