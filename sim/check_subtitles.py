"""Host/RTL shared subtitle vectors and card compatibility tests."""
from pathlib import Path
import json
import struct
import subprocess
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import subtitles
import media_card


def host_tests(work):
    entries=[dict(text=('字幕 %d FPGA'%i) if i!=9 else '字'*32,
                  color='#%06X'%(0x123400+i),rainbow=bool(i%2)) for i in range(10)]
    blob=subtitles.encode(entries)
    assert len(blob)==11264
    styles=subtitles.decode(blob)
    assert len(styles)==10 and styles[9]['characters']==32
    assert subtitles.encode([])==b'' and subtitles.normalize([{'text':' '}])==[]
    for bad in [[{'text':'a'*33}],entries+[entries[0]],[{'text':'a','color':'red'}],
                [{'text':'a','rainbow':1}],[{'text':'line\nbreak'}]]:
        try: subtitles.encode(bad)
        except ValueError: pass
        else: raise AssertionError('Invalid subtitle accepted')
    for offset in [100,512+10,len(blob)-1]:
        bad=bytearray(blob);bad[offset]^=1
        try:subtitles.decode(bad)
        except ValueError:pass
        else:raise AssertionError('Corrupt subtitle accepted')
    vector=work/'subtitles.hex';vector.write_text(''.join('%02x\n'%v for v in blob))
    image=work/'图片.png';Image.new('RGB',(320,180),'navy').save(image)
    config=work/'字幕.json';config.write_text(json.dumps({'subtitles':entries},ensure_ascii=False),encoding='utf-8')
    card=work/'with-subtitles.img'
    subprocess.run([sys.executable,str(ROOT/'tools/media_card.py'),'pack',str(image),'-o',str(card),'--subtitles',str(config)],check=True)
    report=media_card.inspect(card)
    assert len(report['subtitles'])==10 and report['media'][0]['frames']==1
    contents=bytearray(card.read_bytes());lba=struct.unpack_from('<I',contents,52)[0]
    assert contents[lba*512:(lba+22)*512]==blob
    contents[lba*512+600]^=1;badcard=work/'bad-subtitle.img';badcard.write_bytes(contents)
    try:media_card.inspect(badcard)
    except ValueError:pass
    else:raise AssertionError('Corrupt card subtitle accepted')
    config.write_text('{"subtitles":[]}',encoding='utf-8')
    subprocess.run([sys.executable,str(ROOT/'tools/media_card.py'),'pack',str(image),'-o',str(card),'--subtitles',str(config)],check=True)
    assert struct.unpack_from('<I',card.read_bytes(),52)[0]==0
    assert media_card.inspect(card)['subtitles']==[]
    subprocess.run([sys.executable,str(ROOT/'tools/media_preview.py'),'image',str(image),str(work/'image-preview.png')],check=True)
    assert Image.open(work/'image-preview.png').size==(640,480)
    subtitles.preview(entries[0],work/'subtitle-preview.png')
    assert Image.open(work/'subtitle-preview.png').getbbox()
    print('PASS: host subtitle limits/styles, all-sector CRCs, card roundtrip, empty legacy format and Chinese-path image preview',flush=True)
    return vector
